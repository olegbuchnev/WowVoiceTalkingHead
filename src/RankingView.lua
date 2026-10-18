local WV, Ranking, L = WowVoice, TalkingHeadRuVoiceRanking, WowVoiceLocale
local panel
local races = {
    ancient='Древень',banshee='Банши',bloodelf='Эльф крови',centaur='Кентавр',child='Ребёнок',
    dragon='Дракон',dreadlord='Повелитель ужаса',dwarf='Дворф',elemental_water='Элементаль воды',furbolg='Фурболг',
    gnome='Гном',goblin='Гоблин',human='Человек',human_child='Человек (ребёнок)',imp='Бес',
    nightelf='Ночной эльф',orc='Орк',orc_child='Орк (ребёнок)',quilboar='Свинобраз',scourge='Нежить',
    skyborne='Небеснорождённый',stone_construct='Каменное создание',succubus='Суккуб',tauren='Таурен',troll='Тролль',
}
local names={wowvoice='WowVoice',catquest='CatQuest',wayfarer='Wayfarer'}
local colors={wowvoice={0.25,0.7,1},catquest={1,0.55,0.2},wayfarer={0.4,0.85,0.45}}
local origins={custom='Ваш порядок',ranking='По рейтингу',fallback='Нет оценок',manual='Общий порядок'}
local portraitJob='voice-ranking-portraits'
local function setPortrait(row,group)
    local entry=TalkingHeadRuVoiceGroupPortraits and TalkingHeadRuVoiceGroupPortraits[Ranking.GroupID(group)]
    local display=entry and entry.displayID
    if row.portraitGroup==Ranking.GroupID(group) and row.portraitDisplay==display then return end
    row.portraitGroup,row.portraitDisplay=Ranking.GroupID(group),display
    row.portraitReady=false
    row.Portrait:SetTexture('Interface\\Icons\\INV_Misc_Note_01')
end
local function preparePortraits()
    WV.Work:Cancel(portraitJob)
    if not panel or not panel:IsShown() or not panel.List:IsShown() then return end
    WV.Work:Queue(portraitJob,function()
        for _,row in ipairs(panel.Rows) do
            if not panel:IsShown() or not panel.List:IsShown() then return end
            if row:IsShown() and not row.portraitReady then
                if row.portraitDisplay and SetPortraitTextureFromCreatureDisplayID then
                    SetPortraitTextureFromCreatureDisplayID(row.Portrait,row.portraitDisplay)
                end
                row.portraitReady=true
                -- A cold native texture request cannot be interrupted. Never issue
                -- several on the same frame, even when the shared budget allows it.
                coroutine.yield(0.001)
            end
        end
    end,0,false)
end
local function title(g) return g.speakerType=='narrator' and 'Рассказчик' or (races[g.race] or g.race) end
local function sex(g) return g.sex=='male' and 'Мужской' or g.sex=='female' and 'Женский' or '' end
local function label(parent,text,x,y,width,height,font)
    local value=parent:CreateFontString(nil,'ARTWORK',font or 'GameFontHighlightSmall')
    value:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); value:SetSize(width,height)
    value:SetJustifyH('LEFT'); value:SetJustifyV('TOP'); L.SetOptionsText(value,text)
    return value
end
local function button(parent,text,x,y,width,callback)
    local value=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate')
    value:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); value:SetSize(width,26)
    L.SetOptionsText(value,text); value:SetScript('OnClick',callback)
    if WV.StyleButton then WV.StyleButton(value) end
    return value
end
local function edit(parent,name,x,y,width)
    local value=CreateFrame('EditBox',name,parent,'BackdropTemplate')
    value:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y); value:SetSize(width,32)
    value:SetAutoFocus(false); value:SetFontObject('GameFontHighlightSmall')
    value:SetTextInsets(8,8,0,0)
    value:SetBackdrop({bgFile='Interface\\ChatFrame\\ChatFrameBackground',edgeFile='Interface\\ChatFrame\\ChatFrameBackground',edgeSize=1})
    value:SetBackdropColor(0.04,0.04,0.04,0.9); value:SetBackdropBorderColor(0.4,0.4,0.4,0.8)
    return value
