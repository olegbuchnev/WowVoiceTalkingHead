package ru.talkinghead.vote;

import jakarta.annotation.PreDestroy;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.file.*;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicLong;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;
import tools.jackson.databind.ObjectMapper;

/** Durable inbox: acknowledge disk admission, then commit votes on one worker. */
@Component
public class VoteInbox implements AutoCloseable {
    public record Job(String id,String visitor,Catalogue.Quest quest,String selected,String visitID,String receivedAt) {}
    public record Accepted(String comparisonID,String selected,String receipt,String state) {}
    private final VoteStore store;
    private final ObjectMapper mapper;
    private final Path directory;
    private final FileChannel lockChannel;
    private final java.nio.channels.FileLock directoryLock;
    private final ConcurrentLinkedDeque<Job> jobs=new ConcurrentLinkedDeque<>();
    private final ScheduledExecutorService worker=Executors.newSingleThreadScheduledExecutor(r->{var t=new Thread(r,"vote-inbox");t.setDaemon(true);return t;});
    private final AtomicLong processed=new AtomicLong(),failures=new AtomicLong();
    private final AtomicLong admissionFailures=new AtomicLong();
    private final AtomicLong quarantined=new AtomicLong();
    private volatile String admissionError,admissionErrorAt;
    private volatile String lastSuccess,lastError,lastFailure;
    private volatile long retryAt;
    private volatile boolean closed;
    private final int capacity;

