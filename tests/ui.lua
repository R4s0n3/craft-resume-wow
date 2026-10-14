-- Exercise actual UI callbacks with a small frame harness. Native textures and
-- font rendering still need a WoW client; mode changes and data routing do not.
local methods = {}
local function widget()
    return setmetatable({ shown = true, scripts = {}, text = "", width = 1, height = 1 }, { __index = methods })
end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:Show()
    if not self.shown then self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
end
function methods:Hide()
    if self.shown then self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width end
function methods:GetHeight() return self.height end
function methods:SetPoint(...) self.point = { ... } end
function methods:GetPoint() return unpack(self.point) end
function methods:SetText(text)
    self.text = tostring(text or "")
    if self.fontString then self.fontString.text = self.text end
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end
end
function methods:GetText() return self.text end
function methods:GetFontString() return self.fontString end
function methods:CreateFontString() return widget() end
function methods:CreateTexture() return widget() end
function methods:SetScrollChild(child) self.child = child end
function methods:SetVerticalScroll(value) self.offset = value end
function methods:GetVerticalScroll() return self.offset or 0 end
function methods:SetEnabled(value) self.enabled = value end
function methods:Click() if self.enabled ~= false then self.scripts.OnClick(self) end end
for _, name in ipairs({ "SetFont", "SetTextColor", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetAllPoints",
    "SetColorTexture", "SetHighlightTexture", "SetTexture", "SetAutoFocus", "SetMaxLetters", "ClearFocus", "ClearAllPoints",
    "SetScale", "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag",
    "StartMoving", "StopMovingOrSizing", "LockHighlight", "UnlockHighlight", "RegisterEvent",
    "SetMultiLine", "SetFontObject", "SetFocus", "HighlightText" }) do methods[name] = function() end end
local allFrames = {}
function CreateFrame(_, name, parent, template)
    local f = widget(); f.parent, f.template = parent, template
    if template == "BasicFrameTemplateWithInset" then
        f.TitleText, f.CloseButton = widget(), widget()
        f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    elseif template == "UIPanelButtonTemplate" then f.fontString = widget() end
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end
UIParent = widget(); UIParent:SetSize(1920, 1080)
UISpecialFrames, StaticPopupDialogs = {}, {}
STANDARD_TEXT_FONT, ChatFontNormal = "font", "font"
DELETE, CANCEL, ACCEPT = "Delete", "Cancel", "Accept"
date, time = os.date, function() return 10000 end
C_Item = { GetItemNameByID = function(id) return "Item " .. id end, GetItemIconByID = function() return 134400 end,
    RequestLoadItemDataByID = function() end }
C_CurrencyInfo = { GetCurrencyInfo = function() return { name = "Currency" } end }
IsShiftKeyDown = function() return false end

local A = { db = { sessions = {}, settings = {} } }
assert(loadfile("CraftResume/Model.lua"))("CraftResume", A)
assert(loadfile("CraftResume/Export.lua"))("CraftResume", A)
function A:Active() return self.active end
function A:FindSession(id)
    for _, session in ipairs(self.db.sessions) do if session.id == id then return session end end
end
function A:Changed() self.UI.dirty = true end
function A:Print() end
function A:Pause()
    self.Model.SetStatus(self.active, self.active.status == "recording" and "paused" or "recording", time())
    self:Changed()
end
function A:Stop() self.Model.SetStatus(self.active, "finished", time()); self.active = nil; self:Changed() end

local function initialize(settings)
    A.db.settings = settings or {}
    assert(loadfile("CraftResume/UI.lua"))("CraftResume", A)
    A.UI:Initialize()
    return A.UI
end
local function visible(u, view)
    assert(u.frame:IsShown() == (view == "full"), "wrong full visibility")
    assert(u.mini:IsShown() == (view == "mini"), "wrong mini visibility")
    assert(u.view == view and A.db.settings.view == view, "wrong saved view")
end
local function tick()
    for _, frame in ipairs(allFrames) do
        if frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, .3) end
    end
