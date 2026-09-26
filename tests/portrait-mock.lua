local baseCreateFrame = CreateFrame
gameUIShown = true
function SetUIVisibility(shown) gameUIShown = shown end
C_Texture = { GetAtlasInfo = function(name)
    if modernRadioAtlases and (name=='common-dropdown-tickradial' or name=='common-dropdown-icon-radialtick-yellow') then
        return {width=18,height=18}
    end
end }
playerGUID = 'Player-1-ABC'
npcGUID = 'Creature-0-1-0-1-658-0000000001'
npcName, npcDisplay = 'Стен Крепкорук', 1234
modelLoadsImmediately = true
playerDisplayID, playerSetUnitSuccess, playerModelEvent = 98765, true, true
function UnitGUID(unit)
    if unit == 'player' then return playerGUID end
    if unit == 'npc' or unit == 'target' then return npcGUID end
end
function UnitName(unit)
    if unit == 'player' then return 'Тестовый персонаж' end
    if unit == 'npc' or unit == 'target' then return npcName end
end
C_QuestLog = { GetTitleForQuestID = function(id) return 'Journal quest '..id end }
UIParent:SetSize(1920,1080)
function UIParent:GetWidth() return self.width end
function UIParent:GetHeight() return self.height end
function UIParent:GetCenter() return self.width/2,self.height/2 end
local function region(fontObject)
    local t = {visible=true,fontObject=fontObject,fontFile=fontObject or 'mock-font',
        fontSize=fontObject=='QuestTitleFont' and 18 or fontObject=='QuestFont' and 13 or 14,fontFlags=''}
    function t:SetTexture(s)
        self.texture=s
        if s==missingTexture then return false end
        return true
    end
    function t:SetBlendMode(mode) self.blendMode=mode end
    function t:SetAtlas(s) self.atlas=s end
    function t:SetVertexColor(...) self.vertexColor={...} end
    function t:SetTexCoord(...) self.texCoord={...} end
    function t:SetText(s) self.text=s end
    function t:SetTextColor(...) self.textColor={...} end
    function t:GetText() return self.text end
    function t:SetSize(w,h) self.width,self.height=w,h end
    function t:SetPoint(...) self.point={...} end
    function t:ClearAllPoints() self.point=nil end
    function t:SetJustifyH() end
    function t:SetJustifyV() end
    function t:SetWordWrap() end
    function t:SetWidth(w) self.width=w end
    function t:SetHeight(h) self.height=h end
    function t:GetFont() return self.fontFile,self.fontSize,self.fontFlags end
    function t:SetFont(file,size,flags) self.fontFile,self.fontSize,self.fontFlags=file,size,flags end
    function t:GetSpacing() return 0 end
    function t:SetSpacing() end
    function t:GetStringHeight()
        local rows=0
        for line in ((self.text or '')..'\n'):gmatch('(.-)\n') do
            local characters=#line:gsub('[\128-\191]','')
            rows=rows+math.max(1,math.ceil(characters/math.max(1,math.floor(self.width/(self.fontSize/2)))))
        end
        return rows*self.fontSize
    end
    function t:SetColorTexture(...) self.color={...} end
    function t:SetAllPoints() end
    function t:SetAlpha(v) self.alpha=v end
    function t:Show() self.visible=true end
    function t:Hide() self.visible=false end
    return t
