package ru.talkinghead.vote;

import static org.junit.jupiter.api.Assertions.*;
import java.nio.file.*;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import tools.jackson.databind.ObjectMapper;

class ResultsExporterTest {
    @TempDir Path directory;
    final ObjectMapper mapper=new ObjectMapper();
    final Catalogue.Npc human=new Catalogue.Npc(1,2,3,"human","male");
    Catalogue.Variant variant(char id,String source,String version) {
        String hash=String.valueOf(id).repeat(64);
        return new Catalogue.Variant(String.valueOf(id).repeat(24),source,source,version,hash,List.of(hash));
    }
    @Test void exportsCurrentAndHistoricalBallotsWithoutInventingPairwiseLosses() throws Exception {
        Path database=directory.resolve("votes.sqlite"), catalogue=directory.resolve("catalogue.json");
        Catalogue.Variant a=variant('a',"WowVoice","1"), b=variant('b',"CatQuest","1"), c=variant('c',"Wayfarer","1");
        var three=new Catalogue.Quest(1,human,List.of(a,b,c));
        var two=new Catalogue.Quest(2,human,List.of(a,b));
        var unknown=new Catalogue.Quest(3,new Catalogue.Npc(0,0,0,null,null),List.of(a,b));
        var old=new Catalogue.Quest(4,human,List.of(a,b));
        var changed=new Catalogue.Quest(4,human,List.of(variant('d',"WowVoice","2"),b));
        var sameBytesNewRelease=new Catalogue.Quest(1,human,List.of(variant('a',"WowVoice","2"),b,c));
        Files.writeString(catalogue,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(sameBytesNewRelease,two,unknown,changed))));
        try(var store=new VoteStore(database.toString(),mapper)) {
            var first=store.createVisitor(); var second=store.createVisitor();
            store.save(first.id(),three,a.id()); store.save(first.id(),three,b.id());
            store.save(second.id(),three,c.id()); store.save(first.id(),two,a.id());
            store.save(first.id(),unknown,b.id()); store.save(first.id(),old,a.id());
            // Export while the API-style connection remains open with WAL data.
            var snapshot=ResultsExporter.read(database,catalogue);
            assertEquals(5,snapshot.summary().votes());
            assertEquals(4,snapshot.summary().currentVotes());
            assertEquals(1,snapshot.summary().historicalVotes());
            assertEquals(1,snapshot.summary().currentVotesWithoutDemographics());
            assertEquals(4,snapshot.comparisons().size());
            assertTrue(snapshot.comparisons().stream().filter(q->q.questID()==4).noneMatch(ResultsExporter.Comparison::current));
            var wow=snapshot.raceSex().stream().filter(g->"human".equals(g.race()) && g.source().equals("WowVoice")).findFirst().orElseThrow();
            assertEquals(1,wow.selectedVotes());assertEquals(3,wow.offeredVotes());
            var catVsWow=snapshot.pairwise().stream().filter(p->"human".equals(p.race()) && p.source().equals("CatQuest") && p.opponent().equals("WowVoice")).findFirst().orElseThrow();
            assertEquals(1,catVsWow.wins());assertEquals(1,catVsWow.losses());
            var way=snapshot.raceSex().stream().filter(g->g.source().equals("Wayfarer")).findFirst().orElseThrow();
            assertEquals(2,way.offeredVotes());
            String json=mapper.writeValueAsString(snapshot);
            assertFalse(json.contains(first.id()));assertFalse(json.contains(first.token()));
            assertFalse(json.contains("visitor"));
            Path output=ResultsExporter.export(database,catalogue,directory.resolve("exports"));
            try(var files=Files.list(output)) {assertEquals(Set.of("results.json","quests.csv","race-sex.csv","pairwise.csv"),
                new HashSet<>(files.map(p->p.getFileName().toString()).toList()));}
            assertEquals(5,mapper.readTree(Files.readString(output.resolve("results.json"))).get("summary").get("votes").asLong());
            assertTrue(Files.readString(output.resolve("quests.csv")).contains("\"false\""));
            assertEquals(4,store.summary(first.id()).total(),"export must not modify votes");
            assertNotEquals(output,ResultsExporter.export(database,catalogue,directory.resolve("exports")));
        }
    }
    @Test void correctedFurbolgRaceDoesNotInheritTaurenBallots() throws Exception {
        Path database=directory.resolve("votes.sqlite"), catalogue=directory.resolve("catalogue.json");
        var a=variant('a',"WowVoice","1"); var b=variant('b',"CatQuest","1");
        var old=new Catalogue.Quest(8231,new Catalogue.Npc(8405,1012,124118,"tauren","male"),List.of(a,b));
        var corrected=new Catalogue.Quest(8231,new Catalogue.Npc(8405,1012,124118,"furbolg","male"),List.of(a,b));
        var tauren=new Catalogue.Quest(99,new Catalogue.Npc(99,100,118652,"tauren","male"),List.of(a,b));
        Files.writeString(catalogue,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(corrected,tauren))));
        assertNotEquals(VoteStore.comparisonID(old,mapper),VoteStore.comparisonID(corrected,mapper));
        try(var store=new VoteStore(database.toString(),mapper)) {
            var visitor=store.createVisitor();
            store.save(visitor.id(),old,a.id());
            store.save(visitor.id(),tauren,a.id());
            var priority=store.queue(visitor.id(),List.of(corrected)).getFirst();
            assertFalse(priority.rated());assertEquals(0,priority.votes());
            store.save(visitor.id(),corrected,b.id());
            var snapshot=ResultsExporter.read(database,catalogue);
            assertEquals(2,snapshot.summary().votes());
            assertEquals(2,snapshot.summary().currentVotes());
            assertEquals(0,snapshot.summary().historicalVotes());
            var furbolg=snapshot.raceSex().stream().filter(g->"furbolg".equals(g.race()) && g.source().equals("CatQuest")).findFirst().orElseThrow();
            assertEquals(1,furbolg.selectedVotes());assertEquals(1,furbolg.offeredVotes());
            var separateTauren=snapshot.raceSex().stream().filter(g->"tauren".equals(g.race()) && g.source().equals("WowVoice")).findFirst().orElseThrow();
            assertEquals(1,separateTauren.selectedVotes());assertEquals(1,separateTauren.offeredVotes());
        }
    }
    @Test void waterElementalsDoNotInheritUnknownDemographicVotes() throws Exception {
        Path database=directory.resolve("votes.sqlite"), catalogue=directory.resolve("catalogue.json");
        var a=variant('a',"WowVoice","1"); var b=variant('b',"CatQuest","1");
        var old=new Catalogue.Quest(7486,new Catalogue.Npc(13278,10849,126426,null,null),List.of(a,b));
        var corrected=new Catalogue.Quest(7486,new Catalogue.Npc(13278,10849,126426,"elemental_water","male"),List.of(a,b));
        Files.writeString(catalogue,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(corrected))));
        try(var store=new VoteStore(database.toString(),mapper)) {
            var visitor=store.createVisitor();store.save(visitor.id(),old,a.id());
            var priority=store.queue(visitor.id(),List.of(corrected)).getFirst();
            assertFalse(priority.rated());assertEquals(0,priority.votes());
            store.save(visitor.id(),corrected,b.id());
            var snapshot=ResultsExporter.read(database,catalogue);
            assertEquals(0,snapshot.summary().historicalVotes());
            assertEquals(1,snapshot.summary().currentVotes());
            assertTrue(snapshot.raceSex().stream().allMatch(g->"elemental_water".equals(g.race()) && "male".equals(g.sex())));
            assertEquals(1,snapshot.raceSex().stream().filter(g->g.source().equals("CatQuest")).findFirst().orElseThrow().selectedVotes());
        }
    }
    @Test void dreadlordsDoNotInheritUnknownOrScourgeVotes() throws Exception {
        Path database=directory.resolve("votes.sqlite"), catalogue=directory.resolve("catalogue.json");
        var a=variant('a',"WowVoice","1"); var b=variant('b',"CatQuest","1");
        var oldVarimathras=new Catalogue.Quest(6145,new Catalogue.Npc(2425,11658,123673,null,"male"),List.of(a,b));
        var oldBanehollow=new Catalogue.Quest(7624,new Catalogue.Npc(9516,8611,123673,"scourge","male"),List.of(a,b));
        var varimathras=new Catalogue.Quest(6145,new Catalogue.Npc(2425,11658,123673,"dreadlord","male"),List.of(a,b));
        var banehollow=new Catalogue.Quest(7624,new Catalogue.Npc(9516,8611,123673,"dreadlord","male"),List.of(a,b));
        var current=List.of(varimathras,banehollow);
        Files.writeString(catalogue,mapper.writeValueAsString(new Catalogue.Snapshot(2,current)));
        try(var store=new VoteStore(database.toString(),mapper)) {
            var visitor=store.createVisitor();
            store.save(visitor.id(),oldVarimathras,a.id());store.save(visitor.id(),oldBanehollow,a.id());
            assertTrue(store.queue(visitor.id(),current).stream().allMatch(q->!q.rated() && q.votes()==0));
            store.save(visitor.id(),varimathras,b.id());store.save(visitor.id(),banehollow,b.id());
            var snapshot=ResultsExporter.read(database,catalogue);
            assertEquals(0,snapshot.summary().historicalVotes());
            assertEquals(2,snapshot.summary().currentVotes());
            assertTrue(snapshot.raceSex().stream().allMatch(g->"dreadlord".equals(g.race()) && "male".equals(g.sex())));
            assertEquals(2,snapshot.raceSex().stream().filter(g->g.source().equals("CatQuest")).findFirst().orElseThrow().selectedVotes());
            assertEquals(0,snapshot.raceSex().stream().filter(g->g.source().equals("WowVoice")).findFirst().orElseThrow().selectedVotes());
        }
    }
    @Test void mangletoothQuilboarGroupStartsWithoutUnknownRaceVotes() throws Exception {
        Path database=directory.resolve("votes.sqlite"),catalogue=directory.resolve("catalogue.json");
        var a=variant('a',"WowVoice","1");var b=variant('b',"CatQuest","1");
        var old=new Catalogue.Quest(878,new Catalogue.Npc(3430,1346,125497,null,"male"),List.of(a,b));
        var corrected=new Catalogue.Quest(878,new Catalogue.Npc(3430,1346,125497,"quilboar","male"),List.of(a,b));
        Files.writeString(catalogue,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(corrected))));
        try(var store=new VoteStore(database.toString(),mapper)) {
            var visitor=store.createVisitor();store.save(visitor.id(),old,a.id());
            var initial=ResultsExporter.read(database,catalogue);
            assertEquals(1,initial.summary().historicalVotes());assertEquals(0,initial.summary().currentVotes());
            assertTrue(AddonRanking.read(database,catalogue).groups().stream()
                .anyMatch(g->g.race().equals("quilboar") && g.sex().equals("male") && g.status().equals("no_data")));
            store.save(visitor.id(),corrected,b.id());
            var updated=ResultsExporter.read(database,catalogue);
            assertEquals(0,updated.summary().historicalVotes());assertEquals(1,updated.summary().currentVotes());
            assertTrue(updated.raceSex().stream().allMatch(g->"quilboar".equals(g.race()) && "male".equals(g.sex())));
        }
    }
    @Test void centaursDoNotInheritUnknownRaceVotes() throws Exception {
        Path database=directory.resolve("votes.sqlite"),catalogue=directory.resolve("catalogue.json");
        var a=variant('a',"WowVoice","1");var b=variant('b',"CatQuest","1");
        var old=new Catalogue.Quest(1381,new Catalogue.Npc(5398,1258,123170,null,"male"),List.of(a,b));
        var corrected=new Catalogue.Quest(1381,new Catalogue.Npc(5398,1258,123170,"centaur","male"),List.of(a,b));
        Files.writeString(catalogue,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(corrected))));
        try(var store=new VoteStore(database.toString(),mapper)) {
            var visitor=store.createVisitor();store.save(visitor.id(),old,a.id());
            assertEquals(1,ResultsExporter.read(database,catalogue).summary().historicalVotes());
            assertTrue(AddonRanking.read(database,catalogue).groups().stream()
                .anyMatch(g->g.race().equals("centaur") && g.sex().equals("male") && g.status().equals("no_data")));
            store.save(visitor.id(),corrected,b.id());
            var updated=ResultsExporter.read(database,catalogue);
            assertEquals(0,updated.summary().historicalVotes());assertEquals(1,updated.summary().currentVotes());
            assertTrue(updated.raceSex().stream().allMatch(g->"centaur".equals(g.race()) && "male".equals(g.sex())));
        }
    }
    @Test void stoneConstructsDoNotInheritUnclassifiedVotes() throws Exception {
        Path database=directory.resolve("votes.sqlite"), catalogue=directory.resolve("catalogue.json");
        var a=variant('a',"WowVoice","1"); var b=variant('b',"CatQuest","1");
        var old=new Catalogue.Quest(2954,new Catalogue.Npc(7918,6589,126072,null,"male"),List.of(a,b));
        var corrected=new Catalogue.Quest(2954,new Catalogue.Npc(7918,6589,126072,"stone_construct","male"),List.of(a,b));
        Files.writeString(catalogue,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(corrected))));
        try(var store=new VoteStore(database.toString(),mapper)) {
            var visitor=store.createVisitor();store.save(visitor.id(),old,a.id());
            var priority=store.queue(visitor.id(),List.of(corrected)).getFirst();
            assertFalse(priority.rated());assertEquals(0,priority.votes());
            store.save(visitor.id(),corrected,b.id());
            var snapshot=ResultsExporter.read(database,catalogue);
            assertEquals(0,snapshot.summary().historicalVotes());
            assertEquals(1,snapshot.summary().currentVotes());
            assertFalse(snapshot.raceSex().isEmpty());
            assertTrue(snapshot.raceSex().stream().allMatch(g->"stone_construct".equals(g.race()) && "male".equals(g.sex())));
            assertEquals(1,snapshot.raceSex().stream().filter(g->g.source().equals("CatQuest")).findFirst().orElseThrow().selectedVotes());
        }
    }
    @Test void mountainGiantsKeepUnknownSexAndSeparateVotesFromConstructs() throws Exception {
        Path database=directory.resolve("votes.sqlite"), catalogue=directory.resolve("catalogue.json");
        var a=variant('a',"WowVoice","1"); var b=variant('b',"CatQuest","1");
        var old=new Catalogue.Quest(2844,new Catalogue.Npc(7765,1918,124952,null,null),List.of(a,b));
        var giant=new Catalogue.Quest(2844,new Catalogue.Npc(7765,1918,124952,"mountain_giant",null),List.of(a,b));
        var stone=new Catalogue.Quest(2954,new Catalogue.Npc(7918,6589,126072,"stone_construct","male"),List.of(a,b));
        Files.writeString(catalogue,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(giant,stone))));
        try(var store=new VoteStore(database.toString(),mapper)) {
            var visitor=store.createVisitor();store.save(visitor.id(),old,a.id());
            var priority=store.queue(visitor.id(),List.of(giant)).getFirst();
            assertFalse(priority.rated());assertEquals(0,priority.votes());
            store.save(visitor.id(),giant,b.id());store.save(visitor.id(),stone,a.id());
            var snapshot=ResultsExporter.read(database,catalogue);
            assertEquals(0,snapshot.summary().historicalVotes());assertEquals(2,snapshot.summary().currentVotes());
            assertEquals(1,snapshot.summary().currentVotesWithoutDemographics());
            var group=snapshot.raceSex().stream().filter(g->"mountain_giant".equals(g.race()) && "CatQuest".equals(g.source())).findFirst().orElseThrow();
            assertNull(group.sex());assertEquals(1,group.selectedVotes());assertEquals(1,group.offeredVotes());
            var construct=snapshot.raceSex().stream().filter(g->"stone_construct".equals(g.race()) && "WowVoice".equals(g.source())).findFirst().orElseThrow();
            assertEquals("male",construct.sex());assertEquals(1,construct.selectedVotes());assertEquals(1,construct.offeredVotes());
        }
    }
    @Test void childRaceAndSexGroupsRemainSeparateFromEachOtherAndAdults() throws Exception {
        Path database=directory.resolve("votes.sqlite"), catalogue=directory.resolve("catalogue.json");
        var a=variant('a',"WowVoice","1"); var b=variant('b',"CatQuest","1");
        var variants=List.of(a,b);
        var orcBoy=new Catalogue.Quest(5502,new Catalogue.Npc(14444,14589,125367,"orc_child","male"),variants);
        var humanBoy=new Catalogue.Quest(1479,new Catalogue.Npc(14305,338,124495,"human_child","male"),variants);
        var orcGirl=new Catalogue.Quest(97326,new Catalogue.Npc(268684,14616,125362,"orc_child","female"),variants);
        var humanGirl=new Catalogue.Quest(92110,new Catalogue.Npc(249713,257,124456,"human_child","female"),variants);
        var adult=new Catalogue.Quest(1,new Catalogue.Npc(1,2,3,"orc","male"),variants);
        var current=List.of(orcBoy,humanBoy,orcGirl,humanGirl,adult);
        Files.writeString(catalogue,mapper.writeValueAsString(new Catalogue.Snapshot(2,current)));
        try(var store=new VoteStore(database.toString(),mapper)) {
            var visitor=store.createVisitor();
            for(var quest:List.of(orcBoy,humanBoy)) {
                var npc=quest.npc();
                var old=new Catalogue.Quest(quest.questID(),new Catalogue.Npc(npc.id(),npc.displayID(),npc.modelFileID(),"child","male"),variants);
                assertNotEquals(VoteStore.comparisonID(old,mapper),VoteStore.comparisonID(quest,mapper));
                store.save(visitor.id(),old,a.id());
            }
            assertTrue(store.queue(visitor.id(),current).stream().allMatch(q->!q.rated() && q.votes()==0));
            for(var quest:current) store.save(visitor.id(),quest,b.id());
            var snapshot=ResultsExporter.read(database,catalogue);
            assertEquals(0,snapshot.summary().historicalVotes());assertEquals(5,snapshot.summary().currentVotes());
            var selected=snapshot.raceSex().stream().filter(g->g.source().equals("CatQuest")).toList();
            assertEquals(Set.of("orc_child/male","human_child/male","orc_child/female","human_child/female","orc/male"),
                    selected.stream().map(g->g.race()+"/"+g.sex()).collect(java.util.stream.Collectors.toSet()));
            assertTrue(selected.stream().allMatch(g->g.selectedVotes()==1 && g.offeredVotes()==1));
            assertTrue(snapshot.raceSex().stream().noneMatch(g->"child".equals(g.race())));
        }
    }
    @Test void emptyDatabaseExportsAndMissingDatabaseIsNotCreated() throws Exception {
        Path database=directory.resolve("votes.sqlite"), catalogue=directory.resolve("catalogue.json");
        var quest=new Catalogue.Quest(1,human,List.of(variant('a',"WowVoice","1"),variant('b',"CatQuest","1")));
        Files.writeString(catalogue,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(quest))));
        assertThrows(IllegalArgumentException.class,()->ResultsExporter.read(database,catalogue));
        assertFalse(Files.exists(database));
        try(var store=new VoteStore(database.toString(),mapper)) {
            var snapshot=ResultsExporter.read(database,catalogue);
            assertEquals(0,snapshot.summary().votes());assertTrue(snapshot.comparisons().isEmpty());
            assertTrue(snapshot.raceSex().isEmpty());assertTrue(snapshot.pairwise().isEmpty());
        }
    }
    @Test void csvEscapesQuotedVersionsAndNeutralizesFormulaPrefixes() throws Exception {
        Path database=directory.resolve("votes.sqlite"), catalogue=directory.resolve("catalogue.json");
        Catalogue.Variant a=variant('a',"WowVoice","=\"release,one\"\nnext"), b=variant('b',"CatQuest","1");
        var quest=new Catalogue.Quest(1,human,List.of(a,b));
        Files.writeString(catalogue,mapper.writeValueAsString(new Catalogue.Snapshot(2,List.of(quest))));
        try(var store=new VoteStore(database.toString(),mapper)) {
            store.save(store.createVisitor().id(),quest,a.id());
            var output=ResultsExporter.export(database,catalogue,directory.resolve("exports"));
            assertTrue(Files.readString(output.resolve("quests.csv")).contains("\"'=\"\"release,one\"\"\nnext\""));
        }
    }
}
