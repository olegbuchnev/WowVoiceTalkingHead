# Portrait Camera Validation Checklist

Internal development checklist. This file is not included in the release ZIP or
deployed to the game: the build copies only `src/`, the sound-pack TOCs and
`USER_README.md`.

Last updated: 2026-09-26.

## Confirmed in game

Checked entries reflect user confirmation, not automated tests. Approval applies
to the tested models; it does not automatically cover every model variant using
the same profile.

- [x] Undead — male. Profile: `undead`.
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
- [x] Tauren — previously tested model(s); sex was not explicitly recorded. Profile: `tauren`. Preserve the accepted framing.

- [x] Night elf — male. Profile: `nightelf_male`. User confirmed the raised,
  rightward framing on Keeper Ilthalaine: distance `1.18`, lateral offset `0.04`,
  vertical offset `0.025`. The tested model file ID was not reported;
  other standard, HD and HD SDR variants remain unverified.

- [x] Human — male. Profile: `human_male`. User confirmed the revised framing
  on Marshal McBride: distance `1.15`, lateral offset `0.02`, vertical offset `0`.
  The initial `0.04` / `0.025` shift was too strong and was reduced by half.
  The tested model file ID was not reported; other male human variants remain
  unverified.

## Maintenance

- Add a checked entry only after explicit in-game confirmation.
- Record sex and model file ID when available; do not infer approval for the opposite sex.
- Reopen an affected entry if its camera parameters or animation behavior changes.
- Other archetypes and variants remain unverified until recorded here.

Camera settings: [CameraProfiles.lua](../../src/CameraProfiles.lua).
Model mappings: [CameraModels.lua](../../src/CameraModels.lua).