end
local function closeImport()
    panel.Import:Hide(); panel.Input:ClearFocus(); panel.Link:ClearFocus()
    panel.Input:SetText('')
    panel.Group:Hide(); panel.Confirm:Hide()
    panel.List:Show(); panel.ImportButton:Show(); panel.ResetButton:Show()
    panel.Header:Show(); panel.Legend:Show()
end
local function back()
    if not panel then return end
    if panel.Group:IsShown() or panel.Import:IsShown() then closeImport(); return end
    closeImport(); panel:Hide(); panel.Options.Scroll:Show()
end
local function layoutRows()
    if not panel then return end
    local width=panel.List:GetWidth() or 536
    local buttonWidth=width>=620 and 196 or 120
    local groupWidth=math.min(228,math.max(196,width*0.3))
    local sourceWidth=(width-groupWidth-buttonWidth-12)/3
    panel.Content:SetWidth(width)
    panel.Header:SetWidth(width)
    for rank=1,3 do
        local heading=panel.Places[rank]
        heading:ClearAllPoints()
        heading:SetPoint('TOPLEFT',panel.Header,'TOPLEFT',groupWidth+(rank-1)*sourceWidth,0)
        heading:SetWidth(sourceWidth-6)
        heading:SetJustifyH('CENTER')
    end
    for _,row in ipairs(panel.Rows) do
        row:SetWidth(width); row.Title:SetWidth(groupWidth-64); row.Detail:SetWidth(groupWidth-64)
        for rank=1,3 do
            local source=row.Sources[rank]
            source:ClearAllPoints()
            source:SetPoint('LEFT',row,'LEFT',groupWidth+(rank-1)*sourceWidth,0)
            source:SetWidth(sourceWidth-6)
            source:SetJustifyH('CENTER')
        end
        row.Open:ClearAllPoints()
        row.Open:SetPoint('RIGHT',row,'RIGHT',0,0)
        row.Open:SetWidth(buttonWidth)
        L.SetOptionsText(row.Open,width>=620 and 'Сравнить и настроить >' or 'Настроить >')
    end
