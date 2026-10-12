package ru.talkinghead.vote;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.HashSet;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.DeserializationFeature;

@Component
public class Catalogue {
    public record Npc(long id, long displayID, long modelFileID, String race, String sex) {}
    public record Variant(String id, String source, String pack, String version, String sha256, List<String> revisions) {}
    public record Quest(long questID, Npc npc, List<Variant> variants) {}
    public record Snapshot(int schemaVersion, List<Quest> quests) {}
    private final Path file;
    private final ObjectMapper mapper;
    private volatile Cached cached;
    private record Stamp(java.nio.file.attribute.FileTime modified, long size, Object key) {}
    private record Cached(Stamp stamp, Snapshot snapshot) {}
    private Stamp stamp() throws IOException {
        var attributes=Files.readAttributes(file,java.nio.file.attribute.BasicFileAttributes.class);
        return new Stamp(attributes.lastModifiedTime(),attributes.size(),attributes.fileKey());
    }

    public Catalogue(@Value("${voice-vote.catalogue}") String file, ObjectMapper mapper) throws IOException {
        this.file = Path.of(file).toAbsolutePath().normalize();
        this.mapper = mapper;
        readSnapshot();
    }

    private Snapshot readSnapshot() throws IOException {
        var current=cached;
        var stamp=stamp();
        if(current!=null && current.stamp().equals(stamp)) return current.snapshot();
        synchronized(this) {
            stamp=stamp();current=cached;
            if(current!=null && current.stamp().equals(stamp)) return current.snapshot();
            // Publish one validated snapshot. All requests share it until the
            // file is replaced; a failed reload never validates stale ballots.
            var snapshot=parseSnapshot(Files.readString(file),mapper);
            if(!stamp.equals(stamp())) throw new IOException("Catalogue changed while loading. Retry the request.");
            cached=new Cached(stamp,snapshot);
            return snapshot;
        }
    }

    static Snapshot parseSnapshot(String json, ObjectMapper mapper) throws IOException {
        // Only a prepared metadata snapshot is needed at runtime. Reject legacy
        // path-bearing catalogues instead of silently accepting their format.
        Snapshot snapshot = mapper.readerFor(Snapshot.class)
            .with(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES).readValue(json);
        if (snapshot == null || snapshot.schemaVersion() != 2 || snapshot.quests() == null || snapshot.quests().isEmpty())
            throw new IOException("Unsupported voting catalogue. Export a schema version 2 snapshot.");
        var questIDs = new HashSet<Long>();
        for (var quest : snapshot.quests()) {
            if (quest == null || quest.questID() <= 0 || !questIDs.add(quest.questID()) || quest.npc() == null
                || quest.npc().modelFileID() < 0 || quest.npc().id() < 0 || quest.npc().displayID() < 0
                || (quest.npc().id() == 0 && (quest.npc().displayID() != 0 || quest.npc().modelFileID() != 0
                    || quest.npc().race() != null || quest.npc().sex() != null))
                || (quest.npc().displayID() == 0 && quest.npc().modelFileID() != 0)
                || quest.variants() == null || quest.variants().size() < 2 || quest.variants().size() > 3)
                throw new IOException("Invalid comparison or speaker metadata in voting catalogue.");
            var variantIDs = new HashSet<String>();
            var sources = new HashSet<String>();
            for (var variant : quest.variants()) {
                if (variant == null || variant.id() == null || !variant.id().matches("[a-f0-9]{24}")
                    || !variantIDs.add(variant.id()) || variant.sha256() == null || !variant.sha256().matches("[a-f0-9]{64}")
                    || variant.source() == null || !List.of("WowVoice","CatQuest","Wayfarer").contains(variant.source())
                    || !sources.add(variant.source()) || variant.pack() == null || !variant.pack().matches("[A-Za-z0-9_]+")
                    || variant.version() == null || variant.version().isBlank()
                    || variant.revisions() == null || variant.revisions().isEmpty() || variant.revisions().size() > 3
                    || variant.revisions().stream().anyMatch(h -> h == null || !h.matches("[a-f0-9]{64}"))
                    || new HashSet<>(variant.revisions()).size() != variant.revisions().size()
                    || !variant.revisions().contains(variant.sha256()))
                    throw new IOException("Invalid recording metadata in voting catalogue.");
            }
        }
        return snapshot;
    }

    public List<Quest> quests() throws IOException { return readSnapshot().quests(); }

    public Quest verified(long questID, String selectedId, List<String> variantIds) throws IOException {
        var snapshot = readSnapshot();
        var quest = snapshot.quests().stream().filter(q -> q.questID() == questID).findFirst()
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Comparison not found."));
        if (quest.variants().stream().noneMatch(v -> v.id().equals(selectedId)) ||
            !quest.variants().stream().map(Variant::id).sorted().toList().equals(variantIds.stream().sorted().toList()))
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Comparison recordings have changed. Reload the page.");
        return quest;
    }

    public static String hash(byte[] bytes) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)); }
        catch (java.security.NoSuchAlgorithmException e) { throw new IllegalStateException(e); }
    }
}
