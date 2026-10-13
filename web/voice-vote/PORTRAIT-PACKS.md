# Portrait model packs

The website keeps the original quality, full body, textures, camera and lighting.
There is no waist cut, mesh simplification or texture downscaling.

The renderer downloads one base skin, but the original M2 can contain vertices
for other skins and hundreds of animation clips. The offline packer copies the
base skin's vertex range and the tracks required for base Stand and Talk,
including dependencies and per-track fallbacks. It retains the skeleton,
material animation and authored cameras. Selected external `.anim` descriptors
still point to the original animation files. Sequence indices stay unchanged;
unused sequence table slots do not contain animation keys.

This is an adapter for the cached viewer, not a general M2 converter. External
SKID skeletons without parents are packed separately under `skel/`; the model and
skeleton are verified and served as a pair. Particle/ribbon data and all their
tracks are preserved, including particle lifetime and global animation.
Parent skeleton layouts still fail closed pending explicit verification.
Inspect every `unsupported` entry and report its transfer size and affected
portraits. Never present an original fallback as an optimized model.

## Build and verify after changing model assets

Run from the repository root after normal model-cache preparation. Requires
installed Firefox/Playwright and cached viewer assets. Browser tests block
external network access and do not submit votes.

```powershell
npm.cmd --prefix web/voice-vote run test:portrait-packs
node web/voice-vote/install-portrait-packs.mjs
```

`tests/portrait-pack-cache.mjs` parses source and packed bytes through the actual
cached viewer, comparing retained vertices, tracks, materials, attachments and
cameras. It writes M2 files and a report to `artifacts/portrait-packs/`, outside
Git. `tests/portrait-pack-render.mjs` compares rest, nine Talk samples and return
to rest in WebGL, including bone matrices, materials and camera profile. The pose test
clears frame-dependent cloth simulation overrides in both viewers so it compares
authored animation tracks at identical times. Runtime cloth rendering is unchanged. Use
`--quests=1116,898,271,5657` to select external-skeleton and emitter cases. These
families are also included in the default regression set. Before/after screenshots and
mismatching poses are saved alongside the report. The known original camera
failure for quest 97290 is not an optimization test.

Optimization and verification are mandatory whenever server models change.
The installer rechecks hashes and publishes M2 and `skel/*.skel` files under
`artifacts/voice-vote-model-cache/portrait-packs-v1/`. Original M2/skin files are
never modified. Transfer that directory into the existing `model_cache` volume
alongside `modelviewer/`, before deploying the web image. Do not put models in
the application image. Preserve the manifest and filenames.

The frontend uses `/modelviewer/portrait-v1/classicplus/`. Asset requests select
verified packs for M2 and SKEL; other assets use the original cache. A changed viewer, source
M2/skeleton, skin or derived file invalidates the pair. Missing or invalid packs use the
original assets. Camera calibration reads the original M2. The audio-preload
deployment gate remains mandatory; pack safety tests also run in image builds.

Hash verification is cached by file timestamps and size. Models are read
asynchronously, not pinned in Node's heap. Logs include `portraitPack` for M2/SKEL
requests. Old asset paths remain supported for already open pages.
