package ru.talkinghead.vote;

import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.sql.DriverManager;
import java.time.Instant;
import java.util.*;
import org.sqlite.SQLiteConfig;
import tools.jackson.databind.ObjectMapper;

/** Read-only, version-aware aggregates. Never exports visitor identifiers. */
public final class ResultsExporter {
    public record Recording(String id, String source, String pack, String sha256,
                            List<String> libraryVersions, long selectedVotes, long offeredVotes) {}
    public record Comparison(String comparisonID, long questID, String stage, Catalogue.Npc npc,
                             boolean current, long votes, List<Recording> recordings) {}
    public record Group(String race, String sex, String source, long selectedVotes, long offeredVotes) {}
    public record Pair(String race, String sex, String source, String opponent, long wins, long losses) {}
    public record Summary(long votes, long currentVotes, long historicalVotes, long currentVotesWithoutDemographics,
                          int votedComparisons, int catalogueComparisons) {}
    public record Snapshot(int schemaVersion, String generatedAt, String catalogueSha256, Summary summary,
                           List<Comparison> comparisons, List<Group> raceSex, List<Pair> pairwise) {}
    private record GroupKey(String race, String sex, String source) {}
    private record PairKey(String race, String sex, String source, String opponent) {}
    private static final class Tally { long selected, offered; }
    private static final class Candidate {
        String id, source, pack, sha256;
        final Set<String> versions = new TreeSet<>();
        long selected, offered;
        Recording result() { return new Recording(id,source,pack,sha256,List.copyOf(versions),selected,offered); }
    }
    private static final class Compared {
        String id;
        long questID, votes;
        Catalogue.Npc npc;
        boolean current;
        final Map<String,Candidate> candidates = new TreeMap<>();
        Comparison result() { return new Comparison(id,questID,"a",npc,current,votes,
            candidates.values().stream().map(Candidate::result).toList()); }
    }

    public static Snapshot read(Path database, Path catalogueFile) throws Exception {
        if (!Files.isRegularFile(database)) throw new IllegalArgumentException("Voting database does not exist: " + database);
        var mapper = new ObjectMapper();
        // Validate and hash the same catalogue bytes, even if an operator replaces
        // the live catalogue while the export is running.
        byte[] catalogueBytes = Files.readAllBytes(catalogueFile);
        var catalogue = Catalogue.parseSnapshot(new String(catalogueBytes,StandardCharsets.UTF_8),mapper);
        var current = new HashSet<String>();
        for (var quest : catalogue.quests()) current.add(VoteStore.comparisonID(quest,mapper));
        var comparisons = new TreeMap<String,Compared>();
        var groups = new LinkedHashMap<GroupKey,Tally>();
        var pairs = new LinkedHashMap<PairKey,Tally>();
        long votes=0, currentVotes=0, unknown=0;
        var config = new SQLiteConfig();
        config.setReadOnly(true);
        config.setBusyTimeout(5000);
        try (var db = DriverManager.getConnection("jdbc:sqlite:"+database.toAbsolutePath(),config.toProperties())) {
            db.setAutoCommit(false);
            // A single read transaction includes committed WAL data and remains
            // consistent while the API continues accepting votes.
            try (var statement=db.createStatement(); var version=statement.executeQuery("PRAGMA user_version")) {
                if (!version.next() || version.getInt(1)<1 || version.getInt(1)>3) throw new IllegalArgumentException("Unsupported voting database schema");
            }
            try (var statement=db.createStatement(); var rows=statement.executeQuery("""
                SELECT c.id,c.quest_id,c.stage,c.npc_id,c.display_id,c.model_file_id,c.race,c.sex,
                       v.selected_id,v.candidates_json
                FROM votes v JOIN comparisons c ON c.id=v.comparison_id
                ORDER BY c.quest_id,c.id,v.selected_id
                """)) {
                while (rows.next()) {
                    if (!"a".equals(rows.getString("stage"))) throw new IllegalArgumentException("Unexpected voting stage");
                    String id=rows.getString("id"), selected=rows.getString("selected_id");
                    Compared comparison=comparisons.get(id);
                    if (comparison==null) {
                        comparison=new Compared(); comparison.id=id; comparison.questID=rows.getLong("quest_id");
                        comparison.npc=new Catalogue.Npc(rows.getLong("npc_id"),rows.getLong("display_id"),
                            rows.getLong("model_file_id"),rows.getString("race"),rows.getString("sex"));
                        comparison.current=current.contains(id); comparisons.put(id,comparison);
                    }
                    var candidates=mapper.readTree(rows.getString("candidates_json"));
                    if (!candidates.isArray() || candidates.size()<2 || candidates.size()>3)
                        throw new IllegalArgumentException("Invalid stored candidate set");
                    var ballot=new ArrayList<Candidate>();
                    for (var node : candidates) {
                        String candidateID=node.required("id").asString();
                        var candidate=comparison.candidates.computeIfAbsent(candidateID,ignored->new Candidate());
                        candidate.id=candidateID; candidate.source=node.required("source").asString();
                        candidate.pack=node.required("pack").asString(); candidate.sha256=node.required("sha256").asString();
                        candidate.versions.add(node.required("version").asString());
                        candidate.offered++; if (candidateID.equals(selected)) candidate.selected++;
                        ballot.add(candidate);
                    }
                    Candidate winner=ballot.stream().filter(c->c.id.equals(selected)).findFirst()
                        .orElseThrow(()->new IllegalArgumentException("Selected recording is absent from stored candidates"));
                    comparison.votes++; votes++;
                    if (!comparison.current) continue;
                    currentVotes++;
                    String race=comparison.npc.race(), sex=comparison.npc.sex();
                    if (race==null || sex==null) unknown++;
                    for (var candidate : ballot) {
                        var tally=groups.computeIfAbsent(new GroupKey(race,sex,candidate.source),ignored->new Tally());
                        tally.offered++; if (candidate==winner) tally.selected++;
                        if (candidate==winner) continue;
                        // Only the winner beats an opponent. Two non-selected
                        // options in a three-way ballot are not ranked.
                        var win=pairs.computeIfAbsent(new PairKey(race,sex,winner.source,candidate.source),ignored->new Tally());
                        win.selected++;
                        var loss=pairs.computeIfAbsent(new PairKey(race,sex,candidate.source,winner.source),ignored->new Tally());
                        loss.offered++;
                    }
                }
            }
            db.rollback();
        }
        return new Snapshot(1,Instant.now().toString(),Catalogue.hash(catalogueBytes),
            new Summary(votes,currentVotes,votes-currentVotes,unknown,comparisons.size(),catalogue.quests().size()),
            comparisons.values().stream().map(Compared::result)
                .sorted(Comparator.comparingLong(Comparison::questID).thenComparing(Comparison::comparisonID)).toList(),
            groups.entrySet().stream().map(e->new Group(e.getKey().race,e.getKey().sex,e.getKey().source,
                e.getValue().selected,e.getValue().offered)).toList(),
            pairs.entrySet().stream().map(e->new Pair(e.getKey().race,e.getKey().sex,e.getKey().source,e.getKey().opponent,
                e.getValue().selected,e.getValue().offered)).toList());
    }

