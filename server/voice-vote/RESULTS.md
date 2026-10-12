# Results export, schema version 1

The exporter is an operator CLI, not a public HTTP endpoint. It runs from the
same JAR/image as the API. It opens an existing SQLite database read-only and
uses a single transaction, including committed WAL data. Voting can continue.
Visitor identifiers, cookies and individual ballots are not exported.

From `server/voice-vote`:

```shell
java --enable-native-access=ALL-UNNAMED -jar target/voice-vote-server-0.1.0.jar export-results
```

Defaults use `VOICE_VOTE_DB`, `VOICE_VOTE_CATALOGUE`, `VOICE_VOTE_EXPORT_DIR`,
or `../../data/voice-vote/{votes.sqlite,catalogue.json,exports}`. Explicit options:

```shell
java --enable-native-access=ALL-UNNAMED -jar server.jar export-results --database=/data/votes.sqlite --catalogue=/catalogue/catalogue.json --output=/data/exports
```

In Docker Compose:

```shell
docker compose exec -T api java --enable-native-access=ALL-UNNAMED -jar /app/server.jar export-results
docker compose cp api:/data/exports ./exports
```

Each invocation creates a new `results-<UTC timestamp>-<suffix>` directory.
Files are prepared in a temporary directory and the completed directory is
renamed into place; consumers must ignore dot-prefixed temporary directories.
Previous exports are never overwritten. Export archives are independent of the
three-revision audio-history window: historical votes remain available.

| File | Contents |
| --- | --- |
| `results.json` | Versioned complete aggregate snapshot for further processing |
| `quests.csv` | One row per exact comparison and candidate recording, including historical comparisons |
| `race-sex.csv` | Current comparisons grouped by race, sex and source |
| `pairwise.csv` | Current winner-versus-opponent counts grouped by race and sex |

JSON is defined by [results.schema.json](results.schema.json). CSV is UTF-8,
comma-separated, with a header, quoted cells and CRLF records. Empty race/sex
cells mean unknown; JSON uses null. Versions are semicolon-separated in CSV and
an array in JSON. Formula-like text receives a leading apostrophe in CSV only.

## Identity and version rules

Before implementing addon voice selection, revisit the
[planned revision-weighted ranking](../../docs/internal/audio-recording-history.md#задача-учитывать-прошлые-оценки-при-выборе-озвучки-в-аддоне).
It proposes a capped, fading contribution from previous recordings (initial
weight suggestion: 0.5). This is a future derived ranking, not a change to raw
vote counts or the current export contract; thresholds are not finalized.

- `comparisonID` identifies quest description, speaker metadata and the sorted
  candidate recording IDs. `stage` is always `a`. Candidate IDs include library,
  file path and SHA-256. A release-number change without changed bytes does not
  create a new comparison. Changing any candidate, candidate membership or
  speaker metadata creates a different comparison, matching the live API.
- `current` means an exact comparison is present in the exported catalogue.
  Historical comparisons remain in JSON and `quests.csv` with `current=false`.
  They are excluded from `raceSex` and `pairwise`. Old and new audio results are
  never merged into a recording's tally. `catalogueSha256` identifies the exact
  catalogue bytes used to classify the snapshot.
- `libraryVersions` lists release labels observed in retained ballots, not an
  exhaustive library release history. `sha256` is the recording identity.
- Only comparisons with votes appear. An absent current quest/recording is
  unevaluated, not a zero-rated loser. Use the catalogue to enumerate all quests.
- Repeated ballots from one visitor replace the previous selection for that
  exact comparison. Exports count these retained choices, not click history.

## Counts and interpretation

`selectedVotes` counts selections. `offeredVotes` counts **submitted ballots**
containing that candidate. It does not count page impressions or prove every
candidate was listened to. A missing library receives neither a selection nor
an offered vote. Group totals intentionally include the known current recording
for each quest; retain `comparisons` when analysing a specific revision or NPC.

In a ballot with A, B and C, selecting A contributes A>B and A>C. It gives no
ordering between B and C. `pairwise` contains both directions: each pair's wins
equal the reverse pair's losses. Do not sum both directions as distinct votes.
For A against B, use `wins / (wins + losses)` when the denominator is nonzero,
and always retain that denominator. This describes preferences within observed
opponent sets; unequal samples and changing mixes of quests still affect it.

Unknown race or sex remains a separate null group. Exclude those groups when
deriving recommendations for a known race/sex. Race labels are copied from the
shared speaker database (including its `child` voice category); the exporter
does not infer biology or relabel those categories.

The export provides evidence, not a definitive winner or a ready-to-load addon
rating table. Minimum sample sizes, ties and confidence rules should be decided
before automatically applying recommendations. The addon rating importer is a
separate step. `schemaVersion` changes when the export contract changes.

`summary.votes = currentVotes + historicalVotes`; the unknown-demographics count
is a subset of current votes. `votedComparisons` includes historical comparisons;
`catalogueComparisons` includes unevaluated current comparisons as well.
