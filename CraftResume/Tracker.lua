local _, A = ...
local T = { operations = {}, operationOrder = {}, pending = {} }
A.Tracker = T

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

local function accessible(value)
    return not issecretvalue or not issecretvalue(value)
end

function T:Reset()
    self.operations, self.operationOrder, self.pending = {}, {}, {}
    self.batch, self.latest = nil, nil
    self.serial = 0
    self.disenchant = nil
end

function T:IsDisenchantSpell(spellID)
    if spellID == 13262 then return true end
    local info = C_Spell and safe(C_Spell.GetSpellInfo, spellID)
    return info and info.name == (DISENCHANT or "Disenchant")
end

function T:IsRecording()
    local session = A:Active()
    return session and session.status == "recording" and session
end

-- Match localized names. bonusStatValue is a rating, not a stable stat ID.
-- ratingPct already contains the bonus; bonusRatingPct must not be added.
function T:ReadChances(info)
    local chances = {}
    local names = {
        multicraft = ITEM_MOD_MULTICRAFT_SHORT or "Multicraft",
        resourcefulness = ITEM_MOD_RESOURCEFULNESS_SHORT or "Resourcefulness",
        ingenuity = ITEM_MOD_INGENUITY_SHORT or "Ingenuity",
    }
    for _, stat in ipairs(info and info.bonusStats or {}) do
        for key, name in pairs(names) do
            if stat.bonusStatName == name and type(stat.ratingPct) == "number" then
                chances[key] = math.max(0, math.min(100, stat.ratingPct))
            end
        end
    end
    return chances
end

function T:Snapshot(recipeID, batch)
    local recipe = safe(C_TradeSkillUI.GetRecipeInfo, recipeID)
    local profession = safe(C_TradeSkillUI.GetProfessionInfoByRecipeID, recipeID)
    local context = { recipeID = recipeID, name = recipe and recipe.name or "Recipe #" .. recipeID,
        icon = recipe and recipe.icon,
        profession = profession and profession.professionName or "", scope = "unknown", chances = {}, reagents = {} }
    local operationInfo
    if batch then
        context.scope = batch.orderID and "order" or batch.isRecraft and "recraft" or "personal"
        context.isRecraft = batch.isRecraft
        context.isSalvage = batch.isSalvage
        for _, info in ipairs(batch.reagents or {}) do
            local reagent = info.reagent or info
            local id = reagent.itemID or reagent.currencyID
            if id and (info.quantity or 0) > 0 then
                context.reagents[#context.reagents + 1] = {
                    kind = reagent.itemID and "item" or "currency", id = id, quantity = info.quantity,
                }
            end
        end
        if batch.orderID then
            operationInfo = safe(C_TradeSkillUI.GetCraftingOperationInfoForOrder,
                recipeID, batch.reagents, batch.orderID, batch.concentration)
        else
            operationInfo = safe(C_TradeSkillUI.GetCraftingOperationInfo,
                recipeID, batch.reagents, batch.itemGUID, batch.concentration)
        end
    else
        local frame = ProfessionsFrame
        local crafting = frame and frame.CraftingPage and frame.CraftingPage.SchematicForm
        local orderView = frame and frame.OrdersPage and frame.OrdersPage.OrderView
        local orderForm = orderView and orderView.OrderDetails and orderView.OrderDetails.SchematicForm
        for _, form in pairs({ crafting = crafting, order = orderForm }) do
            if form:IsShown() and form.currentRecipeInfo and form.currentRecipeInfo.recipeID == recipeID then
                operationInfo = safe(form.GetRecipeOperationInfo, form)
                context.scope = form == orderForm and "order" or "personal"
                if form.recipeSchematic and form.recipeSchematic.isRecraft then
                    context.isRecraft = true
                    if context.scope == "personal" then context.scope = "recraft" end
                end
                break
            end
        end
    end
    context.chances = self:ReadChances(operationInfo)
    -- Salvaging can have random output independently of multicraft.
    if context.isSalvage then context.chances = {} end
    return context
