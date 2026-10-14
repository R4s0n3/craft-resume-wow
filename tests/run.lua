local A = {}
local function load(name) assert(loadfile("CraftResume/" .. name .. ".lua"))("CraftResume", A) end
load("Model")
local M = A.Model
local passed = 0
local function eq(actual, expected, message)
    assert(actual == expected, (message or "mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.00001, tostring(actual) .. " ~= " .. tostring(expected))
end
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ": " .. err, 0) end
    passed = passed + 1; print("ok " .. passed .. " - " .. name)
end
local function session()
    return M.NewSession(1, "Alchemy", "Crafter-Realm", "player1", 1000)
end
local function context(chances)
    return { recipeID = 123, name = "Flask", profession = "Alchemy", scope = "personal",
        chances = chances or { multicraft = 20, resourcefulness = 30, ingenuity = 15 } }
end
local function result(overrides)
    local r = { itemID = 500, quantity = 2, multicraft = 0, operationID = 1,
        hyperlink = "item:500", craftingQuality = 3, concentrationSpent = 0 }
    for k, v in pairs(overrides or {}) do r[k] = v end
    return r
end
local function add(s, r, ctx)
    local op = M.NewOperation(ctx or context(), 1005, r.operationID)
    M.AddResult(s, op, r, "item")
    return op
end
local function sum(map)
    local n = 0; for _, row in pairs(map) do n = n + row.quantity end; return n
end

test("actual quantity already includes multicraft", function()
    local s = session()
    add(s, result({ quantity = 5, multicraft = 3 }))
    eq(s.totals.items, 5); eq(s.totals.baseItems, 2); eq(s.totals.extraItems, 3)
    eq(s.totals.crafts, 1); eq(s.totals.stats.multicraft.hits, 1)
end)

test("only successful result events create trials", function()
    local s = session()
    M.NewOperation(context(), 1001, 1)
    eq(s.totals.crafts, 0); eq(s.totals.stats.multicraft.trials, 0)
end)

test("reagent returns retain item ranks and currency separately", function()
    local s = session()
    add(s, result({ resourcesReturned = {
        { reagent = { itemID = 10 }, quantity = 3 },
        { reagent = { itemID = 11 }, quantity = 2 },
        { reagent = { currencyID = 8 }, quantity = 4 },
    } }))
    eq(s.totals.savedItems, 5); eq(s.totals.savedCurrency, 4)
    eq(s.totals.stats.resourcefulness.hits, 1); eq(sum(s.totals.returns), 9)
end)

test("completed enchant records selected reagents once", function()
    local s = session()
    local ctx = context(); ctx.reagents = {
        { kind = "item", id = 20, quantity = 3 },
        { kind = "item", id = 21, quantity = 1 },
    }
    add(s, result({ isEnchant = true }), ctx)
    eq(sum(s.totals.reagents), 4); eq(s.totals.items, 0)
    eq(sum(s.log[1].reagents), 4)
end)

test("duplicate result does not inflate any counts", function()
    local s, r = session(), result({ quantity = 7, multicraft = 5 })
    local op = add(s, r)
    eq(M.AddResult(s, op, r, "item"), false)
    eq(s.totals.items, 7); eq(s.totals.crafts, 1); eq(#s.log, 1)
end)

test("first-craft reward arriving before parent preserves one craft", function()
    local s = session()
    local op = M.NewOperation(context(), 1005, 1)
    M.AddResult(s, op, { currencyID = 42, quantity = 100, firstCraftReward = true }, "currency")
    M.AddResult(s, op, result({ itemID = 600, firstCraftReward = true, quantity = 5 }), "item")
    eq(s.totals.crafts, 0); eq(s.totals.items, 0)
    M.AddResult(s, op, result(), "item")
    eq(s.totals.crafts, 1); eq(s.totals.items, 2); eq(sum(s.totals.outputs), 107)
end)

test("multiple output qualities share one operation and one proc", function()
    local s = session(); local op = add(s, result({ multicraft = 1 }))
    M.AddResult(s, op, result({ itemID = 501, craftingQuality = 2, multicraft = 1 }), "item")
    eq(s.totals.crafts, 1); eq(s.totals.items, 4); eq(s.totals.extraItems, 2)
    eq(s.totals.stats.multicraft.hits, 1)
end)

test("bonus craft rewards do not become extra trials or normal output", function()
    local s = session(); local op = add(s, result())
    M.AddResult(s, op, result({ itemID = 600, quantity = 1, bonusCraft = true }), "item")
    eq(s.totals.crafts, 1); eq(s.totals.items, 2); eq(sum(s.totals.outputs), 3)
end)

test("weighted displayed rate follows changing stats", function()
    local s = session()
    add(s, result(), context({ multicraft = 10 }))
    add(s, result({ operationID = 2, quantity = 3, multicraft = 1 }), context({ multicraft = 30 }))
    add(s, result({ operationID = 3 }), context({ multicraft = 50 }))
    local observed, expected = M.Rate(s.totals.stats.multicraft)
    near(observed, 100 / 3); near(expected, 30)
end)

test("missing snapshots and unsupported stats are not zero-chance trials", function()
    local s = session()
    add(s, result({ quantity = 5, multicraft = 3 }), context({}))
    eq(s.totals.stats.multicraft.trials, 0); eq(s.totals.stats.multicraft.totalHits, 1)
    eq(M.Rate(s.totals.stats.multicraft), nil); eq(s.totals.items, 5)
end)

test("known zero percent is a valid sample", function()
    local s = session(); add(s, result(), context({ multicraft = 0 }))
    local observed, expected, low, high = M.Rate(s.totals.stats.multicraft)
    eq(observed, 0); eq(expected, 0); near(low, 0); assert(high > 0 and high <= 100)
end)

test("ingenuity only samples concentration-using crafts", function()
    local s = session(); add(s, result())
    add(s, result({ operationID = 2, concentrationSpent = 100, hasIngenuityProc = true, ingenuityRefund = 50 }))
    eq(s.totals.stats.ingenuity.trials, 1); eq(s.totals.stats.ingenuity.hits, 1)
    eq(s.totals.concentration, 100); eq(s.totals.refund, 50)
end)

test("enchanting and recrafting do not claim newly created items", function()
    local s = session(); add(s, result({ isEnchant = true }))
    local ctx = context(); ctx.scope = "recraft"; ctx.isRecraft = true
    add(s, result(), ctx); ctx.scope = "order"; add(s, result(), ctx)
    eq(s.totals.crafts, 3); eq(s.totals.items, 0); eq(sum(s.totals.outputs), 6)
end)

test("quality and order scope are kept in separate output rows", function()
    local s = session(); add(s, result())
    add(s, result({ craftingQuality = 2 }))
    local ctx = context(); ctx.scope = "order"; add(s, result(), ctx)
    local n = 0; for _ in pairs(s.totals.outputs) do n = n + 1 end
    eq(n, 3)
end)

test("pause and resume exclude idle time", function()
    local s = session(); M.SetStatus(s, "paused", 1060)
    eq(M.Duration(s, 5000), 60)
    M.SetStatus(s, "recording", 5000); M.SetStatus(s, "finished", 5060)
    eq(s.elapsed, 120); eq(s.endedAt, 5060)
end)

test("bounded craft log preserves lifetime totals", function()
    local s = session()
    for i = 1, M.LOG_LIMIT + 25 do add(s, result({ operationID = i })) end
    eq(#s.log, M.LOG_LIMIT); eq(s.trimmed, 25); eq(s.totals.crafts, M.LOG_LIMIT + 25)
end)

test("disenchant outcomes are separate from crafting and retain materials", function()
    local s = session()
    M.AddDisenchant(s, {
        { kind = "item", id = 700, link = "item:700", quantity = 3, icon = 10 },
        { kind = "item", id = 701, link = "item:701", quantity = 1, icon = 11 },
    }, 1010, "de-1")
    eq(s.totals.disenchants, 1); eq(s.totals.disenchantMaterials, 4)
    eq(s.totals.crafts, 0); eq(s.totals.items, 0); eq(sum(s.totals.disenchantOutputs), 4)
    eq(#s.log, 1); eq(s.log[1].context.scope, "disenchant")
end)

test("old saved sessions gain new fields without losing totals", function()
    local s = session(); s.totals.disenchants = nil; s.totals.disenchantOutputs = nil; s.totals.reagents = nil
    M.EnsureSession(s)
    eq(s.totals.disenchants, 0); eq(type(s.totals.disenchantOutputs), "table"); eq(type(s.totals.reagents), "table")
end)

test("history retention preserves active sessions on other characters", function()
    local db = { sessions = { session() } }
    for i = 1, M.HISTORY_LIMIT + 10 do
        local s = session(); s.id = i + 1; s.status = "finished"; table.insert(db.sessions, s)
    end
    M.Prune(db); eq(#db.sessions, M.HISTORY_LIMIT + 1); eq(db.sessions[1].status, "recording")
    eq(db.sessions[2].id, 12)
end)

-- Adapter and lifecycle tests use event-shaped Retail payloads, not chat text.
local clock = 10
time = function() return 1000 + clock end
GetTime = function() return clock end
date = os.date
UnitGUID = function() return "player1" end
UnitName = function() return "Crafter" end
GetRealmName = function() return "Realm" end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
ITEM_MOD_MULTICRAFT_SHORT = "Multifabrication"
ITEM_MOD_RESOURCEFULNESS_SHORT = "Ingeniosite"
ITEM_MOD_INGENUITY_SHORT = "IngenuitY"
local frames, hooks = {}, {}
CreateFrame = function()
    local f = { RegisterEvent = function() end, RegisterUnitEvent = function() end,
        SetScript = function(self, _, fn) self.handler = fn end }
    frames[#frames + 1] = f; return f
end
hooksecurefunc = function(_, key, fn) hooks[key] = fn end
local chance = 20
C_TradeSkillUI = {
    GetRecipeInfo = function(id) return { name = "Recipe " .. id } end,
    GetProfessionInfoByRecipeID = function() return { professionName = "Alchemy" } end,
    GetCraftingOperationInfo = function(id, reagents, _, conc)
        assert(type(reagents) == "table"); assert(type(conc) == "boolean")
        return { recipeID = id, bonusStats = {
            { bonusStatName = ITEM_MOD_MULTICRAFT_SHORT, ratingPct = chance, bonusRatingPct = 8, bonusStatValue = 300 },
            { bonusStatName = ITEM_MOD_RESOURCEFULNESS_SHORT, ratingPct = 30, bonusRatingPct = 3 },
        } }
    end,
}
C_TradeSkillUI.GetCraftingOperationInfoForOrder = C_TradeSkillUI.GetCraftingOperationInfo
C_Spell = { GetSpellInfo = function(id) return { name = id == 13262 and "Disenchant" or "Other" } end }
C_Item = C_Item or {}
C_Item.GetItemInfoInstant = function(link) return tonumber(link:match("item:(%d+)")) end
DISENCHANT, ENCHANTING = "Disenchant", "Enchanting"
load("Core"); load("Tracker"); load("Export")
A.UI = { Initialize = function() end, Toggle = function() end }
A:Initialize()
local T = A.Tracker
local function reset()
    A.db.sessions, A.db.active = {}, {}; A:Start("Test"); chance = 20
    return A:Active()
end

test("localized stat names and ratingPct avoid double-counting bonus", function()
    reset(); T:Capture(123, {}, nil, false)
    T:Result(result(), "item")
    near(A:Active().totals.stats.multicraft.expected, .2)
end)

test("enchant adapter keeps nested item and currency reagent allocations", function()
    local s = reset()
    hooks.CraftEnchant(123, 1, {
        { reagent = { itemID = 810 }, quantity = 4, dataSlotIndex = 1 },
        { reagent = { currencyID = 811 }, quantity = 2, dataSlotIndex = 2 },
    }, nil, false)
    T:Result(result({ isEnchant = true }), "item")
    eq(s.totals.crafts, 1); eq(sum(s.totals.reagents), 6)
    local kinds = {}; for _, entry in pairs(s.totals.reagents) do kinds[entry.kind] = true end
    eq(kinds.item, true); eq(kinds.currency, true)
end)

test("batch crafts refresh rates and deduplicate real operation IDs", function()
    local s = reset()
    T:Begin(123); hooks.CraftRecipe(123, 3, {}, nil, nil, false)
    T:CastStart("player", "cast1", 123); T:Result(result(), "item"); T:Result(result(), "item")
    clock = clock + 3; chance = 40
    T:CastStart("player", "cast2", 123); T:Result(result({ operationID = 2 }), "item")
    eq(s.totals.crafts, 2); near(s.totals.stats.multicraft.expected, .6); eq(#T.pending, 0)
end)

test("unit-start before craft-begin does not leave a phantom context", function()
    local s = reset(); T:Capture(123, {}, nil, false)
    T:CastStart("player", "cast1", 123); T:Begin(123)
    eq(#T.pending, 1); T:Result(result(), "item"); eq(#T.pending, 0); eq(s.totals.crafts, 1)
end)

test("recipe switch before delayed result keeps original attribution", function()
    local s = reset(); T:Capture(123, {}, nil, false)
    clock = clock + 2; T:Capture(456, {}, nil, false)
    T:Result(result(), "item"); T:Result(result({ operationID = 2 }), "item")
    eq(s.log[1].context.recipeID, 123); eq(s.log[2].context.recipeID, 456)
end)

test("next batch cast can start before the previous result arrives", function()
    local s = reset(); T:Capture(123, {}, nil, false)
    T:CastStart("player", "cast1", 123); T:Result(result(), "item")
    clock = clock + 2; T:CastStart("player", "cast2", 123)
    clock = clock + 2; chance = 40; T:CastStart("player", "cast3", 123)
    eq(#T.pending, 2)
    T:Result(result({ operationID = 2 }), "item"); T:Result(result({ operationID = 3 }), "item")
    eq(#T.pending, 0); eq(s.totals.crafts, 3); near(s.totals.stats.multicraft.expected, .8)
end)

test("instant result before the API post-hook leaves no stale context", function()
    local s = reset(); T:Begin(123); T:Result(result(), "item")
    hooks.CraftRecipe(123, 1, {}, nil, nil, false)
    eq(#T.pending, 0); eq(s.totals.crafts, 1)
end)

test("currency-first adapter delivery uses the same operation as its item", function()
    local s = reset(); T:Capture(123, {}, nil, false)
    T.frame.handler(nil, "TRADE_SKILL_CURRENCY_REWARD_RESULT", { currencyID = 8, quantity = 5, operationID = 1, firstCraftReward = true })
    T.frame.handler(nil, "TRADE_SKILL_ITEM_CRAFTED_RESULT", result())
    eq(s.totals.crafts, 1); eq(s.log[1].context.recipeID, 123); eq(#T.pending, 0)
end)

test("failed casts remove their pending context without adding trials", function()
    local s = reset(); T:Capture(123, {}, nil, false); T:CastStart("player", "fail", 123)
    T:CastFailed("player", "fail"); eq(#T.pending, 0)
    T:Capture(456, {}, nil, false); T:Result(result(), "item")
    eq(s.totals.crafts, 1); eq(s.log[1].context.recipeID, 456)
end)

test("zero operation IDs never collapse identical repeated crafts", function()
    local s = reset()
    for _ = 1, 3 do T:Begin(123); T:Result(result({ operationID = 0 }), "item") end
    eq(s.totals.crafts, 3); eq(s.totals.items, 6)
end)

test("secret unit spell identifiers are ignored safely", function()
    reset()
    issecretvalue = function(v) return type(v) == "table" end
    T:CastStart("player", {}, {}); eq(#T.pending, 0)
    issecretvalue = nil
end)

test("pause, stop and next session isolate late or repeated events", function()
    local first = reset(); T:Capture(123, {}, nil, false); T:Result(result(), "item")
    A:Pause(); T:Result(result({ operationID = 2 }), "item"); eq(first.totals.crafts, 1)
    A:Pause(); T:Capture(123, {}, nil, false); T:Result(result({ operationID = 3 }), "item")
    A:Stop(); T:Result(result({ operationID = 4 }), "item"); eq(first.totals.crafts, 2)
    A:Start("Second"); T:Capture(123, {}, nil, false); T:Result(result(), "item")
    eq(A:Active().totals.crafts, 1); eq(first.totals.crafts, 2)
end)

test("reload restores active session paused without losing totals", function()
    local s = reset(); T:Capture(123, {}, nil, false); T:Result(result(), "item")
    clock = clock + 60
    frames[1].handler(nil, "PLAYER_LOGOUT")
    local elapsed = s.elapsed
    A:Initialize(); eq(A:Active(), s); eq(s.status, "paused"); eq(s.totals.crafts, 1)
    clock = clock + 3600; eq(M.Duration(s, time()), elapsed)
end)

test("disenchant loot is captured once and unrelated loot is ignored", function()
    local s = reset()
    local loot = {
        { icon = 10, quantity = 3, link = "item:700" },
        { icon = 11, quantity = 1, link = "item:701" },
    }
    GetNumLootItems = function() return #loot end
    GetLootSlotInfo = function(slot) local x = loot[slot]; return x.icon, "Dust", x.quantity, nil end
    GetLootSlotLink = function(slot) return loot[slot].link end
    T:LootReady(); eq(s.totals.disenchants, 0)
    T:CastStart("player", "de-cast", 13262); T:LootReady(); T:LootReady()
    eq(s.totals.disenchants, 1); eq(s.totals.disenchantMaterials, 4); eq(#s.log, 1)
end)

test("failed disenchant and expired loot correlation add nothing", function()
    local s = reset(); T:CastStart("player", "failed-de", 13262); T:CastFailed("player", "failed-de"); T:LootReady()
    eq(s.totals.disenchants, 0)
    T:CastStart("player", "old-de", 13262); clock = clock + 16; T:LootReady()
    eq(s.totals.disenchants, 0); eq(T.disenchant, nil)
end)

test("CSV quotes names, neutralizes formulas and exports full totals", function()
    local s = session(); s.name = '=SUM(1,2) "quoted"\nline'
    add(s, result())
    local csv = A.Export.Session(s)
    assert(csv:find('"\'=SUM(1,2) ""quoted""\nline"', 1, true))
    assert(csv:find('"sampled_crafts"', 1, true)); assert(csv:find('"outputs","item","500"', 1, true))
end)

print(string.format("\n%d tests passed", passed))