end
local passed = 0
local function test(name, fn)
    fn(); passed = passed + 1; print("ok " .. passed .. " - " .. name)
end
local u = initialize()
test("first load is hidden; opening renders the empty native window", function()
    visible(u, "hidden"); u:Toggle(); visible(u, "full")
    assert(u.frame.template == "BasicFrameTemplateWithInset")
    assert(u.frame:GetWidth() * u.frame:GetHeight() < 1000 * 690 / 2)
end)
test("Mini and Details buttons swap views, never show both", function()
    u.miniButton:Click(); visible(u, "mini")
    u.mini.open:Click(); visible(u, "full")
    u:ToggleMini(); visible(u, "mini")
    u:ToggleMini(); visible(u, "full")
end)
test("slash toggle expands mini and closes full", function()
    u:SetView("mini"); u:Toggle(); visible(u, "full")
    u:Toggle(); visible(u, "hidden")
end)
test("native close and Escape stay closed after a data refresh", function()
    u:SetView("mini"); u.mini.CloseButton:Click(); A:Changed(); tick(); visible(u, "hidden")
    u:SetView("full"); u.frame:Hide(); A:Changed(); tick(); visible(u, "hidden")
    u:SetView("mini"); u.mini:Hide(); A:Changed(); tick(); visible(u, "hidden")
end)

local s = A.Model.NewSession(1, "Flasks", "Crafter-Realm", "guid", time())
local op = A.Model.NewOperation({ recipeID = 123, name = "Flask", scope = "personal",
    chances = { multicraft = 20, resourcefulness = 30 } }, time(), 1)
A.Model.AddResult(s, op, { itemID = 50, quantity = 5, multicraft = 3, resourcesReturned = {
    { reagent = { itemID = 51 }, quantity = 2 },
} }, "item")
A.db.sessions, A.active = { s }, s
test("live refresh updates only the visible mode; mini controls work", function()
    u:SetView("mini"); A:Changed(); tick(); visible(u, "mini")
    assert(u.mini.numbers:GetText():find("Extra +3", 1, true))
    u.mini.pause:Click(); tick(); assert(s.status == "paused"); assert(u.mini.pause:GetText() == "Resume")
    u.mini.pause:Click(); tick(); assert(s.status == "recording"); visible(u, "mini")
end)
test("all compact tabs render and history selects the correct session", function()
    u:SetView("full")
    for _, tab in ipairs({ "Items", "Reagents", "Craft log", "History", "Overview" }) do
        u.tabs[tab]:Click(); tick(); assert(u.rowIndex > 0); visible(u, "full")
    end
    u.tabs.History:Click(); tick(); assert(u.search:IsShown())
    u.search:SetText("missing"); tick(); assert(u.rows[1].title:GetText() == "No sessions found")
    u.search:SetText("flasks"); tick(); u.rows[1]:Click(); tick()
    assert(A.selectedID == 1 and u.tab == "Overview" and not u.search:IsShown())
    assert(u.rows[1].value:GetText() == "100.0% observed")
end)
test("export from mini switches to full and closes when minimized", function()
    u:SetView("mini"); u:ShowExport(); visible(u, "full")
    assert(u.exportFrame:IsShown())
    assert(u.exportFrame.box:GetText():find('"Flasks"', 1, true))
    u.miniButton:Click(); visible(u, "mini"); assert(not u.exportFrame:IsShown())
end)
test("finishing from mini preserves history and keeps mini selected", function()
    u.mini.finish:Click(); tick(); visible(u, "mini")
    assert(s.status == "finished" and A.db.sessions[1] == s and A.active == nil)
    assert(u.mini.pause.enabled == false and u.mini.finish.enabled == false)
end)
test("reload restores exactly one view and migrates the old mini setting", function()
    for _, mode in ipairs({ "full", "mini", "hidden" }) do
        u = initialize({ view = mode }); visible(u, mode)
    end
    u = initialize({ mini = true }); visible(u, "mini"); assert(A.db.settings.mini == nil)
end)
print(string.format("\n%d UI workflow tests passed", passed))
