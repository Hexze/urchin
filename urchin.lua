plugin = {
    name = "urchin",
    displayName = "Urchin",
    prefix = "§5BL",
    version = "0.4.0",
    description = "Urchin blacklist integration",
    dependencies = {
        { name = "denicker", minVersion = "1.1.0" },
        { name = "anticheat", optional = true }
    }
}

-- Constants

local API_HOST = "https://api.urchin.gg"
local SEPARATOR = "§7§m-------------------------------------§r"
local HYPIXEL_STATS_MAX_CACHE_AGE = "90s"

local TAGS = {
    sniper            = { display = "Sniper",            short = "s",   icon = "S",   color = "c", priority = 1, addable = true },
    blatant_cheater   = { display = "Blatant Cheater",   short = "bc",  icon = "BC",  color = "6", priority = 1, addable = true },
    closet_cheater    = { display = "Closet Cheater",    short = "cc",  icon = "CC",  color = "6", priority = 1, addable = true },
    confirmed_cheater = { display = "Confirmed Cheater", short = "ccc", icon = "CCC", color = "5", priority = 1, addable = false },
    replays_needed    = { display = "Replays Needed",    short = "rn",  icon = "RN",  color = "7", priority = 2, addable = false },
    caution           = { display = "Caution",           short = "c",   icon = "C",   color = "7", priority = 3, addable = true },
}

local TAG_ORDER = { "sniper", "blatant_cheater", "closet_cheater", "confirmed_cheater", "replays_needed", "caution" }
local UNKNOWN_TAG = { display = "Unknown", icon = "?", color = "f", priority = 99 }

local ALIASES = {}
local ADDABLE = {}
for _, name in ipairs(TAG_ORDER) do
    local def = TAGS[name]
    ALIASES[def.short] = name
    if def.addable then
        table.insert(ADDABLE, name)
    end
end

local OP_ERRORS = {
    ["player is locked"] = "This player's tags are locked",
    ["insufficient permissions"] = "You don't have permission to do this",
    ["invalid tag type"] = "Invalid tag type",
    ["player already has this tag type"] = "Player already has this tag type",
    ["tag not found"] = "Tag not found or already removed",
    ["edit window has expired"] = "The 30-minute edit window has passed",
    ["moderator access required"] = "Only moderators can do this"
}

local function tier(value, thresholds)
    for _, entry in ipairs(thresholds) do
        if value >= entry[1] then return entry[2] end
    end
    return "7"
end

local BW_COLORS = {
    wlr        = function(v) return tier(v, {{150, "5"}, {75, "d"}, {45, "4"}, {30, "c"}, {15, "6"}, {10.5, "e"}, {7.5, "2"}, {4.5, "a"}, {1.5, "f"}}) end,
    fkdr       = function(v) return tier(v, {{500, "5"}, {250, "d"}, {150, "4"}, {100, "c"}, {50, "6"}, {35, "e"}, {25, "2"}, {15, "a"}, {5, "f"}}) end,
    kdr        = function(v) return tier(v, {{8, "5"}, {7, "d"}, {6, "4"}, {5, "c"}, {4, "6"}, {3, "e"}, {2, "2"}, {1, "a"}, {0.5, "f"}}) end,
    bblr       = function(v) return tier(v, {{100, "5"}, {50, "d"}, {30, "4"}, {20, "c"}, {10, "6"}, {7, "e"}, {5, "2"}, {3, "a"}, {1, "f"}}) end,
    wins       = function(v) return tier(v, {{30000, "5"}, {15000, "d"}, {7500, "4"}, {4500, "c"}, {2250, "6"}, {1500, "e"}, {450, "2"}, {300, "a"}, {150, "f"}}) end,
    finalKills = function(v) return tier(v, {{100000, "5"}, {50000, "d"}, {25000, "4"}, {15000, "c"}, {7500, "6"}, {5000, "e"}, {2500, "2"}, {1000, "a"}, {500, "f"}}) end,
    kills      = function(v) return tier(v, {{75000, "5"}, {37500, "d"}, {18750, "4"}, {11250, "c"}, {5625, "6"}, {3750, "e"}, {1875, "2"}, {750, "a"}, {375, "f"}}) end,
    bedsBroken = function(v) return tier(v, {{50000, "5"}, {25000, "d"}, {12500, "4"}, {7500, "c"}, {3750, "6"}, {2500, "e"}, {1250, "2"}, {500, "a"}, {250, "f"}}) end,
    winstreak  = function(v) return tier(v, {{500, "5"}, {250, "d"}, {100, "4"}, {75, "c"}, {50, "6"}, {40, "e"}, {25, "2"}, {15, "a"}, {5, "f"}}) end
}