    public static Map<String,byte[]> files(Snapshot snapshot) {
        var files=new LinkedHashMap<String,byte[]>();
        var mapper=new ObjectMapper();
        files.put("results.json",(mapper.writerWithDefaultPrettyPrinter().writeValueAsString(snapshot)+"\n").getBytes(StandardCharsets.UTF_8));
        var quests=new StringBuilder();
        csv(quests,"comparison_id","quest_id","stage","npc_id","display_id","model_file_id","race","sex","current",
            "recording_id","source","pack","sha256","library_versions","selected_votes","offered_votes");
        for (var comparison : snapshot.comparisons()) for (var recording : comparison.recordings()) {
            var npc=comparison.npc();
            csv(quests,comparison.comparisonID(),comparison.questID(),comparison.stage(),npc.id(),npc.displayID(),npc.modelFileID(),
                npc.race(),npc.sex(),comparison.current(),recording.id(),recording.source(),recording.pack(),recording.sha256(),
                String.join(";",recording.libraryVersions()),recording.selectedVotes(),recording.offeredVotes());
        }
        files.put("quests.csv",quests.toString().getBytes(StandardCharsets.UTF_8));
        var groups=new StringBuilder(); csv(groups,"race","sex","source","selected_votes","offered_votes");
        for (var group : snapshot.raceSex()) csv(groups,group.race(),group.sex(),group.source(),group.selectedVotes(),group.offeredVotes());
        files.put("race-sex.csv",groups.toString().getBytes(StandardCharsets.UTF_8));
        var pairs=new StringBuilder(); csv(pairs,"race","sex","source","opponent","wins","losses");
        for (var pair : snapshot.pairwise()) csv(pairs,pair.race(),pair.sex(),pair.source(),pair.opponent(),pair.wins(),pair.losses());
        files.put("pairwise.csv",pairs.toString().getBytes(StandardCharsets.UTF_8));
        return files;
    }

    public static Path export(Path database, Path catalogue, Path output) throws Exception {
        var snapshot=read(database,catalogue);
        Files.createDirectories(output);
        String name="results-"+snapshot.generatedAt().replace(":", "-")+"-"+UUID.randomUUID().toString().substring(0,8);
        Path temporary=Files.createDirectory(output.resolve("."+name+".tmp"));
        for(var file:files(snapshot).entrySet()) Files.write(temporary.resolve(file.getKey()),file.getValue());
        Path destination=output.resolve(name);
        try { Files.move(temporary,destination,StandardCopyOption.ATOMIC_MOVE); }
        catch (AtomicMoveNotSupportedException e) { Files.move(temporary,destination); }
        return destination;
    }
    private static void csv(StringBuilder result, Object... cells) {
        var row=new StringJoiner(",");
        for (Object cell : cells) {
            String text=cell==null ? "" : cell.toString();
            // CSV quoting is not enough to neutralize spreadsheet formulas.
            if (!text.isEmpty() && "=+@-\t\r".indexOf(text.charAt(0))>=0) text="'"+text;
            row.add("\""+text.replace("\"","\"\"")+"\"");
        }
        result.append(row).append("\r\n");
    }
    public static void main(String[] args) throws Exception {
        var options=new HashMap<String,String>();
        for (String arg : args) {
            String[] option=arg.split("=",2);
            if (option.length!=2 || !Set.of("--database","--catalogue","--output").contains(option[0])
                || option[1].isBlank() || options.put(option[0],option[1])!=null)
                throw new IllegalArgumentException("Usage: export-results [--database=path] [--catalogue=path] [--output=directory]");
        }
        Path database=Path.of(options.getOrDefault("--database",System.getenv().getOrDefault("VOICE_VOTE_DB","../../data/voice-vote/votes.sqlite")));
        Path catalogue=Path.of(options.getOrDefault("--catalogue",System.getenv().getOrDefault("VOICE_VOTE_CATALOGUE","../../data/voice-vote/catalogue.json")));
        Path output=Path.of(options.getOrDefault("--output",System.getenv().getOrDefault("VOICE_VOTE_EXPORT_DIR","../../data/voice-vote/exports")));
        System.out.println("Results exported to: "+export(database,catalogue,output).toAbsolutePath());
    }
}
