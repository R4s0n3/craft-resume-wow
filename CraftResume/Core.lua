local addonName, A = ...
A.name = addonName
A.version = "0.5.0"

function A:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Craft Resume:|r " .. message)
end

function A:Changed()
    if self.UI then self.UI.dirty = true end
end

function A:FindSession(id)
    for _, session in ipairs(self.db.sessions) do
        if session.id == id then return session end
    end
end

function A:Active()
    return self:FindSession(self.db.active[self.guid])
end

function A:Start(name)
    if self:Active() then
        self:Print("You already have a session. Resume or finish it first.")
        return
    end
    local now = time()
    local id = self.db.nextID
    self.db.nextID = id + 1
    name = name and name:match("^%s*(.-)%s*$") or ""
    if name == "" then name = "Crafting · " .. date("%d %b, %H:%M", now) end
    local session = self.Model.NewSession(id, name:sub(1, 100), self.character, self.guid, now)
    table.insert(self.db.sessions, session)
    self.db.active[self.guid] = id
    self.Tracker:Reset()
    self.selectedID = id
    self.recipeFilter = nil
    self:Changed()
    self:Print("Session started. Craft normally; /tr opens your summary.")
end

function A:Pause()
    local session = self:Active()
    if not session then return end
    local status = session.status == "recording" and "paused" or "recording"
    self.Model.SetStatus(session, status, time())
    self.Tracker:Reset()
    self:Changed()
    self:Print(status == "paused" and "Session paused." or "Session resumed.")
end

function A:Stop()
    local session = self:Active()
    if not session then return end
    self.Model.SetStatus(session, "finished", time())
    self.db.active[self.guid] = nil
    self.Tracker:Reset()
    self.Model.Prune(self.db)
    self:Changed()
    self:Print(string.format("Saved %s: %d crafts, %d items, +%d multicraft, %d reagent units saved.",
        session.name, session.totals.crafts, session.totals.items,
        session.totals.extraItems, session.totals.savedItems))
end

function A:Delete(id)
    for i, session in ipairs(self.db.sessions) do
        if session.id == id and session.status == "finished" then
            table.remove(self.db.sessions, i)
            self.selectedID, self.recipeFilter = nil, nil
            self:Changed()
            return
        end
    end
end

function A:Initialize()
    -- Import the database saved under the addon's original Trade Resume name.
    CraftResumeDB = CraftResumeDB or TradeResumeDB or { schema = 1, nextID = 1, sessions = {}, active = {}, settings = {} }
    TradeResumeDB = nil
    self.db = CraftResumeDB
    if self.db.schema ~= 1 then
        self:Print("This database was created by a different version. History has been left untouched.")
        return
    end
    self.guid = UnitGUID("player")
    self.character = UnitName("player") .. "-" .. GetRealmName()
    for _, savedSession in ipairs(self.db.sessions) do self.Model.EnsureSession(savedSession) end
    -- Reload/login restores the session paused: no stale casts or offline time.
    local session = self:Active()
    if session then
        session.runningSince = nil
        session.status = "paused"
        self.selectedID = session.id
        self:Print("Your session is saved and paused. Use /tr resume to continue.")
    end
    self.Tracker:Initialize()
    self.UI:Initialize()
    self.ready = true
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == addonName then A:Initialize()
    elseif event == "PLAYER_LOGOUT" and A.ready then
        local session = A:Active()
        if session then A.Model.SetStatus(session, "paused", time()) end
    end
end)

SLASH_CRAFTRESUME1 = "/tr"
SLASH_CRAFTRESUME2 = "/cr"
SLASH_CRAFTRESUME3 = "/craftresume"
SLASH_CRAFTRESUME4 = "/traderesume"
SlashCmdList.CRAFTRESUME = function(message)
    if not A.ready then return end
    local command, rest = message:match("^(%S*)%s*(.-)$")
    command = command:lower()
    if command == "start" then A:Start(rest)
    elseif command == "stop" or command == "finish" then A:Stop()
    elseif command == "pause" or command == "resume" then
        local s = A:Active()
        if s and ((command == "pause" and s.status == "recording") or
            (command == "resume" and s.status == "paused")) then A:Pause() end
    elseif command == "mini" then A.UI:ToggleMini()
    elseif command == "export" then A.UI:ShowExport()
    elseif command == "resetui" then A.UI:ResetPosition()
    elseif command == "help" then
        A:Print("/tr · start [name] · pause · resume · stop · mini · export · resetui")
    else A.UI:Toggle() end
end