-- Config schema

starfish.schema.section({
    key = "alerts",
    label = "Alerts",
    description = "Configure the plugin's chat alerts.",
    settings = {
        { key = "alerts.enabled", type = "toggle", default = true, description = "Enable or disable all chat alerts." },
        { key = "alerts.audioAlerts.enabled", type = "soundToggle", default = true, description = "Play a sound when a tagged player is found." },
        { key = "alerts.alertDelay", type = "cycle", default = 0, description = "The delay in milliseconds before sending a tag alert.", displayLabel = "Delay", values = {
            { text = "0ms", value = 0 },
            { text = "500ms", value = 500 },
            { text = "1000ms", value = 1000 }
        }},
    }
})

starfish.schema.section({
    key = "modifyDisplayNames",
    label = "Label Tags in Tab",
    description = "Enable or disable tab suffixes for tagged players.",
    settings = {
        { key = "modifyDisplayNames.enabled", type = "toggle", default = true, description = "Adds a label to tagged players in tab to indicate their tags." },
    }
})

starfish.schema.section({
    key = "stats",
    label = "Stats",
    description = "Configure the Bedwars stats shown when you /urchin check a player.",
    settings = {
        { key = "stats.period", type = "cycle", default = "monthly", description = "Show the Bedwars session for the calendar month or a rolling 30 days.", displayLabel = "Period", values = {
            { text = "Monthly", value = "monthly" },
            { text = "Last 30 days", value = "30d" }
        }},
    }
})

starfish.schema.section({
    key = "urchinApi",
    label = "Urchin API Key",
    description = "Optional personal API key used to authenticate requests to the Urchin API.",
    settings = {
        { key = "urchinApi.key", type = "text", default = "", description = "Get a key with /dashboard in the Urchin Discord." },
    }
})

-- State

local taggedDisplayNames = {}
local playerTags = {}
local pending = {}

-- Config and formatting helpers

local function normalizeUuid(uuid)
    return uuid:gsub("-", ""):lower()
end

local function dashUuid(uuid)
    if #uuid ~= 32 then return uuid end
    return uuid:sub(1, 8) .. "-" .. uuid:sub(9, 12) .. "-" .. uuid:sub(13, 16) .. "-" .. uuid:sub(17, 20) .. "-" .. uuid:sub(21, 32)
end

local function tagDef(tagType)
    return TAGS[tagType] or UNKNOWN_TAG
end

local function resolveType(input)
    local key = input:lower()
    return ALIASES[key] or key
end

local function sendError(message)
    starfish.chat.error(message)
end

local function sendInfo(message)
    starfish.chat.warning(message)
end

local function sendComponents(parts)
    starfish.chat.info(starfish.text.join(parts))
end

local function component(text, hoverText, clickAction, clickValue)
    local c = starfish.text.of(text)
    if hoverText then
        c = c:hover(hoverText)
    end
    if clickAction == "suggest_command" then
        c = c:suggest(clickValue)
    elseif clickAction == "run_command" then
        c = c:run(clickValue)
    end
    return c
end

-- Relative time

local TIME_UNITS = {
    { secs = 31536000, name = "year" },
    { secs = 2592000, name = "month" },
    { secs = 86400, name = "day" },
    { secs = 3600, name = "hour" },
    { secs = 60, name = "minute" }
}

local function relativeTime(seconds, suffix, floor)
    if seconds < 60 then return floor end
    for _, unit in ipairs(TIME_UNITS) do
        local value = math.floor(seconds / unit.secs)
        if value >= 1 then
            local text = value .. " " .. unit.name .. (value == 1 and "" or "s")
            if suffix ~= "" then text = text .. " " .. suffix end
            return text
        end
    end
    return floor
end

local function timeAgo(timestampMs)
    return relativeTime(os.time() - math.floor(timestampMs / 1000), "ago", "just now")
end

local function expiry(timestampMs)
    local seconds = math.floor(timestampMs / 1000) - os.time()
    if seconds <= 0 then return "Expired" end
    return "Expires in " .. relativeTime(seconds, "", "under a minute")
end

-- API layer

local function apiRequest(method, path, body, callback)
    local options = {
        url = API_HOST .. path,
        method = method,
        headers = {}
    }
    local apiKey = starfish.config.get("urchinApi.key", "")
    if apiKey ~= "" then
        options.headers["X-API-Key"] = apiKey
    end
    if body then
        options.body = json.encode(body)
        options.headers["Content-Type"] = "application/json"
    end
    starfish.http.request(options, callback)
end

