package ru.talkinghead.vote;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.file.Path;
import java.sql.DriverManager;
import java.util.List;
import java.util.Map;
import java.util.concurrent.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import tools.jackson.databind.ObjectMapper;

class CommunitySummaryTest {
    @TempDir Path directory;
    final ObjectMapper mapper=new ObjectMapper();
    Catalogue.Quest quest(long id,String revision) {
        String hash=revision.repeat(64);
        return new Catalogue.Quest(id,new Catalogue.Npc(1,2,3,"human","male"),List.of(
            new Catalogue.Variant(revision.repeat(24),"WowVoice","WowVoice",revision,hash,List.of(hash)),
            new Catalogue.Variant("b".repeat(24),"CatQuest","CatQuest",revision,hash,List.of(hash))));
    }
    void counts(VoteStore.Summary summary,long wow,long cat) {
        assertEquals(Map.of("WowVoice",wow,"CatQuest",cat,"Wayfarer",0L),summary.counts());
        assertEquals(wow+cat,summary.total());
    }
    @Test void eagerRestartSnapshotDoesNotReadTheDatabaseAndRetainsPreviousChoices() throws Exception {
        String file=directory.resolve("votes.sqlite").toString();
        String visitor;
        var quest=quest(1479,"a");
        try(var store=new VoteStore(file,mapper)) {
            visitor=store.createVisitor().id();
            store.save(visitor,quest,quest.variants().getFirst().id());
            store.save(visitor,quest(1480,"a"),quest.variants().getFirst().id());
        }
        try(var store=new VoteStore(file,mapper);
            var connection=DriverManager.getConnection("jdbc:sqlite:"+file);
            var statement=connection.createStatement();
            var executor=Executors.newSingleThreadExecutor()) {
            // Remove the SQL read path before the first summary request.
            statement.execute("ALTER TABLE votes RENAME TO hidden_votes");
            try {
                synchronized(store) {
                    counts(executor.submit(store::communitySummary).get(2,TimeUnit.SECONDS),2,0);
                }
            } finally {statement.execute("ALTER TABLE hidden_votes RENAME TO votes");}
            var snapshot=store.communitySummary();
            assertThrows(UnsupportedOperationException.class,()->snapshot.counts().put("CatQuest",9L));
            // A changed recording is still the same person's choice for this quest.
            var revised=quest(1479,"c");
            store.save(visitor,revised,revised.variants().getLast().id());
            counts(store.communitySummary(),1,1);
            counts(snapshot,2,0);
            store.save(visitor,revised,revised.variants().getLast().id());
            counts(store.communitySummary(),1,1);
            store.save(store.createVisitor().id(),quest,quest.variants().getLast().id());
            counts(store.communitySummary(),1,2);
        }
    }
    @Test void rollbackAndObsoleteReplayDoNotAlterTheCache() throws Exception {
        try(var store=new VoteStore(directory.resolve("votes.sqlite").toString(),mapper)) {
            String first=store.createVisitor().id(),second=store.createVisitor().id();
            var quest=quest(1479,"a");
            String wow=quest.variants().getFirst().id(),cat=quest.variants().getLast().id();
            store.save(first,quest,wow,"shared-visit",10);
            store.save(second,quest,wow,null,11);
            var snapshot=store.communitySummary();
            assertThrows(org.springframework.web.server.ResponseStatusException.class,
                ()->store.save(second,quest,cat,"shared-visit",12));
            assertSame(snapshot,store.communitySummary());
            store.save(second,quest,cat,null,13);
            counts(store.communitySummary(),1,1);
            snapshot=store.communitySummary();
            store.save(second,quest,wow,null,11);
            store.save(second,quest,wow,null,13);
            assertSame(snapshot,store.communitySummary());
            counts(store.communitySummary(),1,1);
            assertEquals(store.summary(second).counts().get("CatQuest"),1L);
        }
    }
    @Test void readersAlwaysSeeACompleteSnapshotDuringRevotes() throws Exception {
        try(var store=new VoteStore(directory.resolve("votes.sqlite").toString(),mapper);
            var executor=Executors.newSingleThreadExecutor()) {
            String visitor=store.createVisitor().id();var quest=quest(1479,"a");
            store.save(visitor,quest,quest.variants().getFirst().id());
            var start=new CountDownLatch(1);
            var writer=executor.submit(()->{
                start.await();
                for(int i=0;i<100;i++) store.save(visitor,quest,quest.variants().get(i%2).id());
                return null;
            });
            start.countDown();
            do {
                var summary=store.communitySummary();
                assertEquals(1,summary.total());
                assertEquals(1,summary.counts().values().stream().mapToLong(Long::longValue).sum());
                assertTrue(summary.counts().values().stream().allMatch(value->value>=0));
            } while(!writer.isDone());
            writer.get(10,TimeUnit.SECONDS);
            counts(store.communitySummary(),0,1);
        }
    }
}
