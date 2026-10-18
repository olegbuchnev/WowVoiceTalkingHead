local WV,R,E,C,L=WowVoice,TalkingHeadRuVoiceRanking,TalkingHeadRuVoiceGroupExamples,WowVoiceComparison,WowVoiceLocale
local names={wowvoice='WowVoice',catquest='CatQuest',wayfarer='Wayfarer'}
local colors={wowvoice={0.25,0.7,1},catquest={1,0.55,0.2},wayfarer={0.4,0.85,0.45}}
function WV:CreateVoiceGroupView(parent,label,button)
    local viewport=CreateFrame('ScrollFrame','TalkingHeadRuVoiceGroupView',parent,'UIPanelScrollFrameTemplate')
    viewport:SetPoint('TOPLEFT',parent,'TOPLEFT',20,-116)
    viewport:SetPoint('BOTTOMRIGHT',parent,'BOTTOMRIGHT',-30,12)
    local frame=CreateFrame('Frame',nil,viewport)
    frame:SetPoint('TOPLEFT',viewport,'TOPLEFT',0,0)
    frame:SetSize(536,402); viewport:SetScrollChild(frame)
    viewport.Body=frame
    label(frame,'Перетащите библиотеки в нужном порядке.',0,0,532,22)
    frame.Cards={}
    local dragging
    local ghost=CreateFrame('Frame',nil,frame,'BackdropTemplate')
    ghost:SetSize(166,66); ghost:SetFrameLevel(frame:GetFrameLevel()+20)
    ghost:SetBackdrop({bgFile='Interface\\ChatFrame\\ChatFrameBackground',edgeFile='Interface\\ChatFrame\\ChatFrameBackground',edgeSize=1})
    ghost:SetBackdropColor(0.1,0.1,0.1,1); ghost:SetBackdropBorderColor(1,0.82,0.25,1)
    ghost.Text=label(ghost,'',10,-22,146,24,'GameFontHighlight'); ghost:Hide()
    local function target()
        if not GetCursorPosition then return end
        local x,y=GetCursorPosition()
        for index,card in ipairs(frame.Cards) do
            local cx,cy=card:GetCenter(); local scale=card:GetEffectiveScale()
            if cx and cy and math.abs(x/scale-cx)<=90 and math.abs(y/scale-cy)<=40 then return index end
        end
    end
    local function finish(cancel)
        local state,destination=dragging,not cancel and target()
        dragging=nil; ghost:Hide(); ghost:SetScript('OnUpdate',nil)
        if SetCursor then SetCursor(nil) end
        for _,card in ipairs(frame.Cards) do card:SetAlpha(1); card:SetBackdropBorderColor(0.4,0.4,0.4,0.8) end
        if state and destination and destination~=state.index then
            local current=R.ConfiguredOrder(frame.key)
            if table.concat(current,',')==state.signature then
                local source=table.remove(current,state.index); table.insert(current,destination,source)
                R.SetOverride(frame.key,current)
            end
        end
    end
    frame.CancelDrag=function() finish(true) end
    for index=1,3 do
        local card=CreateFrame('Frame',nil,frame,'BackdropTemplate')
        card:SetPoint('TOPLEFT',frame,'TOPLEFT',(index-1)*180,-28); card:SetSize(166,66)
        card:SetBackdrop({bgFile='Interface\\ChatFrame\\ChatFrameBackground',edgeFile='Interface\\ChatFrame\\ChatFrameBackground',edgeSize=1})
        card:SetBackdropColor(0.06,0.06,0.06,0.9); card:SetBackdropBorderColor(0.4,0.4,0.4,0.8)
        card.Label=label(card,'',10,-10,146,22,'GameFontHighlight')
        card.Status=label(card,'',10,-36,146,22)
        card:EnableMouse(true); card:RegisterForDrag('LeftButton')
        local function start()
            if dragging or not card:IsVisible() then return end
            dragging={index=index,signature=table.concat(R.ConfiguredOrder(frame.key),',')}
            L.SetOptionsText(ghost.Text,names[card.source]); card:SetAlpha(0.35); ghost:Show()
            if SetCursor then SetCursor('Interface/CURSOR/UI-Cursor-Move.crosshair') end
            local function update()
                if IsMouseButtonDown and not IsMouseButtonDown('LeftButton') then finish(false); return end
                local x,y=GetCursorPosition(); local cx,cy=frame:GetCenter()
                if not cx or not cy then finish(true); return end
                local scale=frame:GetEffectiveScale()
                ghost:ClearAllPoints(); ghost:SetPoint('CENTER',frame,'CENTER',x/scale-cx,y/scale-cy)
                local hovered=target()
                for i,item in ipairs(frame.Cards) do
                    if hovered==i then item:SetBackdropBorderColor(1,0.82,0.25,1)
                    else item:SetBackdropBorderColor(0.4,0.4,0.4,0.8) end
                end
            end
            ghost:SetScript('OnUpdate',update); update()
        end
        card:SetScript('OnMouseDown',function(_,key) if key=='LeftButton' then start() end end)
        card:SetScript('OnDragStart',start)
        card:SetScript('OnDragStop',function() finish(false) end)
        card:SetScript('OnMouseUp',function(_,key) if key=='LeftButton' then finish(false) end end)
        frame.Cards[index]=card
    end
    frame.Reset=button(frame,'Вернуть по умолчанию',0,-108,210,function() R.Reset(frame.key) end)
    frame.Dice=CreateFrame('Button',nil,frame)
    frame.Dice:SetSize(28,28)
    frame.Dice:SetNormalTexture('Interface\\Buttons\\UI-GroupLoot-Dice-Up')
    frame.Dice:SetPushedTexture('Interface\\Buttons\\UI-GroupLoot-Dice-Down')
    frame.Dice:SetHighlightTexture('Interface\\Buttons\\UI-GroupLoot-Dice-Highlight')
    frame.Dice:SetScript('OnEnter',function(self)
        GameTooltip:SetOwner(self,'ANCHOR_TOP'); GameTooltip:SetText('Другое случайное задание'); GameTooltip:Show(); L.OptionsTooltip(GameTooltip)
    end)
    frame.Dice:SetScript('OnLeave',function() GameTooltip:Hide() end)
    frame.Quest=label(frame,'',20,-164,430,26,'GameFontNormalLarge')
    frame.Quest:SetJustifyV('MIDDLE')
    frame.QuestIcon=frame:CreateTexture(nil,'ARTWORK')
    -- Offset the texture's transparent inset so the visible mark aligns with the cards.
    frame.QuestIcon:SetPoint('RIGHT',frame.Quest,'LEFT',-2,0); frame.QuestIcon:SetSize(26,26)
    if frame.QuestIcon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo('QuestNormal') then
        frame.QuestIcon:SetAtlas('QuestNormal')
    else frame.QuestIcon:SetTexture('Interface\\GossipFrame\\AvailableQuestIcon') end
    frame.Dice:SetPoint('LEFT',frame.Quest,'RIGHT',10,0)
    frame.NPC=label(frame,'',20,-194,512,26,'GameFontHighlightLarge')
    frame.NPC:SetTextColor(0.85,0.8,0.68)
    frame.Hint=label(frame,'',0,-260,532,36)
    frame.Loading=CreateFrame('Frame',nil,frame)
    frame.Loading:SetPoint('TOPLEFT',frame,'TOPLEFT',0,-164); frame.Loading:SetSize(470,48)
    frame.Loading.Text=label(frame.Loading,'Подбираем задания для сравнения…',20,0,430,26,'GameFontHighlight')
    frame.Loading.Text:SetJustifyV('MIDDLE')
    local dots={}
    for i=1,8 do
        local dot=frame.Loading:CreateTexture(nil,'ARTWORK')
        dot:SetColorTexture(1,0.82,0.35,1); dot:SetSize(3,3)
        local angle=(i-1)*math.pi/4
        dot:SetPoint('CENTER',frame.Loading.Text,'LEFT',-10+math.cos(angle)*8,math.sin(angle)*8)
        dots[i]=dot
    end
    frame.Loading:SetScript('OnUpdate',function(self,elapsed)
        self.elapsed=(self.elapsed or 0)+elapsed
        local phase=math.floor(self.elapsed*10)%8
        for i,dot in ipairs(dots) do dot:SetAlpha(0.2+0.8*((i+phase)%8)/7) end
    end)
    frame.Loading:Hide()
    frame.Players={}
    for i,source in ipairs({'wowvoice','catquest','wayfarer'}) do
        local play=CreateFrame('Button',nil,frame)
        play:SetPoint('TOPLEFT',frame,'TOPLEFT',(i-1)*180+65,-306); play:SetSize(36,36)
        play.Icon=play:CreateTexture(nil,'ARTWORK')
        play.Icon:SetTexture('Interface\\AddOns\\TalkingHeadRu\\Media\\Play.tga')
        play.Icon:SetPoint('CENTER',play,'CENTER',0,0); play.Icon:SetSize(36,36)
        local color=colors[source]; play.Icon:SetVertexColor(color[1],color[2],color[3])
        play.UnavailableMark=play:CreateTexture(nil,'OVERLAY')
        play.UnavailableMark:SetTexture('Interface\\AddOns\\TalkingHeadRu\\Media\\QueueClose.png')
        play.UnavailableMark:SetAllPoints(play.Icon); play.UnavailableMark:SetVertexColor(0.25,0.25,0.25)
        play.UnavailableMark:Hide()
        play:SetScript('OnEnter',function(self) if self:IsEnabled() then self.Icon:SetSize(40,40) end end)
        local function leave(self) self.Icon:SetSize(36,36) end
        play:SetScript('OnLeave',leave); play:SetScript('OnHide',leave)
        play:SetScript('OnClick',function()
            local current=frame.samples and frame.samples.current
            if current and not frame.loading then
                if not C.Play(current.id,source,viewport) then
                    L.SetOptionsText(frame.Hint,'Не удалось включить запись. Проверьте библиотеку и настройки озвучки.')
                end
            end
        end)
        play.Name=label(frame,names[source],(i-1)*180,-350,166,22,'GameFontHighlight')
        play.Name:SetTextColor(color[1],color[2],color[3]); play.Name:SetJustifyH('CENTER')
        play.Status=label(frame,'',(i-1)*180,-376,166,24); play.Status:SetJustifyH('CENTER')
        frame.Players[source]=play
    end
    local function layoutSample()
        -- Measure after applying the localized font; keep the dice beside even
        -- a short title, and reserve room for wrapping unusually long titles.
        frame.Quest:SetWidth(430)
        local width=frame.Quest.GetUnboundedStringWidth and frame.Quest:GetUnboundedStringWidth() or frame.Quest:GetStringWidth()
        frame.Quest:SetWidth(math.min(430,math.max(1,width+2)))
        local height=math.max(26,frame.Quest:GetStringHeight()+2)
        frame.Quest:SetHeight(height)
        local npcTop=164+height+4
        frame.NPC:ClearAllPoints(); frame.NPC:SetPoint('TOPLEFT',frame,'TOPLEFT',20,-npcTop)
        frame.Hint:ClearAllPoints(); frame.Hint:SetPoint('TOPLEFT',frame,'TOPLEFT',20,-npcTop-34)
        frame.Hint:SetWidth(512)
        local playTop=npcTop+46+(frame.Hint:GetText()~='' and 36 or 0)
        for i,source in ipairs({'wowvoice','catquest','wayfarer'}) do
            local play=frame.Players[source]
            play:ClearAllPoints(); play:SetPoint('TOPLEFT',frame,'TOPLEFT',(i-1)*180+65,-playTop)
            play.Name:ClearAllPoints(); play.Name:SetPoint('TOPLEFT',frame,'TOPLEFT',(i-1)*180,-playTop-44)
            play.Status:ClearAllPoints(); play.Status:SetPoint('TOPLEFT',frame,'TOPLEFT',(i-1)*180,-playTop-70)
        end
        frame:SetHeight(playTop+96); viewport:UpdateScrollChildRect()
    end
    function viewport:Refresh()
        if not frame.key then return end
        finish(true)
        local order=R.ConfiguredOrder(frame.key)
        for i,id in ipairs(order) do
            local card=frame.Cards[i]; card.source=id
            L.SetOptionsText(card.Label,i..'. '..names[id]); local color=colors[id]
            card.Label:SetTextColor(color[1],color[2],color[3])
            local available=C.SourceAvailable(id)
            card.Label:SetAlpha(available and 1 or 0.4)
            L.SetOptionsText(card.Status,available and 'Подключена' or 'Не подключена')
        end
        frame.Reset:SetEnabled(R.Override(frame.key)~=nil)
        if frame.revision~=WV.audioCatalogRevision then
            E.Stop(viewport)
            frame.revision=WV.audioCatalogRevision
            frame.loading=true; frame.loadError=nil
            local requestedKey,requestedRevision=frame.key,frame.revision
            E.Request(requestedKey,function(candidates,available,err)
                if not viewport:IsShown() or frame.key~=requestedKey or frame.revision~=requestedRevision then return end
                frame.loading=false; frame.loadError=err
                if candidates then
                    local ids={}; for _,candidate in ipairs(candidates) do ids[#ids+1]=candidate.id end
                    local signature=table.concat(ids,',')..':'..available
                    if frame.signature~=signature then frame.samples=E.New(candidates); frame.signature=signature end
                    frame.available=available
                else frame.samples=nil; frame.signature=nil end
                viewport:Refresh()
            end)
        end
        if frame.loading then
            frame.Loading:Show(); frame.Quest:Hide(); frame.NPC:Hide(); frame.QuestIcon:Hide(); frame.Dice:Hide()
            L.SetOptionsText(frame.Hint,'')
            frame.Dice:SetEnabled(false); frame.Dice:SetAlpha(0.35)
            for _,play in pairs(frame.Players) do
                play:SetEnabled(false); play.Icon:SetAlpha(0.35); play.Name:SetAlpha(0.35)
                play.UnavailableMark:Hide(); L.SetOptionsText(play.Status,'')
            end
            return
        end
        frame.Loading:Hide(); frame.Quest:Show(); frame.NPC:Show()
        local current=frame.samples and frame.samples.current
        if current then frame.QuestIcon:Show(); frame.Dice:Show()
        else frame.QuestIcon:Hide(); frame.Dice:Hide() end
        local context=current and current.context
        L.SetOptionsText(frame.Quest,frame.loadError and 'Не удалось подготовить примеры' or current and (context and context.title or 'Задание '..current.id) or 'Подходящих примеров пока нет')
        local speaker=context and context.speaker
        local npc=speaker and TalkingHeadRuSpeakers and TalkingHeadRuSpeakers.npcs[speaker.npcID]
        L.SetOptionsText(frame.NPC,current and ((speaker and speaker.name) or (npc and npc.name) or (frame.key=='narrator' and 'Рассказчик' or 'Неизвестный NPC')) or '')
        local hint=frame.loadError and 'Откройте это сочетание ещё раз, чтобы повторить загрузку.'
            or frame.available==1 and 'Для сравнения подключите ещё одну библиотеку.'
            or frame.available==0 and 'Подключите хотя бы одну библиотеку озвучки.'
            or not current and 'Нет заданий с двумя доступными озвучками для этого сочетания.'
            or ''
        L.SetOptionsText(frame.Hint,hint)
        frame.Dice:SetEnabled(frame.samples and #frame.samples.candidates>1)
        frame.Dice:SetAlpha(frame.samples and #frame.samples.candidates>1 and 1 or 0.35)
        for source,play in pairs(frame.Players) do
            local available=C.SourceAvailable(source)
            local playable=current and available and C.Resolve(current.id,source)~=nil
            play:SetEnabled(playable==true)
            play.Icon:SetAlpha(playable and 1 or 0.4); play.Name:SetAlpha(playable and 1 or 0.4)
            if playable then play.UnavailableMark:Hide() else play.UnavailableMark:Show() end
            L.SetOptionsText(play.Status,not available and 'Не подключена' or not playable and 'Нет записи' or '')
        end
        layoutSample()
    end
    frame.Dice:SetScript('OnClick',function()
        if frame.samples and not frame.loading then E.Stop(viewport); E.Next(frame.samples); viewport:Refresh() end
    end)
    function viewport:Open(group,title)
        frame.key=R.GroupID(group); frame.revision=false; frame.signature=nil; frame.samples=nil
        L.SetOptionsText(parent.Title,title); self:Show(); self:SetVerticalScroll(0); self:Refresh()
    end
    viewport:SetScript('OnHide',function()
        finish(true); E.Cancel(); frame.loading=false; frame.Loading:Hide()
        E.Stop(viewport); GameTooltip:Hide()
        L.SetOptionsText(parent.Title,'Озвучка по расе и полу')
    end)
    viewport:Hide()
    return viewport
end