local function apiFailureMessage(result)
    if result.data and result.data.error then return result.data.error end
    local fallback = { [401] = "Authentication failed.", [403] = "Insufficient permissions.", [429] = "Rate limited." }
    return fallback[result.status] or ("request failed (" .. (result.status or "?") .. ")")
end

local function batchLookup(uuids, callback)
    if #uuids == 0 then
        callback({})
        return
    end
    local normalized = {}
    for i, uuid in ipairs(uuids) do
        normalized[i] = normalizeUuid(uuid)
    end
    apiRequest("POST", "/v3/players", { uuids = normalized }, function(result)
        if result.status == 200 and result.data then
            callback(result.data.players or {})
        else
            starfish.log.debug("Urchin: batch lookup failed: " .. apiFailureMessage(result))
            callback(nil)
        end
    end)
end

local function lookupPlayer(player, callback)
    apiRequest("GET", "/v3/player/tags?player=" .. starfish.http.encodeUri(player), nil, function(result)
        if result.status == 200 then
            callback(result.data)
        elseif result.status == 404 then
            callback(nil)
        else
            callback(nil, apiFailureMessage(result))
        end
    end)
end

local function fetchSession(player, period, callback)
    local path = period == "30d"
        and ("/v3/player/sessions/custom?player=" .. starfish.http.encodeUri(player) .. "&duration=30d")
        or ("/v3/player/sessions/monthly?player=" .. starfish.http.encodeUri(player))
    apiRequest("GET", path, nil, function(result)
        callback(result.status == 200 and result.data or nil)
    end)
end

local function fetchWinstreaks(player, callback)
    apiRequest("GET", "/v3/player/winstreaks?player=" .. starfish.http.encodeUri(player), nil, function(result)
        callback(result.status == 200 and result.data or nil)
    end)
end

local function fetchHypixelPlayer(player, callback)
    local path = "/v3/hypixel/player?player=" .. starfish.http.encodeUri(player) .. "&max_cache_age=" .. HYPIXEL_STATS_MAX_CACHE_AGE
    apiRequest("GET", path, nil, function(result)
        if result.status ~= 200 or not result.data then
            callback(nil, apiFailureMessage(result))
        elseif result.data.player == nil then
            callback(nil, "nicked")
        else
            callback(result.data.player)
        end
    end)
end

local function describeTagError(result)
    local raw = result.data and result.data.error
    if raw then
        if OP_ERRORS[raw] then return OP_ERRORS[raw] end
        if raw:match("^conflicts") then return "Conflicts with an existing tag" end
        if raw:find("tagging is disabled", 1, true) then return "Your tagging ability has been disabled" end
        return raw
    end
    if result.status == 401 then return "Authentication failed. Try relaunching Starfish." end
    if result.status == 403 then return "You do not have permission to do that." end
    if result.status == 429 then return "Rate limited - slow down and try again." end
    return "Request failed (" .. (result.status or "?") .. ")."
end

-- Player identity helpers

local function getRealName(name)
    return starfish.plugins.optional("denicker").getRealName(name)
end

local function resolveTarget(name)
    return getRealName(name) or name
end

local function properName(name)
    local player = starfish.players.byName(name)
    return player and player.name or name
end

local function teamFormatted(name)
    local player = starfish.players.byName(name)
    local team = player and player.team
    local prefix = team and team.prefix or ""
    local suffix = team and team.suffix or ""
    return prefix .. name .. suffix
end

local function headerName(username, displayName)
    if displayName and displayName ~= "" then return displayName end
    return "§7" .. teamFormatted(username)
end

-- Tag rendering

local function tagDetailLines(tag)
    local def = tagDef(tag.tag_type)
    local lines = {
        "§8[§" .. def.color .. def.icon .. "§8] §f" .. def.display,
        "§8> §7" .. (tag.reason or "No reason")
    }
    if tag.added_on then
        local by = tag.added_by_username and (" by §7@" .. tag.added_by_username .. "§8") or ""
        table.insert(lines, "§8- Added" .. by .. " " .. timeAgo(tag.added_on))
    end
    if tag.expires_at then
        table.insert(lines, "§8- " .. expiry(tag.expires_at))
    end
    return lines
end

local function detailComponents(tag)
    local components = {}
    for _, line in ipairs(tagDetailLines(tag)) do
        table.insert(components, component("\n" .. line))
    end
    return components
end

local function buildHover(tags)
    local lines = { "§5Urchin Blacklist Tags", SEPARATOR }
    for i, tag in ipairs(tags) do
        if i > 1 then table.insert(lines, "") end
        for _, line in ipairs(tagDetailLines(tag)) do
            table.insert(lines, line)
        end
    end
    table.insert(lines, SEPARATOR)
    table.insert(lines, "§8Click to paste info in chat")
    return table.concat(lines, "\n")