end
function CreateFrame(kind,name,parent,template)
    local f = baseCreateFrame(kind,name,parent,template)
    function f:GetFrameLevel() return self.frameLevel or 1 end
    function f:SetFrameLevel(v) self.frameLevel=v end
    function f:SetNormalTexture(v) self.normalTexture=v end
    function f:SetCheckedTexture(v) self.checkedTexture=v end
    function f:SetPushedTexture(v) self.pushedTexture=v end
    function f:SetHighlightTexture(v) self.highlightTexture=v end
    function f:SetScale(v) self.scale=v end
    function f:GetScale() return self.scale or 1 end
    function f:IsShown() return self.visible end
    function f:Show()
        local was=self.visible; self.visible=true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function f:Hide()
        local was=self.visible; self.visible=false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function f:EnableMouse(v) self.mouseEnabled=v end
    function f:SetAllPoints(parent) self.allPoints=parent end
    function f:RegisterForClicks(...) self.clicks={...} end
    function f:StartMoving() self.moving=true end
    function f:StopMovingOrSizing() self.moving=false end
    function f:SetAutoFocus() end
    function f:SetMaxLetters() end
    function f:ClearFocus() self.focus=false end
    function f:SetFocus() self.focus=true end
    function f:GetText() return self.text or '' end
    function f:SetChecked(v) self.checked=v end
    function f:GetChecked() return self.checked end
    function f:SetClampedToScreen() end
    function f:SetBackdrop(v) self.backdrop=v end
    function f:SetBackdropColor(...) self.backdropColor={...} end
    function f:SetBackdropBorderColor(...) self.backdropBorderColor={...} end
    function f:CreateTexture() return region() end
    function f:CreateFontString(_,_,fontObject) return region(fontObject) end
    function f:SetStatusBarTexture() end
    function f:SetStatusBarColor(...) self.statusBarColor={...} end
    function f:SetMinMaxValues() end
    function f:SetValue(v) self.value=v end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:SetScrollChild(child) self.child=child end
    function f:UpdateScrollChildRect() end
    function f:SetVerticalScroll(v) self.scroll=v end
    function f:GetCenter()
        local p=self.points[1]
        local parent=p[2] or self.parent
        local cx,cy=parent:GetCenter()
        local function offset(point,w,h)
            return (point:find('LEFT') and -w/2 or point:find('RIGHT') and w/2 or 0),
                (point:find('TOP') and h/2 or point:find('BOTTOM') and -h/2 or 0)
        end
        local rx,ry=offset(p[3],parent:GetWidth(),parent:GetHeight())
        local x,y=offset(p[1],self:GetWidth(),self:GetHeight())
        return cx+rx-x+(p[4] or 0),cy+ry-y+(p[5] or 0)
    end
    if kind == 'PlayerModel' then
        function f:SetModelAlpha(v) self.modelAlpha=v end
        function f:ClearModel() self.displayID=0; self.unit=nil end
        function f:GetDisplayInfo() return self.displayID or 0 end
        function f:GetModelFileID() return self.modelFileID or 0 end
        function f:CompleteLoad(display)
            self.displayID=display
            if self.scripts.OnModelLoaded then self.scripts.OnModelLoaded(self) end
        end
        function f:SetUnit(unit)
            self.unit=unit
            if unit=='player' and not playerSetUnitSuccess then return false end
            if modelLoadsImmediately then
                local display=unit=='player' and playerDisplayID or npcDisplay
                if unit=='player' and not playerModelEvent then self.displayID=display
                else self:CompleteLoad(display) end
            end
            return true
        end
        function f:SetDisplayInfo(id) self:CompleteLoad(id) end
        function f:SetCreature(id) self.creatureID=id; self:CompleteLoad(id+10000) end
        function f:SetCamera(v) self.camera=v end
        function f:RefreshCamera() self.cameraRefreshes=(self.cameraRefreshes or 0)+1 end
        function f:SetPortraitZoom(v) self.zoom=v end
        function f:SetCamDistanceScale(v) self.cameraDistanceScale=v end
        function f:SetPosition(x,y,z) self.modelPosition={x,y,z} end
        function f:SetRotation(v) self.rotation=v end
        function f:HasAnimation(v) return v == 60 end
        function f:SetAnimation(v) self.animation=v end
    end
    return f
end
function IsShiftKeyDown() return false end
settingsCategories={}
Settings={
    RegisterCanvasLayoutCategory=function(panel,name)
        return {panel=panel,name=name,GetID=function() return 123 end}
    end,
    RegisterAddOnCategory=function(category) settingsCategories[#settingsCategories+1]=category end,
    OpenToCategory=function(id)
        assert(id==123)
        settingsCategories[1].panel:Show()
    end,
}
function portraitEvent(event,id)
    local f = frames.WowVoicePortraitEvents
    assert(f.events[event], 'unregistered portrait event '..event)
    f.scripts.OnEvent(f,event,id)
end
function questCache() return WowVoiceDB.questSpeakers[playerGUID] end
