package ru.talkinghead.vote;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.file.Path;
import java.sql.DriverManager;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import tools.jackson.databind.ObjectMapper;

class AnalyticsMigrationTest {
    @TempDir Path directory;
    @Test void historicalVotesRemainVisibleWithoutInventingVisits() throws Exception {
        Path file=directory.resolve("votes.sqlite");
        var mapper=new ObjectMapper();
        String token;
        var quest=new Catalogue.Quest(1,new Catalogue.Npc(1,2,3,"human","male"),List.of(
            new Catalogue.Variant("a".repeat(24),"WowVoice","WowVoice","1","c".repeat(64),List.of("c".repeat(64))),
            new Catalogue.Variant("b".repeat(24),"CatQuest","CatQuest","1","c".repeat(64),List.of("c".repeat(64)))));
        try(var store=new VoteStore(file.toString(),mapper)) {
            var visitor=store.createVisitor();token=visitor.token();
            store.save(visitor.id(),quest,quest.variants().getFirst().id());
            store.createVisitor();
        }
        try(var db=DriverManager.getConnection("jdbc:sqlite:"+file);var sql=db.createStatement()) {
            for(String table:List.of("visit_votes","plays","visits","analytics_meta")) sql.execute("DROP TABLE "+table);
            sql.execute("PRAGMA user_version=1");
        }
        try(var store=new VoteStore(file.toString(),mapper)) {
            assertNotNull(store.visitor(token));
            assertEquals(1,store.summary(store.visitor(token)).total());
            var dashboard=mapper.valueToTree(store.dashboard(""));
            assertEquals(1,dashboard.get("votes").get("voters").asInt());
            assertEquals(0,dashboard.get("traffic").get("pageViews").asInt());
            assertEquals(1,mapper.valueToTree(store.adminVisitors("",0,"")).get("total").asInt());
        }
    }
}
