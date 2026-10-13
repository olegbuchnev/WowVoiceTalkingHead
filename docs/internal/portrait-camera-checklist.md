# Portrait Camera Validation Checklist

Internal development checklist. This file is not included in the release ZIP or
deployed to the game: the build copies only the runtime from `src/`.

Last updated: 2026-10-13.

## Confirmed in game

Checked entries reflect user confirmation, not automated tests. Approval applies
to the tested models; it does not automatically cover every model variant using
the same profile.

- [x] Human girl — quest `92110`, NPC `249713`, display `257`, model `124456`.
  User confirmed final framing on 2026-10-13: `human_child_female`, distance `1.5`,
  lateral `0.02`, vertical `0.015`. The initial correction at `0` was raised
  slightly on request. The former generic child lift (`0.08`) clipped the face.
  Additional check candidate: quest `5149`, Pamela Redpath, the same model.
  Website profile deployed on 2026-10-13. This model has no native camera measurement;
  the male child's calibration must not be assumed to apply to the girl.

- [x] Orc Orphan — NPC `14444`, quest `925`, model `125367`, display `14589`.
  User confirmed final framing on 2026-10-13: `orc_child`, distance `1.5`,
  lateral `0.02`, vertical `0.04`. More distance accommodates the forward Talk
  dip; the rightward shift keeps the bent pose inside the frame.
  Other orc models retain their existing profiles. The beta client has this
  framing; website deployment is still pending and uses the same source settings.

- [x] Goblin — male. Profile: `goblin_male`. User confirmed the leftward shift:
  distance `1.3`, lateral offset `-0.04`, vertical offset `0.04`.
  The tested model file ID was not reported; other variants remain unverified.
- [x] Troll — male. Profile: `troll`. Keep the accepted lateral offset of `0.12`.
- [x] Troll — female. Profile: `troll_female`. Confirmed after removing the lateral offset.
- [x] Blood elf — female. Profile: `bloodelf_female`. User confirmed revised
  framing: distance `1.45`, lateral offset `0`, vertical offset `0.025`.
  The former vertical offset `0.10` clipped the upper half of the head.
  The tested model file ID was not reported; other variants remain unverified.
- [x] Orc — previously tested model(s); sex was not explicitly recorded. Profile: `orc`. Preserve the accepted framing.
- [x] Orc — female. Profile: `orc_female`. User confirmed revised framing:
  distance `1.35`, lateral offset `-0.04`, vertical offset `0`.
  The earlier lateral offset `-0.06` placed the upright pose too far left.
  The tested model file ID was not reported; other variants remain unverified.
- [x] Tauren — previously tested model(s); sex was not explicitly recorded. Profile: `tauren`. Preserve framing for models without the female correction below.

- [x] Night elf — male. Profile: `nightelf_male`. User confirmed the raised,
  rightward framing on Keeper Ilthalaine: distance `1.18`, lateral offset `0.04`,
  vertical offset `0.025`. The tested model file ID was not reported;
  other standard, HD and HD SDR variants remain unverified.

- [x] Human — male. Profile: `human_male`. User confirmed the revised framing
  on Marshal McBride: distance `1.15`, lateral offset `0.02`, vertical offset `0`.
  The initial `0.04` / `0.025` shift was too strong and was reduced by half.
  The tested model file ID was not reported; other male human variants remain
  unverified.

- [x] Tauren — female. Profile: `tauren_female`. User confirmed the slight lift
  on Yama Snowhoof: vertical offset `-0.025` → `0`, distance `1.1`, lateral `0`.
  Keep this distance: the strong talking sway is accepted rather than making
  the portrait visibly smaller. The tested model file ID was not reported;
  other standard, HD and HD SDR female variants remain unverified.

- [x] Undead — female. Profile: `undead_female`. User confirmed the lowered,
  rightward framing on Tabitha Heartweaver: vertical offset `0`, distance `1.22`,
  lateral `0.02`. The tested model file ID was not reported; other standard,
  HD and HD SDR female variants remain unverified.

- [x] Furbolg — male. User confirmed the lowered framing on Krolg (quest `1046`):
  profile `furbolg`, vertical offset `0.04` → `-0.04`, distance `1.32`, lateral `0`.
  The tested model file ID was not reported; other variants remain unverified.
  CatQuest's NPC record `3897` labels Krolg as `tauren`, `male`; that race field
  does not identify the actual furbolg model used for camera selection.

- [x] Dwarf — female. User confirmed the lowered framing on Mountaineer Pebblebitty
  (quest `3182`): profile `dwarf_female`, vertical offset `0.025` → `0`, distance
  `1.2`, lateral `0`. The tested model file ID was not reported; other standard,
  HD, SDR, Dark Iron, Earthen and female rifleman variants remain unverified.

