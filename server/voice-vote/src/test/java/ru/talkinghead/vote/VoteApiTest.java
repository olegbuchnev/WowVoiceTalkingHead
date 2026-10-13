package ru.talkinghead.vote;

import static org.junit.jupiter.api.Assertions.*;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.sql.DriverManager;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ConfigurableApplicationContext;
import tools.jackson.databind.ObjectMapper;

class VoteApiTest {
    @TempDir Path directory;
    ConfigurableApplicationContext context;
    final ObjectMapper mapper=new ObjectMapper();
    String base;
    Path catalogueFile, database;
    Catalogue.Quest quest;
    final String first="a".repeat(24), second="b".repeat(24);
    HttpClient browser;

    Catalogue.Variant variant(String id, String source, String pack, String version, String sha256) {
        return new Catalogue.Variant(id,source,pack,version,sha256,List.of(sha256));
    }
    @BeforeEach void start() throws Exception {
        catalogueFile=directory.resolve("catalogue.json"); database=directory.resolve("votes.sqlite");
        String hash="f".repeat(64);
        quest=new Catalogue.Quest(179,new Catalogue.Npc(658,1362,878772,"dwarf","male"),List.of(
            variant(first,"WowVoice","WowVoiceSounds","1",hash),
            variant(second,"CatQuest","CatQuest_Voices","0.6.0",hash)));
        writeCatalogue(); restart();
        browser=HttpClient.newBuilder().cookieHandler(new CookieManager(null,CookiePolicy.ACCEPT_ALL)).build();
    }
    void writeCatalogue() throws Exception {Files.writeString(catalogueFile,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(quest))));}
    void restart() {
        if(context!=null) context.close();
        context=SpringApplication.run(VoteApplication.class,"--server.port=0","--voice-vote.database="+database,
            "--voice-vote.catalogue="+catalogueFile,"--spring.main.banner-mode=off");
        base="http://127.0.0.1:"+context.getEnvironment().getProperty("local.server.port");
    }
    @AfterEach void close() {if(context!=null)context.close();}
    HttpResponse<String> summary() throws Exception {
        return browser.send(HttpRequest.newBuilder(URI.create(base+"/api/votes/summary")).GET().build(),HttpResponse.BodyHandlers.ofString());
    }
    String ballot(String selected) {return mapper.writeValueAsString(new VoteController.Ballot(179,selected,List.of(first,second)));}
    HttpResponse<String> post(String body,String origin) throws Exception {
        return browser.send(HttpRequest.newBuilder(URI.create(base+"/api/votes")).header("Content-Type","application/json")
            .header("Origin",origin).POST(HttpRequest.BodyPublishers.ofString(body)).build(),HttpResponse.BodyHandlers.ofString());
    }
    long total(HttpResponse<String> response) {assertEquals(200,response.statusCode(),response.body());return mapper.readTree(response.body()).get("total").asLong();}

    @Test void durableVotesDeduplicateAndUseTrustedMetadata() throws Exception {
        var initial=summary(); assertEquals(0,total(initial));
        String cookie=initial.headers().firstValue("set-cookie").orElseThrow();
        assertTrue(cookie.contains("HttpOnly"));assertTrue(cookie.contains("SameSite=Lax"));
        assertEquals(1,total(post(ballot(first),base)));
        assertEquals(1,total(post(ballot(first),base)));
        var changed=post(ballot(second),base); assertEquals(1,total(changed));
        assertEquals(1,mapper.readTree(changed.body()).get("counts").get("CatQuest").asInt());
        restart(); assertEquals(1,total(summary()));
        try(var db=DriverManager.getConnection("jdbc:sqlite:"+database);var statement=db.createStatement();
            var row=statement.executeQuery("SELECT * FROM votes JOIN comparisons ON comparison_id=comparisons.id")) {
            assertTrue(row.next()); assertEquals(179,row.getInt("quest_id"));assertEquals(658,row.getInt("npc_id"));
            assertEquals(878772,row.getInt("model_file_id"));assertEquals("dwarf",row.getString("race"));
            assertEquals("male",row.getString("sex"));assertEquals("0.6.0",row.getString("library_version"));
            assertEquals(quest.variants().get(1).sha256(),row.getString("sha256"));assertFalse(row.next());
        }
        browser=HttpClient.newBuilder().cookieHandler(new CookieManager(null,CookiePolicy.ACCEPT_ALL)).build();
        assertEquals(0,total(summary())); // another visitor cannot see the first visitor's counters
    }
    @Test void acceptsUnknownSpeakerWithoutFabricatingDemographics() throws Exception {
        quest=new Catalogue.Quest(quest.questID(),new Catalogue.Npc(0,0,0,null,null),quest.variants());
        writeCatalogue();
        summary();
        assertEquals(1,total(post(ballot(first),base)));
        assertEquals(List.of(new VoteStore.Priority(179,true,1)),queue());
        try(var db=DriverManager.getConnection("jdbc:sqlite:"+database);var statement=db.createStatement();
            var row=statement.executeQuery("SELECT npc_id,race,sex FROM comparisons")) {
            assertTrue(row.next());assertEquals(0,row.getLong("npc_id"));
            assertNull(row.getString("race"));assertNull(row.getString("sex"));
        }
        quest=new Catalogue.Quest(quest.questID(),new Catalogue.Npc(0,1362,878772,"dwarf","male"),quest.variants());
        writeCatalogue();
        assertThrows(Exception.class,()->new Catalogue(catalogueFile.toString(),mapper));
    }

    @Test void rejectsInvalidRequestsAndOutdatedComparisonsWithoutSaving() throws Exception {
        assertEquals(401,post(ballot(first),base).statusCode());summary();
        assertEquals(403,post(ballot(first),"https://foreign.example").statusCode());
        assertEquals(400,post("{",base).statusCode());
        assertEquals(400,post("{}",base).statusCode());
        assertEquals(413,post(" ".repeat(17000),base).statusCode());
        assertEquals(409,post(ballot("c".repeat(24)),base).statusCode());
        var previous=quest.variants().getFirst();
        quest=new Catalogue.Quest(quest.questID(),quest.npc(),List.of(variant(
            "d".repeat(24),previous.source(),previous.pack(),"2","e".repeat(64)),quest.variants().get(1)));
        writeCatalogue();
        assertEquals(409,post(ballot(first),base).statusCode()); assertEquals(0,total(summary()));
    }
    @Test void versionNumberAloneDoesNotCreateAnotherComparisonButNewBytesDo() throws Exception {
        summary(); assertEquals(1,total(post(ballot(first),base)));
        var previous=quest.variants().getFirst();
        quest=new Catalogue.Quest(quest.questID(),quest.npc(),List.of(variant(
            first,previous.source(),previous.pack(),"2",previous.sha256()),quest.variants().get(1)));
        writeCatalogue(); assertEquals(1,total(post(ballot(first),base)));
        var updated=variant("d".repeat(24),previous.source(),previous.pack(),"3","e".repeat(64));
        quest=new Catalogue.Quest(quest.questID(),quest.npc(),List.of(updated,quest.variants().get(1)));writeCatalogue();
        var body=mapper.writeValueAsString(new VoteController.Ballot(179,updated.id(),List.of(updated.id(),second)));
        assertEquals(2,total(post(body,base)));
    }

    List<VoteStore.Priority> queue() throws Exception {
        var response=browser.send(HttpRequest.newBuilder(URI.create(base+"/api/votes/queue")).GET().build(),HttpResponse.BodyHandlers.ofString());
        assertEquals(200,response.statusCode(),response.body());
        assertEquals("no-store",response.headers().firstValue("cache-control").orElseThrow());
        return List.of(mapper.readValue(response.body(),VoteStore.Priority[].class));
    }

    @Test void queueUsesCookieAndCurrentRecordingCoverage() throws Exception {
        summary();
        assertEquals(List.of(new VoteStore.Priority(179,false,0)),queue());
        post(ballot(first),base); post(ballot(second),base);
        assertEquals(List.of(new VoteStore.Priority(179,true,1)),queue());
        restart(); assertEquals(List.of(new VoteStore.Priority(179,true,1)),queue());
        browser=HttpClient.newBuilder().cookieHandler(new CookieManager(null,CookiePolicy.ACCEPT_ALL)).build();
        summary(); assertEquals(List.of(new VoteStore.Priority(179,false,1)),queue());
        post(ballot(first),base);
        assertEquals(List.of(new VoteStore.Priority(179,true,2)),queue());
        var previous=quest.variants().getFirst();
        quest=new Catalogue.Quest(quest.questID(),quest.npc(),List.of(variant(
            first,previous.source(),previous.pack(),"2",previous.sha256()),quest.variants().get(1)));
        writeCatalogue(); assertEquals(List.of(new VoteStore.Priority(179,true,2)),queue());
        quest=new Catalogue.Quest(quest.questID(),quest.npc(),List.of(variant(
            "d".repeat(24),previous.source(),previous.pack(),"3","e".repeat(64)),quest.variants().get(1)));
        writeCatalogue(); assertEquals(List.of(new VoteStore.Priority(179,false,0)),queue());
        assertEquals(1,total(summary()));
    }

    @Test void queuePrioritizesUnratedThenLeastCoveredComparisons() throws Exception {
        var secondQuest=new Catalogue.Quest(7,quest.npc(),quest.variants());
        var thirdQuest=new Catalogue.Quest(3741,quest.npc(),quest.variants());
        Files.writeString(catalogueFile,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(quest,secondQuest,thirdQuest))));
        var store=context.getBean(VoteStore.class);
        var visitor=store.createVisitor();
        store.save(visitor.id(),quest,first);
        store.save(visitor.id(),secondQuest,first);
        store.save(store.createVisitor().id(),quest,first);
        summary();
        assertEquals(List.of(3741L,7L,179L),queue().stream().map(VoteStore.Priority::questID).toList());
        assertEquals(List.of(0L,1L,2L),queue().stream().map(VoteStore.Priority::votes).toList());
        // Personal unseen status takes precedence over global coverage.
        post(mapper.writeValueAsString(new VoteController.Ballot(3741,first,List.of(first,second))),base);
        assertEquals(List.of(7L,179L,3741L),queue().stream().map(VoteStore.Priority::questID).toList());
    }

    @Test void queueSamplesRaceSexGroupsAcrossRequestsAndIncludesPendingVotes() throws Exception {
        var secondDwarf=new Catalogue.Quest(7,quest.npc(),quest.variants());
        var orc=new Catalogue.Quest(8,new Catalogue.Npc(99,12,123,"orc","female"),quest.variants());
        var otherOrc=new Catalogue.Quest(9,orc.npc(),quest.variants());
        var quests=List.of(quest,secondDwarf,orc,otherOrc);
        Files.writeString(catalogueFile,mapper.writeValueAsString(new Catalogue.Snapshot(2,quests)));
        var store=context.getBean(VoteStore.class);
        // Coverage would put both dwarves first without group rotation.
        store.save(store.createVisitor().id(),orc,first);
        store.save(store.createVisitor().id(),otherOrc,first);
        summary();
        var initialFirsts=new HashSet<Long>();
        for(int i=0;i<40;i++) initialFirsts.add(queue().getFirst().questID());
        assertTrue(initialFirsts.stream().anyMatch(Set.of(8L,9L)::contains),"Controller must not re-sort groups by quest coverage");
        assertTrue(initialFirsts.stream().anyMatch(Set.of(179L,7L)::contains));
        post(ballot(first),base);
        assertFalse(queue().getFirst().rated());
        restart();
        assertTrue(queue().stream().filter(p->p.questID()==179).findFirst().orElseThrow().rated());
        store=context.getBean(VoteStore.class);
        var visitor=store.createVisitor();
        var pending=store.queue(visitor.id(),quests,Set.of(179L));
        assertFalse(pending.getFirst().rated());
        assertTrue(pending.stream().filter(p->p.questID()==179).findFirst().orElseThrow().rated());
    }

    @Test void validatesThreeDistinctRecordingRevisions() throws Exception {
        var current=quest.variants().getFirst();
        for (var hashes : List.of(List.of("f".repeat(64),"e".repeat(64),"d".repeat(64)),
                List.of("f".repeat(64),"f".repeat(64)), List.of("e".repeat(64)),
                List.of("f".repeat(64),"e".repeat(64),"d".repeat(64),"c".repeat(64)))) {
            quest=new Catalogue.Quest(quest.questID(),quest.npc(),List.of(new Catalogue.Variant(
                current.id(),current.source(),current.pack(),current.version(),current.sha256(),hashes),quest.variants().get(1)));
            writeCatalogue();
            if (hashes.size()==3) assertEquals(hashes,new Catalogue(catalogueFile.toString(),mapper).quests().getFirst().variants().getFirst().revisions());
            else assertThrows(Exception.class,()->new Catalogue(catalogueFile.toString(),mapper));
        }
    }

    @Test void rejectsLegacyOrInvalidSnapshotsWithoutAcceptingVotes() throws Exception {
        summary();
        String valid=Files.readString(catalogueFile);
        for (String invalid : List.of(
            valid.replace("\"schemaVersion\":2", "\"schemaVersion\":1"),
            valid.replace("\"sha256\":", "\"audioFile\":\"C:/unavailable/library/recording.ogg\",\"sha256\":"),
            valid.replace("f".repeat(64), "invalid-hash"))) {
            Files.writeString(catalogueFile,invalid);
            assertThrows(Exception.class,()->new Catalogue(catalogueFile.toString(),mapper));
            assertEquals(503,post(ballot(first),base).statusCode());
            assertEquals(0,total(summary()));
        }
        Files.writeString(catalogueFile,valid);
        assertEquals(1,total(post(ballot(first),base)));
    }
}