end

function T:NewPending(recipeID, batch, beginSeen)
    local pending = { recipeID = recipeID, context = self:Snapshot(recipeID, batch), at = GetTime(), beginSeen = beginSeen }
    table.insert(self.pending, pending)
    self.latest = pending
    -- Failed/unsupported operations cannot grow this queue indefinitely.
    if #self.pending > 20 then table.remove(self.pending, 1) end
end

function T:Begin(recipeID)
    if not self:IsRecording() or not accessible(recipeID) or type(recipeID) ~= "number" then return end
    if safe(C_TradeSkillUI.IsTradeSkillLinked) or safe(C_TradeSkillUI.IsTradeSkillGuild) then return end
    local batch = self.batch and self.batch.recipeID == recipeID and self.batch or nil
    local pending = self.latest
    if pending and not pending.consumed and not pending.beginSeen and pending.recipeID == recipeID
        and GetTime() - pending.at < .1 then
        pending.beginSeen = true
        pending.context = self:Snapshot(recipeID, batch)
        return
    end
    self:NewPending(recipeID, batch, true)
end

function T:Capture(recipeID, reagents, orderID, concentration, itemGUID, isRecraft, isSalvage)
    if not self:IsRecording() or not accessible(recipeID) or type(recipeID) ~= "number" then return end
    self.batch = { recipeID = recipeID, reagents = A.Model.Copy(reagents or {}),
        orderID = orderID and orderID ~= 0 and orderID or nil, concentration = concentration == true,
        itemGUID = itemGUID, isRecraft = isRecraft, isSalvage = isSalvage }
    -- TRADE_SKILL_CRAFT_BEGIN may be dispatched inside the hooked C call.
    local pending = self.latest
    if pending and pending.recipeID == recipeID and GetTime() - pending.at < 1 then
        -- An instant result can arrive inside the C call, before its post-hook.
        -- Do not leave a second pending craft behind after it was consumed.
        if not pending.consumed then pending.context = self:Snapshot(recipeID, self.batch) end
    else self:NewPending(recipeID, self.batch, false) end
end

function T:CastStart(unit, castGUID, spellID)
    if unit ~= "player" or not accessible(spellID) or not accessible(castGUID) or not self:IsRecording() then return end
    if self:IsDisenchantSpell(spellID) then
        self.disenchant = { castGUID = castGUID, started = GetTime(), looted = false }
        return
    end
    local batch = self.batch and self.batch.recipeID == spellID and self.batch or nil
    local pending = self.latest
    if pending and not pending.consumed and not pending.castGUID and pending.recipeID == spellID
        and GetTime() - pending.at < 1 then
        pending.castGUID = castGUID
    elseif batch then
        self:NewPending(spellID, batch, false)
        self.latest.castGUID = castGUID
    end
    -- A fresh snapshot on each cast reflects equipment/buff changes in a batch.
    if self.latest and self.latest.castGUID == castGUID and batch then
        self.latest.context = self:Snapshot(spellID, batch)
    end
end

function T:CastFailed(unit, castGUID)
    if unit ~= "player" or not accessible(castGUID) then return end
    if self.disenchant and self.disenchant.castGUID == castGUID then self.disenchant = nil end
    for i = #self.pending, 1, -1 do
        if self.pending[i].castGUID == castGUID then table.remove(self.pending, i) end
    end
    if self.latest and self.latest.castGUID == castGUID then self.latest = nil; self.batch = nil end
end

function T:CastSucceeded(unit, castGUID, spellID)
    if unit ~= "player" or not accessible(spellID) or not self:IsRecording() then return end
    if self:IsDisenchantSpell(spellID) and not self.disenchant then
        self.disenchant = { castGUID = castGUID, started = GetTime(), looted = false }
    end
end

