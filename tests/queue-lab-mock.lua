local create = CreateFrame
function CreateFrame(...)
    local frame = create(...)
    local _, name = ...
    if name then _G[name] = frame end
    function frame:GetScript(event) return self.scripts[event] end
    function frame:SetShown(value) if value then self:Show() else self:Hide() end end
    function frame:EnableMouseWheel(value) self.mouseWheel = value end
    function frame:SetOrientation(value) self.orientation = value end
    function frame:SetThumbTexture(value) self.thumbTexture = value end
    local texture = frame.CreateTexture
    function frame:CreateTexture(...)
        local t = texture(self, ...)
        function t:SetShown(value) if value then self:Show() else self:Hide() end end
        function t:SetMask(value) self.mask = value end
        return t
    end
    return frame
end
function GameTooltip:SetText(text) self.text = text end
function MouseIsOver(frame) return frame.mouseOver or false end
function SetPortraitTextureFromCreatureDisplayID(texture, id) texture.displayID = id end
