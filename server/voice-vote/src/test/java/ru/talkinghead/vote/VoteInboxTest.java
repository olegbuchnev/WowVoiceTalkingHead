package ru.talkinghead.vote;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.file.*;
import java.sql.SQLException;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import tools.jackson.databind.ObjectMapper;

class VoteInboxTest {
    @TempDir Path directory;
    final ObjectMapper mapper=new ObjectMapper();
    Catalogue.Quest quest() {
        String hash="c".repeat(64);
        return new Catalogue.Quest(1479,new Catalogue.Npc(1,2,3,"human","male"),List.of(
            new Catalogue.Variant("a".repeat(24),"WowVoice","WowVoice","1",hash,List.of(hash)),
            new Catalogue.Variant("b".repeat(24),"CatQuest","CatQuest","1",hash,List.of(hash))));
    }
    void await(java.util.function.BooleanSupplier condition) throws Exception {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
        while(!condition.getAsBoolean() && System.nanoTime()<deadline) Thread.sleep(10);
        assertTrue(condition.getAsBoolean());
    }
    @Test void acceptedVotesSurviveWriteFailureAndRestartWithoutDoubleCounting() throws Exception {
        String file=directory.resolve("votes.sqlite").toString();
        var failing=new AtomicBoolean(true);
        try(var store=new VoteStore(file,mapper) {
            @Override public synchronized Saved save(String visitor,Catalogue.Quest quest,String selected,String visit) throws SQLException {
                if(failing.get()) throw new SQLException("Injected storage failure");
                return super.save(visitor,quest,selected,visit);
            }
        }) {
            var visitor=store.createVisitor();var quest=quest();String visit=UUID.randomUUID().toString();
            try(var inbox=new VoteInbox(store,mapper,file,10)) {
                assertEquals("queued",inbox.accept(visitor.id(),quest,quest.variants().getFirst().id(),visit).state());
                inbox.accept(visitor.id(),quest,quest.variants().getLast().id(),visit);
                await(()->((Number)inbox.status().get("failures")).longValue()>0);
                assertEquals(2,inbox.status().get("pending"));
                assertEquals(0,store.summary(visitor.id()).total());
                assertTrue(inbox.pendingQuests(visitor.id(),List.of(quest)).contains(1479L));
            }
            failing.set(false);
            try(var inbox=new VoteInbox(store,mapper,file,10)) {
                await(()->((Number)inbox.status().get("pending")).intValue()==0);
                assertEquals(1,store.summary(visitor.id()).total());
                assertEquals(1,store.summary(visitor.id()).counts().get("CatQuest"));
                assertEquals(1,mapper.valueToTree(store.dashboard("")).get("traffic").get("pageViews").asInt());
            }
        }
    }
    @Test void readsAndInboxAdmissionDoNotWaitForTheWriterMonitor() throws Exception {
        String file=directory.resolve("votes.sqlite").toString();
        try(var store=new VoteStore(file,mapper);var inbox=new VoteInbox(store,mapper,file,10);
            var executor=Executors.newSingleThreadExecutor()) {
            var visitor=store.createVisitor();
            synchronized(store) {
                executor.submit(()->store.summary(visitor.id())).get(2,TimeUnit.SECONDS);
                executor.submit(()->inbox.accept(visitor.id(),quest(),quest().variants().getFirst().id(),null)).get(2,TimeUnit.SECONDS);
            }
        }
    }
    @Test void fullInboxRejectsAdmissionWithoutDroppingAcceptedFiles() throws Exception {
        String file=directory.resolve("votes.sqlite").toString();
        try(var store=new VoteStore(file,mapper);var inbox=new VoteInbox(store,mapper,file,1)) {
            var visitor=store.createVisitor();
            synchronized(store) {
                inbox.accept(visitor.id(),quest(),quest().variants().getFirst().id(),null);
                assertThrows(org.springframework.web.server.ResponseStatusException.class,()->inbox.accept(visitor.id(),quest(),quest().variants().getLast().id(),null));
                assertEquals(1,inbox.status().get("pending"));
            }
        }
    }
    @Test void permanentVisitConflictCannotStallOtherAcceptedVotes() throws Exception {
        String file=directory.resolve("votes.sqlite").toString();
        try(var store=new VoteStore(file,mapper);var inbox=new VoteInbox(store,mapper,file,10)) {
            var first=store.createVisitor();var second=store.createVisitor();String visit=UUID.randomUUID().toString();
            synchronized(store) {
                inbox.accept(first.id(),quest(),quest().variants().getFirst().id(),visit);
                store.save(second.id(),quest(),quest().variants().getFirst().id(),visit);
                inbox.accept(first.id(),quest(),quest().variants().getLast().id(),UUID.randomUUID().toString());
            }
            await(()->((Number)inbox.status().get("pending")).intValue()==0);
            assertEquals(1L,inbox.status().get("quarantined"));
            assertEquals(1,store.summary(first.id()).total());
        }
    }
}