function T:LootReady()
    local session = self:IsRecording()
    local pending = self.disenchant
    if not session or not pending or pending.looted or GetTime() - pending.started > 15 then
        if pending and GetTime() - pending.started > 15 then self.disenchant = nil end
        return
    end
    local results = {}
    for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
        local icon, _, quantity, currencyID = GetLootSlotInfo(slot)
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local itemID = link and C_Item.GetItemInfoInstant(link)
        if itemID then
            results[#results + 1] = { kind = "item", id = itemID, link = link, quantity = quantity or 1, icon = icon }
        elseif currencyID and currencyID > 0 then
            results[#results + 1] = { kind = "currency", id = currencyID, quantity = quantity or 1, icon = icon }
        end
    end
    if #results == 0 then return end
    pending.looted = true
    self.serial = self.serial + 1
    A.Model.AddDisenchant(session, results, time(), "disenchant-" .. self.serial)
    self.disenchant = nil
    A:Changed()
end

function T:Result(data, kind)
    local session = self:IsRecording()
    if not session or type(data) ~= "table" then return end
    local operationID = data.operationID
    local key = operationID and operationID ~= 0 and tostring(operationID) or nil
    local operation = key and self.operations[key]
    if not operation then
        -- Result payloads have no recipe ID: consume the oldest live craft
        -- context, never whatever recipe happens to be selected now.
        local pending
        while #self.pending > 0 do
            local candidate = table.remove(self.pending, 1)
            if GetTime() - candidate.at < 120 then pending = candidate; break end
        end
        local context = pending and pending.context or { name = "Unattributed craft", scope = "unknown", chances = {} }
        if pending then pending.consumed = true end
        self.serial = self.serial + 1
        operation = A.Model.NewOperation(context, time(), key or "local-" .. self.serial)
        if key then
            self.operations[key] = operation
            table.insert(self.operationOrder, key)
            if #self.operationOrder > 256 then self.operations[table.remove(self.operationOrder, 1)] = nil end
        end
    end
    if A.Model.AddResult(session, operation, data, kind) then A:Changed() end
end

function T:Initialize()
    self:Reset()
    local frame = CreateFrame("Frame")
    self.frame = frame
    frame:RegisterEvent("TRADE_SKILL_CRAFT_BEGIN")
    frame:RegisterEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT")
    frame:RegisterEvent("TRADE_SKILL_CURRENCY_REWARD_RESULT")
    frame:RegisterEvent("LOOT_READY")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "TRADE_SKILL_CRAFT_BEGIN" then self:Begin(...)
        elseif event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then self:Result(..., "item")
        elseif event == "TRADE_SKILL_CURRENCY_REWARD_RESULT" then self:Result(..., "currency")
        elseif event == "LOOT_READY" then self:LootReady()
        elseif event == "UNIT_SPELLCAST_START" then self:CastStart(...)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then self:CastSucceeded(...)
        else self:CastFailed(...) end
    end)
    hooksecurefunc(C_TradeSkillUI, "CraftRecipe", function(id, _, reagents, _, orderID, concentration)
        self:Capture(id, reagents, orderID, concentration)
    end)
    hooksecurefunc(C_TradeSkillUI, "CraftEnchant", function(id, _, reagents, _, concentration)
        self:Capture(id, reagents, nil, concentration)
    end)
    hooksecurefunc(C_TradeSkillUI, "CraftSalvage", function(id, _, _, reagents, concentration)
        self:Capture(id, reagents, nil, concentration, nil, false, true)
    end)
    hooksecurefunc(C_TradeSkillUI, "RecraftRecipe", function(guid, reagents, _, concentration)
        local id = safe(C_TradeSkillUI.GetOriginalCraftRecipeID, guid)
        self:Capture(id, reagents, nil, concentration, guid, true)
    end)
    hooksecurefunc(C_TradeSkillUI, "RecraftRecipeForOrder", function(orderID, guid, reagents, _, concentration)
        local id = safe(C_TradeSkillUI.GetOriginalCraftRecipeID, guid)
        self:Capture(id, reagents, orderID, concentration, guid, true)
    end)
end
