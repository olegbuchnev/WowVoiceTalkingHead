package ru.talkinghead.vote;

import static org.junit.jupiter.api.Assertions.*;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.boot.SpringApplication;
import org.springframework.context.ConfigurableApplicationContext;
import tools.jackson.databind.ObjectMapper;

class AdminApiTest {
    @TempDir Path directory;
    ConfigurableApplicationContext context;
    final ObjectMapper mapper=new ObjectMapper();
    final String password="test-secret-for-admin-only-123456";
    final String first="a".repeat(24),second="b".repeat(24),hash="c".repeat(64);
    String base;
    HttpClient client;
    @BeforeEach void start() throws Exception {
        var catalogue=new Catalogue.Snapshot(2,List.of(new Catalogue.Quest(1,new Catalogue.Npc(1,2,3,"human","male"),List.of(
            new Catalogue.Variant(first,"WowVoice","WowVoice","1",hash,List.of(hash)),
            new Catalogue.Variant(second,"CatQuest","CatQuest","1",hash,List.of(hash))))));
        Files.writeString(directory.resolve("catalogue.json"),mapper.writeValueAsString(catalogue));
        Files.writeString(directory.resolve("password.txt"),password);
        context=SpringApplication.run(VoteApplication.class,"--server.port=0","--voice-vote.database="+directory.resolve("votes.sqlite"),
            "--voice-vote.catalogue="+directory.resolve("catalogue.json"),"--voice-vote.admin-password-file="+directory.resolve("password.txt"),"--spring.main.banner-mode=off");
        base="http://127.0.0.1:"+context.getEnvironment().getProperty("local.server.port");
        client=HttpClient.newBuilder().cookieHandler(new CookieManager(null,CookiePolicy.ACCEPT_ALL)).build();
    }
    @AfterEach void close() {if(context!=null)context.close();}
    HttpResponse<String> get(String path) throws Exception {return client.send(HttpRequest.newBuilder(URI.create(base+path)).GET().build(),HttpResponse.BodyHandlers.ofString());}
    HttpResponse<String> post(String path,String body,String csrf,boolean form) throws Exception {
        var request=HttpRequest.newBuilder(URI.create(base+path)).header("Origin",base).header("Content-Type",form?"application/x-www-form-urlencoded":"application/json");
        if(csrf!=null) request.header("X-CSRF-TOKEN",csrf);
        return client.send(request.POST(HttpRequest.BodyPublishers.ofString(body)).build(),HttpResponse.BodyHandlers.ofString());
    }
    String csrf() throws Exception {return mapper.readTree(get("/api/admin/session").body()).get("csrf").asString();}
    void login() throws Exception {assertEquals(200,post("/api/admin/login","username=admin&password="+password,csrf(),true).statusCode());}
    @Test void adminRequiresAuthenticationCsrfAndLogoutInvalidatesSession() throws Exception {
        assertEquals(401,get("/api/admin/dashboard").statusCode());
        assertEquals(401,get("/api/admin/visitors").statusCode());
        assertEquals(401,get("/api/admin/visitors/"+hash).statusCode());
        assertEquals(403,post("/api/admin/login","username=admin&password="+password,null,true).statusCode());
        assertEquals(401,post("/api/admin/login","username=admin&password=wrong",csrf(),true).statusCode());
        login();
        var response=get("/api/admin/dashboard?days=0");
        assertEquals(200,response.statusCode(),response.body());
        assertTrue(response.headers().firstValue("cache-control").orElseThrow().contains("no-store"));
        assertEquals(403,post("/api/admin/logout","",null,true).statusCode());
        assertEquals(200,post("/api/admin/logout","",csrf(),true).statusCode());
        assertEquals(401,get("/api/admin/dashboard").statusCode());
    }
    @Test void visitsCountOnlyConfirmedBallotsAndDeduplicatePlayback() throws Exception {
        get("/api/votes/summary");login();
        assertEquals(0,mapper.readTree(get("/api/admin/visitors?days=0").body()).get("total").asInt());
        String visit=UUID.randomUUID().toString();
        String event=mapper.writeValueAsString(new VoteController.Playback(visit,1,first));
        assertEquals(404,post("/api/votes/playback",event,null,false).statusCode());
        String ballot=mapper.writeValueAsString(new VoteController.Ballot(1,first,List.of(first,second),visit));
        assertEquals(200,post("/api/votes",ballot,null,false).statusCode());
        assertEquals(200,post("/api/votes/playback",event,null,false).statusCode());
        assertEquals(200,post("/api/votes/playback",event,null,false).statusCode());
        assertEquals(200,post("/api/votes",ballot,null,false).statusCode());
        var report=mapper.readTree(get("/api/admin/dashboard?days=0").body());
        assertEquals(1,report.get("traffic").get("pageViews").asInt());
        assertEquals(1,report.get("votes").get("total").asInt());
        var visitors=mapper.readTree(get("/api/admin/visitors?days=0").body());
        assertEquals(1,visitors.get("total").asInt());
        assertEquals(1,visitors.get("items").get(0).get("plays").asInt());
        String id=visitors.get("items").get(0).get("id").asString();
        assertEquals(1,mapper.readTree(get("/api/admin/visitors/"+id).body()).get("visits").size());
        ballot=mapper.writeValueAsString(new VoteController.Ballot(1,second,List.of(first,second),UUID.randomUUID().toString()));
        assertEquals(200,post("/api/votes",ballot,null,false).statusCode());
        report=mapper.readTree(get("/api/admin/dashboard?days=0").body());
        assertEquals(2,report.get("traffic").get("pageViews").asInt());
        assertEquals(1,report.get("votes").get("total").asInt());
    }
    @Test void loginAttemptsAreRateLimited() throws Exception {
        String token=csrf();
        for(int i=0;i<20;i++) assertEquals(401,post("/api/admin/login","username=admin&password=wrong",token,true).statusCode());
        assertEquals(429,post("/api/admin/login","username=admin&password=wrong",token,true).statusCode());
    }
    @Test void exportsRequireLoginAndReuseTheExistingResultFormats() throws Exception {
        assertEquals(401,get("/api/admin/export/results.json").statusCode());
        get("/api/votes/summary");
        assertEquals(200,post("/api/votes",mapper.writeValueAsString(new VoteController.Ballot(1,first,List.of(first,second))),null,false).statusCode());
        login();
        var result=get("/api/admin/export/results.json");
        assertEquals(200,result.statusCode());
        assertEquals(1,mapper.readTree(result.body()).get("summary").get("votes").asInt());
        assertTrue(result.headers().firstValue("content-disposition").orElseThrow().contains("attachment"));
        assertFalse(result.body().contains("visitor_id"));
        for(String file:List.of("quests.csv","race-sex.csv","pairwise.csv")) assertEquals(200,get("/api/admin/export/"+file).statusCode());
        var zip=client.send(HttpRequest.newBuilder(URI.create(base+"/api/admin/export/results.zip")).GET().build(),HttpResponse.BodyHandlers.ofByteArray());
        assertEquals(200,zip.statusCode());
        var names=new HashSet<String>();
        try(var entries=new java.util.zip.ZipInputStream(new java.io.ByteArrayInputStream(zip.body()))) {
            for(var entry=entries.getNextEntry();entry!=null;entry=entries.getNextEntry()) names.add(entry.getName());
        }
        assertEquals(Set.of("results.json","quests.csv","race-sex.csv","pairwise.csv"),names);
        assertEquals(404,get("/api/admin/export/unknown.csv").statusCode());
    }
}