- [x] Skyborne — male. User confirmed the revised framing on Raan Wildwind
  (quest `96646`, NPC `263664`): profile `skyborne_male`, vertical offset `0`,
  distance `1.1`, lateral `0`. Applied to model file ID `7478487` as a per-model
  override (`model:7478487` in diagnostics). Identity comes from the locally
  installed `CatQuest/RaceModels.lua`; the live model ID was not reported.
  Female model `7478494` retains its existing framing.

- [x] Goblin — Forever SD male model `8125066`, confirmed by live `/thead diag`
  on Mebok Mizzyrix (NPC `3446`, quest `1069`). Previously used `default` and
  showed only the top of the head. Now mapped to the existing `goblin_male`
  profile: vertical offset `0.04`, distance `1.3`, lateral `-0.04`.
  User confirmed the family framing in game; no SD-specific profile is needed
  for this model.
  Models `119376`, `1838570` and `124224` retain `goblin_male` unchanged.

- [x] Human Orphan — NPC `14305`, quest `1479`, model `124495` confirmed by
  live diagnostics. User confirmed final framing: distance `1.5`, vertical
  offset `0.04`, lateral offset `0.02`. Face clipping is resolved and the
  model is centered after the rightward adjustment. This correction applies
  to every NPC using model `124495`; the shared `human_child_male` profile now
  carries these values for male human child variants. Other variants still need visual checks.

- [x] Human child — Shawn / Шоун (NPC `8965`, quest `3741`, «Ожерелье Хилари»).
  User confirmed the current framing on 2026-10-11, after the quest `1479`
  correction. Shawn's live model file ID was not reported. This confirmation
  applies to the tested NPC, not every variant of the `human_child_male` profile.

- [x] Dwarf — male. User confirmed the final height on 2026-10-11 after the
  Prospector Ryedol and Balir Frosthammer screenshots:
  profile `dwarf`, vertical offset `0.025` → `0.015` → `0.005`, distance `1.2`, lateral `0`.
  The second small step follows Balir Frosthammer feedback: the top of the head
  was still slightly clipped at `0.015`.
  Applies to the shared male profile, including standard, HD, SDR, Dark Iron,
  Earthen and rifleman variants. The live model file ID was not reported;
  other variants remain individually unverified.

## Awaiting in-game confirmation

- [ ] Human — female. Raised on Priestess Josetta feedback: profile `human_female`,
  vertical offset `-0.025` → `0.025`, distance `1.15`, lateral `0`.
  Applies to standard, HD and SDR character variants; visual confirmation pending.

- [ ] Gnomes. Lowered on Narain Soothfancy feedback: vertical offset `0.08` → `0`,
  distance `1.25`, lateral `0`. Applies to the `gnome` profile; visual confirmation pending.

- [ ] Skyborne — female. Model file ID `7478494`, profile `skyborne_female`
  applied as a per-model override (`model:7478494` in diagnostics).
  Refined on Ayessa Dawnsinger feedback (quest `95349`): vertical offset
  `0.025` → `0.015` for slightly more room above the hair after the initial lift
  from `-0.025`. Distance `1.1`, lateral `0`. Identity comes from the
  locally installed `CatQuest/RaceModels.lua`; live model ID and visual result
  are not yet confirmed. Male model `7478487` uses a separate correction below.

- [ ] Undead — male. Profile: `undead_male`. Reopened after feedback on
  Deathguard Kristof: lowered very slightly, vertical offset `0.025` → `0.015`,
  distance `1.22`, lateral `0`. Previously confirmed framing used the shared
  `undead` profile. Applies to standard, HD and HD SDR male undead; the tested
  model file ID was not reported.

- [x] Night elf — female. User confirmed framing on Sentinel Kyra Starsong:
  profile `nightelf_female`, vertical offset `0.025` → `0.015` to leave room
  above the hair after the initial lift from `-0.025`. Distance `1.18`,
  lateral `0`. Standard (`120590`), HD (`921844`) and HD SDR (`1838574`)
  variants are mapped. The tested model file ID was not reported;
  other variants remain individually unverified.

## Maintenance

- Add a checked entry only after explicit in-game confirmation.
- Record sex and model file ID when available; do not infer approval for the opposite sex.
- Reopen an affected entry if its camera parameters or animation behavior changes.
- Other archetypes and variants remain unverified until recorded here.

Camera settings: [CameraProfiles.lua](../../src/CameraProfiles.lua).
Model mappings: [CameraModels.lua](../../src/CameraModels.lua).
