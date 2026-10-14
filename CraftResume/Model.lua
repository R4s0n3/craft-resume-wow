local _, A = ...
local M = {}
A.Model = M
M.LOG_LIMIT = 1000
M.HISTORY_LIMIT = 200
M.STATS = { "multicraft", "resourcefulness", "ingenuity" }

function M.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = M.Copy(v) end
    return copy
end

function M.NewTotals()
    local t = { crafts = 0, items = 0, baseItems = 0, extraItems = 0,
        savedItems = 0, savedCurrency = 0, concentration = 0, refund = 0,
        disenchants = 0, disenchantMaterials = 0,
        outputs = {}, reagents = {}, returns = {}, disenchantOutputs = {}, stats = {} }
    for _, key in ipairs(M.STATS) do
        t.stats[key] = { trials = 0, hits = 0, expected = 0, totalHits = 0 }
    end
    return t
end

function M.EnsureTotals(t)
    t.crafts, t.items, t.baseItems, t.extraItems = t.crafts or 0, t.items or 0, t.baseItems or 0, t.extraItems or 0
    t.savedItems, t.savedCurrency = t.savedItems or 0, t.savedCurrency or 0
    t.concentration, t.refund = t.concentration or 0, t.refund or 0
    t.disenchants, t.disenchantMaterials = t.disenchants or 0, t.disenchantMaterials or 0
    t.outputs, t.reagents, t.returns = t.outputs or {}, t.reagents or {}, t.returns or {}
    t.disenchantOutputs = t.disenchantOutputs or {}
    t.stats = t.stats or {}
    for _, key in ipairs(M.STATS) do
        t.stats[key] = t.stats[key] or { trials = 0, hits = 0, expected = 0, totalHits = 0 }
    end
    return t
end

function M.EnsureSession(session)
    M.EnsureTotals(session.totals)
    session.recipes, session.log, session.trimmed = session.recipes or {}, session.log or {}, session.trimmed or 0
    for _, recipe in pairs(session.recipes) do M.EnsureTotals(recipe.totals) end
    return session
end

function M.NewSession(id, name, character, guid, now)
    return { id = id, name = name, character = character, guid = guid,
        startedAt = now, lastAt = now, runningSince = now, elapsed = 0,
        status = "recording", totals = M.NewTotals(), recipes = {}, log = {}, trimmed = 0 }
end

function M.Duration(session, now)
    return session.elapsed + (session.runningSince and math.max(0, now - session.runningSince) or 0)
end

function M.SetStatus(session, status, now)
    session.elapsed = M.Duration(session, now)
    session.runningSince = status == "recording" and now or nil
    session.status = status
    session.lastAt = now
    if status == "finished" then session.endedAt = now end
end

function M.RecipeKey(context)
    return tostring(context.recipeID or 0) .. ":" .. (context.scope or "unknown")
end

function M.NewOperation(context, now, id)
    return { seen = {}, record = { id = id, at = now,
        context = M.Copy(context), outputs = {}, reagents = {}, returns = {},
        items = 0, extraItems = 0, savedItems = 0, savedCurrency = 0,
        concentration = 0, refund = 0, procs = {} } }
end

local function addEntry(entries, entry, quantity)
    local key = table.concat({ entry.kind or "item", entry.id or 0, entry.quality or 0,
        entry.role or "", entry.scope or "" }, ":")
    if not entries[key] then
        entries[key] = M.Copy(entry)
        entries[key].quantity = 0
    end
    entries[key].quantity = entries[key].quantity + quantity
end

local function number(value)
    return type(value) == "number" and math.max(0, value) or 0
end

