allFrames, hookCounts = {}, {}
local baseCreateFrame=CreateFrame
function CreateFrame(kind,name,parent,template)
    local f=baseCreateFrame(kind,name)
    f.parent,f.template,f.points=parent,template,{}
    allFrames[#allFrames+1]=f
    function f:SetSize(w,h) self.width,self.height=w,h end
    function f:SetWidth(w) self.width=w end
    function f:SetHeight(h) self.height=h end
    function f:SetText(t) self.text=t end
    function f:SetAlpha(a) self.alpha=a end
    function f:SetFrameStrata() end
    function f:SetMovable() end
    function f:EnableMouse() end
    function f:RegisterForDrag() end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:ClearAllPoints() self.points={} end
    function f:SetPoint(...) self.points[#self.points+1]={...} end
    function f:GetPoint() return table.unpack(self.points[1]) end
    function f:CreateTexture()
        local t={}
        function t:SetTexture(v) self.texture=v end
        function t:SetSize(w,h) self.width,self.height=w,h end
        function t:SetPoint() end
        return t
    end
    function f:HookScript(event,callback)
        local old=self.scripts[event]
        self.scripts[event]=function(...) if old then old(...) end; callback(...) end
    end
    return f
end
function hooksecurefunc(name,callback)
    hookCounts[name]=(hookCounts[name] or 0)+1
    local original=_G[name]
    _G[name]=function(...) original(...); callback(...) end
end
UIParent=CreateFrame('Frame','UIParent')
GameTooltip={lines={}}
function GameTooltip:SetOwner() self.lines={} end
function GameTooltip:AddLine(s) self.lines[#self.lines+1]=s end
function GameTooltip:Show() end
function GameTooltip:Hide() end
