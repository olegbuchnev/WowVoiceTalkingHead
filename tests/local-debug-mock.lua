UISpecialFrames = {}
local original = CreateFrame
function CreateFrame(kind, name, parent, template)
    local frame = original(kind, name, parent, template)
    if name then _G[name] = frame end
    local makeFont = frame.CreateFontString
    frame.regions = {}
    function frame:CreateFontString(...)
        local region = makeFont(self, ...)
        self.regions[#self.regions + 1] = region
        return region
    end
    function frame:GetRegions() return table.unpack(self.regions) end
    function frame:IsMouseOver() return self.mouseOver == true end
    function frame:EnableMouseWheel(value) self.mouseWheelEnabled = value end
    if kind == 'EditBox' then
        function frame:SetTextInsets(...) self.textInsets = {...} end
        local setText = frame.SetText
        function frame:SetText(value)
            setText(self, value)
            if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
        end
    end
    -- Resolve stretched frame dimensions from their parent instead of treating
    -- a shown flag as proof that the child has an on-screen rectangle.
    local getWidth, getHeight = frame.GetWidth, frame.GetHeight
    local function stretchedSize(self, axis)
        local first, last = self.points[1], self.points[2]
        if first and last and first[1] == 'TOPLEFT' and last[1] == 'BOTTOMRIGHT'
            and first[2] == last[2] then
            if axis == 'width' then return first[2]:GetWidth() + last[4] - first[4] end
            return first[2]:GetHeight() + first[5] - last[5]
        end
    end
    function frame:GetWidth() return getWidth(self) or stretchedSize(self, 'width') end
    function frame:GetHeight() return getHeight(self) or stretchedSize(self, 'height') end
    return frame
end
