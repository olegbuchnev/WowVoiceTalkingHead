package ru.talkinghead.vote;

import java.time.Instant;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.DoubleSupplier;

/** Sample voice groups with a soft recency penalty, then choose quest recordings. */
final class ComparisonQueue {
    private static final double RECENCY_DECAY = 0.8;
    private static final double RECENCY_PENALTY = 3;
    private static final int HISTORY_LIMIT = 20;
    record Candidate(VoteStore.Priority priority, Catalogue.Npc npc, Instant lastRated, boolean unratedGroup) {}
    private record Group(boolean narrator, String race, String sex) {
        static Group of(Catalogue.Npc npc) {
            // Explicit narrators have ID 0. Unknown NPC demographics remain separate.
            return new Group(npc.id() == 0, npc.race(), npc.sex());
        }
    }

    static List<VoteStore.Priority> order(List<Candidate> candidates) {
        return order(candidates, () -> ThreadLocalRandom.current().nextDouble());
    }

    static List<VoteStore.Priority> order(List<Candidate> candidates, DoubleSupplier random) {
        var recency = new HashMap<Group, Double>();
        var history = new ArrayList<>(candidates.stream().filter(c -> c.lastRated() != null).toList());
        // Pending votes or committed timestamps can tie; do not privilege catalogue order.
        Collections.shuffle(history);
        history.sort(Comparator.comparing(Candidate::lastRated).reversed());
        double contribution = 1;
        for (var candidate : history.subList(0, Math.min(HISTORY_LIMIT, history.size()))) {
            recency.merge(Group.of(candidate.npc()), contribution, Double::sum);
            contribution *= RECENCY_DECAY;
        }
        var result = new ArrayList<VoteStore.Priority>();
        // Keep automatic batches free of repeats, even when a whole group is exhausted.
        for (boolean rated : new boolean[]{false, true}) for (boolean unratedGroup : new boolean[]{true, false}) {
            var shuffled = new ArrayList<>(candidates.stream()
                .filter(c -> c.priority().rated() == rated && c.unratedGroup() == unratedGroup).toList());
            Collections.shuffle(shuffled);
            shuffled.sort(Comparator.comparingLong(c -> c.priority().votes()));
            var groups = new LinkedHashMap<Group, ArrayDeque<VoteStore.Priority>>();
            for (var candidate : shuffled)
                groups.computeIfAbsent(Group.of(candidate.npc()), key -> new ArrayDeque<>())
                    .addLast(candidate.priority());
            while (!groups.isEmpty()) {
                // Every group keeps a positive chance, including the previous group.
                // Within the coverage tier, group size and quest votes do not affect this draw.
                var weights = new LinkedHashMap<Group, Double>();
                for (var group : groups.keySet())
                    weights.put(group, 1 / (1 + RECENCY_PENALTY * recency.getOrDefault(group, 0d)));
                double draw = random.getAsDouble() * weights.values().stream().mapToDouble(Double::doubleValue).sum();
                Group selected = groups.lastEntry().getKey();
                for (var entry : weights.entrySet()) {
                    draw -= entry.getValue();
                    if (draw < 0) { selected = entry.getKey(); break; }
                }
                var group = groups.get(selected);
                result.add(group.removeFirst());
                if (group.isEmpty()) groups.remove(selected);
                recency.replaceAll((key, value) -> value * RECENCY_DECAY);
                recency.merge(selected, 1d, Double::sum);
            }
        }
        return result;
    }
}
