package ru.talkinghead.vote;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.sql.*;
import java.util.*;
import tools.jackson.databind.ObjectMapper;

/** Two bounded evidence layers; all mutations share the ballot transaction. */
final class RankingHistory {
    static final double DECAY = 0.98;
    private final Connection db;
    private final ObjectMapper mapper;
    record Identity(String pool, String revision, int mask) {}
    record State(String pool, String revision, long generation) {}

    RankingHistory(Connection db, ObjectMapper mapper) { this.db=db;this.mapper=mapper; }

    private int update(String sql,Object... args) throws SQLException {
        try(var statement=db.prepareStatement(sql)) {
            for(int i=0;i<args.length;i++) statement.setObject(i+1,args[i]);
            statement.execute();return statement.getUpdateCount();
        }
    }
    private String hash(Object value) {
        return Catalogue.hash(mapper.writeValueAsString(value).getBytes(StandardCharsets.UTF_8));
    }
    Identity identity(Catalogue.Quest quest) {
        int mask=0;var files=new TreeMap<String,String>();
        for(var v:quest.variants()) {
            mask|=1<<AddonRanking.SOURCES.indexOf(v.source());files.put(v.source(),v.sha256());
        }
        var npc=quest.npc();
        String pool=hash(new Object[]{quest.questID(),"a",npc.id(),npc.race(),npc.sex(),mask});
        return new Identity(pool,hash(new Object[]{pool,files}),mask);
    }
    void migrate(Path path) throws Exception {
        try(var statement=db.createStatement();var rows=statement.executeQuery("PRAGMA user_version")) {
            if(rows.next() && rows.getInt(1)==4) return;
        }
        try(var statement=db.createStatement()) {
            // The backup also covers databases with no active ballots but existing analytics.
            statement.execute("VACUUM INTO '"+path.resolveSibling(path.getFileName()+".before-ranking-layers-"+UUID.randomUUID()+".sqlite").toString().replace("'","''")+"'");
        }
        db.setAutoCommit(false);
        try {
            var columns=new HashSet<String>();
            try(var s=db.createStatement();var rows=s.executeQuery("PRAGMA table_info(votes)")) {
                while(rows.next()) columns.add(rows.getString("name"));
            }
            for(String definition:List.of("ranking_weight REAL NOT NULL DEFAULT 1.0",
                "ranking_current INTEGER NOT NULL DEFAULT 0", "ranking_generation INTEGER NOT NULL DEFAULT 0",
                "ranking_pool TEXT NOT NULL DEFAULT ''", "ranking_revision TEXT NOT NULL DEFAULT ''",
                "ranking_mask INTEGER NOT NULL DEFAULT 0")) {
                if(!columns.contains(definition.split(" ")[0])) update("ALTER TABLE votes ADD COLUMN "+definition);
            }
            update("""
                CREATE TABLE IF NOT EXISTS ranking_state (
                    quest_id INTEGER PRIMARY KEY, pool TEXT NOT NULL, revision TEXT NOT NULL,
                    generation INTEGER NOT NULL
                ) STRICT
                """);
            update("""
                CREATE TABLE IF NOT EXISTS ranking_layers (
                    pool TEXT NOT NULL, source TEXT NOT NULL, quest_id INTEGER NOT NULL,
                    stage TEXT NOT NULL, npc_id INTEGER NOT NULL, race TEXT, sex TEXT,
                    mask INTEGER NOT NULL, historical REAL NOT NULL, current REAL NOT NULL,
                    PRIMARY KEY(pool,source)
                ) STRICT
                """);
            update("CREATE INDEX IF NOT EXISTS votes_ranking_pool ON votes(ranking_pool,ranking_current)");
            update("CREATE INDEX IF NOT EXISTS ranking_layers_quest ON ranking_layers(quest_id)");
            var quests=new HashSet<Long>();
            try(var s=db.createStatement();var rows=s.executeQuery("SELECT v.rowid AS vote_row,v.*,c.npc_id,c.race,c.sex FROM votes v JOIN comparisons c ON c.id=v.comparison_id")) {
                while(rows.next()) {
                    var variants=new ArrayList<Catalogue.Variant>();
                    for(var v:mapper.readTree(rows.getString("candidates_json"))) variants.add(new Catalogue.Variant(
                        v.required("id").asString(),v.required("source").asString(),"","",v.required("sha256").asString(),List.of()));
                    long quest=rows.getLong("quest_id");quests.add(quest);
                    var identity=identity(new Catalogue.Quest(quest,new Catalogue.Npc(rows.getLong("npc_id"),0,0,rows.getString("race"),rows.getString("sex")),variants));
                    update("UPDATE votes SET ranking_pool=?,ranking_revision=?,ranking_mask=?,ranking_weight=1.0,ranking_current=0,ranking_generation=0 WHERE rowid=?",
                        identity.pool(),identity.revision(),identity.mask(),rows.getLong("vote_row"));
                }
            }
            update("DELETE FROM ranking_state");update("DELETE FROM ranking_layers");
            for(long quest:quests) rebuild(quest);
            update("PRAGMA user_version=4");db.commit();
        } catch(Exception error) {db.rollback();throw error;}
        finally {db.setAutoCommit(true);}
    }
    State state(long quest) throws SQLException {
        try(var s=db.prepareStatement("SELECT pool,revision,generation FROM ranking_state WHERE quest_id=?")) {
            s.setLong(1,quest);try(var r=s.executeQuery()) {return r.next()?new State(r.getString(1),r.getString(2),r.getLong(3)):null;}
        }
    }
    void synchronize(List<Catalogue.Quest> quests) throws SQLException {
        var present=new HashSet<Long>();
        for(var quest:quests) {present.add(quest.questID());activate(quest);}
        var removed=new ArrayList<Long>();
        try(var s=db.createStatement();var r=s.executeQuery("SELECT quest_id FROM ranking_state WHERE revision<>''")) {
            while(r.next()) if(!present.contains(r.getLong(1))) removed.add(r.getLong(1));
        }
        for(long id:removed) {
            update("UPDATE ranking_state SET revision='',generation=generation+1 WHERE quest_id=?",id);
            update("UPDATE votes SET ranking_current=0 WHERE quest_id=?",id);rebuild(id);
        }
    }
    void activate(Catalogue.Quest quest) throws SQLException {
        var identity=identity(quest);var state=state(quest.questID());
        if(state!=null && state.revision().equals(identity.revision())) return;
        long generation=state==null?1:state.generation()+1;
        update("INSERT INTO ranking_state VALUES (?,?,?,?) ON CONFLICT(quest_id) DO UPDATE SET pool=excluded.pool,revision=excluded.revision,generation=excluded.generation",
            quest.questID(),identity.pool(),identity.revision(),generation);
        update("UPDATE votes SET ranking_current=0 WHERE quest_id=?",quest.questID());
        if(state==null) {
            // Migration baseline only. Returning to old files must never restore lost weight.
            update("UPDATE votes SET ranking_current=1,ranking_generation=? WHERE quest_id=? AND ranking_revision=? AND ranking_generation=0",
                generation,quest.questID(),identity.revision());
        }
        rebuild(quest.questID());
    }
    record Previous(long order,long generation,boolean current) {}
    Previous previous(String visitor,long quest) throws SQLException {
        try(var s=db.prepareStatement("SELECT accepted_order,ranking_generation,ranking_current FROM votes WHERE visitor_id=? AND quest_id=? AND stage='a'")) {
            s.setString(1,visitor);s.setLong(2,quest);
            try(var r=s.executeQuery()) {return r.next()?new Previous(r.getLong(1),r.getLong(2),r.getInt(3)==1):null;}
        }
    }
    void beforeVote(String visitor,Catalogue.Quest quest,Previous previous) throws SQLException {
        var identity=identity(quest);var state=state(quest.questID());
        boolean current=state!=null && state.revision().equals(identity.revision());
        if(current && (previous==null || !previous.current() || previous.generation()!=state.generation())) {
            // Exclude the replaced ballot before decaying the remaining historical evidence.
            update("UPDATE votes SET ranking_weight=ranking_weight*? WHERE ranking_pool=? AND ranking_current=0 AND visitor_id<>?",
                DECAY,identity.pool(),visitor);
        }
    }
    void afterVote(String visitor,Catalogue.Quest quest) throws SQLException {
        var identity=identity(quest);var state=state(quest.questID());
        boolean current=state!=null && state.revision().equals(identity.revision());
        update("UPDATE votes SET ranking_weight=1.0,ranking_current=?,ranking_generation=?,ranking_pool=?,ranking_revision=?,ranking_mask=? WHERE visitor_id=? AND quest_id=? AND stage='a'",
            current?1:0,current?state.generation():0,identity.pool(),identity.revision(),identity.mask(),visitor,quest.questID());
        rebuild(quest.questID());
    }
    private void rebuild(long quest) throws SQLException {
        update("DELETE FROM ranking_layers WHERE quest_id=?",quest);
        update("""
            INSERT INTO ranking_layers
            SELECT v.ranking_pool,v.source,v.quest_id,v.stage,c.npc_id,c.race,c.sex,v.ranking_mask,
                SUM(CASE WHEN v.ranking_current=0 THEN v.ranking_weight ELSE 0.0 END),
                SUM(CASE WHEN v.ranking_current=1 THEN v.ranking_weight ELSE 0.0 END)
            FROM votes v JOIN comparisons c ON c.id=v.comparison_id WHERE v.quest_id=?
            GROUP BY v.ranking_pool,v.source,v.quest_id,v.stage,c.npc_id,c.race,c.sex,v.ranking_mask
            """,quest);
    }
}
