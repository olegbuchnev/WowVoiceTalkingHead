package ru.talkinghead.vote;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.sql.DriverManager;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import tools.jackson.databind.ObjectMapper;

class AddonRankingTest {
    @TempDir Path directory;
    final ObjectMapper mapper=new ObjectMapper();
    Catalogue.Variant variant(char id,String source) {
        return new Catalogue.Variant((""+id).repeat(24),source,source,"1",(""+id).repeat(64),List.of((""+id).repeat(64)));
    }
    Catalogue.Quest quest(long id,List<Catalogue.Variant> variants) {
        return new Catalogue.Quest(id,new Catalogue.Npc(101,1,1,"dwarf","male"),variants);
    }
    Path catalogue(Catalogue.Quest... quests) throws Exception {
        var file=directory.resolve("catalogue.json");
        Files.writeString(file,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(quests))));return file;
    }
    AddonRanking.Group dwarf(AddonRanking.Snapshot snapshot) {
        return snapshot.groups().stream().filter(g->g.race().equals("dwarf") && g.sex().equals("male")).findFirst().orElseThrow();
    }
    @Test void luceUsesWholeChoiceSetsAndHasFiniteSymmetricEstimates() {
        long[][] counts=new long[8][3];counts[7][1]=50;
        var scores=AddonRanking.fit(counts);
        assertEquals(scores[0],scores[2],1e-10);assertTrue(scores[1]>scores[0]);
        var group=AddonRanking.group(new AddonRanking.Key("dwarf","male"),counts);
        assertEquals("CatQuest",group.ranking().getFirst().source());
        assertEquals(List.of("CatQuest","WowVoice","Wayfarer"),group.ranking().stream().map(AddonRanking.Place::source).toList());
        var gradient=new double[3];var hessian=new double[3][3];
        AddonRanking.objective(scores,counts,gradient,hessian);
        for(double value:gradient) assertEquals(0,value,1e-8);
        counts[7][0]=50;counts[7][2]=50;
        for(double value:AddonRanking.fit(counts)) assertEquals(0,value,1e-8);
    }
    @Test void sparseAndLargeSamplesConvergeAndUnseenSourcesRemainFallbacks() {
        var random=new Random(72);
        for(int test=0;test<50;test++) {
            var counts=new long[8][3];
            for(int mask:new int[]{3,5,6,7}) for(int source=0;source<3;source++)
                if((mask&(1<<source))!=0) counts[mask][source]=random.nextInt(10000);
            for(double value:AddonRanking.fit(counts)) assertTrue(Double.isFinite(value));
        }
        var counts=new long[8][3];counts[3][1]=1;
        var group=AddonRanking.group(new AddonRanking.Key("dwarf","male"),counts);
        assertEquals("partial",group.status());assertEquals("Wayfarer",group.ranking().getLast().source());
        assertEquals("fallback",group.ranking().getLast().basis());
    }
    @Test void updatedRecordingsKeepOldVotesAndExportRoundTripsWithoutPersonalData() throws Exception {
        var a=variant('a',"WowVoice");var b=variant('b',"CatQuest");var c=variant('c',"Wayfarer");
        var quest=quest(1,List.of(a,b,c));var db=directory.resolve("votes.sqlite");var file=catalogue(quest);
        try(var store=new VoteStore(db.toString(),mapper)) {
            var visitor=store.createVisitor();store.save(visitor.id(),quest,b.id());
            var before=dwarf(AddonRanking.read(db,file));
            catalogue(quest(1,List.of(a,variant('d',"CatQuest"),c)));
            assertEquals(before,dwarf(AddonRanking.read(db,file)));
            var export=AddonRanking.export(db,file);
            var parts=export.importString().substring(5).split("\\.");
            byte[] decoded=Base64.getUrlDecoder().decode(parts[0]);
            assertEquals(export.json(),new String(decoded,StandardCharsets.UTF_8));
            assertEquals(Catalogue.hash(decoded),parts[1]);
            assertFalse(export.json().contains("tieGroup"));
            for(var group:mapper.readTree(export.json()).required("groups")) {
                int rank=1;
                for(var place:group.required("ranking")) {
                    assertEquals(3,place.size());
                    assertEquals(rank++,place.required("rank").asInt());
                    assertTrue(place.has("source"));assertTrue(place.has("basis"));
                }
                assertEquals(4,rank);
            }
            assertFalse(export.json().contains(visitor.id()));assertFalse(export.json().contains(visitor.token()));
            assertTrue(AddonRanking.read(db,file).groups().stream().anyMatch(g->g.status().equals("no_data")));
        }
    }
    @Test void revoteReplacesAllOldEvidenceAndLateInboxReplayCannotOverwriteIt() throws Exception {
        var a=variant('a',"WowVoice");var b=variant('b',"CatQuest");var c=variant('c',"Wayfarer");
        var old=quest(1,List.of(a,b,c));var current=quest(1,List.of(a,b));var db=directory.resolve("votes.sqlite");
        try(var store=new VoteStore(db.toString(),mapper)) {
            var visitor=store.createVisitor();
            store.save(visitor.id(),old,c.id(),null,100);
            store.save(visitor.id(),current,a.id(),null,200);
            store.save(visitor.id(),old,c.id(),null,100);
            store.save(visitor.id(),current,a.id(),null,200);
            assertEquals(1,store.summary(visitor.id()).total());
            assertEquals(1,store.summary(visitor.id()).counts().get("WowVoice"));
            var group=dwarf(AddonRanking.read(db,catalogue(current)));
            assertEquals("WowVoice",group.ranking().getFirst().source());
            assertEquals("fallback",group.ranking().getLast().basis());
        }
    }
    @Test void correctedDemographicsDoNotInheritOldBallots() throws Exception {
        var a=variant('a',"WowVoice");var b=variant('b',"CatQuest");var old=quest(1,List.of(a,b));
        var current=new Catalogue.Quest(1,new Catalogue.Npc(101,1,1,"human","male"),old.variants());
        var db=directory.resolve("votes.sqlite");
        try(var store=new VoteStore(db.toString(),mapper)) {
            store.save(store.createVisitor().id(),old,b.id());
            assertTrue(AddonRanking.read(db,catalogue(current)).groups().stream().allMatch(g->g.status().equals("no_data")));
        }
    }
    @Test void queueUsesHistoricalGroupCoverageAndExcludesCorrectedDemographics() throws Exception {
        var a=variant('a',"WowVoice");var b=variant('b',"CatQuest");
        var old=quest(900001,List.of(a,b));
        var current=quest(900001,List.of(a,variant('d',"CatQuest")));
        var prior=new Catalogue.Quest(900002,new Catalogue.Npc(102,1,1,"orc","female"),List.of(a,b));
        var fresh=new Catalogue.Quest(900002,new Catalogue.Npc(102,1,1,"dwarf","female"),List.of(a,b));
        var db=directory.resolve("votes.sqlite");
        try(var store=new VoteStore(db.toString(),mapper)) {
            store.save(store.createVisitor().id(),old,b.id());
            store.save(store.createVisitor().id(),prior,b.id());
            var visitor=store.createVisitor();
            var quests=List.of(current,fresh);
            var snapshot=AddonRanking.read(db,catalogue(current,fresh));
            assertEquals("partial",dwarf(snapshot).status());
            assertTrue(snapshot.groups().stream().anyMatch(g->g.race().equals("dwarf") && g.sex().equals("female") && g.status().equals("no_data")));
            for(int i=0;i<10;i++) {
                var ordered=store.queue(visitor.id(),quests);
                assertEquals(900002,ordered.getFirst().questID());
                assertTrue(ordered.stream().allMatch(p->p.votes()==0 && !p.rated()));
            }
            // A pending personal answer must not displace a still-unseen comparison.
            assertEquals(900001,store.queue(visitor.id(),quests,Set.of(900002L)).getFirst().questID());
            store.save(visitor.id(),fresh,a.id());
            assertEquals(900001,store.queue(visitor.id(),quests).getFirst().questID());
        }
    }

    @Test void migrationKeepsLatestPerQuestAndPreservesDatabaseBackup() throws Exception {
        var a=variant('a',"WowVoice");var b=variant('b',"CatQuest");var db=directory.resolve("votes.sqlite");String visitor;
        try(var store=new VoteStore(db.toString(),mapper)) {
            visitor=store.createVisitor().id();store.save(visitor,quest(1,List.of(a,b)),a.id());
            store.save(visitor,quest(2,List.of(a,b)),b.id());
        }
        try(var connection=DriverManager.getConnection("jdbc:sqlite:"+db);var sql=connection.createStatement()) {
            sql.execute("DROP INDEX votes_active_quest");
            for(String column:List.of("quest_id","stage","accepted_order")) sql.execute("ALTER TABLE votes DROP COLUMN "+column);
            sql.execute("UPDATE votes SET updated_at=CASE source WHEN 'WowVoice' THEN '2026-01-01T00:00:00Z' ELSE '2026-02-01T00:00:00Z' END");
            sql.execute("UPDATE comparisons SET quest_id=1");sql.execute("PRAGMA user_version=2");
        }
        try(var store=new VoteStore(db.toString(),mapper)) {
            assertEquals(1,store.summary(visitor).total());assertEquals(1,store.summary(visitor).counts().get("CatQuest"));
        }
        try(var files=Files.list(directory)) {
            var backup=files.filter(p->p.getFileName().toString().contains("before-active-votes")).findFirst().orElseThrow();
            try(var connection=DriverManager.getConnection("jdbc:sqlite:"+backup);var sql=connection.createStatement();var rows=sql.executeQuery("SELECT COUNT(*) FROM votes")) {
                rows.next();assertEquals(2,rows.getLong(1));
            }
        }
    }
}