-- One operation may deliver several item/currency events. Only its first main
-- result adds a craft; first-craft rewards never add trials or crafted units.
function M.AddResult(session, operation, data, kind)
    local record = operation.record
    local identity = table.concat({ kind, data.itemID or data.currencyID or 0,
        data.itemGUID or "", data.hyperlink or "", data.quantity or 0,
        data.craftingQuality or 0, tostring(data.firstCraftReward == true),
        tostring(data.bonusCraft == true), data.multicraft or 0 }, "|")
    if operation.seen[identity] then return false end
    operation.seen[identity] = true
    local context = record.context
    local key = M.RecipeKey(context)
    if not session.recipes[key] then
        session.recipes[key] = { context = M.Copy(context), totals = M.NewTotals() }
    end
    local targets = { session.totals, session.recipes[key].totals }
    local main = kind == "item" and not data.firstCraftReward and not data.bonusCraft
    if main and not record.counted then
        record.counted = true
        table.insert(session.log, record)
        if #session.log > M.LOG_LIMIT then
            table.remove(session.log, 1)
            session.trimmed = session.trimmed + 1
        end
        for _, totals in ipairs(targets) do
            totals.crafts = totals.crafts + 1
            for _, stat in ipairs(M.STATS) do
                local chance = context.chances and context.chances[stat]
                if stat == "ingenuity" and number(data.concentrationSpent) == 0 then chance = nil end
                if type(chance) == "number" then
                    record[stat .. "Sampled"] = true
                    totals.stats[stat].trials = totals.stats[stat].trials + 1
                    totals.stats[stat].expected = totals.stats[stat].expected + chance / 100
                end
            end
        end
        for _, reagent in ipairs(context.reagents or {}) do
            local quantity = number(reagent.quantity)
            if reagent.id and reagent.id > 0 and quantity > 0 then
                local entry = { kind = reagent.kind or "item", id = reagent.id, link = reagent.link,
                    role = "Used", scope = context.scope, icon = reagent.icon }
                addEntry(record.reagents, entry, quantity)
                for _, totals in ipairs(targets) do addEntry(totals.reagents, entry, quantity) end
            end
        end
    end
    local quantity = number(data.quantity)
    local extra = main and math.min(quantity, number(data.multicraft)) or 0
    local crafted = main and not data.isEnchant and not context.isRecraft and context.scope ~= "recraft"
    local role = data.firstCraftReward and "First craft" or data.bonusCraft and "Bonus"
        or data.isEnchant and "Enchanted" or (context.isRecraft or context.scope == "recraft") and "Recrafted" or "Crafted"
    local entry = { kind = kind, id = data.itemID or data.currencyID, link = data.hyperlink,
        quality = data.craftingQuality, role = role, scope = context.scope }
    if entry.id and entry.id > 0 and quantity > 0 then
        addEntry(record.outputs, entry, quantity)
        for _, totals in ipairs(targets) do addEntry(totals.outputs, entry, quantity) end
    end
    if main then
        local savedItems, savedCurrency = 0, 0
        for _, resource in ipairs(data.resourcesReturned or {}) do
            local reagent = resource.reagent or {}
            local resourceKind = reagent.itemID and "item" or "currency"
            local id = reagent.itemID or reagent.currencyID
            local amount = number(resource.quantity)
            if id and id > 0 and amount > 0 then
                local returned = { kind = resourceKind, id = id }
                addEntry(record.returns, returned, amount)
                for _, totals in ipairs(targets) do addEntry(totals.returns, returned, amount) end
                if resourceKind == "item" then savedItems = savedItems + amount
                else savedCurrency = savedCurrency + amount end
            end
        end
        local deltas = { items = crafted and quantity or 0, baseItems = crafted and quantity - extra or 0,
            extraItems = crafted and extra or 0, savedItems = savedItems, savedCurrency = savedCurrency,
            concentration = number(data.concentrationSpent), refund = number(data.ingenuityRefund) }
        for field, amount in pairs(deltas) do
            record[field] = (record[field] or 0) + amount
            for _, totals in ipairs(targets) do totals[field] = totals[field] + amount end
        end
        local procs = { multicraft = extra > 0, resourcefulness = savedItems + savedCurrency > 0,
            ingenuity = data.hasIngenuityProc == true }
        for stat, hit in pairs(procs) do
            if hit and not record.procs[stat] then
                record.procs[stat] = true
                for _, totals in ipairs(targets) do
                    totals.stats[stat].totalHits = totals.stats[stat].totalHits + 1
                    if record[stat .. "Sampled"] then totals.stats[stat].hits = totals.stats[stat].hits + 1 end
                end
            end
        end
    end
    session.lastAt = record.at
    return true
end

function M.AddDisenchant(session, results, now, id)
    local context = { recipeID = 13262, name = DISENCHANT or "Disenchant", profession = ENCHANTING or "Enchanting",
        scope = "disenchant", isDisenchant = true, chances = {}, icon = 136244 }
    local key = M.RecipeKey(context)
    if not session.recipes[key] then session.recipes[key] = { context = M.Copy(context), totals = M.NewTotals() } end
    local record = { id = id, at = now, context = M.Copy(context), outputs = {}, reagents = {}, returns = {},
        items = 0, extraItems = 0, savedItems = 0, savedCurrency = 0, concentration = 0, refund = 0, procs = {} }
    local targets = { session.totals, session.recipes[key].totals }
    for _, totals in ipairs(targets) do totals.disenchants = totals.disenchants + 1 end
    for _, result in ipairs(results) do
        local quantity = number(result.quantity)
        if result.id and result.id > 0 and quantity > 0 then
            local entry = { kind = result.kind or "item", id = result.id, link = result.link,
                role = "Disenchanted", scope = "disenchant", icon = result.icon }
            addEntry(record.outputs, entry, quantity)
            for _, totals in ipairs(targets) do
                addEntry(totals.outputs, entry, quantity)
                addEntry(totals.disenchantOutputs, entry, quantity)
                totals.disenchantMaterials = totals.disenchantMaterials + quantity
            end
            record.items = record.items + quantity
        end
    end
    table.insert(session.log, record)
    if #session.log > M.LOG_LIMIT then table.remove(session.log, 1); session.trimmed = session.trimmed + 1 end
    session.lastAt = now
    return record
end

-- Descriptive interval for the observed rate, not a test of Blizzard's RNG.
function M.Rate(stat)
    local n, k = stat.trials, stat.hits
    if n == 0 then return nil end
    local p, z = k / n, 1.96
    local divisor = 1 + z * z / n
    local center = (p + z * z / (2 * n)) / divisor
    local half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / divisor
    return p * 100, stat.expected / n * 100,
        math.max(0, center - half) * 100, math.min(1, center + half) * 100
end

function M.Prune(db)
    local finished = 0
    for i = #db.sessions, 1, -1 do
        if db.sessions[i].status == "finished" then
            finished = finished + 1
            if finished > M.HISTORY_LIMIT then table.remove(db.sessions, i) end
        end
    end
end
