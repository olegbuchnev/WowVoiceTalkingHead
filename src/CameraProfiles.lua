-- Initial model-family framing, to be refined with in-game feedback.
-- Offsets move the model, not the camera. Orc models without a dedicated
-- profile and tauren models without a dedicated profile retain the original default.
local WV = WowVoice
local profiles = {
    default = { distance = 1.1, y = 0, z = -0.025 },
    -- Female orcs lean down and right while talking; allow room for both poses.
    -- Rightward adjustment confirmed in game for Seereth Stonebreaker, 2026-10-03.
    orc_female = { distance = 1.35, y = -0.02, z = 0 },
    -- Slightly lift female tauren; keep the accepted zoom and lateral position.
    tauren_female = { distance = 1.1, y = 0, z = 0 },
    human = { distance = 1.15, y = 0, z = -0.025 },
    -- Lift adult female humans within the portrait.
    human_female = { distance = 1.15, y = 0, z = 0.025 },
    -- Children sit lower than adults and dip during the talking animation.
    human_child = { distance = 1.15, y = 0, z = 0.08 },
    -- Lift male humans and shift slightly right within the portrait.
    human_male = { distance = 1.15, y = 0.02, z = 0 },
    dwarf = { distance = 1.2, y = 0, z = 0.025 },
    -- Lower adult female dwarves to leave room above their hair while talking.
    dwarf_female = { distance = 1.2, y = 0, z = 0 },
    -- Lower gnomes to leave room above the head during the talking animation.
    gnome = { distance = 1.25, y = 0, z = 0 },
    goblin = { distance = 1.3, y = 0, z = 0.04 },
    goblin_male = { distance = 1.3, y = -0.04, z = 0.04 },
    troll = { distance = 1.28, y = 0.12, z = 0.025 },
    troll_female = { distance = 1.28, y = 0, z = 0.025 },
    elf = { distance = 1.18, y = 0, z = -0.025 },
    -- Lift male night elves and shift slightly right within the portrait.
    nightelf_male = { distance = 1.18, y = 0.04, z = 0.025 },
    -- Lift adult female night elves, preserving their zoom and horizontal position.
    nightelf_female = { distance = 1.18, y = 0, z = 0.015 },
    -- Leave room for the female blood elf's wide talking animation on both sides.
    -- A 0.10 vertical offset clipped the head at the top; use a smaller lift.
    -- The revised framing was confirmed in game for the tested female blood elf.
    bloodelf_female = { distance = 1.45, y = 0, z = 0.025 },
    -- Keep the lift for female Skyborne, with a little more room above the hair.
    skyborne_female = { distance = 1.1, y = 0, z = 0.015 },
    -- A 0.025 offset clipped the hair; use half the lift from the default.
    skyborne_male = { distance = 1.1, y = 0, z = 0 },
    undead = { distance = 1.22, y = 0, z = 0.025 },
    -- Lower male undead just enough to leave a small margin above the head.
    undead_male = { distance = 1.22, y = 0, z = 0.015 },
    -- Give female undead more room above the head and shift slightly right.
    undead_female = { distance = 1.22, y = 0.02, z = 0 },
    draenei = { distance = 1.2, y = 0, z = -0.025 },
    worgen = { distance = 1.3, y = 0, z = 0.04 },
    pandaren = { distance = 1.22, y = 0, z = 0 },
    vulpera = { distance = 1.3, y = 0, z = 0.06 },
    dracthyr = { distance = 1.3, y = 0, z = 0 },
    ogre = { distance = 1.35, y = 0, z = 0 },
    giant = { distance = 1.4, y = 0, z = 0 },
    -- Lower furbolgs so the upper face stays inside the portrait.
    furbolg = { distance = 1.32, y = 0, z = -0.04 },
    gnoll = { distance = 1.3, y = 0, z = 0.04 },
    murloc = { distance = 1.35, y = 0, z = 0.06 },
    kobold = { distance = 1.3, y = 0, z = 0.08 },
    quillboar = { distance = 1.3, y = 0, z = 0.025 },
    trogg = { distance = 1.3, y = 0, z = 0.04 },
    sporeling = { distance = 1.4, y = 0, z = 0.025 },
    serpent = { distance = 1.35, y = 0, z = 0 },
    tortollan = { distance = 1.35, y = 0, z = 0.025 },
    hozen = { distance = 1.35, y = 0, z = 0.025 },
    drogbar = { distance = 1.35, y = 0, z = 0 },
    niffen = { distance = 1.3, y = 0, z = 0.05 },
    centaur = { distance = 1.4, y = 0, z = 0 },
    dryad = { distance = 1.35, y = 0, z = 0 },
    naga = { distance = 1.4, y = 0, z = 0.025 },
    satyr = { distance = 1.3, y = 0, z = 0.025 },
    harpy = { distance = 1.4, y = 0, z = 0 },
    dragon = { distance = 1.5, y = 0, z = 0 },
    dragonkin = { distance = 1.35, y = 0, z = 0 },
    treant = { distance = 1.45, y = 0, z = 0 },
    elemental = { distance = 1.45, y = 0, z = 0 },
    demon = { distance = 1.4, y = 0, z = 0 },
    ethereal = { distance = 1.25, y = 0, z = 0 },
    tuskarr = { distance = 1.3, y = 0, z = 0.025 },
    arrakoa = { distance = 1.35, y = 0, z = 0.025 },
    tolvir = { distance = 1.45, y = 0, z = 0 },
    construct = { distance = 1.4, y = 0, z = 0 },
    quadruped = { distance = 1.45, y = 0, z = 0 },
    bird = { distance = 1.4, y = 0, z = 0 },
    aquatic = { distance = 1.5, y = 0, z = 0 },
    insect = { distance = 1.45, y = 0, z = 0 },
}
WV.PortraitCameraProfiles = profiles

-- Add narrowly scoped corrections here when a particular model needs them.
-- Keys are model file IDs, never NPC IDs or creature display IDs.
WV.PortraitCameraOverrides = {
    -- Forever model absent from the generated listfile mapping. Identity is
    -- recorded in the locally installed CatQuest/RaceModels.lua (Skyborne).
    [7478487] = profiles.skyborne_male,
    [7478494] = profiles.skyborne_female,
    -- Live /thead diag: Mebok Mizzyrix, NPC 3446, quest 1069, SD models.
    -- Reuse the male goblin family framing for this unlisted Forever model.
    [8125066] = profiles.goblin_male,
}

function WV:GetPortraitCameraProfile(model)
    local fileID
    if type(model.GetModelFileID) == "function" then
        local ok, value = pcall(model.GetModelFileID, model)
        if ok and type(value) == "number" and value > 0 then fileID = value end
    end
    local key = fileID and self.CameraModelProfiles and self.CameraModelProfiles[fileID] or "default"
    -- Protected families retain the accepted framing even when overrides exist.
    if key == "orc" or key == "tauren" then return profiles.default, key, fileID end
    local override = fileID and self.PortraitCameraOverrides[fileID]
    if override then return override, "model:" .. fileID, fileID end
    return profiles[key] or profiles.default, profiles[key] and key or "default", fileID
end
