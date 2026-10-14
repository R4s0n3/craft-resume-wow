local _, A = ...
local U = { dirty = true, tab = "Overview", logPage = 1 }
A.UI = U
local WIDTH, HEIGHT, CONTENT = 600, 460, 544
local C = {
    text = { 1, 1, 1 }, muted = { .65, .65, .65 }, gold = { 1, .82, 0 },
}
local unpack = unpack or table.unpack

local function tooltip(frame, title, text)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, .82, 0)
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
end

local function label(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size)
    fs:SetTextColor(unpack(color or C.text))
    fs:SetJustifyH("LEFT")
    return fs
end

local function button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b.text = b:GetFontString()
    b:SetScript("OnClick", onClick)
    return b
end

local function edit(parent, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 22)
    box:SetAutoFocus(false)
    box:SetMaxLetters(100)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function scroll(parent, x, y, width, height)
    local frame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(width, height)
    local child = CreateFrame("Frame", nil, frame)
    child:SetSize(width, 1)
    frame:SetScrollChild(child)
    frame.child = child
    return frame
end

local function duration(seconds)
    local minutes = math.floor(seconds / 60)
    return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
end

local function count(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local requestedItems = {}
local function entryIcon(entry)
    if not entry then return nil end
    if entry.icon then return entry.icon end
    if entry.kind == "currency" then
        local info = C_CurrencyInfo.GetCurrencyInfo(entry.id)
        return info and info.iconFileID
    end
    return C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.id)
end

local function itemName(entry)
    if entry.kind == "currency" then
        local info = C_CurrencyInfo.GetCurrencyInfo(entry.id)
        return info and info.name or "Currency #" .. entry.id
    end
    if entry.link and entry.link ~= "" then return entry.link end
    local name = C_Item.GetItemNameByID(entry.id)
    if not name and not requestedItems[entry.id] then
        requestedItems[entry.id] = true
        C_Item.RequestLoadItemDataByID(entry.id)
    end
    return name or "Item #" .. entry.id
end