end

local function tagBadge(tag, index, hover, pasteName)
    local def = tagDef(tag.tag_type)
    local pasteText = "⚠ " .. pasteName .. " [" .. def.display .. "] | \"" .. (tag.reason or "") .. "\" - Added "
        .. (tag.added_on and timeAgo(tag.added_on) or "unknown")
    return component((index == 1 and " " or "") .. "§8[§" .. def.color .. def.icon .. "§8]§r", hover, "suggest_command", pasteText)
end

local function manageButton(username)
    return component(" §8[§a+§8]§r", "§8Manage tags for §f" .. username, "run_command", "/urchin tag " .. username)
end

local function priorityOf(tagType)
    return tagDef(tagType).priority
end

local function highestPriority(tags)
    local best = tags[1]
    for _, tag in ipairs(tags) do
        if priorityOf(tag.tag_type) < priorityOf(best.tag_type) then
            best = tag
        end
    end
    return best
end

-- Tab list suffixes

local function suffixFor(tag)
    local def = tagDef(tag.tag_type)
    return " §8[§" .. def.color .. def.icon .. "§8]§r"
end

local function applyTagSuffix(uuid, tag)
    taggedDisplayNames[uuid] = tag
    if starfish.config.get("modifyDisplayNames.enabled", true) then
        starfish.display.setSuffix(uuid, suffixFor(tag))
    end
end

local function restoreDisplayNames()
    for uuid, tag in pairs(taggedDisplayNames) do
        starfish.display.setSuffix(uuid, suffixFor(tag))
    end
end

local function clearDisplayNames()
    for uuid in pairs(taggedDisplayNames) do
        starfish.display.clearSuffix(uuid)
    end
end

-- Automatic blacklist alerts

local function renderPlayerLine(username, tags, realName)
    local nameDisplay = realName
        and (teamFormatted(username):gsub(username, username .. " §c(" .. realName .. ")§r", 1))
        or teamFormatted(username)
    local target = realName or username
    local hover = buildHover(tags)

    local extra = {
        component(nameDisplay, "§8Click to copy name", "suggest_command", target),
    }

    if #tags > 0 then
        for i, tag in ipairs(tags) do
            table.insert(extra, tagBadge(tag, i, hover, target))
        end
    else
        table.insert(extra, component(" §8(§7clean§8)"))
    end
    table.insert(extra, manageButton(target))

    sendComponents(extra)
end

local function emitAlerts(entries)
    local anyTags = false
    for _, entry in ipairs(entries) do
        if #entry.tags > 0 then
            anyTags = true
            renderPlayerLine(entry.name, entry.tags, entry.realName)
            playerTags[(entry.realName or entry.name):lower()] = entry.tags
            playerTags[entry.name:lower()] = entry.tags

            local player = entry.player or starfish.players.byName(entry.name)
            if player then
                applyTagSuffix(player.uuid, highestPriority(entry.tags))
            end
        end
    end
    if anyTags and starfish.config.get("alerts.audioAlerts.enabled", true) then
        starfish.client.world.playSound("note.pling", { volume = 1.0, pitch = 1.0 })
    end
end

local function gatherAndAlert(usernames)
    local entries = {}
    local batchEntries = {}
    local batchUuids = {}
    local pendingLookups = 0
    local batchDone = false

    local function finishIfReady()
        if not batchDone or pendingLookups > 0 then return end
        local delay = starfish.config.get("alerts.alertDelay", 0)
        if delay > 0 then
            starfish.timers.delay(delay, function() emitAlerts(entries) end)
        else
            emitAlerts(entries)
        end
    end

    for _, name in ipairs(usernames) do
        local entry = { name = name, realName = getRealName(name), player = nil, tags = {} }
        table.insert(entries, entry)

        if not entry.realName then
            entry.player = starfish.players.byName(name)
        end

        if entry.player and entry.player.uuid then
            table.insert(batchUuids, entry.player.uuid)
            batchEntries[normalizeUuid(entry.player.uuid)] = entry
        else
            pendingLookups = pendingLookups + 1
            lookupPlayer(entry.realName or entry.name, function(result)
                entry.tags = (result and result.tags) or {}
                pendingLookups = pendingLookups - 1
                finishIfReady()
            end)
        end
    end

    batchLookup(batchUuids, function(players)
        if players then
            for uuid, entry in pairs(batchEntries) do
                entry.tags = players[uuid] or {}
            end
        end
        batchDone = true
        finishIfReady()
    end)