    public VoteInbox(VoteStore store,ObjectMapper mapper,@Value("${voice-vote.database}") String database,
        @Value("${voice-vote.inbox-capacity:10000}") int capacity) throws IOException {
        this.store=store;this.mapper=mapper;this.capacity=capacity;
        directory=Path.of(database+".pending").toAbsolutePath().normalize();
        Files.createDirectories(directory);
        lockChannel=FileChannel.open(directory.resolve(".lock"),StandardOpenOption.CREATE,StandardOpenOption.WRITE);
        directoryLock=lockChannel.tryLock();
        if(directoryLock==null) {lockChannel.close();throw new IOException("Another server owns the voting inbox");}
        try(var files=Files.list(directory)) {quarantined.set(files.filter(p->p.getFileName().toString().endsWith(".failed")).count());}
        try(var files=Files.list(directory)) {
            for(var file:files.filter(p->p.getFileName().toString().endsWith(".json")).sorted().toList()) {
                var job=mapper.readValue(Files.readString(file),Job.class);
                if(!file.getFileName().toString().equals(job.id()+".json")) throw new IOException("Invalid inbox receipt");
                jobs.add(job);store.observeVoteOrder(Long.parseLong(job.id()));
            }
        }
        worker.scheduleWithFixedDelay(this::drain,100,25,TimeUnit.MILLISECONDS);
    }
    public synchronized Accepted accept(String visitor,Catalogue.Quest quest,String selected,String visitID) throws IOException,java.sql.SQLException {
        if(closed || jobs.size()>=capacity) throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,"Voting inbox is full. Retry later.");
        store.validateVisit(visitor,visitID);
        if(visitID!=null && jobs.stream().anyMatch(j->visitID.equals(j.visitID()) && !visitor.equals(j.visitor())))
            throw new ResponseStatusException(HttpStatus.CONFLICT,"Visit belongs to another visitor.");
        String id=String.format(Locale.ROOT,"%019d",store.nextVoteOrder());
        var job=new Job(id,visitor,quest,selected,visitID,Instant.now().toString());
        Path temporary=directory.resolve(id+".tmp"),target=directory.resolve(id+".json");
        byte[] bytes=mapper.writeValueAsBytes(job);
        try(var channel=FileChannel.open(temporary,StandardOpenOption.CREATE_NEW,StandardOpenOption.WRITE)) {
            var buffer=ByteBuffer.wrap(bytes);
            while(buffer.hasRemaining()) channel.write(buffer);
            channel.force(true);
        }
        Files.move(temporary,target,StandardCopyOption.ATOMIC_MOVE);
        jobs.add(job);
        // Directory syncing is supported on the Linux hosting filesystem.
        // Windows does not allow opening a directory with FileChannel.
        syncDirectory();
        String source=quest.variants().stream().filter(v->v.id().equals(selected)).findFirst().orElseThrow().source();
        return new Accepted(VoteStore.comparisonID(quest,mapper),source,id,"queued");
    }
    private void drain() {
        if(System.currentTimeMillis()<retryAt) return;
        for(int i=0;i<50 && !closed;i++) {
            var job=jobs.peekFirst();if(job==null) return;
            try {
                // Use the trusted snapshot accepted at submission, even after a library update.
                store.save(job.visitor(),job.quest(),job.selected(),job.visitID(),Long.parseLong(job.id()));
                Files.deleteIfExists(directory.resolve(job.id()+".json"));
                syncDirectory();
                synchronized(this) {jobs.removeFirst();}
                processed.incrementAndGet();lastSuccess=Instant.now().toString();retryAt=0;
            } catch(Exception error) {
                failures.incrementAndGet();lastFailure=Instant.now().toString();
                lastError=error.getClass().getSimpleName()+": "+Objects.toString(error.getMessage(),"Write failed");
                if(error instanceof ResponseStatusException status && status.getStatusCode().value()==409) {
                    // A conflicting visit is permanent. Preserve it for inspection
                    // without allowing one invalid request to stall every voter.
                    try {
                        Files.move(directory.resolve(job.id()+".json"),directory.resolve(job.id()+".failed"),StandardCopyOption.ATOMIC_MOVE);
                        syncDirectory();synchronized(this) {jobs.removeFirst();}quarantined.incrementAndGet();
                        continue;
                    } catch(IOException quarantineError) {error.addSuppressed(quarantineError);}
                }
                retryAt=System.currentTimeMillis()+5000;
                org.slf4j.LoggerFactory.getLogger(VoteInbox.class).error("Queued vote could not be committed; retry scheduled",error);
                return;
            }
        }
    }
    private void syncDirectory() throws IOException {
        if(!System.getProperty("os.name").startsWith("Windows"))
            try(var channel=FileChannel.open(directory,StandardOpenOption.READ)) {channel.force(true);}
    }
    public Map<String,Object> status() {
        var result=new LinkedHashMap<String,Object>();var oldest=jobs.peekFirst();
        result.put("pending",jobs.size());result.put("capacity",capacity);
        result.put("quarantined",quarantined.get());
        result.put("oldestAt",oldest==null?null:oldest.receivedAt());
        result.put("processed",processed.get());result.put("failures",failures.get());
        result.put("admissionFailures",admissionFailures.get());result.put("admissionError",admissionError);result.put("admissionErrorAt",admissionErrorAt);
        result.put("lastSuccess",lastSuccess);result.put("lastError",lastError);result.put("lastFailure",lastFailure);
        result.put("retrying",retryAt>System.currentTimeMillis());
        result.put("items",jobs.stream().limit(30).map(j->Map.of("visitor",j.visitor(),"questID",j.quest().questID(),"receivedAt",j.receivedAt())).toList());
        return result;
    }
    public void rejected(Exception error) {
        admissionFailures.incrementAndGet();admissionErrorAt=Instant.now().toString();
        admissionError=error.getClass().getSimpleName()+": "+Objects.toString(error.getMessage(),"Admission failed");
    }
    public Set<Long> pendingQuests(String visitor,List<Catalogue.Quest> current) {
        var byID=new HashMap<Long,Catalogue.Quest>();
        for(var quest:current) byID.put(quest.questID(),quest);
        var result=new HashSet<Long>();
        for(var job:jobs) {
            var quest=byID.get(job.quest().questID());
            if(job.visitor().equals(visitor) && quest!=null && VoteStore.comparisonID(quest,mapper).equals(VoteStore.comparisonID(job.quest(),mapper))) result.add(quest.questID());
        }
        return result;
    }
    @Override @PreDestroy public void close() {
        synchronized(this) {closed=true;}
        worker.shutdown();
        try {if(!worker.awaitTermination(15,TimeUnit.SECONDS)) worker.shutdownNow();}
        catch(InterruptedException e) {Thread.currentThread().interrupt();worker.shutdownNow();}
        try {directoryLock.release();lockChannel.close();}
        catch(IOException e) {throw new java.io.UncheckedIOException(e);}
    }
}
