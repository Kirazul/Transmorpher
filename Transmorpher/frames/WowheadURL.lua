local addon, ns = ...


StaticPopupDialogs["DRESSME_WOWHEAD_URL_DIALOG"] = {
    text = "DRESSME_WOWHEAD_URL_DIALOG",
    button1 = "Version",
    button2 = CLOSE,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    hasEditBox = true,
    hasWideEditBox = true,
    preferredIndex = 3,

    OnAccept = function(self)
        self.data.isRetail = not self.data.isRetail
        StaticPopup_Hide("DRESSME_WOWHEAD_URL_DIALOG")
    end,

    OnCancel = function(self)
        self.data.isClosed = true
    end,

    OnHide = function(self)
        if not self.data.isClosed then
            StaticPopup_Show("DRESSME_WOWHEAD_URL_DIALOG", nil, nil, self.data)
        end
    end,

    OnShow = function(self)
        local data = self.data
        self.text:SetText(("Wowhead \124cff00ff00%s\124r"):format(data.isRetail and "Retail" or "Classic"))
        self.wideEditBox:SetText(("https://%s.wowhead.com/item=%s"):format((data.isRetail and "www" or "classic"), data.itemId))
        self.wideEditBox:HighlightText()
        self.button1:SetText(data.isRetail and "Classic" or "Retail")
    end,
}


function ns.ShowWowheadURLDialog(itemId)
    if StaticPopup_Visible("DRESSME_WOWHEAD_URL_DIALOG") then
        StaticPopup_Hide("DRESSME_WOWHEAD_URL_DIALOG")
    end
    local data = {
        ["isRetail"] = true,
        ["itemId"] = itemId,
        ["isClosed"] = false,
    }
    local dialog = StaticPopup_Show("DRESSME_WOWHEAD_URL_DIALOG", nil, nil, data)
end