end

local function onChat(event)
    if not starfish.config.get("alerts.enabled", true) then return end
    if event.kind == "actionBar" then return end

    local text = starfish.text.plain(event.message or "")
    if not text:match("^ONLINE:") then return end

    local usernames = {}
    local seen = {}
    for name in text:gsub("^ONLINE:", ""):gmatch("[^,]+") do
        local trimmed = name:match("^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 and not seen[trimmed:lower()] then
            seen[trimmed:lower()] = true
            table.insert(usernames, trimmed)
        end
    end

    if #usernames > 0 then
        gatherAndAlert(usernames)
    end
end

-- Bedwars stats

local function topMode(bw)
    local modes = {
        { "Solo", "eight_one" }, { "Doubles", "eight_two" },
        { "Threes", "four_three" }, { "Fours", "four_four" }, { "4v4", "two_four" }
    }
    local best, top = nil, 0
    for _, mode in ipairs(modes) do
        local games = (bw[mode[2] .. "_wins_bedwars"] or 0) + (bw[mode[2] .. "_losses_bedwars"] or 0)
        if games > top then
            top = games
            best = mode[1]
        end
    end
    return best
end

local function ratioLine(label, pos, neg, ratioColor, countColor)
    local ratio = neg > 0 and pos / neg or pos
    return string.format("§7%s: §%s%.2f §8(§%s%d §8/ §7%d§8)", label, ratioColor(ratio), ratio, countColor(pos), pos, neg)
end

local function bedwarsSummary(session, period)
    local bw = session and session.delta and session.delta.stats and session.delta.stats.Bedwars
    if not bw then return nil end

    local w, l = bw.wins_bedwars or 0, bw.losses_bedwars or 0
    local fk, fd = bw.final_kills_bedwars or 0, bw.final_deaths_bedwars or 0
    local k, d = bw.kills_bedwars or 0, bw.deaths_bedwars or 0
    local beds, bedsLost = bw.beds_broken_bedwars or 0, bw.beds_lost_bedwars or 0
    if w == 0 and l == 0 and fk == 0 then return nil end

    local level = session.delta.achievements and session.delta.achievements.bedwars_level
    local stars = 0
    if type(level) == "number" then
        stars = level
    elseif type(level) == "table" and level.new and level.old then
        stars = level.new - level.old
    end

    local mode = topMode(bw)
    local header = "§7Bedwars Session §8(" .. (period == "30d" and "30d" or "Monthly") .. ")"
    if mode then header = header .. " §8| §7Most Played: §f" .. mode end
    if stars > 0 then header = header .. " §8| §b+" .. stars .. "✫" end

    return {
        header,
        ratioLine("WLR", w, l, BW_COLORS.wlr, BW_COLORS.wins),
        ratioLine("FKDR", fk, fd, BW_COLORS.fkdr, BW_COLORS.finalKills),
        ratioLine("KDR", k, d, BW_COLORS.kdr, BW_COLORS.kills),
        ratioLine("BBLR", beds, bedsLost, BW_COLORS.bblr, BW_COLORS.bedsBroken)
    }
end

local function winstreakLine(data)
    local core = data and data.modes and data.modes.core
    if not core or #core == 0 then return nil end

    local badges = {}
    local hoverLines = { "§fTop Winstreaks", SEPARATOR }
    for i = 1, math.min(3, #core) do
        local streak = core[i]
        local badge = "§8" .. i .. ". §" .. BW_COLORS.winstreak(streak.value) .. streak.value .. (streak.approximate and "+" or "")
        table.insert(badges, badge)
        table.insert(hoverLines, badge .. " §8— §7" .. (streak.readable or ""))
    end
    table.insert(hoverLines, "§8+ approximate")

    return {
        text = "§7Top Winstreaks: " .. table.concat(badges, " §8| "),
        hover = table.concat(hoverLines, "\n")
    }
end

local function appendStats(extra, stats)
    local bedwars = bedwarsSummary(stats.session, stats.period)
    local streaks = winstreakLine(stats.winstreaks)

    if bedwars then
        for _, line in ipairs(bedwars) do
            table.insert(extra, component("\n" .. line))
        end
    end
    if streaks then
        table.insert(extra, component("\n" .. streaks.text, streaks.hover))
    end
    if not bedwars and not streaks then
        table.insert(extra, component("\n§8No tracked stats yet"))
    end
end

-- Manage panel

local function appendTagDetail(extra, username, tag)
    local lines = tagDetailLines(tag)
    table.insert(extra, component("\n" .. lines[1] .. " "))
    table.insert(extra, component(
        "§8[§cX§8]§r",
        "§cClick to remove this tag",
        "run_command",
        "/urchin untag " .. username .. " " .. tag.tag_type
    ))
    for i = 2, #lines do
        table.insert(extra, component("\n" .. lines[i]))
    end
end

local function appendAddButton(extra, username, tagName)
    local def = TAGS[tagName]
    table.insert(extra, component(
        " §8[§" .. def.color .. def.icon .. "§8]§r",
        "§7Add §" .. def.color .. def.display .. "§7 to §f" .. username .. "\n§8Click, then type a reason and press enter",
        "suggest_command",
        "/urchin tag " .. username .. " " .. def.short .. " "
    ))
end

local function appendAnticheatFlags(extra, username)
    local names = { username }
    local nicked = starfish.plugins.optional("denicker").getNickedPlayers()
    if nicked then
        for _, info in ipairs(nicked) do
            if info.realName and info.realName:lower() == username:lower() then
                table.insert(names, info.nickName)
            end
        end
    end

    local parts = {}
    for _, name in ipairs(names) do
        local flags = starfish.plugins.optional("anticheat").getFlags(name)
        for _, flag in ipairs(flags or {}) do
            table.insert(parts, "§c" .. flag.check .. " §8x" .. flag.count)
        end
    end
    if #parts == 0 then return end

    table.insert(extra, component("\n§7Anticheat: " .. table.concat(parts, "§8, ")))
    table.insert(extra, component("\n" .. SEPARATOR))
end

local function sendPanel(username, uuid, tags, displayName, stats)
    local extra = {
        component(headerName(username, displayName), "§8" .. dashUuid(uuid) .. "\n§8Click to copy name", "suggest_command", username),
        component(" §8(§7" .. #tags .. " tag" .. (#tags == 1 and "" or "s") .. "§8)"),
        component("\n" .. SEPARATOR),
    }

    if #tags == 0 then
        table.insert(extra, component("\n§8None"))
    else
        for i, tag in ipairs(tags) do
            if i > 1 then table.insert(extra, component("\n")) end
            appendTagDetail(extra, username, tag)
        end
    end

    table.insert(extra, component("\n" .. SEPARATOR))
    if stats then
        appendStats(extra, stats)
        table.insert(extra, component("\n" .. SEPARATOR))
    end
    appendAnticheatFlags(extra, username)
    table.insert(extra, component("\n§7Add:"))
    for _, tagName in ipairs(ADDABLE) do
        appendAddButton(extra, username, tagName)
    end

    sendComponents(extra)
end

local function fetchStats(uuid, callback)
    local period = starfish.config.get("stats.period", "monthly")
    local session, winstreaks
    local remaining = 2

    local function finish()
        remaining = remaining - 1
        if remaining == 0 then
            callback({ session = session, winstreaks = winstreaks, period = period })
        end
    end

    fetchSession(uuid, period, function(result) session = result; finish() end)
    fetchWinstreaks(uuid, function(result) winstreaks = result; finish() end)
end

local function openPanel(username, withStats)
    lookupPlayer(username, function(lookup, err)
        if err then
            sendError(err)
            return
        end
        if not lookup then
            sendError("Player not found: " .. username)
            return
        end

        local name = properName(username)
        if withStats then
            fetchStats(lookup.uuid, function(stats)
                sendPanel(name, lookup.uuid, lookup.tags, lookup.displayname, stats)
            end)
        else
            sendPanel(name, lookup.uuid, lookup.tags, lookup.displayname, nil)
        end
    end)
end

local function openRemovePanel(username)
    lookupPlayer(username, function(lookup, err)
        if err then
            sendError(err)
            return
        end
        if not lookup then
            sendError("Player not found: " .. username)
            return
        end
        if #lookup.tags == 0 then
            sendInfo(username .. " has no tags to remove.")
            return
        end

        local clean = properName(username)
        local extra = { component("§7Remove from " .. headerName(clean, lookup.displayname) .. "§7:") }
        for _, tag in ipairs(lookup.tags) do
            appendTagDetail(extra, clean, tag)
        end
        sendComponents(extra)
    end)
end

-- Confirmation prompts

local function sendConfirm(username, header, confirmHover)
    local function confirmButton()
        return component("§8[§a██§8]§r", confirmHover, "run_command", "/urchin confirm " .. username)
    end

    local extra = {}
    for _, part in ipairs(header) do
        table.insert(extra, part)
    end
    table.insert(extra, component("\n§7Proceed?"))
    table.insert(extra, component("\n"))
    table.insert(extra, confirmButton())
    table.insert(extra, component("\n"))
    table.insert(extra, confirmButton())

    sendComponents(extra)
end

local function sendAddPrompt(username, display, tagType, reason)
    local def = TAGS[tagType]
    local header = {
        component("§aAdd Tag"),
        component("\n§7IGN - " .. display),
        component("\n" .. SEPARATOR),
    }
    for _, part in ipairs(detailComponents({ tag_type = tagType, reason = reason })) do
        table.insert(header, part)
    end
    table.insert(header, component("\n" .. SEPARATOR))
    sendConfirm(username, header, "§aAdd the §" .. def.color .. def.display .. "§a tag")
end

local function sendOverwritePrompt(username, display, conflict, newType, reason)
    local newDef = TAGS[newType]
    local header = {
        component("§6Tag Overwrite"),
        component("\n§7This player already has an incompatible tag. Overwriting replaces it with your tag."),
        component("\n" .. SEPARATOR),
        component("\n§8Current"),
        component("\n§7IGN - " .. display),
    }
    for _, part in ipairs(detailComponents(conflict)) do
        table.insert(header, part)
    end
    table.insert(header, component("\n" .. SEPARATOR))
    table.insert(header, component("\n§8New"))
    for _, part in ipairs(detailComponents({ tag_type = newType, reason = reason })) do
        table.insert(header, part)
    end
    table.insert(header, component("\n" .. SEPARATOR))
    sendConfirm(username, header, "§aOverwrite with §" .. newDef.color .. newDef.display)
end

local function sendRemovePrompt(username, display, tag)
    local def = tagDef(tag.tag_type)
    local header = {
        component("§cRemove Tag"),
        component("\n§7IGN - " .. display),
        component("\n" .. SEPARATOR),
    }
    for _, part in ipairs(detailComponents(tag)) do
        table.insert(header, part)
    end
    table.insert(header, component("\n" .. SEPARATOR))
    sendConfirm(username, header, "§aRemove the §" .. def.color .. def.display .. "§a tag")
end

local function sendResult(message, tagType)
    local extra = { component(message) }
    if tagType then
        local def = tagDef(tagType)
        table.insert(extra, component(" §8[§" .. def.color .. def.icon .. "§8] §f" .. def.display .. "§a."))
    end
    sendComponents(extra)
end

local function sendAddableHelp()
    local extra = { component("§7Tag types: ") }
    for i, name in ipairs(ADDABLE) do
        local def = TAGS[name]
        table.insert(extra, component(
            (i > 1 and "§7, " or "") .. "§" .. def.color .. def.short .. "§8 (§7" .. def.display .. "§8)",
            "§" .. def.color .. def.display .. "\n§8/urchin tag <player> " .. def.short .. " <reason>"
        ))
    end
    sendComponents(extra)
end

-- Tag actions

local function actionTag(username, typeArg, reason)
    if not typeArg or typeArg == "" then
        openPanel(username, false)
        return
    end

    local tagType = resolveType(typeArg)
    if tagType == "confirmed_cheater" then
        sendError("Confirmed Cheater tags can only be applied through the review system.")
        return
    end
    if tagType == "replays_needed" then
        sendError("Replays Needed tags must be added through the Urchin bot (/watch).")
        return
    end
    local def = TAGS[tagType]
    if not def or not def.addable then
        sendError("Unknown tag type \"" .. typeArg .. "\".")
        sendAddableHelp()
        return
    end

    reason = (reason or ""):match("^%s*(.-)%s*$")
    if reason == "" then
        sendInfo("Add a reason: §f/urchin tag " .. username .. " " .. def.short .. " <reason>")
        return
    end

    lookupPlayer(username, function(lookup, err)
        if err then
            sendError(err)
            return
        end
        if not lookup then
            sendError("Player not found: " .. username)
            return
        end

        local clean = properName(username)
        local display = headerName(clean, lookup.displayname)
        local key = username:lower()

        for _, tag in ipairs(lookup.tags) do
            if priorityOf(tag.tag_type) == def.priority then
                pending[key] = { kind = "overwrite", uuid = lookup.uuid, oldType = tag.tag_type, newType = tagType, reason = reason, display = display }
                sendOverwritePrompt(clean, display, tag, tagType, reason)
                return
            end
        end

        pending[key] = { kind = "add", uuid = lookup.uuid, type = tagType, reason = reason, display = display }
        sendAddPrompt(clean, display, tagType, reason)
    end)
end

local function actionUntag(username, typeArg)
    if not typeArg or typeArg == "" then
        openRemovePanel(username)
        return
    end

    local tagType = resolveType(typeArg)
    if not TAGS[tagType] then
        sendError("Unknown tag type \"" .. typeArg .. "\".")
        sendAddableHelp()
        return
    end

    lookupPlayer(username, function(lookup, err)
        if err then
            sendError(err)
            return
        end
        if not lookup then
            sendError("Player not found: " .. username)
            return
        end

        local found = nil
        for _, tag in ipairs(lookup.tags) do
            if tag.tag_type == tagType then
                found = tag
                break
            end
        end
        if not found then
            sendError(username .. " has no " .. TAGS[tagType].display .. " tag.")
            return
        end

        local clean = properName(username)
        local display = headerName(clean, lookup.displayname)
        pending[username:lower()] = { kind = "remove", uuid = lookup.uuid, type = tagType, display = display }
        sendRemovePrompt(clean, display, found)
    end)
end

local function actionConfirm(username)
    local key = username:lower()
    local action = pending[key]
    if not action then
        sendError("That action expired. Reopen the panel with /urchin tag " .. username .. ".")
        return
    end
    pending[key] = nil

    local who = action.display or ("§f" .. username)

    if action.kind == "add" then
        apiRequest("POST", "/v3/tags?player=" .. starfish.http.encodeUri(action.uuid), { type = action.type, reason = action.reason }, function(result)
            if result.status == 201 then
                sendResult("§aTagged " .. who .. "§a as", action.type)
            else
                sendError(describeTagError(result))
            end
        end)
    elseif action.kind == "overwrite" then
        apiRequest("PATCH", "/v3/tags?player=" .. starfish.http.encodeUri(action.uuid), { type = action.oldType, new_type = action.newType, new_reason = action.reason }, function(result)
            if result.status == 200 then
                sendResult("§aOverwrote " .. who .. "§a's tag with", action.newType)
            else
                sendError(describeTagError(result))
            end
        end)
    else
        apiRequest("DELETE", "/v3/tags?player=" .. starfish.http.encodeUri(action.uuid), { type = action.type }, function(result)
            if result.status == 204 then
                sendResult("§cRemoved §f" .. tagDef(action.type).display .. "§c from " .. who .. "§c.")
            else
                sendError(describeTagError(result))
            end
        end)
    end
end

-- Lifecycle events

local function resetSession()
    clearDisplayNames()
    taggedDisplayNames = {}
    playerTags = {}
    pending = {}
end

starfish.events.on("chat:receive", onChat)
starfish.events.on("world:respawn", resetSession)

starfish.events.on("config:changed", function(event)
    if event.key == "modifyDisplayNames.enabled" then
        if event.value == false then
            clearDisplayNames()
        else
            restoreDisplayNames()
        end
    end
end)

-- Commands

starfish.commands.register("check", {
    description = "Check and manage blacklist tags for one or more players",
    arguments = {
        { name = "usernames", type = "greedy", description = "Space-separated usernames" }
    }
}, function(ctx)
    for username in ctx.args.usernames:gmatch("%S+") do
        openPanel(resolveTarget(username), true)
    end
end)

starfish.commands.register("tag", {
    description = "Tag a player (omit the type to open the panel)",
    arguments = {
        { name = "player", type = "string", description = "Player to tag" },
        { name = "tagtype", type = "string", optional = true, description = "Tag type (e.g. bc, cc, s, c) - omit to choose" },
        { name = "reason", type = "greedy", optional = true, description = "Reason for the tag" }
    }
}, function(ctx)
    actionTag(resolveTarget(ctx.args.player), ctx.args.tagtype, ctx.args.reason)
end)

starfish.commands.register("untag", {
    description = "Remove a tag from a player (omit the type to choose)",
    arguments = {
        { name = "player", type = "string", description = "Player to untag" },
        { name = "tagtype", type = "string", optional = true, description = "Tag type to remove - omit to choose" }
    }
}, function(ctx)
    actionUntag(resolveTarget(ctx.args.player), ctx.args.tagtype)
end)

starfish.commands.register("confirm", {
    description = "Confirm a pending tag action",
    arguments = {
        { name = "player", type = "string", description = "Player whose action to confirm" }
    }
}, function(ctx)
    actionConfirm(ctx.args.player)
end)

-- Exports

starfish.plugin.export("getPlayerTags", function(username)
    if not username then return nil end
    return playerTags[username:lower()]
end)

starfish.plugin.export("getTagIcon", function(tagType)
    return tagDef(tagType).icon
end)

starfish.plugin.export("getTagColor", function(tagType)
    return tagDef(tagType).color
end)

starfish.plugin.export("fetchPlayer", fetchHypixelPlayer)

function plugin.onDisable()
    resetSession()
end
