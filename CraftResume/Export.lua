local _, A = ...
local E = {}
A.Export = E

local function escape(value)
    local text = tostring(value == nil and "" or value)
    -- Spreadsheet formula injection is possible in user-supplied session names.
    if text:match("^[=+@\t\r]") or (text:sub(1, 1) == "-" and not tonumber(text)) then text = "'" .. text end
    return '"' .. text:gsub('"', '""') .. '"'
end

function E.Session(session)
    local lines = {}
    local function row(...)
        local cells = { ... }
        for i = 1, select("#", ...) do cells[i] = escape(cells[i]) end
        lines[#lines + 1] = table.concat(cells, ",")
    end
    row("session_id", "session", "character", "started", "status", "crafts", "disenchants", "items", "disenchant_materials", "multicraft_extra", "reagent_units_saved", "active_seconds")
    row(session.id, session.name, session.character, date("%Y-%m-%d %H:%M:%S", session.startedAt),
        session.status, session.totals.crafts, session.totals.disenchants, session.totals.items,
        session.totals.disenchantMaterials, session.totals.extraItems,
        session.totals.savedItems, A.Model.Duration(session, time()))
    row()
    row("recipe_id", "recipe", "scope", "crafts", "disenchants", "items", "disenchant_materials", "multicraft_extra", "reagent_units_saved", "stat", "sampled_crafts", "observed_procs", "observed_pct", "displayed_pct_avg")
    local keys = {}
    for key in pairs(session.recipes) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local recipe = session.recipes[key]
        local t, c = recipe.totals, recipe.context
        for _, stat in ipairs(A.Model.STATS) do
            local observed, expected = A.Model.Rate(t.stats[stat])
            row(c.recipeID, c.name, c.scope, t.crafts, t.disenchants, t.items, t.disenchantMaterials, t.extraItems, t.savedItems,
                stat, t.stats[stat].trials, t.stats[stat].hits, observed, expected)
        end
    end
    row()
    row("entry", "kind", "id", "quality", "role", "scope", "quantity")
    for _, category in ipairs({ "outputs", "reagents", "returns" }) do
        local entries = {}
        for key in pairs(session.totals[category]) do entries[#entries + 1] = key end
        table.sort(entries)
        for _, key in ipairs(entries) do
            local item = session.totals[category][key]
            row(category, item.kind, item.id, item.quality, item.role, item.scope, item.quantity)
        end
    end
    row()
    row("recent_craft_time", "recipe_id", "recipe", "scope", "items", "multicraft_extra", "reagent_units_saved", "concentration_spent", "ingenuity_refund")
    for _, craft in ipairs(session.log) do
        row(date("%Y-%m-%d %H:%M:%S", craft.at), craft.context.recipeID, craft.context.name, craft.context.scope,
            craft.items, craft.extraItems, craft.savedItems, craft.concentration, craft.refund)
    end
    return table.concat(lines, "\r\n")
end