local function sortedValues(map)
    local entries = {}
    for _, entry in pairs(map) do entries[#entries + 1] = entry end
    table.sort(entries, function(a, b)
        if a.quantity == b.quantity then return (a.id or 0) < (b.id or 0) end
        return a.quantity > b.quantity
    end)
    return entries
end

function U:Selected()
    return A:FindSession(A.selectedID) or A:Active() or A.db.sessions[#A.db.sessions]
end

function U:ResetRows()
    self.rowIndex, self.rowY = 0, 0
    for _, row in ipairs(self.rows) do row:Hide() end
end

function U:Row(title, sub, value, height, onClick, entry, help, icon)
    self.rowIndex = self.rowIndex + 1
    local row = self.rows[self.rowIndex]
    if not row then
        row = CreateFrame("Button", nil, self.body.child)
        row:SetWidth(CONTENT)
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(1, 1, 1, .035)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(30, 30)
        row.icon:SetPoint("LEFT", 6, 0)
        row.title = label(row, 12, C.gold)
        row.title:SetPoint("TOPLEFT", 8, -6)
        row.title:SetWordWrap(false)
        row.sub = label(row, 11, C.muted)
        row.sub:SetPoint("TOPLEFT", 8, -23)
        row.sub:SetWidth(CONTENT - 16)
        row.sub:SetJustifyV("TOP")
        row.value = label(row, 12)
        row.value:SetPoint("TOPRIGHT", -8, -6)
        row.value:SetWidth(170)
        row.value:SetJustifyH("RIGHT")
        row:SetScript("OnEnter", function(self)
            if self.entry then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.entry.kind == "currency" then GameTooltip:SetCurrencyByID(self.entry.id)
                elseif self.entry.link and self.entry.link ~= "" then GameTooltip:SetHyperlink(self.entry.link)
                else GameTooltip:SetItemByID(self.entry.id) end
                GameTooltip:Show()
            elseif self.help then tooltip(self, self.title:GetText(), self.help)
            else tooltip(self, self.title:GetText(), self.sub:GetText()) end
        end)
        row:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
        row:SetScript("OnClick", function(self)
            if self.entry and self.entry.link then HandleModifiedItemClick(self.entry.link) end
            if self.action then self.action() end
        end)
        self.rows[self.rowIndex] = row
    end
    row:SetPoint("TOPLEFT", 0, -self.rowY)
    height = height or 42
    row:SetHeight(height)
    icon = icon or entryIcon(entry)
    row.icon:SetTexture(icon)
    row.icon:SetShown(icon ~= nil)
    local inset = icon and 42 or 8
    row.title:ClearAllPoints()
    row.title:SetPoint("TOPLEFT", inset, -6)
    row.sub:ClearAllPoints()
    row.sub:SetPoint("TOPLEFT", inset, -23)
    row.sub:SetWidth(CONTENT - inset - 8)
    row.title:SetWidth(value and value ~= "" and CONTENT - 190 or CONTENT - 16)
    row.title:SetText(title)
    row.sub:SetText(sub or "")
    row.sub:SetHeight(math.max(1, height - 26))
    row.value:SetText(value or "")
    row.action, row.entry, row.help = onClick, entry, help
    row:Show()
    self.rowY = self.rowY + height + 3
end

function U:Overview(session, totals)
    if totals.disenchants > 0 then
        local disenchantKey = "13262:disenchant"
        self:Row("Disenchanting", string.format("%d materials recovered · click to filter", totals.disenchantMaterials),
            totals.disenchants .. " disenchants", 42, function()
                if session.recipes[disenchantKey] then A.recipeFilter = disenchantKey; self.body:SetVerticalScroll(0); A:Changed() end
            end, nil, "Counts materials shown in the disenchant loot window while this session is recording.", 136244)
    end
    for _, key in ipairs(A.Model.STATS) do
        local stat = totals.stats[key]
        local observed, expected, low, high = A.Model.Rate(stat)
        local title = key == "multicraft" and "Multicraft" or key == "resourcefulness" and "Resourcefulness" or "Ingenuity"
        local value, sub, help
        if observed then
            value = string.format("%.1f%% observed", observed)
            sub = string.format("%.1f%% displayed · %d / %d crafts · %+.1f percentage points",
                expected, stat.hits, stat.trials, observed - expected)
            help = string.format("95%% observed-rate interval: %.1f–%.1f%%. %s\n\nDisplayed chance is averaged over sampled crafts. Proc chance is different from the percentage of extra items or saved materials.", low, high,
                stat.trials < 100 and "Small sample; expect variation." or "More crafts give a steadier estimate.")
        else
            value = "No sample yet"
            sub = "Recorded outcomes still count toward your totals."
            help = "A comparison needs a matching recipe and a stat snapshot at craft time. A missing stat is not a zero-percent sample."
        end
        if key == "resourcefulness" then help = help .. "\n\nThis measures crafts with a visible reagent return. Hidden rolls that saved nothing cannot be observed." end
        if key == "ingenuity" then help = help .. "\n\nOnly crafts that spent concentration enter this sample." end
        self:Row(title, sub, value, 42, nil, nil, help)
    end
    self:Row("Concentration", string.format("%s spent · %s refunded by ingenuity",
        count(totals.concentration), count(totals.refund)), "")
    if not A.recipeFilter then
        local recipes = {}
        for key, recipe in pairs(session.recipes) do recipes[#recipes + 1] = { key = key, recipe = recipe } end
        table.sort(recipes, function(a, b) return a.recipe.totals.crafts > b.recipe.totals.crafts end)
        if #recipes > 0 then self:Row("Recipes", "Select a recipe to filter the session.", "") end
        for _, row in ipairs(recipes) do
            local recipe, key = row.recipe, row.key
            self:Row(recipe.context.name, (recipe.context.profession or "") .. " · " .. recipe.context.scope .. " · click to filter",
                recipe.context.isDisenchant and recipe.totals.disenchants .. " disenchants" or recipe.totals.crafts .. " crafts", 42,
                function() A.recipeFilter = key; self.body:SetVerticalScroll(0); A:Changed() end, nil, nil, recipe.context.icon)
        end
    end
end

function U:Entries(totals, field)
    local entries = sortedValues(totals[field])
    if #entries == 0 then
        self:Row(field == "returns" and "No reagent returns yet" or "No output yet",
            field == "returns" and "Reagents appear here when resourcefulness returns them." or "Completed results appear here by item and quality.", "")
    end
    for _, entry in ipairs(entries) do
        local detail = entry.kind == "currency" and "Currency" or "Item"
        if entry.quality and entry.quality > 0 then detail = detail .. " · Quality " .. entry.quality end
        if entry.role then detail = detail .. " · " .. entry.role end
        if entry.scope then detail = detail .. " · " .. entry.scope end
        if field == "returns" then detail = detail .. " · saved by resourcefulness" end
        self:Row(itemName(entry), detail, "× " .. count(entry.quantity), 42, nil, entry)
    end
end

function U:Reagents(totals)
    local used, returned = sortedValues(totals.reagents), sortedValues(totals.returns)
    self:Row("Used", "Selected reagents committed to completed crafts.", #used > 0 and #used .. " types" or "None")
    for _, entry in ipairs(used) do
        local detail = entry.kind == "currency" and "Currency" or "Item"
        if entry.scope then detail = detail .. " · " .. entry.scope end
        self:Row(itemName(entry), detail, "× " .. count(entry.quantity), 42, nil, entry)
    end
    self:Row("Returned", "Reagents reported back by resourcefulness.", #returned > 0 and #returned .. " types" or "None")
    for _, entry in ipairs(returned) do
        self:Row(itemName(entry), "Saved by resourcefulness", "× " .. count(entry.quantity), 42, nil, entry)
    end
end

function U:Log(session)
    local entries = {}
    for i = #session.log, 1, -1 do
        local craft = session.log[i]
        if not A.recipeFilter or A.Model.RecipeKey(craft.context) == A.recipeFilter then entries[#entries + 1] = craft end
    end
    local pages = math.max(1, math.ceil(#entries / 50))
    self.logPage = math.min(self.logPage, pages)
    self:Row("Recent craft log", "Click for next page; Shift-click for previous.",
        string.format("Page %d / %d", self.logPage, pages), 42, function()
        self.logPage = ((self.logPage - 1 + (IsShiftKeyDown() and -1 or 1)) % pages) + 1
        self.body:SetVerticalScroll(0); A:Changed()
    end, nil, string.format("%d retained crafts. %d older crafts remain in totals only.", #session.log, session.trimmed))
    for i = (self.logPage - 1) * 50 + 1, math.min(#entries, self.logPage * 50) do
        local craft = entries[i]
        self:Row(craft.context.name,
            string.format("%s · %s · %d items · +%d extra · %d saved",
                date("%H:%M:%S", craft.at), craft.context.scope, craft.items, craft.extraItems, craft.savedItems), "",
                nil, nil, nil, craft.context.icon)
    end
end

function U:RenderHistory()
    local query = self.search:GetText():lower()
    local found = false
    for i = #A.db.sessions, 1, -1 do
        local session = A.db.sessions[i]
        local haystack = (session.name .. " " .. session.character):lower()
        if query == "" or haystack:find(query, 1, true) then
            found = true
            self:Row(session.name, string.format("%s · %s · %s", session.character,
                date("%d %b, %H:%M", session.startedAt), session.status), session.totals.crafts .. " crafts", 42, function()
                A.selectedID, A.recipeFilter = session.id, nil
                self.tab, self.logPage = "Overview", 1
                self.body:SetVerticalScroll(0)
                A:Changed()
            end)
        end
    end
    if not found then self:Row("No sessions found", "Finished sessions appear here. Search by session or character.") end
end

function U:Render()
    self.dirty = false
    local active = A:Active()
    local session = self:Selected()
    self.start:SetEnabled(not active)
    self.pause:SetEnabled(active ~= nil)
    self.finish:SetEnabled(active ~= nil)
    self.pause:SetText(active and active.status == "paused" and "Resume" or "Pause")
    self:ResetRows()
    self.exportButton:SetEnabled(session ~= nil)
    self.deleteButton:SetEnabled(session ~= nil and session.status == "finished")
    self.renameButton:SetEnabled(session ~= nil)
    local totals = session and session.totals or A.Model.NewTotals()
    local recipe = session and A.recipeFilter and session.recipes[A.recipeFilter]
    if recipe then totals = recipe.totals end
    self.filter:SetShown(recipe ~= nil and self.tab ~= "History")
    self.sessionTitle:SetText(recipe and recipe.context.name or session and session.name or "Start a crafting session")
    self.sessionMeta:SetText(session and string.format("%s · %s · %s · %s active", session.character,
        date("%d %b, %H:%M", session.startedAt), session.status, duration(A.Model.Duration(session, time())))
        or "Press Start, then craft normally. Session name is optional.")
    local values = { totals.crafts + totals.disenchants,
        recipe and recipe.context.isDisenchant and totals.disenchantMaterials or totals.items,
        totals.extraItems, totals.savedItems }
    local details = {
        string.format("%d crafts and %d disenchants.", totals.crafts, totals.disenchants),
        count(totals.baseItems) .. " base + " .. count(totals.extraItems) .. " extra. Includes order output.",
        totals.stats.multicraft.totalHits .. " observed multicraft procs.",
        totals.stats.resourcefulness.totalHits .. " crafts with visible returns. Item units only; currency returns are listed in Reagents.",
    }
    self.cards[2].heading:SetText(recipe and recipe.context.isDisenchant and "Materials recovered" or "Items produced")
    for i, card in ipairs(self.cards) do card.value:SetText(count(values[i])); card.help = details[i] end
    local history = self.tab == "History"
    self.search:SetShown(history)
    self.searchLabel:SetShown(history)
    if not history then self.search:ClearFocus() end
    self.body:ClearAllPoints()
    self.body:SetPoint("TOPLEFT", 18, history and -244 or -211)
    self.body:SetHeight(history and 152 or 185)
    if history then self:RenderHistory()
    elseif not session then
        self:Row("Your crafting, at a glance", "Actual output, multicraft extras, and returned reagents.")
        self:Row("Start before crafting", "Finish saves the session. Mini switches to a compact tracker.")
    elseif self.tab == "Overview" then self:Overview(session, totals)
    elseif self.tab == "Items" then self:Entries(totals, "outputs")
    elseif self.tab == "Reagents" then self:Reagents(totals)
    else self:Log(session) end
    for name, tab in pairs(self.tabs) do
        tab.text:SetTextColor(unpack(name == self.tab and C.gold or C.text))
        if name == self.tab then tab:LockHighlight() else tab:UnlockHighlight() end
    end
    self.body.child:SetHeight(math.max(1, self.rowY))
    local maxScroll = math.max(0, self.rowY - self.body:GetHeight())
    if self.body:GetVerticalScroll() > maxScroll then self.body:SetVerticalScroll(maxScroll) end
    self.footer:SetText(active and (active.status .. " · " .. active.name)
        or "Saved locally · hover a stat for details")
end

function U:RenderMini()
    local session = A:Active()
    self.mini.pause:SetEnabled(session ~= nil)
    self.mini.finish:SetEnabled(session ~= nil)
    self.mini.pause:SetText(session and session.status == "paused" and "Resume" or "Pause")
    if session then
        local t = session.totals
        self.mini.status:SetText(session.status .. " · " .. session.name)
        self.mini.numbers:SetText(string.format("Crafts %d · DE %d · Items %d\nExtra +%d · Saved %d", t.crafts, t.disenchants, t.items, t.extraItems, t.savedItems))
    else
        self.mini.status:SetText("No active session")
        self.mini.numbers:SetText("Open Details to start a session.")
    end
end

-- Visibility changes only here; refreshing data cannot reopen another view.
function U:SetView(view)
    assert(view == "full" or view == "mini" or view == "hidden")
    self.switching = true
    self.view = view
    A.db.settings.view = view
    A.db.settings.mini = nil -- migrate the old independent mini toggle
    if self.exportFrame then self.exportFrame:Hide() end
    if view ~= "full" then self.frame:Hide() end
    if view ~= "mini" then self.mini:Hide() end
    if view == "full" then self.frame:Show(); self:Render()
    elseif view == "mini" then self.mini:Show(); self:RenderMini() end
    self.switching = false
end

function U:ToggleMini()
    self:SetView(self.view == "mini" and "full" or "mini")
end

function U:Toggle()
    self:SetView(self.view == "full" and "hidden" or "full")
end

function U:SavePosition(frame, key)
    local point, _, relativePoint, x, y = frame:GetPoint()
    A.db.settings[key] = { point, relativePoint, x, y }
end

function U:Position(frame, key)
    frame:ClearAllPoints()
    local pos = A.db.settings[key]
    if pos then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else frame:SetPoint("CENTER", UIParent, "CENTER", 0, key == "miniPosition" and 260 or 0) end
end

function U:ResetPosition()
    A.db.settings.position, A.db.settings.miniPosition = nil, nil
    self:Position(self.frame, "position")
    self:Position(self.mini, "miniPosition")
end

function U:ShowExport()
    local session = self:Selected()
    if not session then A:Print("Start a session before exporting."); return end
    if self.view ~= "full" then self:SetView("full") end
    if not self.exportFrame then
        local frame = CreateFrame("Frame", "CraftResumeExport", self.frame, "BasicFrameTemplateWithInset")
        frame:SetSize(540, 320); frame:SetPoint("CENTER", self.frame, "CENTER"); frame:SetFrameStrata("DIALOG")
        frame.TitleText:SetText("Export session · CSV")
        local hint = label(frame, 11, C.muted); hint:SetPoint("TOPLEFT", 18, -38); hint:SetText("Ctrl+A, Ctrl+C to copy into a CSV file or spreadsheet.")
        local sf = scroll(frame, 18, -62, 484, 236)
        local box = CreateFrame("EditBox", nil, sf.child)
        box:SetMultiLine(true); box:SetAutoFocus(false); box:SetFontObject(ChatFontNormal)
        box:SetWidth(478); box:SetPoint("TOPLEFT"); box:SetMaxLetters(0)
        box:SetScript("OnTextChanged", function(self) sf.child:SetHeight(math.max(236, self:GetHeight())) end)
        box:SetScript("OnEscapePressed", function() frame:Hide() end)
        box:SetScript("OnCursorChanged", function(_, _, y, _, h)
            local offset = sf:GetVerticalScroll()
            y = -y
            if y < offset then sf:SetVerticalScroll(y)
            elseif y + h > offset + sf:GetHeight() then sf:SetVerticalScroll(y + h - sf:GetHeight()) end
        end)
        frame.box = box; self.exportFrame = frame
        table.insert(UISpecialFrames, "CraftResumeExport")
    end
    self.exportFrame:Show()
    self.exportFrame.box:SetText(A.Export.Session(session))
    self.exportFrame.box:SetFocus(); self.exportFrame.box:HighlightText()
end

function U:Initialize()
    local savedView = A.db.settings.view or (A.db.settings.mini and "mini" or "hidden")
    if savedView ~= "full" and savedView ~= "mini" then savedView = "hidden" end
    local frame = CreateFrame("Frame", "CraftResumeWindow", UIParent, "BasicFrameTemplateWithInset")
    self.frame = frame
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetScale(math.min(1, (UIParent:GetWidth() - 40) / WIDTH, (UIParent:GetHeight() - 40) / HEIGHT))
    frame:SetFrameStrata("HIGH"); frame:SetClampedToScreen(true); frame:SetMovable(true); frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); U:SavePosition(self, "position") end)
    frame.TitleText:SetText("Craft Resume")
    frame.CloseButton:SetScript("OnClick", function() self:SetView("hidden") end)
    self:Position(frame, "position")
    table.insert(UISpecialFrames, "CraftResumeWindow")
    local mini = button(frame, "Mini", 54, function() self:SetView("mini") end)
    mini:SetPoint("TOPRIGHT", -34, -1)
    self.miniButton = mini

    local nameLabel = label(frame, 11, C.gold); nameLabel:SetPoint("TOPLEFT", 18, -44); nameLabel:SetText("Name")
    self.nameBox = edit(frame, 224); self.nameBox:SetPoint("TOPLEFT", 62, -39)
    self.nameBox:SetText("")
    self.start = button(frame, "Start", 82, function() A:Start(self.nameBox:GetText()); self.nameBox:ClearFocus(); self.nameBox:SetText("") end)
    self.start:SetPoint("TOPLEFT", 298, -39)
    self.pause = button(frame, "Pause", 82, function() A:Pause() end); self.pause:SetPoint("LEFT", self.start, "RIGHT", 6, 0)
    self.finish = button(frame, "Finish", 82, function() A:Stop() end); self.finish:SetPoint("LEFT", self.pause, "RIGHT", 6, 0)

    self.sessionTitle = label(frame, 14, C.gold); self.sessionTitle:SetPoint("TOPLEFT", 18, -78); self.sessionTitle:SetWidth(440); self.sessionTitle:SetWordWrap(false)
    self.sessionMeta = label(frame, 11, C.muted); self.sessionMeta:SetPoint("TOPLEFT", 18, -101); self.sessionMeta:SetWidth(556); self.sessionMeta:SetWordWrap(false)
    self.filter = button(frame, "All recipes", 90, function() A.recipeFilter = nil; self.body:SetVerticalScroll(0); A:Changed() end)
    self.filter:SetPoint("TOPRIGHT", -24, -74)
    self.cards = {}
    local cardData = {
        { "Actions", "Interface\\Icons\\Trade_Engineering" },
        { "Items produced", "Interface\\Icons\\INV_Misc_Bag_10" },
        { "Multicraft extra", "Interface\\Icons\\INV_Misc_Gear_01" },
        { "Reagents saved", "Interface\\Icons\\INV_Enchant_Dust" },
    }
    for i, data in ipairs(cardData) do
        local text = data[1]
        local card = CreateFrame("Frame", nil, frame)
        card:SetSize(136, 44); card:SetPoint("TOPLEFT", 18 + (i - 1) * 140, -123)
        card.icon = card:CreateTexture(nil, "ARTWORK"); card.icon:SetSize(30, 30); card.icon:SetPoint("LEFT", 0, 0); card.icon:SetTexture(data[2])
        local heading = label(card, 10, C.gold); heading:SetPoint("TOPLEFT", 36, -2); heading:SetText(text); card.heading = heading
        card.value = label(card, 18); card.value:SetPoint("TOPLEFT", 36, -19); card.value:SetWidth(96); card.value:SetWordWrap(false)
        card:EnableMouse(true)
        card:SetScript("OnEnter", function(self) tooltip(self, text, self.help or "") end)
        card:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.cards[i] = card
    end
    self.tabs = {}
    local tabX = 18
    for _, info in ipairs({ { "Overview", 94 }, { "Items", 70 }, { "Reagents", 86 }, { "Craft log", 86 }, { "History", 80 } }) do
        local tabName, width = info[1], info[2]
        local tab = button(frame, tabName, width, function() self.tab = tabName; self.body:SetVerticalScroll(0); A:Changed() end)
        tab:SetPoint("TOPLEFT", tabX, -180)
        tabX = tabX + width + 6
        self.tabs[tabName] = tab
    end
    self.searchLabel = label(frame, 11, C.gold); self.searchLabel:SetPoint("TOPLEFT", 18, -220); self.searchLabel:SetText("Search")
    self.search = edit(frame, 250); self.search:SetPoint("TOPLEFT", 68, -214)
    self.body = scroll(frame, 18, -211, CONTENT, 185); self.rows = {}
    self.search:SetScript("OnTextChanged", function() self.body:SetVerticalScroll(0); A:Changed() end)
    self.search:Hide(); self.searchLabel:Hide()
    self.exportButton = button(frame, "Export CSV", 98, function() self:ShowExport() end); self.exportButton:SetPoint("BOTTOMRIGHT", -22, 12)
    self.deleteButton = button(frame, "Delete", 70, function()
        local session = self:Selected()
        if session then StaticPopup_Show("CRAFT_RESUME_DELETE", session.name, nil, session.id) end
    end); self.deleteButton:SetPoint("RIGHT", self.exportButton, "LEFT", -6, 0)
    self.renameButton = button(frame, "Rename", 76, function()
        local session = self:Selected()
        if session then StaticPopup_Show("CRAFT_RESUME_RENAME", nil, nil, session.id) end
    end); self.renameButton:SetPoint("RIGHT", self.deleteButton, "LEFT", -6, 0)
    self.footer = label(frame, 11, C.muted); self.footer:SetPoint("BOTTOMLEFT", 18, 44); self.footer:SetWidth(556); self.footer:SetWordWrap(false)

    StaticPopupDialogs.CRAFT_RESUME_DELETE = {
        text = "Delete session \"%s\"? This removes its saved history.", button1 = DELETE, button2 = CANCEL,
        OnAccept = function(_, id) A:Delete(id) end, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopupDialogs.CRAFT_RESUME_RENAME = {
        text = "Session name", button1 = ACCEPT, button2 = CANCEL, hasEditBox = true,
        OnShow = function(popup)
            local box = popup.GetEditBox and popup:GetEditBox() or popup.editBox
            local session = A:FindSession(popup.data)
            box:SetMaxLetters(100); box:SetText(session and session.name or ""); box:SetFocus(); box:HighlightText()
        end,
        OnAccept = function(popup, id)
            local box = popup.GetEditBox and popup:GetEditBox() or popup.editBox
            local name = box:GetText():match("^%s*(.-)%s*$")
            local session = A:FindSession(id)
            if session and name ~= "" then session.name = name; A:Changed() end
        end, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }

    local tracker = CreateFrame("Frame", "CraftResumeMini", UIParent, "BasicFrameTemplateWithInset")
    self.mini = tracker; tracker:SetSize(236, 118); tracker:SetFrameStrata("HIGH")
    tracker.TitleText:SetText("Craft Resume")
    tracker:SetMovable(true); tracker:SetClampedToScreen(true); tracker:EnableMouse(true); tracker:RegisterForDrag("LeftButton")
    tracker:SetScript("OnDragStart", tracker.StartMoving)
    tracker:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); U:SavePosition(self, "miniPosition") end)
    self:Position(tracker, "miniPosition")
    tracker.CloseButton:SetScript("OnClick", function() self:SetView("hidden") end)
    table.insert(UISpecialFrames, "CraftResumeMini")
    tracker.status = label(tracker, 10, C.muted); tracker.status:SetPoint("TOPLEFT", 12, -29); tracker.status:SetWidth(210); tracker.status:SetWordWrap(false)
    tracker.numbers = label(tracker, 12); tracker.numbers:SetPoint("TOPLEFT", 12, -48); tracker.numbers:SetWidth(210); tracker.numbers:SetHeight(32)
    tracker.pause = button(tracker, "Pause", 64, function() A:Pause() end); tracker.pause:SetPoint("TOPLEFT", 10, -88)
    tracker.finish = button(tracker, "Finish", 62, function() A:Stop() end); tracker.finish:SetPoint("LEFT", tracker.pause, "RIGHT", 4, 0)
    tracker.open = button(tracker, "Details", 76, function() self:SetView("full") end); tracker.open:SetPoint("LEFT", tracker.finish, "RIGHT", 4, 0)
    -- Escape and native close buttons must update the stored mode too.
    for view, window in pairs({ full = frame, mini = tracker }) do
        local mode = view
        window:SetScript("OnShow", function()
            if not self.switching then self:SetView(mode) end
        end)
        window:SetScript("OnHide", function()
            if not self.switching and self.view == mode then self:SetView("hidden") end
        end)
    end
    local elapsed, clockElapsed = 0, 0
    local update = CreateFrame("Frame")
    update:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        clockElapsed = clockElapsed + dt
        if clockElapsed >= 30 then
            clockElapsed = 0
            if frame:IsShown() and A:Active() then self.dirty = true end
        end
        if elapsed < .25 then return end
        elapsed = 0
        if self.dirty then
            if self.view == "full" then self:Render()
            elseif self.view == "mini" then self:RenderMini() end
            self.dirty = false
        end
    end)
    update:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    update:SetScript("OnEvent", function() A:Changed() end)
    self:SetView(savedView)
end
