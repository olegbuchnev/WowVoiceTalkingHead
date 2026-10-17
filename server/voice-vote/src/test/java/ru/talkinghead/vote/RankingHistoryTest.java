package ru.talkinghead.vote;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.file.*;
import java.sql.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import tools.jackson.databind.ObjectMapper;

class RankingHistoryTest {
    @TempDir Path directory;
    final ObjectMapper mapper=new ObjectMapper();
    long stamp=System.currentTimeMillis();
    Path database() {return directory.resolve("votes.sqlite");}
    Path catalogue() {return directory.resolve("catalogue.json");}
    Catalogue.Quest quest(long id,int revision) {
        var variants=new ArrayList<Catalogue.Variant>();
        for(int i=0;i<3;i++) {
            String hash=String.format("%064x",i==1?revision+100:i+1);
            variants.add(new Catalogue.Variant(hash.substring(40),AddonRanking.SOURCES.get(i),"pack","1",hash,List.of(hash)));
        }
        return new Catalogue.Quest(id,new Catalogue.Npc(101,1,1,"dwarf","male"),variants);
    }
    void publish(Catalogue.Quest... quests) throws Exception {
        Files.writeString(catalogue(),mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(quests))));
        Files.setLastModifiedTime(catalogue(),java.nio.file.attribute.FileTime.fromMillis(++stamp));
    }
    VoteStore store() throws Exception {return new VoteStore(database().toString(),mapper,new Catalogue(catalogue().toString(),mapper));}
    double scalar(String sql) throws Exception {
        try(var db=DriverManager.getConnection("jdbc:sqlite:"+database());var s=db.createStatement();var r=s.executeQuery(sql)) {
            assertTrue(r.next());return r.getDouble(1);
        }
    }
    void ballot(VoteStore store,Catalogue.Quest q,int source) throws Exception {
        store.save(store.createVisitor().id(),q,q.variants().get(source).id());
    }
    void totals(double history,double current) throws Exception {
        assertEquals(history,scalar("SELECT COALESCE(SUM(historical),0) FROM ranking_layers"),1e-10);
        assertEquals(current,scalar("SELECT COALESCE(SUM(current),0) FROM ranking_layers"),1e-10);
        assertEquals(history+current,scalar("SELECT COALESCE(SUM(ranking_weight),0) FROM votes"),1e-10);
    }
    @Test void fiftyTenOneMergesLayersAndSurvivesRestartAndExport() throws Exception {
        var a=quest(1,1);var b=quest(1,2);var c=quest(1,3);publish(a);
        double historical=(50*Math.pow(.98,10)+10)*.98;
        try(var store=store()) {
            for(int i=0;i<50;i++) ballot(store,a,1);
            totals(0,50);var before=AddonRanking.read(database(),catalogue()).groups();
            publish(b);store.synchronizeRanking();totals(50,0);
            assertEquals(before,AddonRanking.read(database(),catalogue()).groups());
            for(int i=0;i<10;i++) ballot(store,b,0);
            totals(50*Math.pow(.98,10),10);
            publish(c);store.synchronizeRanking();totals(50*Math.pow(.98,10)+10,0);
            ballot(store,c,2);totals(historical,1);
            assertEquals(61,scalar("SELECT COUNT(*) FROM votes"));
            double[][] counts=new double[8][3];counts[7][1]=50*Math.pow(.98,11);counts[7][0]=10*.98;counts[7][2]=1;
            var expected=AddonRanking.group(new AddonRanking.Key("dwarf","male"),counts);
            assertEquals(expected,AddonRanking.read(database(),catalogue()).groups().stream().filter(g->g.race().equals("dwarf") && g.sex().equals("male")).findFirst().orElseThrow());
        }
        try(var store=store()) {
            store.synchronizeRanking();AddonRanking.export(database(),catalogue());AddonRanking.export(database(),catalogue());
            totals(historical,1);
        }
    }
    @Test void revoteRemovesRemainingWeightAndTogglingOrReplayDoesNotDecayAgain() throws Exception {
        var a=quest(1,1);var b=quest(1,2);publish(a);
        try(var store=store()) {
            var visitor=store.createVisitor().id();store.save(visitor,a,a.variants().getFirst().id(),null,100);
            ballot(store,a,1);publish(b);store.synchronizeRanking();
            ballot(store,b,1);totals(1.96,1);
            store.save(visitor,b,b.variants().getFirst().id(),null,200);totals(.98*.98,2);
            store.save(visitor,b,b.variants().get(2).id(),null,201);totals(.98*.98,2);
            store.save(visitor,b,b.variants().get(2).id(),null,201);
            store.save(visitor,a,a.variants().getFirst().id(),null,100);totals(.98*.98,2);
            assertEquals(3,scalar("SELECT COUNT(*) FROM votes"));
        }
    }
    @Test void fiftyRevisionsStayBoundedAndUnchangedFilesDoNotBecomeHistorical() throws Exception {
        var a=quest(1,1);publish(a);
        try(var store=store()) {
            var visitor=store.createVisitor().id();store.save(visitor,a,a.variants().getFirst().id());
            var release=new Catalogue.Quest(a.questID(),new Catalogue.Npc(101,999,999,"dwarf","male"),a.variants().stream()
                .map(v->new Catalogue.Variant(v.id(),v.source(),v.pack(),"50",v.sha256(),v.revisions())).toList());
            publish(release);store.synchronizeRanking();totals(0,1);
            for(int i=2;i<=51;i++) {
                var updated=quest(1,i);publish(updated);store.synchronizeRanking();totals(1,0);
                store.save(visitor,updated,updated.variants().getFirst().id());totals(0,1);
                assertEquals(1,scalar("SELECT COUNT(*) FROM votes"));
                assertEquals(1,scalar("SELECT COUNT(*) FROM ranking_layers"));
                assertEquals(1,scalar("SELECT COUNT(*) FROM ranking_state"));
            }
        }
    }
    @Test void oldInboxBallotsAndOtherQuestsOrOfferedSetsDoNotAgeHistory() throws Exception {
        var a=quest(1,1);var b=quest(1,2);var other=quest(2,1);publish(a,other);
        try(var store=store()) {
            ballot(store,a,0);publish(b,other);store.synchronizeRanking();
            ballot(store,a,1);totals(2,0); // Accepted before replacement, delivered after it.
            ballot(store,other,1);totals(2,1);
            var pair=new Catalogue.Quest(1,b.npc(),b.variants().subList(0,2));publish(pair,other);
            ballot(store,pair,1);totals(2,2);
            publish(b,other);store.synchronizeRanking();totals(3,1);
            ballot(store,b,0);totals(2*.98+1,2); // Only the triple history decays.
        }
    }
    @Test void rollbackRestoresVotesWeightsAndLayersAndDoesNotChangeCommunityCache() throws Exception {
        var a=quest(1,1);var b=quest(1,2);publish(a);
        try(var store=store()) {
            ballot(store,a,0);publish(b);store.synchronizeRanking();
            var visitor=store.createVisitor();var before=store.communitySummary();
            try(var db=DriverManager.getConnection("jdbc:sqlite:"+database());var sql=db.createStatement()) {
                sql.execute("CREATE TRIGGER reject_layer BEFORE INSERT ON ranking_layers BEGIN SELECT RAISE(ABORT,'Test failure'); END");
            }
            assertThrows(SQLException.class,()->store.save(visitor.id(),b,b.variants().getFirst().id()));
            totals(1,0);assertEquals(before,store.communitySummary());
            assertEquals(1,scalar("SELECT COUNT(*) FROM votes"));
        }
    }
    @Test void migrationPreservesVotesAtUnitWeightAndKeepsBackup() throws Exception {
        var a=quest(1,1);publish(a);
        try(var store=store()) {ballot(store,a,0);ballot(store,a,1);}
        try(var db=DriverManager.getConnection("jdbc:sqlite:"+database());var s=db.createStatement()) {
            s.execute("DROP TABLE ranking_state");s.execute("DROP TABLE ranking_layers");s.execute("DROP INDEX votes_ranking_pool");
            for(String name:List.of("weight","current","generation","pool","revision","mask")) s.execute("ALTER TABLE votes DROP COLUMN ranking_"+name);
            s.execute("PRAGMA user_version=3");
        }
        publish(quest(1,2));
        try(var store=store()) {totals(2,0);assertEquals(2,scalar("SELECT COUNT(*) FROM votes"));}
        assertEquals(4,scalar("PRAGMA user_version"));
        try(var files=Files.list(directory)) {assertTrue(files.anyMatch(p->p.getFileName().toString().contains("before-ranking-layers")));}
    }
    @Test void exportUsesFractionalEvidenceAndMetadataCorrectionsRemainExcluded() throws Exception {
        var a=quest(1,1);var b=quest(1,2);publish(a);
        try(var store=store()) {
            ballot(store,a,1);ballot(store,a,1);publish(b);
            ballot(store,b,0);ballot(store,b,0);
            var group=AddonRanking.read(database(),catalogue()).groups().stream()
                .filter(g->g.race().equals("dwarf") && g.sex().equals("male")).findFirst().orElseThrow();
            assertEquals("WowVoice",group.ranking().getFirst().source());
            assertNull(group.ranking().getFirst().tieGroup());
            publish(new Catalogue.Quest(1,new Catalogue.Npc(101,1,1,"human","male"),b.variants()));
            store.synchronizeRanking();
            assertTrue(AddonRanking.read(database(),catalogue()).groups().stream().allMatch(g->g.status().equals("no_data")));
        }
    }
}
