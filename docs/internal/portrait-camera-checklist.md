# Portrait Camera Validation Checklist

Internal development checklist. This file is not included in the release ZIP or
deployed to the game: the build copies only `src/`, the sound-pack TOCs and
`USER_README.md`.

Last updated: 2026-09-29.

## Confirmed in game

Checked entries reflect user confirmation, not automated tests. Approval applies
to the tested models; it does not automatically cover every model variant using
the same profile.

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

## Awaiting in-game confirmation

- [ ] Human — child. Raised on Shawn feedback: profile `human_child`,
  vertical offset `-0.025` → `0.08`, distance `1.15`, lateral `0`.
  Covers human boy/girl models and their variants; inspect both upright and
  downward talking poses. Adult human profiles remain separate.

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
  are not yet confirmed. Male model `7478487` keeps the fallback framing.

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
