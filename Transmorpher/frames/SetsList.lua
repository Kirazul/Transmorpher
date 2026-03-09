local addon, ns = ...

-- Simple sets list that displays armor sets in a grid

local function CreateSetPreview(parent, index)
    local frame = CreateFrame("Frame", "$parentSet"..index, parent)
    frame:SetSize(140, 170)
    
    -- Background
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0.10, 0.09, 0.08, 1)
    frame:SetBackdropBorderColor(0.45, 0.38, 0.28, 1)
    
    -- Dressing room model
    frame.model = ns.CreateDressingRoom("$parentModel", frame)
    frame.model:SetPoint("TOPLEFT", 5, -5)
    frame.model:SetPoint("BOTTOMRIGHT", -5, 20)
    frame.model:EnableDragRotation(false)
    frame.model:EnableMouseWheel(false)
    
    -- Set name label
    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.label:SetPoint("BOTTOM", 0, 3)
    frame.label:SetTextColor(0.95, 0.88, 0.65)
    frame.label:SetJustifyH("CENTER")
    
    -- Click button
    frame.button = CreateFrame("Button", nil, frame)
    frame.button:SetAllPoints()
    frame.button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame.button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    frame.button:GetHighlightTexture():SetAlpha(0.3)
    
    frame.setData = nil
    
    return frame
end

function ns.CreateSetsList(parent)
    local frame = CreateFrame("Frame", addon.."SetsList", parent)
    
    frame.sets = {}
    frame.previews = {}
    frame.currentPage = 1
    frame.perPage = 6  -- 3 columns x 2 rows
    
    -- Create 6 preview frames in a grid
    for i = 1, 6 do
        local preview = CreateSetPreview(frame, i)
        local row = math.floor((i - 1) / 3)
        local col = (i - 1) % 3
        preview:SetPoint("TOPLEFT", 10 + col * 150, -10 - row * 180)
        preview:Hide()
        frame.previews[i] = preview
    end
    
    -- Set the sets to display
    function frame:SetSets(sets)
        self.sets = sets or {}
        self.currentPage = 1
    end
    
    -- Get page count
    function frame:GetPageCount()
        if #self.sets == 0 then return 1 end
        return math.ceil(#self.sets / self.perPage)
    end
    
    -- Set current page
    function frame:SetPage(page)
        self.currentPage = page
    end
    
    -- Get current page
    function frame:GetPage()
        return self.currentPage
    end
    
    -- Update display
    function frame:Update()
        local startIdx = (self.currentPage - 1) * self.perPage + 1
        
        for i = 1, self.perPage do
            local preview = self.previews[i]
            local setIdx = startIdx + i - 1
            local setData = self.sets[setIdx]
            
            if setData then
                preview.setData = setData
                preview.label:SetText(setData.name)
                
                -- Setup model
                preview.model:Reset()
                preview.model:Undress()
                preview.model:SetPosition(0, 0, 0)
                preview.model:SetFacing(0)
                
                -- Apply all items
                for _, item in ipairs(setData.items) do
                    preview.model:TryOn(item.itemId)
                end
                
                preview:Show()
                
                -- Setup button click
                preview.button:SetScript("OnClick", function(btn, button)
                    if frame.onSetClick then
                        frame.onSetClick(btn, button, setData)
                    end
                end)
                
                preview.button:SetScript("OnEnter", function(btn)
                    if frame.onEnter then
                        frame.onEnter(btn, setData)
                    end
                end)
                
                preview.button:SetScript("OnLeave", function(btn)
                    if frame.onLeave then
                        frame.onLeave(btn)
                    end
                end)
            else
                preview.setData = nil
                preview:Hide()
            end
        end
    end
    
    return frame
end
