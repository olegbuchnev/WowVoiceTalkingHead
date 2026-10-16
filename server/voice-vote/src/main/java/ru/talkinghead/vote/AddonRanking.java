package ru.talkinghead.vote;

import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.sql.DriverManager;
import java.time.Instant;
import java.util.*;
import org.sqlite.SQLiteConfig;
import tools.jackson.databind.ObjectMapper;

/** Regularized Luce top-1 estimates from the latest ballot per visitor and quest. */
public final class AddonRanking {
    static final List<String> SOURCES=List.of("WowVoice","CatQuest","Wayfarer");
    public record Place(int rank,String source,String basis) {}
    public record Group(String speakerType,String race,String sex,String status,List<Place> ranking) {}
    public record Snapshot(int schemaVersion,String generatedAt,List<Group> groups) {}
    public record Export(String json,String importString) {}
    record Key(String race,String sex) implements Comparable<Key> {
        public int compareTo(Key other) {int c=race.compareTo(other.race);return c!=0?c:sex.compareTo(other.sex);}
    }
    static Key key(Catalogue.Npc npc) {
        return npc.id()>0 && npc.race()!=null && !npc.race().isBlank() && Set.of("male","female").contains(Objects.toString(npc.sex(),""))
            ? new Key(npc.race(),npc.sex()):null;
    }
    private static final class SharedSpeakers {
        static final Map<Long,Catalogue.Quest> QUESTS=load();
        private static Map<Long,Catalogue.Quest> load() {
            var result=new HashMap<Long,Catalogue.Quest>();var mapper=new ObjectMapper();
            try(var resource=AddonRanking.class.getResourceAsStream("/ranking-speakers.json")) {
                if(resource!=null) for(var node:mapper.readTree(resource)) {
                    long id=node.required("questID").asLong();
                    result.put(id,new Catalogue.Quest(id,mapper.treeToValue(node.required("npc"),Catalogue.Npc.class),List.of()));
                }
            } catch(Exception error) {throw new IllegalStateException("Cannot load shared ranking speakers",error);}
            return Map.copyOf(result);
        }
    }
    static Map<Long,Catalogue.Quest> speakers(List<Catalogue.Quest> current) {
        var result=new HashMap<>(SharedSpeakers.QUESTS);
        for(var quest:current) result.put(quest.questID(),quest);
        return result;
    }
    static Key eligibleGroup(Catalogue.Quest quest,long npcID,String race,String sex,String stage) {
        if(quest==null || !"a".equals(stage)) return null;
        var group=key(quest.npc());
        return group!=null && quest.npc().id()==npcID && group.race().equals(race) && group.sex().equals(sex)?group:null;
    }
    static double objective(double[] s,long[][] counts,double[] gradient,double[][] hessian) {
        double value=0;
        for(int i=0;i<3;i++) {value+=s[i]*s[i]/2;if(gradient!=null) {gradient[i]=s[i];Arrays.fill(hessian[i],0);hessian[i][i]=1;}}
        for(int mask:new int[]{3,5,6,7}) {
            long total=Arrays.stream(counts[mask]).sum();if(total==0) continue;
            double max=-Double.MAX_VALUE,sum=0;double[] p=new double[3];
            for(int i=0;i<3;i++) if((mask&(1<<i))!=0) max=Math.max(max,s[i]);
            for(int i=0;i<3;i++) if((mask&(1<<i))!=0) {p[i]=Math.exp(s[i]-max);sum+=p[i];}
            value+=total*(max+Math.log(sum));
            for(int i=0;i<3;i++) {p[i]/=sum;value-=counts[mask][i]*s[i];}
            if(gradient!=null) for(int i=0;i<3;i++) {
                gradient[i]+=total*p[i]-counts[mask][i];
                for(int j=0;j<3;j++) hessian[i][j]+=total*p[i]*((i==j?1:0)-p[j]);
            }
        }
        return value;
    }
    static double[] fit(long[][] counts) {
        double[] s=new double[3],gradient=new double[3];double[][] hessian=new double[3][3];
        for(int iteration=0;iteration<100;iteration++) {
            double value=objective(s,counts,gradient,hessian);
            if(Arrays.stream(gradient).map(Math::abs).max().orElseThrow()<1e-8) return s;
            // The identity regularizer makes the Hessian positive definite.
            double[][] a=new double[3][4];
            for(int i=0;i<3;i++) {System.arraycopy(hessian[i],0,a[i],0,3);a[i][3]=gradient[i];}
            for(int i=0;i<3;i++) {
                double pivot=a[i][i];for(int j=i;j<4;j++) a[i][j]/=pivot;
                for(int k=0;k<3;k++) if(k!=i) {double factor=a[k][i];for(int j=i;j<4;j++) a[k][j]-=factor*a[i][j];}
            }
            double slope=0;for(int i=0;i<3;i++) slope+=gradient[i]*a[i][3];
            boolean accepted=false;
            for(double step=1;step>=1e-10;step/=2) {
                double[] next=s.clone();for(int i=0;i<3;i++) next[i]-=step*a[i][3];
                if(objective(next,counts,null,null)<=value-1e-4*step*slope+Math.max(1e-12,8*Math.ulp(value))) {s=next;accepted=true;break;}
            }
            if(!accepted) break;
        }
        throw new IllegalStateException("Luce optimization did not converge");
    }
    static Group group(Key key,long[][] counts) {
        double[] scores=fit(counts);boolean[] observed=new boolean[3];
        for(int mask:new int[]{3,5,6,7}) if(Arrays.stream(counts[mask]).sum()>0)
            for(int i=0;i<3;i++) if((mask&(1<<i))!=0) observed[i]=true;
        long[] rounded=Arrays.stream(scores).mapToLong(s->(long)Math.floor(s*1_000_000+0.5)).toArray();
        var order=new ArrayList<>(List.of(0,1,2));
        order.sort(Comparator.<Integer>comparingInt(i->observed[i]?0:1)
            .thenComparing(Comparator.<Integer>comparingLong(i->observed[i]?rounded[i]:0).reversed()).thenComparingInt(i->i));
        var places=new ArrayList<Place>();int seen=0;
        for(int i:order) {
            places.add(new Place(places.size()+1,SOURCES.get(i),observed[i]?"votes":"fallback"));
            if(observed[i]) seen++;
        }
        return new Group("npc",key.race(),key.sex(),seen==0?"no_data":seen==3?"ranked":"partial",List.copyOf(places));
    }
    public static Snapshot read(Path database,Path catalogueFile) throws Exception {
        if(!Files.isRegularFile(database)) throw new IllegalArgumentException("Voting database does not exist");
        var mapper=new ObjectMapper();byte[] bytes=Files.readAllBytes(catalogueFile);
        var catalogue=Catalogue.parseSnapshot(new String(bytes,StandardCharsets.UTF_8),mapper);
        var quests=speakers(catalogue.quests());var groups=new TreeMap<Key,long[][]>();
        try(var resource=AddonRanking.class.getResourceAsStream("/ranking-groups.json")) {
            if(resource!=null) for(var node:mapper.readTree(resource))
                groups.put(new Key(node.required("race").asString(),node.required("sex").asString()),new long[8][3]);
        }
        for(var quest:catalogue.quests()) {quests.put(quest.questID(),quest);var key=key(quest.npc());if(key!=null) groups.computeIfAbsent(key,k->new long[8][3]);}
        var config=new SQLiteConfig();config.setReadOnly(true);config.setBusyTimeout(5000);
        try(var db=DriverManager.getConnection("jdbc:sqlite:"+database.toAbsolutePath(),config.toProperties())) {
            db.setAutoCommit(false);
            try(var statement=db.createStatement();var schema=statement.executeQuery("PRAGMA user_version")) {
                if(!schema.next() || schema.getInt(1)<1 || schema.getInt(1)>3) throw new IllegalArgumentException("Unsupported voting schema");
            }
            try(var statement=db.createStatement();var rows=statement.executeQuery("""
                SELECT * FROM (
                  SELECT c.quest_id,c.stage,c.npc_id,c.race,c.sex,v.selected_id,v.candidates_json,
                    ROW_NUMBER() OVER (PARTITION BY v.visitor_id,c.quest_id,c.stage ORDER BY julianday(v.updated_at) DESC,c.id DESC) AS position
                  FROM votes v JOIN comparisons c ON c.id=v.comparison_id
                ) WHERE position=1 ORDER BY quest_id,selected_id,candidates_json
                """)) {
                while(rows.next()) {
                    var quest=quests.get(rows.getLong("quest_id"));
                    var key=eligibleGroup(quest,rows.getLong("npc_id"),rows.getString("race"),rows.getString("sex"),rows.getString("stage"));
                    if(key==null) continue;
                    var candidates=mapper.readTree(rows.getString("candidates_json"));
                    if(!candidates.isArray() || candidates.size()<2 || candidates.size()>3) throw new IllegalArgumentException("Invalid stored ballot");
                    int mask=0,winner=-1;var ids=new HashSet<String>();
                    for(var candidate:candidates) {
                        int source=SOURCES.indexOf(candidate.required("source").asString());
                        String id=candidate.required("id").asString(),hash=candidate.required("sha256").asString();
                        if(source<0 || (mask&(1<<source))!=0 || !ids.add(id) || !id.matches("[a-f0-9]{24}") || !hash.matches("[a-f0-9]{64}"))
                            throw new IllegalArgumentException("Invalid stored candidate");
                        mask|=1<<source;if(id.equals(rows.getString("selected_id"))) winner=source;
                    }
                    if(winner<0) throw new IllegalArgumentException("Selected candidate is missing");
                    groups.get(key)[mask][winner]++;
                }
            }
            db.commit();
        }
        // Do not combine votes with a catalogue replaced during the read.
        if(!Arrays.equals(bytes,Files.readAllBytes(catalogueFile))) throw new IllegalStateException("Catalogue changed during export; retry");
        return new Snapshot(1,Instant.now().toString(),groups.entrySet().stream().map(e->group(e.getKey(),e.getValue())).toList());
    }
    public static Export export(Path database,Path catalogue) throws Exception {
        var snapshot=read(database,catalogue);byte[] json=new ObjectMapper().writeValueAsBytes(snapshot);
        if(json.length>65536 || snapshot.groups().size()>256) throw new IllegalStateException("Ranking exceeds import limits");
        return new Export(new String(json,StandardCharsets.UTF_8),"THR1:"+Base64.getUrlEncoder().withoutPadding().encodeToString(json)+"."+Catalogue.hash(json));
    }
    public static void main(String[] args) throws Exception {
        var options=new HashMap<String,String>();
        for(String arg:args) {
            var pair=arg.split("=",2);
            if(pair.length!=2 || !Set.of("--database","--catalogue").contains(pair[0]) || pair[1].isBlank() || options.put(pair[0],pair[1])!=null)
                throw new IllegalArgumentException("Usage: export-addon-ranking [--database=path] [--catalogue=path]");
        }
        Path database=Path.of(options.getOrDefault("--database",System.getenv().getOrDefault("VOICE_VOTE_DB","../../data/voice-vote/votes.sqlite")));
        Path catalogue=Path.of(options.getOrDefault("--catalogue",System.getenv().getOrDefault("VOICE_VOTE_CATALOGUE","../../data/voice-vote/catalogue.json")));
        System.out.println(export(database,catalogue).json());
    }
}
