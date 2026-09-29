event('ADDON_LOADED')
event('PLAYER_LOGIN')
local WV=WowVoice
local families, count, protected = {}, 0, 0
local model={}
function model:GetModelFileID() return self.id end
for id, key in pairs(WV.CameraModelProfiles) do
    model.id=id
    local profile, actual, fileID=WV:GetPortraitCameraProfile(model)
    assert(fileID==id and actual==key, 'every generated model mapping must resolve to a profile')
    assert(profile.distance>=1.1 and profile.distance<=1.5)
    assert(type(profile.y)=='number' and type(profile.z)=='number')
    count=count+1; families[key]=true
    if key=='orc' or key=='tauren' then
        WV.PortraitCameraOverrides[id]={distance=9,y=9,z=9}
        profile=WV:GetPortraitCameraProfile(model)
        assert(profile.distance==1.1 and profile.y==0 and profile.z==-.025)
        WV.PortraitCameraOverrides[id]=nil
        protected=protected+1
    end
end
assert(count>1000 and protected>=58)
for _, family in ipairs({'goblin','troll','furbolg','murloc','centaur','dragon','ogre','quillboar'}) do
    assert(families[family])
end
assert(WV.CameraModelProfiles[125358]=='aquatic', 'orcas are not orcs')
assert(WV.CameraModelProfiles[124225]=='construct', 'goblin shredders are machines')
for _, id in ipairs({121087,949470,1838580}) do
    model.id=id
    local profile,key=WV:GetPortraitCameraProfile(model)
    assert(key=='orc_female' and profile.y<0 and profile.z>WV.PortraitCameraProfiles.default.z
        and profile.distance>WV.PortraitCameraProfiles.default.distance,
        'adult female orcs need their own framing, not the protected orc default')
end
for _, id in ipairs({121287,917116,1838578,1968587,125362,125367,118652}) do
    model.id=id
    local profile,key=WV:GetPortraitCameraProfile(model)
    assert(key=='orc' and profile.distance==1.1 and profile.y==0 and profile.z==-.025,
        'female orc correction must not affect males, children or other orc families')
end
for _, id in ipairs({119376,1838570,124224}) do
    model.id=id
    local profile,key=WV:GetPortraitCameraProfile(model)
    assert(key=='goblin_male' and profile.y<0 and profile.distance==1.3 and profile.z==.04,
        'male goblins need leftward room for the nose while preserving accepted zoom and height')
end
for _, id in ipairs({119369,1838568,516489,518459,321588,368597}) do
    model.id=id
    local profile,key=WV:GetPortraitCameraProfile(model)
    assert(key=='goblin' and profile.y==0,
        'male goblin correction must not affect females, children or related creatures')
end
for _, id in ipairs({116921,1100258,1839709}) do
    model.id=id
    local profile,key=WV:GetPortraitCameraProfile(model)
    assert(key=='bloodelf_female' and profile.y==0,
        'female blood elf variants need centered framing for movement in both directions')
    assert(profile.distance>WV.PortraitCameraProfiles.elf.distance and profile.z>WV.PortraitCameraProfiles.elf.z,
        'female blood elf framing needs more room and a higher model position')
end
for _, id in ipairs({117170,1100087,1853408,1733758,123079}) do
    model.id=id
    local profile,key=WV:GetPortraitCameraProfile(model)
    assert(key=='elf' and profile.distance==1.18 and profile.y==0 and profile.z==-.025,
        'female blood elf correction must not affect males, other elves or children')
end
for _, id in ipairs({122414,1018060,1838588,1662187,1710180,2463883}) do
    model.id=id
    local profile,key=WV:GetPortraitCameraProfile(model)
    assert(key=='troll_female' and profile.y==0 and profile.distance==1.28 and profile.z==.025)
end
for _, id in ipairs({122560,1022938,1838590,1630447}) do
    model.id=id
    local profile,key=WV:GetPortraitCameraProfile(model)
    assert(key=='troll' and profile.y==.12 and profile.distance==1.28 and profile.z==.025,
        'accepted male troll framing must not change')
end
print('PASS: all model IDs resolve, female orcs have dedicated framing, other orc/tauren mappings preserve accepted framing')

WV:ToggleHeadPreview()
local head=frames.WowVoiceTalkingHead
head.Model.modelFileID=7478494
head.Model:CompleteLoad(1234)
assert(head.Model.cameraProfile=='model:7478494' and head.Model.modelPosition[3]==.015
    and head.Model.cameraDistanceScale==1.1 and head.Model.modelPosition[2]==0,
    'female Skyborne need a lift even though their model is absent from the generated listfile')
head.Model.modelFileID=7478487
head.Model:CompleteLoad(1234)
assert(head.Model.cameraProfile=='default' and head.Model.modelPosition[3]==-.025,
    'female Skyborne lift must not carry over to the male model')
for _, id in ipairs({119376,1838570,124224,119369,122560,122414,1018060,116921,1100258,1839709,117170,121087,949470,1838580,121287,121961,986648,1839008,122055,121608,997378,1838582,121768,959310,1838584,124225,125358,99999999}) do
    head.Model.modelFileID=id
    head.Model:CompleteLoad(1234)
    local profile,key=WV:GetPortraitCameraProfile(head.Model)
    assert(head.Model.cameraProfile==key and head.Model.cameraFileID==id)
    assert(head.Model.zoom==1 and head.Model.rotation==0)
    assert(head.Model.cameraDistanceScale==profile.distance)
    assert(head.Model.modelPosition[1]==0 and head.Model.modelPosition[2]==profile.y
        and head.Model.modelPosition[3]==profile.z)
    if id==121287 or id==122055 or id==99999999 then
        assert(head.Model.cameraDistanceScale==1.1 and head.Model.modelPosition[2]==0
            and head.Model.modelPosition[3]==-.025, 'previous model offsets must be cleared')
    end
end
-- The model's identity, never the current target's race, drives journal cameras.
npcGUID='Creature-0-1-0-1-999-0000000099'
head.Model.modelFileID=119376
WV:HideHeadPreview(); WV:ReplayQuest(179)
assert(head.Model.cameraProfile=='goblin_male' and head.Model.modelPosition[2]<0 and head.Model.modelPosition[3]==.04)
local sounds=#plays
do
    assert(head.Model.cameraProfile=='goblin_male' and #plays==sounds)
end
local profile,key=WV:GetPortraitCameraProfile({})
assert(key=='default' and profile.distance==1.1)
profile,key=WV:GetPortraitCameraProfile({GetModelFileID=function() error('unsupported') end})
assert(key=='default' and profile.z==-.025)
model.id=119376
WV.PortraitCameraOverrides[119376]={distance=1.4,y=.02,z=.1}
profile,key=WV:GetPortraitCameraProfile(model)
assert(key=='model:119376' and profile.z==.1)
WV.PortraitCameraOverrides[119376]=nil
command('diag'); assert(has('Camera: model=119376 profile=goblin_male'))
print('PASS: loaded model selects camera for replay and preview, offsets reset between species, optional API fallback and per-model corrections')

WV:Silence()
restored('1','0.37')
assert(frames.WowVoiceStopButton==nil, 'standalone stop control is removed')
