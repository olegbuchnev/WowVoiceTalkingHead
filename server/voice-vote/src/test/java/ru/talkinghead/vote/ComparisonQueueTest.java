package ru.talkinghead.vote;

import static org.junit.jupiter.api.Assertions.*;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class ComparisonQueueTest {
    ComparisonQueue.Candidate candidate(long id, String race, String sex, boolean rated, long votes, Instant last) {
        return new ComparisonQueue.Candidate(new VoteStore.Priority(id, rated, votes),
            new Catalogue.Npc(id, 1, 1, race, sex), last);
    }
    ComparisonQueue.Candidate narrator(long id) {
        return new ComparisonQueue.Candidate(new VoteStore.Priority(id, false, 0),
            new Catalogue.Npc(0, 0, 0, null, null), null);
    }

    @Test void groupChanceDoesNotScaleWithQuestCountOrCoverage() {
        var candidates = new ArrayList<ComparisonQueue.Candidate>();
        for (long id = 1; id <= 300; id++) candidates.add(narrator(id));
        candidates.add(candidate(301, "human", "male", false, 5, null));
        candidates.add(candidate(302, "human", "female", false, 8, null));
        candidates.add(candidate(303, "orc", "male", false, 12, null));
        candidates.add(candidate(304, "orc", "female", false, 20, null));
        var random = new java.util.Random(42);
        int narrators = 0;
        for (int attempt = 0; attempt < 1000; attempt++) {
            var ordered = ComparisonQueue.order(candidates, random::nextDouble);
            if (ordered.getFirst().questID() <= 300) narrators++;
            assertEquals(304, ordered.stream().map(VoteStore.Priority::questID).distinct().count());
        }
        assertTrue(narrators > 140 && narrators < 260, "Narrator should get about one fifth of first turns, not 300/304");
    }

    @Test void differentNpcsOfSameRaceAndSexShareOneTurn() {
        var candidates = List.of(
            candidate(1, "dwarf", "male", false, 0, null),
            candidate(2, "dwarf", "male", false, 1, null),
            candidate(3, "dwarf", "female", false, 20, null));
        assertEquals(3, ComparisonQueue.order(candidates, () -> 0.6).getFirst().questID(),
            "The female group has half the initial chance despite having one quest versus two");
    }

    @Test void recentlyRatedGroupHasLowerButPositiveChance() {
        Instant later = Instant.parse("2026-10-13T10:00:00Z");
        var candidates = List.of(
            candidate(1, "human", "male", true, 1, later),
            candidate(2, "human", "male", false, 0, null),
            candidate(4, "orc", "female", false, 5, null));
        assertEquals(4, ComparisonQueue.order(candidates, () -> 0.3).getFirst().questID(),
            "A recently rated group has less than its initial half of the probability");
        assertEquals(2, ComparisonQueue.order(candidates, () -> 0.1).getFirst().questID(),
            "A recently rated group is still eligible immediately");
    }

    @Test void repeatsArePossibleWithoutCompletingAGroupCycle() {
        var candidates = List.of(
            candidate(1, "human", "male", false, 0, null),
            candidate(2, "human", "male", false, 1, null),
            candidate(3, "orc", "female", false, 10, null));
        assertEquals(List.of(1L, 2L, 3L), ComparisonQueue.order(candidates, () -> 0d)
            .stream().map(VoteStore.Priority::questID).toList());
        // Initial 50/50 draw selects human; after its weight falls to 1/4,
        // the same random draw selects orc. Selection within this batch is remembered.
        assertEquals(List.of(1L, 3L, 2L), ComparisonQueue.order(candidates, () -> 0.3)
            .stream().map(VoteStore.Priority::questID).toList());
    }

    @Test void withinGroupUnratedThenLeastCoveredRemainFirstAndExhaustedGroupsDoNotForceRepeats() {
        var candidates = List.of(
            candidate(1, "human", "male", false, 4, null),
            candidate(2, "human", "male", false, 2, null),
            candidate(3, "human", "male", true, 1, Instant.now()),
            candidate(4, "orc", "male", true, 1, null));
        assertEquals(List.of(2L, 1L), ComparisonQueue.order(candidates).subList(0, 2)
            .stream().map(VoteStore.Priority::questID).toList());
        assertTrue(ComparisonQueue.order(List.of()).isEmpty());
    }

    @Test void explicitNarratorAndUnknownDemographicsAreDifferentGroups() {
        var candidates = List.of(narrator(1), narrator(2), candidate(3, null, null, false, 10, null));
        assertEquals(3, ComparisonQueue.order(candidates, () -> 0.6).getFirst().questID());
    }
}