end
function WV:RefreshVoiceRankingView()
    if not panel then return end
    local snapshot,_,origin=Ranking.Current()
    local known,groups={},{}
    local database=TalkingHeadRuSpeakers or {}
    for _,roles in ipairs({database.givers or {},database.finishers or {}}) do
        for _,role in pairs(roles) do
            local npc=type(role)=='table' and not (role.narrator or role.itemID or role.objectID)
                and database.npcs and database.npcs[role.npcID]
            if npc and npc.race and npc.sex then known[npc.race..':'..npc.sex]=true end
        end
    end
    for _,group in ipairs(snapshot and snapshot.groups or {}) do
        if group.speakerType=='narrator' or known[group.race..':'..group.sex] then groups[#groups+1]=group end
    end
    local snapshotTime=snapshot and Ranking.FormatSnapshotTime(snapshot.generatedAt) or 'нет данных'
    L.SetOptionsText(panel.Summary,(origin=='imported' and 'Ваш снимок: ' or 'Встроенный снимок: ')..snapshotTime
        ..(snapshot and ('  |  Групп: '..#groups) or ''))
    L.SetOptionsText(panel.Mode,self:GetVoiceSelectionMode()=='ranking' and ''
        or 'Сейчас для всех используется общий порядок.')
    if self:GetVoiceSelectionMode()~='ranking' and not panel.Import:IsShown() then panel.Activate:Show() else panel.Activate:Hide() end
    panel.ResetButton:SetEnabled(Ranking.HasOverrides())
    for _,row in ipairs(panel.Rows) do row:Hide() end
    table.sort(groups,function(a,b) local x,y=title(a),title(b); return x==y and (a.sex or '')<(b.sex or '') or x<y end)
    for i,group in ipairs(groups) do
        local row=panel.Rows[i]
        if not row then
            row=CreateFrame('Frame',nil,panel.Content); row:SetSize(536,56)
            row:SetPoint('TOPLEFT',panel.Content,'TOPLEFT',0,-(i-1)*56)
            row.Portrait=row:CreateTexture(nil,'ARTWORK')
            row.Portrait:SetSize(44,44); row.Portrait:SetPoint('LEFT',row,'LEFT',2,0)
            if row.Portrait.SetMask then row.Portrait:SetMask('Interface\\CharacterFrame\\TempPortraitAlphaMask') end
            row.Title=label(row,'',56,-4,140,26); row.Title:SetJustifyV('MIDDLE')
            row.Detail=label(row,'',56,-31,140,18); row.Detail:SetTextColor(0.65,0.65,0.65)
            row.Separator=row:CreateTexture(nil,'BACKGROUND')
            row.Separator:SetPoint('BOTTOMLEFT',row,'BOTTOMLEFT',0,0)
            row.Separator:SetPoint('BOTTOMRIGHT',row,'BOTTOMRIGHT',0,0)
            row.Separator:SetHeight(1)
            row.Separator:SetColorTexture(0.6,0.52,0.32,0.25)
            row.Sources={}
            for rank=1,3 do
                row.Sources[rank]=label(row,'',204+(rank-1)*108,-4,106,26)
                row.Sources[rank]:SetJustifyV('MIDDLE')
            end
            row.Open=button(row,'Сравнить и настроить >',334,-4,196,function()
                panel.List:Hide(); panel.Header:Hide(); panel.Legend:Hide()
                panel.ImportButton:Hide(); panel.ResetButton:Hide(); panel.Confirm:Hide()
                panel.Group:Open(row.group,title(row.group)..(sex(row.group)~='' and ' — '..sex(row.group) or ''))
            end)
            panel.Rows[i]=row
        end
        L.SetOptionsText(row.Title,title(group))
        row.group=group
        setPortrait(row,group)
        if i<#groups then row.Separator:Show() else row.Separator:Hide() end
        local order,source=Ranking.EffectiveOrder(Ranking.GroupID(group))
        local originText=source=='custom' and '|cffdfbf73'..origins[source]..'|r' or origins[source]
        L.SetOptionsText(row.Detail,(sex(group)~='' and sex(group)..' | ' or '')..originText)
        for rank,id in ipairs(order) do
            local tie
            if source=='ranking' then
                for _,entry in ipairs(group.ranking) do if entry.source==names[id] then tie=entry.tieGroup end end
            end
            local value=row.Sources[rank]; L.SetOptionsText(value,names[id]..(tie and ' =' or ''))
            local color=colors[id]; value:SetTextColor(color[1],color[2],color[3])
            value:SetAlpha(WowVoiceAudioSources.Available(id) and 1 or 0.4)
        end
        row:Show()
    end
    layoutRows()
    panel.Content:SetHeight(math.max(1,#groups*56)); panel.List:UpdateScrollChildRect()
    preparePortraits()
    if panel.Group:IsShown() then panel.Group:Refresh() end
end
local function create(options)
    local frame=CreateFrame('Frame','TalkingHeadRuRankingView',options)
    frame:SetPoint('TOPLEFT',options,'TOPLEFT',0,0); frame:SetPoint('BOTTOMRIGHT',options,'BOTTOMRIGHT',0,0)
    frame.Options,frame.Rows=options,{}
    frame.Back=button(frame,'Назад',20,-16,90,back)
    frame.Title=label(frame,'Озвучка по расе и полу',126,-16,420,26,'GameFontNormalLarge')
    frame.Title:SetJustifyV('MIDDLE')
    frame.Summary=label(frame,'',20,-56,540,22,'GameFontHighlight')
    frame.Mode=label(frame,'',20,-82,340,28)
    frame.Activate=button(frame,'Включить по группам',370,-78,182,function() WV:SetVoiceSelectionMode('ranking') end)
    frame.ImportButton=button(frame,'Импортировать строку',20,-116,190,function()
        frame.List:Hide(); frame.Header:Hide(); frame.Legend:Hide()
        frame.ImportButton:Hide(); frame.ResetButton:Hide()
        frame.Confirm:Hide(); frame.Import:Show(); frame.Message:SetText('')
        frame.KeepOverrides:SetChecked(true)
        L.SetOptionsText(frame.Apply,'Импортировать'); frame.Input:SetFocus()
    end)
    frame.ResetButton=button(frame,'Вернуть порядок по умолчанию',222,-116,310,function()
        frame.List:Hide(); frame.Header:Hide(); frame.Legend:Hide()
        frame.ImportButton:Hide(); frame.ResetButton:Hide(); frame.Confirm:Show()
    end)
    local importText=frame.ImportButton.GetFontString and frame.ImportButton:GetFontString()
    local resetText=frame.ResetButton.GetFontString and frame.ResetButton:GetFontString()
    if importText and resetText then
        local padding=math.max(0,frame.ImportButton:GetWidth()-importText:GetStringWidth())
        frame.ResetButton:SetWidth(math.ceil(resetText:GetStringWidth()+padding))
    end
    frame.Header=CreateFrame('Frame',nil,frame)
    frame.Header:SetPoint('TOPLEFT',frame,'TOPLEFT',20,-158); frame.Header:SetSize(536,20)
    label(frame.Header,'Раса / пол',0,0,196,20,'GameFontNormal')
    frame.Places={}
    for rank=1,3 do frame.Places[rank]=label(frame.Header,tostring(rank),204+(rank-1)*108,0,106,20,'GameFontNormal') end
    frame.Legend=label(frame,'= равные оценки: используется ваш порядок. Недоступные библиотеки приглушены.',20,-181,540,30)
    local list=CreateFrame('ScrollFrame','TalkingHeadRuRankingList',frame,'UIPanelScrollFrameTemplate')
    list:SetPoint('TOPLEFT',frame,'TOPLEFT',20,-216); list:SetPoint('BOTTOMRIGHT',frame,'BOTTOMRIGHT',-30,12)
    local content=CreateFrame('Frame',nil,list); content:SetSize(536,1); list:SetScrollChild(content)
    frame.List,frame.Content=list,content
    list:SetScript('OnSizeChanged',layoutRows)
    local import=CreateFrame('Frame',nil,frame)
    import:SetPoint('TOPLEFT',frame,'TOPLEFT',20,-116); import:SetPoint('BOTTOMRIGHT',frame,'BOTTOMRIGHT',-24,12)
    label(import,'Получите строку рейтинга на сайте и вставьте её ниже.',0,0,532,26,'GameFontHighlight')
    frame.Link=edit(import,nil,0,-32,532)
    local url='https://talkingheadru.tw1.ru/'
    frame.Link:SetText(url)
    frame.Link:SetScript('OnMouseUp',function(self) self:SetFocus(); self:HighlightText() end)
    frame.Link:SetScript('OnTextChanged',function(self) if self:GetText()~=url then self:SetText(url) end end)
    label(import,'Нажмите на ссылку и скопируйте её: Ctrl+C.',0,-69,532,22)
    frame.Input=edit(import,'TalkingHeadRuRankingInput',0,-101,532); frame.Input:SetMaxLetters(87516)
    frame.KeepOverrides=CreateFrame('CheckButton',nil,import,'UICheckButtonTemplate')
    frame.KeepOverrides:SetPoint('TOPLEFT',import,'TOPLEFT',-4,-143)
    frame.KeepOverrides:SetSize(26,26); frame.KeepOverrides:SetChecked(true)
    frame.KeepOverrides.Label=label(import,'Сохранить мой порядок для рас и пола',28,-143,504,26,'GameFontHighlight')
    frame.KeepOverrides.Label:SetJustifyV('MIDDLE')
    label(import,'Если снять галочку, все личные порядки заменятся рейтингом сообщества.',0,-173,532,30)
    frame.Message=label(import,'',0,-246,532,74)
    local function apply()
        local text=frame.Input:GetText()
        local ok,message=Ranking.Import(text,{preserveOverrides=frame.KeepOverrides:GetChecked() and true or false})
        if ok then
            closeImport(); WV:RefreshVoiceRankingView()
        elseif message=='older' then
            L.SetOptionsText(frame.Message,'У вас уже есть более свежий рейтинг. Этот снимок не применён.')
        else L.SetOptionsText(frame.Message,message) end
    end
    frame.Apply=button(import,'Импортировать',0,-210,190,apply)
    frame.Cancel=button(import,'Отмена',202,-210,110,closeImport)
    frame.Input:SetScript('OnEnterPressed',apply)
    frame.Input:SetScript('OnEscapePressed',closeImport)
    frame.Link:SetScript('OnEscapePressed',closeImport)
    frame.Import=import; import:Hide()
    local snapshotHint=label(import,'Используется самый свежий снимок: встроенный или импортированный.',0,0,532,32)
    snapshotHint:ClearAllPoints()
    snapshotHint:SetPoint('TOPLEFT',frame.Summary,'BOTTOMLEFT',0,0)
    import:SetScript('OnShow',function() frame.Mode:Hide(); frame.Activate:Hide() end)
    import:SetScript('OnHide',function()
        frame.Mode:Show()
        if WV:GetVoiceSelectionMode()~='ranking' then frame.Activate:Show() end
    end)
    frame.Group=WV:CreateVoiceGroupView(frame,label,button)
    frame.Confirm=CreateFrame('Frame',nil,frame)
    frame.Confirm:SetPoint('TOPLEFT',frame,'TOPLEFT',20,-116); frame.Confirm:SetSize(536,180)
    label(frame.Confirm,'Вернуть порядок по умолчанию для всех сочетаний?\nЛичные порядки будут удалены. Будет использоваться актуальный рейтинг сообщества; общий порядок библиотек сохранится.',0,0,532,70,'GameFontHighlight')
    frame.Confirm.Apply=button(frame.Confirm,'Вернуть по умолчанию',0,-86,230,function() Ranking.ResetAll(); closeImport() end)
    frame.Confirm.Cancel=button(frame.Confirm,'Отмена',242,-86,110,closeImport); frame.Confirm:Hide()
    frame.List:HookScript('OnShow',preparePortraits)
    frame.List:HookScript('OnHide',function() WV.Work:Cancel(portraitJob) end)
    frame:SetScript('OnHide',function()
        WV.Work:Cancel(portraitJob)
        frame.Input:ClearFocus(); frame.Link:ClearFocus(); frame.Group:Hide()
    end)
    frame:Hide(); options:HookScript('OnHide',function() if panel then closeImport(); panel:Hide(); options.Scroll:Show() end end)
    return frame
end
function WV:OpenVoiceRanking()
    if self.CloseVoiceComparison then self:CloseVoiceComparison() end
    self:OpenOptions()
    local options=_G.WowVoiceOptionsPanel
    if not options or not options:IsShown() then return end
    if not panel then panel=create(options) end
    self:EndHeadScalePreview(true); self:HideHeadPreview()
    options.PositionX:ClearFocus(); options.PositionY:ClearFocus(); options.ScaleInput:ClearFocus()
    options.Scroll:Hide(); panel:Show(); closeImport()
    self:RefreshVoiceRankingView(); panel.List:SetVerticalScroll(0)
end
function WV:CloseVoiceRanking()
    if panel and panel:IsShown() then closeImport(); back() end
end
