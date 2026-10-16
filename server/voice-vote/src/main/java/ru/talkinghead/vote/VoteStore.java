package ru.talkinghead.vote;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.time.Instant;
import java.util.HexFormat;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import jakarta.annotation.PreDestroy;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import tools.jackson.databind.ObjectMapper;

@Component
public class VoteStore implements AutoCloseable {
    public record Visitor(String token, String id) {}
    public record Summary(Map<String, Long> counts, long total) {}
    public record Saved(String comparisonID, String selected, Map<String, Long> counts, long total) {}
    public record Priority(long questID, boolean rated, long votes) {}
    private final Connection db;
    private final String databaseUrl;
    private final java.util.concurrent.Semaphore readers=new java.util.concurrent.Semaphore(8,true);
    private volatile IdentityCache identities;
    private volatile Summary communityCache;
    private record ActiveChoice(String visitor,long questID,String stage) {}
    private final Map<ActiveChoice,String> communityChoices=new HashMap<>();
    private record IdentityCache(List<Catalogue.Quest> quests, Map<Long,String> ids) {}
    private final ObjectMapper mapper;
    private final java.util.concurrent.atomic.AtomicLong voteOrder = new java.util.concurrent.atomic.AtomicLong();

    public VoteStore(@Value("${voice-vote.database}") String file, ObjectMapper mapper) throws Exception {
        this.mapper = mapper;
        Path path = Path.of(file).toAbsolutePath().normalize();
        Files.createDirectories(path.getParent());
        databaseUrl="jdbc:sqlite:"+path;
        db = DriverManager.getConnection(databaseUrl);
        execute("PRAGMA foreign_keys=ON"); execute("PRAGMA busy_timeout=5000"); execute("PRAGMA journal_mode=WAL");
        try (var statement = db.createStatement(); var row = statement.executeQuery("PRAGMA user_version")) {
            if (row.next() && row.getInt(1) > 3) throw new SQLException("Unsupported voting schema version");
        }
        execute("CREATE TABLE IF NOT EXISTS visitors (id TEXT PRIMARY KEY, created_at TEXT NOT NULL) STRICT");
        execute("""
            CREATE TABLE IF NOT EXISTS comparisons (
                id TEXT PRIMARY KEY, quest_id INTEGER NOT NULL, stage TEXT NOT NULL,
                npc_id INTEGER NOT NULL, display_id INTEGER NOT NULL, model_file_id INTEGER NOT NULL,
                race TEXT, sex TEXT, created_at TEXT NOT NULL
            ) STRICT
            """);
        execute("""
            CREATE TABLE IF NOT EXISTS votes (
                visitor_id TEXT NOT NULL REFERENCES visitors(id), comparison_id TEXT NOT NULL REFERENCES comparisons(id),
                selected_id TEXT NOT NULL, source TEXT NOT NULL, pack TEXT NOT NULL, sha256 TEXT NOT NULL,
                library_version TEXT NOT NULL, candidates_json TEXT NOT NULL,
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                PRIMARY KEY (visitor_id, comparison_id)
            ) STRICT
            """);
        execute("CREATE INDEX IF NOT EXISTS comparisons_speaker ON comparisons(race,sex,model_file_id)");
        execute("CREATE INDEX IF NOT EXISTS votes_comparison ON votes(comparison_id)");
        execute("CREATE TABLE IF NOT EXISTS analytics_meta (key TEXT PRIMARY KEY,value TEXT NOT NULL) STRICT");
        update("INSERT OR IGNORE INTO analytics_meta VALUES ('since',?)",Instant.now().toString());
        execute("""
            CREATE TABLE IF NOT EXISTS visits (
                id TEXT PRIMARY KEY, visitor_id TEXT NOT NULL REFERENCES visitors(id),
                opened_at TEXT NOT NULL, started_at TEXT, last_seen TEXT NOT NULL, referrer TEXT NOT NULL
            ) STRICT
            """);
        execute("CREATE INDEX IF NOT EXISTS visits_visitor ON visits(visitor_id,opened_at)");
        execute("CREATE INDEX IF NOT EXISTS visits_opened ON visits(opened_at)");
        execute("""
            CREATE TABLE IF NOT EXISTS plays (
                visit_id TEXT NOT NULL REFERENCES visits(id), recording_id TEXT NOT NULL,
                quest_id INTEGER NOT NULL, source TEXT NOT NULL, played_at TEXT NOT NULL,
                PRIMARY KEY(visit_id,recording_id)
            ) STRICT
            """);
        execute("""
            CREATE TABLE IF NOT EXISTS visit_votes (
                visit_id TEXT NOT NULL REFERENCES visits(id), comparison_id TEXT NOT NULL REFERENCES comparisons(id),
                updated_at TEXT NOT NULL, PRIMARY KEY(visit_id,comparison_id)
            ) STRICT
            """);
        execute("CREATE INDEX IF NOT EXISTS votes_created ON votes(created_at)");
        execute("CREATE INDEX IF NOT EXISTS votes_visitor_created ON votes(visitor_id,created_at)");
        execute("CREATE INDEX IF NOT EXISTS votes_visitor_updated ON votes(visitor_id,updated_at)");
        execute("CREATE INDEX IF NOT EXISTS visits_visitor_seen ON visits(visitor_id,last_seen)");
        migrateActiveVotes(path);
        try (var statement=db.createStatement();var rows=statement.executeQuery("SELECT COALESCE(MAX(accepted_order),0) FROM votes")) {
            rows.next();voteOrder.set(Math.max(System.currentTimeMillis(),rows.getLong(1)));
        }
        // Warm the aggregate before the application accepts HTTP requests.
        warmCommunitySummary();
    }
    private void migrateActiveVotes(Path path) throws Exception {
        try(var statement=db.createStatement();var rows=statement.executeQuery("PRAGMA user_version")) {
            if(rows.next() && rows.getInt(1)==3) return;
        }
        long count;
        try(var statement=db.createStatement();var rows=statement.executeQuery("SELECT COUNT(*) FROM votes")) {rows.next();count=rows.getLong(1);}
        if(count>0) {
            Path backup=path.resolveSibling(path.getFileName()+".before-active-votes-"+java.util.UUID.randomUUID()+".sqlite");
            execute("VACUUM INTO '"+backup.toString().replace("'","''")+"'");
        }
        db.setAutoCommit(false);
        try {
            execute("ALTER TABLE votes ADD COLUMN quest_id INTEGER NOT NULL DEFAULT 0");
            execute("ALTER TABLE votes ADD COLUMN stage TEXT NOT NULL DEFAULT 'a'");
            execute("ALTER TABLE votes ADD COLUMN accepted_order INTEGER NOT NULL DEFAULT 0");
            execute("UPDATE votes SET quest_id=(SELECT quest_id FROM comparisons WHERE id=comparison_id),stage=(SELECT stage FROM comparisons WHERE id=comparison_id)");
            for(var row:rows(db,"SELECT visitor_id,comparison_id,updated_at FROM votes"))
                update("UPDATE votes SET accepted_order=? WHERE visitor_id=? AND comparison_id=?",
                    Instant.parse((String)row.get("updated_at")).toEpochMilli(),row.get("visitor_id"),row.get("comparison_id"));
            execute("""
                DELETE FROM votes WHERE rowid NOT IN (
                  SELECT rowid FROM (SELECT rowid,ROW_NUMBER() OVER (
                    PARTITION BY visitor_id,quest_id,stage ORDER BY julianday(updated_at) DESC,comparison_id DESC) AS position FROM votes)
                  WHERE position=1)
                """);
            execute("CREATE UNIQUE INDEX votes_active_quest ON votes(visitor_id,quest_id,stage)");
            execute("PRAGMA user_version=3");
            db.commit();
        } catch(Exception error) {db.rollback();throw error;}
        finally {db.setAutoCommit(true);}
    }
    long nextVoteOrder() {return voteOrder.updateAndGet(previous->Math.max(previous+1,System.currentTimeMillis()));}
    void observeVoteOrder(long order) {voteOrder.accumulateAndGet(order,Math::max);}
    private void execute(String sql) throws SQLException {
        try (var statement = db.createStatement()) { statement.execute(sql); }
    }
    private int update(String sql, Object... values) throws SQLException {
        try (var statement = db.prepareStatement(sql)) {
            for (int i = 0; i < values.length; i++) statement.setObject(i + 1, values[i]);
            return statement.executeUpdate();
        }
    }
    private static String hash(String value) { return Catalogue.hash(value.getBytes(StandardCharsets.UTF_8)); }
    public synchronized Visitor createVisitor() throws SQLException {
        byte[] bytes = new byte[32]; new SecureRandom().nextBytes(bytes);
        String token = HexFormat.of().formatHex(bytes), id = hash(token);
        update("INSERT INTO visitors(id,created_at) VALUES (?,?)", id, Instant.now().toString());
        return new Visitor(token, id);
    }
    public String visitor(String token) throws SQLException {
        if (token == null || !token.matches("[a-f0-9]{64}")) return null;
        var result=rows("SELECT id FROM visitors WHERE id=?",hash(token));
        return result.isEmpty() ? null : (String)result.getFirst().get("id");
    }
    public Summary summary(String visitor) throws SQLException {
        return summarize(rows("SELECT source,COUNT(*) AS count FROM votes WHERE visitor_id=? GROUP BY source",visitor));
    }
    public Summary communitySummary() {
        return communityCache;
    }
    private void warmCommunitySummary() throws SQLException {
        var counts=new LinkedHashMap<String,Long>();
        for(String name:List.of("WowVoice","CatQuest","Wayfarer")) counts.put(name,0L);
        for(var row:rows(db,"SELECT visitor_id,quest_id,stage,source FROM votes")) {
            String source=(String)row.get("source");
            communityChoices.put(new ActiveChoice((String)row.get("visitor_id"),((Number)row.get("quest_id")).longValue(),(String)row.get("stage")),source);
            counts.computeIfPresent(source,(name,count)->count+1);
        }
        communityCache=immutableSummary(counts);
    }
    private void committedChoice(String visitor,long questID,String source) {
        // Called only under the writer monitor, after the SQLite commit succeeds.
        String previous=communityChoices.put(new ActiveChoice(visitor,questID,"a"),source);
        if(source.equals(previous)) return;
        var counts=new LinkedHashMap<>(communityCache.counts());
        if(previous!=null) counts.computeIfPresent(previous,(name,count)->count-1);
        counts.computeIfPresent(source,(name,count)->count+1);
        communityCache=immutableSummary(counts);
    }
    private Summary immutableSummary(Map<String,Long> counts) {
        return new Summary(java.util.Collections.unmodifiableMap(counts),counts.values().stream().mapToLong(Long::longValue).sum());
    }
    private Summary summarize(List<Map<String,Object>> totals) {
        Map<String, Long> counts = new LinkedHashMap<>();
        for (String name : List.of("WowVoice", "CatQuest", "Wayfarer")) counts.put(name, 0L);
        for(var row:totals)
            if(counts.containsKey(row.get("source"))) counts.put((String)row.get("source"),((Number)row.get("count")).longValue());
        return immutableSummary(counts);
    }
    static String comparisonID(Catalogue.Quest quest, ObjectMapper mapper) {
        // Recording IDs encode file path, library and bytes. A release number
        // change alone must not turn the same recording into a new comparison.
        String identity = mapper.writeValueAsString(new Object[]{quest.questID(), "a", quest.npc(),
            quest.variants().stream().map(Catalogue.Variant::id).sorted().toList()});
        return hash(identity);
    }
    public List<Priority> queue(String visitor, List<Catalogue.Quest> quests) throws SQLException {
        return queue(visitor, quests, java.util.Set.of());
    }
    public List<Priority> queue(String visitor, List<Catalogue.Quest> quests, java.util.Set<Long> pending) throws SQLException {
        var counts = new HashMap<String, Long>();
        var rated = new HashMap<String, Instant>();
        var speakers=AddonRanking.speakers(quests);
        var votedGroups=new java.util.HashSet<AddonRanking.Key>();
        // Group coverage includes retained old recordings, just like the ranking.
        for(var row:rows("""
            SELECT v.comparison_id,c.quest_id,c.stage,c.npc_id,c.race,c.sex,COUNT(*) AS count
            FROM votes v JOIN comparisons c ON c.id=v.comparison_id
            GROUP BY v.comparison_id,c.quest_id,c.stage,c.npc_id,c.race,c.sex
            """)) {
            counts.put((String)row.get("comparison_id"),((Number)row.get("count")).longValue());
            var group=AddonRanking.eligibleGroup(speakers.get(((Number)row.get("quest_id")).longValue()),
                ((Number)row.get("npc_id")).longValue(),(String)row.get("race"),(String)row.get("sex"),(String)row.get("stage"));
            if(group!=null) votedGroups.add(group);
        }
        for(var row:rows("SELECT comparison_id,updated_at FROM votes WHERE visitor_id=?",visitor))
            rated.put((String)row.get("comparison_id"), Instant.parse((String)row.get("updated_at")));
        var cache=identities;
        if(cache==null || cache.quests()!=quests) {
            // This lock protects only catalogue-derived data, never database IO.
            synchronized(readers) {
                cache=identities;
                if(cache==null || cache.quests()!=quests) {
                    var ids=new HashMap<Long,String>();
                    for(var quest:quests) ids.put(quest.questID(),comparisonID(quest,mapper));
                    cache=new IdentityCache(quests,Map.copyOf(ids));identities=cache;
                }
            }
        }
        // Historical recording revisions must not inflate current coverage.
        var result = new ArrayList<ComparisonQueue.Candidate>();
        for (var quest : quests) {
            String id = cache.ids().get(quest.questID());
            boolean accepted = pending.contains(quest.questID());
            var group=AddonRanking.key(quest.npc());
            result.add(new ComparisonQueue.Candidate(
                new Priority(quest.questID(), accepted || rated.containsKey(id), counts.getOrDefault(id, 0L)),
                quest.npc(), accepted ? Instant.MAX : rated.get(id),group!=null && !votedGroups.contains(group)));
        }
        return ComparisonQueue.order(result);
    }
    public synchronized Saved save(String visitor, Catalogue.Quest quest, String selectedId) throws SQLException {
        return save(visitor,quest,selectedId,null);
    }
    public synchronized Saved save(String visitor, Catalogue.Quest quest, String selectedId, String visitID) throws SQLException {
        return save(visitor,quest,selectedId,visitID,nextVoteOrder());
    }
    public synchronized Saved save(String visitor, Catalogue.Quest quest, String selectedId, String visitID,long acceptedOrder) throws SQLException {
        observeVoteOrder(acceptedOrder);
        var selected = quest.variants().stream().filter(v -> v.id().equals(selectedId)).findFirst().orElseThrow();
        var npc = quest.npc();
        String comparison = comparisonID(quest, mapper), now = Instant.now().toString();
        String candidates = mapper.writeValueAsString(quest.variants().stream().map(v -> Map.of(
            "id", v.id(), "source", v.source(), "pack", v.pack(), "version", v.version(), "sha256", v.sha256())).toList());
        db.setAutoCommit(false);
        try {
            update("INSERT OR IGNORE INTO comparisons VALUES (?,?,?,?,?,?,?,?,?)", comparison, quest.questID(), "a",
                npc.id(), npc.displayID(), npc.modelFileID(), npc.race(), npc.sex(), now);
            int changed=update("""
                INSERT INTO votes (visitor_id,comparison_id,selected_id,source,pack,sha256,library_version,candidates_json,created_at,updated_at,quest_id,stage,accepted_order)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(visitor_id,quest_id,stage) DO UPDATE SET
                    comparison_id=excluded.comparison_id, accepted_order=excluded.accepted_order,
                    selected_id=excluded.selected_id, source=excluded.source, pack=excluded.pack,
                    sha256=excluded.sha256, library_version=excluded.library_version,
                    candidates_json=excluded.candidates_json, updated_at=excluded.updated_at
                WHERE excluded.accepted_order > votes.accepted_order
                """, visitor, comparison, selected.id(), selected.source(), selected.pack(), selected.sha256(),
                selected.version(), candidates, now, now,quest.questID(),"a",acceptedOrder);
            if (visitID!=null) {
                update("INSERT OR IGNORE INTO visits VALUES (?,?,?, ?,?,?)",visitID,visitor,now,now,now,"direct");
                if(!ownsVisit(visitor,visitID)) throw new org.springframework.web.server.ResponseStatusException(org.springframework.http.HttpStatus.CONFLICT,"Visit belongs to another visitor");
                update("INSERT INTO visit_votes VALUES (?,?,?) ON CONFLICT(visit_id,comparison_id) DO UPDATE SET updated_at=excluded.updated_at",visitID,comparison,now);
                update("UPDATE visits SET last_seen=? WHERE id=?",now,visitID);
            }
            db.commit();
            // Rejected, rolled-back and obsolete inbox deliveries leave the cache intact.
            if(changed>0) committedChoice(visitor,quest.questID(),selected.source());
        } catch (Exception e) { db.rollback(); throw e; }
        finally { db.setAutoCommit(true); }
        var summary = summarize(rows(db,"SELECT source,COUNT(*) AS count FROM votes WHERE visitor_id=? GROUP BY source",visitor));
        return new Saved(comparison, selected.source(), summary.counts(), summary.total());
    }
    private List<Map<String,Object>> rows(String sql,Object... args) throws SQLException {
        try { readers.acquire(); }
        catch(InterruptedException e) {Thread.currentThread().interrupt();throw new SQLException("Interrupted while waiting for a read connection",e);}
        try(var connection=DriverManager.getConnection(databaseUrl)) {
            try(var statement=connection.createStatement()) {
                statement.execute("PRAGMA query_only=ON");
                statement.execute("PRAGMA busy_timeout=5000");
            }
            return rows(connection,sql,args);
        } finally {readers.release();}
    }
    private List<Map<String,Object>> rows(Connection connection,String sql,Object... args) throws SQLException {
        var result=new ArrayList<Map<String,Object>>();
        try(var statement=connection.prepareStatement(sql)) {
            for(int i=0;i<args.length;i++) statement.setObject(i+1,args[i]);
            try(var rows=statement.executeQuery()) {
                while(rows.next()) {
                    var row=new LinkedHashMap<String,Object>();
                    for(int i=1;i<=rows.getMetaData().getColumnCount();i++) row.put(rows.getMetaData().getColumnLabel(i),rows.getObject(i));
                    result.add(row);
                }
            }
        }
        return result;
    }
    private boolean ownsVisit(String visitor,String visit) throws SQLException {
        return !rows(db,"SELECT id FROM visits WHERE id=? AND visitor_id=?",visit,visitor).isEmpty();
    }
    public void validateVisit(String visitor,String visit) throws SQLException {
        if(visit==null) return;
        var existing=rows("SELECT visitor_id FROM visits WHERE id=?",visit);
        if(!existing.isEmpty() && !existing.getFirst().get("visitor_id").equals(visitor))
            throw new org.springframework.web.server.ResponseStatusException(org.springframework.http.HttpStatus.CONFLICT,"Visit belongs to another visitor.");
    }
    public synchronized void visit(String visitor,String id,String event,String referrer,Catalogue.Quest quest,String recording) throws SQLException {
        String now=Instant.now().toString();
        if(!ownsVisit(visitor,id)) throw new org.springframework.web.server.ResponseStatusException(org.springframework.http.HttpStatus.NOT_FOUND,"Visit not found.");
        if(event.equals("play")) {
            var variant=quest.variants().stream().filter(v->v.id().equals(recording)).findFirst().orElseThrow();
            update("INSERT OR IGNORE INTO plays VALUES (?,?,?,?,?)",id,recording,quest.questID(),variant.source(),now);
            update("UPDATE visits SET last_seen=? WHERE id=?",now,id);
        }
    }
    public Map<String,Object> dashboard(String since) throws SQLException {
        var result=new LinkedHashMap<String,Object>();
        result.put("analyticsSince",rows("SELECT value FROM analytics_meta WHERE key='since'").getFirst().get("value"));
        result.put("traffic",rows("""
            SELECT COUNT(*) AS pageViews,COUNT(DISTINCT visitor_id) AS visitors,
                COALESCE(SUM(started_at IS NOT NULL),0) AS startedVisits,
                (SELECT COUNT(DISTINCT visitor_id) FROM visits JOIN visit_votes ON visits.id=visit_votes.visit_id WHERE opened_at>=?) AS votingVisitors
            FROM visits WHERE opened_at>=?
            """,since,since).getFirst());
        result.put("votes",rows("""
            SELECT COUNT(*) AS total,(SELECT COUNT(*) FROM (
                SELECT visitor_id FROM visits WHERE opened_at>=?
                UNION SELECT visitor_id FROM votes WHERE created_at>=?
            )) AS voters FROM votes WHERE created_at>=?
            """,since,since,since).getFirst());
        result.put("libraries",rows("SELECT source,COUNT(*) AS votes FROM votes WHERE created_at>=? GROUP BY source ORDER BY votes DESC",since));
        result.put("daily",rows("""
            WITH days AS (SELECT substr(opened_at,1,10) AS day FROM visits WHERE opened_at>=?
                UNION SELECT substr(created_at,1,10) FROM votes WHERE created_at>=?)
            SELECT day,(SELECT COUNT(*) FROM visits WHERE substr(opened_at,1,10)=day) AS pageViews,
                (SELECT COUNT(DISTINCT visitor_id) FROM visits WHERE substr(opened_at,1,10)=day) AS visitors,
                (SELECT COUNT(*) FROM votes WHERE substr(created_at,1,10)=day) AS votes FROM days ORDER BY day
            """,since,since));
        result.put("referrers",rows("SELECT referrer,COUNT(*) AS visits FROM visits WHERE opened_at>=? GROUP BY referrer ORDER BY visits DESC LIMIT 20",since));
        return result;
    }
    public Map<String,Object> adminVisitors(String since,int offset,String search) throws SQLException {
        String filter=" WHERE id LIKE ? AND (EXISTS(SELECT 1 FROM visits s WHERE s.visitor_id=v.id AND s.opened_at>=?) OR EXISTS(SELECT 1 FROM votes b WHERE b.visitor_id=v.id AND b.created_at>=?))";
        var result=new LinkedHashMap<String,Object>();
        result.put("total",rows("SELECT COUNT(*) AS total FROM visitors v"+filter,search+"%",since,since).getFirst().get("total"));
        result.put("items",rows("""
            SELECT id,created_at AS firstSeen,
                MAX(COALESCE((SELECT MAX(last_seen) FROM visits WHERE visitor_id=v.id),created_at),
                    COALESCE((SELECT MAX(updated_at) FROM votes WHERE visitor_id=v.id),created_at)) AS lastSeen,
                (SELECT COUNT(*) FROM visits WHERE visitor_id=v.id AND opened_at>=?) AS visits,
                (SELECT COUNT(*) FROM votes WHERE visitor_id=v.id AND created_at>=?) AS votes,
                (SELECT COUNT(*) FROM votes WHERE visitor_id=v.id) AS lifetimeVotes,
                (SELECT COUNT(*) FROM plays p JOIN visits s ON s.id=p.visit_id WHERE s.visitor_id=v.id AND s.opened_at>=?) AS plays
            FROM visitors v
            """+filter+" ORDER BY lastSeen DESC,id LIMIT 30 OFFSET ?",since,since,since,search+"%",since,since,offset));
        return result;
    }
    public Map<String,Object> adminVisitor(String id,int offset) throws SQLException {
        var result=new LinkedHashMap<String,Object>();
        result.put("visitor",rows("SELECT id,created_at AS firstSeen FROM visitors WHERE id=?",id));
        result.put("summary",summary(id));
        result.put("visits",rows("""
            SELECT id,opened_at AS openedAt,started_at AS startedAt,last_seen AS lastSeen,referrer,
                (SELECT COUNT(*) FROM plays WHERE visit_id=s.id) AS plays,
                (SELECT COUNT(*) FROM visit_votes WHERE visit_id=s.id) AS votes
            FROM visits s WHERE visitor_id=? ORDER BY opened_at DESC LIMIT 30
            """,id));
        result.put("votes",rows("""
            SELECT c.quest_id AS questID,c.race,c.sex,v.source,v.library_version AS version,v.sha256,
                v.created_at AS createdAt,v.updated_at AS updatedAt
            FROM votes v JOIN comparisons c ON c.id=v.comparison_id WHERE v.visitor_id=?
            ORDER BY v.updated_at DESC LIMIT 30 OFFSET ?
            """,id,offset));
        return result;
    }
    @Override @PreDestroy public synchronized void close() throws SQLException { db.close(); }
}
