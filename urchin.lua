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
local XP_PER_PRESTIGE = 487000
local XP_PER_LEVEL = 5000
local HYPIXEL_STATS_CACHE_SECONDS = 90
local HYPIXEL_STATS_MAX_CACHE_AGE = HYPIXEL_STATS_CACHE_SECONDS .. "s"
local HYPIXEL_STATS_CACHE_MS = HYPIXEL_STATS_CACHE_SECONDS * 1000
local NEXT_TICK_MS = 1

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

local OVERVIEW_COLORS = {
    fkdr   = function(v) return tier(v, {{100, "5"}, {50, "d"}, {30, "4"}, {20, "c"}, {10, "6"}, {7, "e"}, {5, "2"}, {3, "a"}, {1, "f"}}) end,
    finals = function(v) return tier(v, {{100000, "5"}, {50000, "d"}, {25000, "4"}, {15000, "c"}, {7500, "6"}, {5000, "e"}, {2500, "2"}, {1000, "a"}, {500, "f"}}) end,
    beds   = function(v) return tier(v, {{50000, "5"}, {25000, "d"}, {12500, "4"}, {7500, "c"}, {3750, "6"}, {2500, "e"}, {1250, "2"}, {500, "a"}, {250, "f"}}) end,
}

local PRESTIGE_SCHEMES = {
    [0] = "7", "f", "6", "b", "2", "3", "4", "d", "9", "5",
    "c6eabd5", "7ffff77", "7eeee67", "7bbbb37", "7aaaa27",
    "7333397", "7cccc47", "7dddd57", "7999917", "7555587",
    "87ff778", "ffee666", "66ffb33", "55dd6ee", "bbff778",
    "ffaa222", "44ccdd5", "eeff888", "aa2266e", "bb33991",
    "ee66cc4", "993366e", "c4774cc", "999dcc4", "2add552",
    "cc442aa", "aaab991", "44ccb33", "11955d1", "ccaa399",
    "55cc66e", "ee6cdd5", "193bf77", "0588550", "22ae65d",
    "ffbb333", "3be66d5", "f4cc919", "55c66b3", "2afffa2",
    "4459910", "4cc6ef4", "193bfe1", "5defed5", "3a282a3",
    "2aefbd5", "4cefec4", "4623958", "5c6fb39", "7087ff7",
    "cffffcf", "6efffb3", "efe66fe", "aeeeea2", "bbcccaa",
    "33aafa3", "9ddddb9", "5ddddf5", "066eeff", "aaaa228",
    "3bbbbf3", "4c6ec6e", "2af2af8", "233bba2", "88888d8",
    "6622fff", "fff77c8", "dcccc6d", "87fffe8", "6f262f6",
    "2aaac42", "87fb391", "fffffaf", "8844cc8", "fdddaaf",
    "36666e3", "dffffed", "8666668", "444ccff", "9bbb339",
    "ddddd58", "0c66cc4", "2dddda2", "f8888ff", "e648888",
    "008877f", "eee00e0", "dddeebe", "0888880", "87fffef",
    "9bfffc4",
}

local STAR_SYMBOLS = { [0] = "✫", "✪", "⚝", "✥", "✭" }

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
        { key = "alerts.compact", type = "toggle", default = false, displayLabel = "Compact", description = "Show alerts as a single line of tag badges instead of the full tag details." },
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
local playerStatsCache = {}
local playerStatsWaiters = {}

-- Config and formatting helpers

local function normalizeUuid(uuid)
    return uuid:gsub("-", ""):lower()
end

local function dashUuid(uuid)
    if #uuid ~= 32 then return uuid end
    return uuid:sub(1, 8) .. "-" .. uuid:sub(9, 12) .. "-" .. uuid:sub(13, 16) .. "-" .. uuid:sub(17, 20) .. "-" .. uuid:sub(21, 32)
end

local function formatNumber(n)
    local grouped = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (grouped:gsub("^,", ""))
end

local function colorizeStars(stars)
    local scheme = PRESTIGE_SCHEMES[math.min(math.floor(stars / 100), 100)]
    local symbol = STAR_SYMBOLS[math.min(math.floor(stars / 1000), 4)]
    local function color(slot)
        local index = math.min(slot, #scheme)
        return "§" .. scheme:sub(index, index)
    end

    local digitsText = tostring(math.floor(stars))
    local parts = { color(1), "[" }
    for i = 1, #digitsText do
        table.insert(parts, color(2 + math.min(i - 1, 3)))
        table.insert(parts, digitsText:sub(i, i))
    end
    table.insert(parts, color(6))
    table.insert(parts, symbol)
    table.insert(parts, color(7))
    table.insert(parts, "]")
    return table.concat(parts)
end

local function levelFromXp(xp)
    local level = 100 * math.floor(xp / XP_PER_PRESTIGE)
    local rem = xp % XP_PER_PRESTIGE
    if rem < 500 then return level end
    if rem < 1500 then return level + 1 end
    if rem < 3500 then return level + 2 end
    if rem < 7000 then return level + 3 end
    return level + 4 + math.floor((rem - 7000) / XP_PER_LEVEL)
end

local function levelProgress(xp)
    local rem = xp % XP_PER_PRESTIGE
    if rem < 500 then return rem / 500 end
    if rem < 1500 then return (rem - 500) / 1000 end
    if rem < 3500 then return (rem - 1500) / 2000 end
    if rem < 7000 then return (rem - 3500) / 3500 end
    return ((rem - 7000) % XP_PER_LEVEL) / XP_PER_LEVEL
end

local function bedwarsLevel(xp, achievementLevel)
    local level = xp and levelFromXp(xp) or achievementLevel or 0
    return {
        level = level,
        progress = xp and levelProgress(xp) or 0,
        starText = colorizeStars(level),
        nextStarText = colorizeStars(level + 1)
    }
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

local function fetchMonthlySession(player, callback)
    apiRequest("GET", "/v3/player/sessions/monthly?player=" .. starfish.http.encodeUri(player), nil, function(result)
        callback(result.status == 200 and result.data or nil)
    end)
end

local function fetchWinstreaks(player, callback)
    apiRequest("GET", "/v3/player/winstreaks?player=" .. starfish.http.encodeUri(player), nil, function(result)
        callback(result.status == 200 and result.data or nil)
    end)
end

local function fetchSessionStats(uuid, callback)
    local session, winstreaks
    local remaining = 2

    local function finish()
        remaining = remaining - 1
        if remaining == 0 then
            callback(session, winstreaks)
        end
    end

    fetchMonthlySession(uuid, function(result) session = result; finish() end)
    fetchWinstreaks(uuid, function(result) winstreaks = result; finish() end)
end

local function freshCachedPlayerStats(key)
    local entry = playerStatsCache[key]
    if entry and starfish.time.since(entry.fetchedAt) < HYPIXEL_STATS_CACHE_MS then
        return entry
    end
end

local function cachePlayerStats(key, data, err)
    for cachedKey, entry in pairs(playerStatsCache) do
        if starfish.time.since(entry.fetchedAt) >= HYPIXEL_STATS_CACHE_MS then
            playerStatsCache[cachedKey] = nil
        end
    end
    playerStatsCache[key] = { data = data, error = err, fetchedAt = starfish.time.monotonic() }
end

local function requestHypixelPlayer(player, callback)
    local key = player:lower()

    local cached = freshCachedPlayerStats(key)
    if cached then
        starfish.timers.delay(NEXT_TICK_MS, function() callback(cached.data, cached.error) end)
        return
    end

    local waiters = playerStatsWaiters[key]
    if waiters then
        table.insert(waiters, callback)
        return
    end
    playerStatsWaiters[key] = { callback }

    local path = "/v3/hypixel/player?player=" .. starfish.http.encodeUri(player) .. "&max_cache_age=" .. HYPIXEL_STATS_MAX_CACHE_AGE
    apiRequest("GET", path, nil, function(result)
        local data, err = nil, nil
        if result.status ~= 200 or not result.data then
            err = apiFailureMessage(result)
        elseif result.data.player == nil then
            err = "nicked"
        else
            data = result.data.player
        end
        if data or err == "nicked" then
            cachePlayerStats(key, data, err)
        end

        local waiting = playerStatsWaiters[key] or {}
        playerStatsWaiters[key] = nil
        for _, waiter in ipairs(waiting) do
            waiter(data, err)
        end
    end)
end

local function fetchHypixelPlayer(player)
    requestHypixelPlayer(player, function(data, err)
        starfish.events.emit("urchin:playerFetched", { player = player, data = data, error = err })
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

local function specComponent(spec)
    return component(spec.text, spec.hover, "suggest_command", spec.paste)
end

local function playerHeaderSpec(username, uuid, displayName, starText)
    local uuidLine = uuid and ("§8" .. dashUuid(uuid) .. "\n") or ""
    return {
        text = (starText and (starText .. " ") or "") .. headerName(username, displayName),
        hover = uuidLine .. "§8Click to copy name",
        paste = username
    }
end

local function tagBadgeSpec(tag, index, hover, pasteName)
    local def = tagDef(tag.tag_type)
    local pasteText = "⚠ " .. pasteName .. " [" .. def.display .. "] | \"" .. (tag.reason or "") .. "\" - Added "
        .. (tag.added_on and timeAgo(tag.added_on) or "unknown")
    return {
        text = (index == 1 and " " or "") .. "§8[§" .. def.color .. def.icon .. "§8]§r",
        hover = hover,
        paste = pasteText
    }
end

local function tagBadge(tag, index, hover, pasteName)
    return specComponent(tagBadgeSpec(tag, index, hover, pasteName))
end

local function tagBadgeSpecs(tags, pasteName)
    local hover = buildHover(tags)
    local specs = {}
    for i, tag in ipairs(tags) do
        specs[i] = tagBadgeSpec(tag, i, hover, pasteName)
    end
    return specs
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

local function appendAlertDetails(extra, tags)
    for i, tag in ipairs(tags) do
        if i > 1 then table.insert(extra, component("\n")) end
        for _, part in ipairs(detailComponents(tag)) do
            table.insert(extra, part)
        end
    end
end

local function renderPlayerLine(username, tags, realName)
    local nameDisplay = realName
        and (teamFormatted(username):gsub(username, username .. " §c(" .. realName .. ")§r", 1))
        or teamFormatted(username)
    local target = realName or username
    local hover = buildHover(tags)

    local extra = { component(nameDisplay, "§8Click to copy name", "suggest_command", target) }
    for i, tag in ipairs(tags) do
        table.insert(extra, tagBadge(tag, i, hover, target))
    end

    if not starfish.config.get("alerts.compact", false) then
        table.insert(extra, component("\n" .. SEPARATOR))
        appendAlertDetails(extra, tags)
        table.insert(extra, component("\n" .. SEPARATOR))
    end

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

-- Bedwars overview

local function bedwarsOverview(player)
    local bw = player.stats and player.stats.Bedwars or {}
    local finals = bw.final_kills_bedwars or 0
    local fkdr = finals / math.max(1, bw.final_deaths_bedwars or 1)
    local beds = bw.beds_broken_bedwars or 0
    local level = bedwarsLevel(bw.Experience, player.achievements and player.achievements.bedwars_level)

    return {
        starText = level.starText,
        line = "§7FKDR: §" .. OVERVIEW_COLORS.fkdr(fkdr) .. string.format("%.1f", fkdr)
            .. " §8| §7Finals: §" .. OVERVIEW_COLORS.finals(finals) .. formatNumber(finals)
            .. " §8| §7Beds: §" .. OVERVIEW_COLORS.beds(beds) .. formatNumber(beds)
    }
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
end

local function appendTagDetails(extra, username, tags)
    if #tags == 0 then
        table.insert(extra, component("\n§8None"))
        return
    end
    for i, tag in ipairs(tags) do
        if i > 1 then table.insert(extra, component("\n")) end
        appendTagDetail(extra, username, tag)
    end
end

local function appendAddButtons(extra, username)
    table.insert(extra, component("\n\n§7Add Tag:"))
    for _, tagName in ipairs(ADDABLE) do
        appendAddButton(extra, username, tagName)
    end
end

local function sendPanel(username, uuid, tags, displayName, overview)
    local header = playerHeaderSpec(username, uuid, displayName, overview and overview.starText)
    local extra = { component("\n" .. SEPARATOR .. "\n"), specComponent(header) }
    local hover = buildHover(tags)
    for i, tag in ipairs(tags) do
        table.insert(extra, tagBadge(tag, i, hover, username))
    end
    if overview then
        table.insert(extra, component("\n" .. overview.line))
    end
    table.insert(extra, component("\n" .. SEPARATOR))

    appendTagDetails(extra, username, tags)
    appendAnticheatFlags(extra, username)
    appendAddButtons(extra, username)
    table.insert(extra, component("\n" .. SEPARATOR))

    sendComponents(extra)
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
            requestHypixelPlayer(username, function(data)
                local overview = data and bedwarsOverview(data) or { line = "§8Stats unavailable" }
                sendPanel(name, lookup.uuid, lookup.tags, lookup.displayname, overview)
            end)
        else
            sendPanel(name, lookup.uuid, lookup.tags, lookup.displayname, nil)
        end
    end)
end

local function fetchCheck(player)
    lookupPlayer(player, function(lookup, err)
        local header = playerHeaderSpec(properName(player), lookup and lookup.uuid, lookup and lookup.displayname)
        if err or not lookup then
            starfish.events.emit("urchin:checkFetched", { player = player, header = header, error = err or "Player not found" })
            return
        end
        fetchSessionStats(lookup.uuid, function(session, winstreaks)
            starfish.events.emit("urchin:checkFetched", {
                player = player,
                header = header,
                badges = tagBadgeSpecs(lookup.tags, player),
                session = session,
                winstreaks = winstreaks
            })
        end)
    end)
end

local function fetchSummary(player)
    local lookup, hypixelPlayer
    local remaining = 2

    local function finish()
        remaining = remaining - 1
        if remaining > 0 then return end

        local overview = hypixelPlayer and bedwarsOverview(hypixelPlayer)
        starfish.events.emit("urchin:summaryFetched", {
            player = player,
            header = playerHeaderSpec(properName(player), lookup and lookup.uuid, lookup and lookup.displayname, overview and overview.starText),
            badges = lookup and tagBadgeSpecs(lookup.tags, player) or {},
            line = overview and overview.line or "§8Stats unavailable"
        })
    end

    lookupPlayer(player, function(result) lookup = result; finish() end)
    requestHypixelPlayer(player, function(result) hypixelPlayer = result; finish() end)
end

-- Confirmation prompts

local function sendConfirm(username, header, question, hover, yesColor)
    local extra = {}
    for _, part in ipairs(header) do
        table.insert(extra, part)
    end
    table.insert(extra, component("\n§7" .. question))
    table.insert(extra, component("\n"))
    table.insert(extra, component("§8[" .. yesColor .. "Yes§8]§r", hover, "run_command", "/urchin confirm " .. username))

    sendComponents(extra)
end

local function promptHeader(title, display, body, label)
    local header = { component(title), component("\n" .. SEPARATOR) }
    if label then
        table.insert(header, component("\n§8" .. label))
    end
    table.insert(header, component("\n§7IGN - " .. display))
    for _, part in ipairs(body) do
        table.insert(header, part)
    end
    table.insert(header, component("\n" .. SEPARATOR))
    return header
end

local function sendAddPrompt(username, display, tagType, reason)
    local def = TAGS[tagType]
    local header = promptHeader("§aAdd Tag", display, detailComponents({ tag_type = tagType, reason = reason }))
    sendConfirm(username, header, "Proceed?", "§aAdd the §" .. def.color .. def.display .. "§a tag", "§a")
end

local function sendOverwritePrompt(username, display, conflict, newType, reason)
    local header = promptHeader("§6Overwrite Tag", display, detailComponents(conflict), "Current")
    local newTagLines = tagDetailLines({ tag_type = newType, reason = reason })
    sendConfirm(
        username,
        header,
        "This player already has an incompatible tag. Proceed and overwrite with yours?",
        "§7Overwrite with:\n" .. table.concat(newTagLines, "\n"),
        "§c"
    )
end

local function sendRemovePrompt(username, display, tag)
    local def = tagDef(tag.tag_type)
    local header = promptHeader("§cRemove Tag", display, detailComponents(tag))
    sendConfirm(username, header, "Remove?", "§cRemove the §" .. def.color .. def.display .. "§c tag", "§c")
end


local function sendResult(message, tagType, undoUsername)
    local extra = { component(message) }
    if tagType then
        local def = tagDef(tagType)
        table.insert(extra, component(" §8[§" .. def.color .. def.icon .. "§8] §f" .. def.display .. "§a."))
    end
    if undoUsername then
        table.insert(extra, component(" §8[§cUndo§8]§r", "§7Remove this tag", "run_command", "/urchin confirm " .. undoUsername))
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

local function applyTag(username, uuid, tagType, reason, display)
    apiRequest("POST", "/v3/tags?player=" .. starfish.http.encodeUri(uuid), { type = tagType, reason = reason }, function(result)
        if result.status ~= 201 then
            sendError(describeTagError(result))
            return
        end
        pending[username:lower()] = { kind = "remove", uuid = uuid, type = tagType, display = display }
        sendResult("§aTagged " .. display .. "§a as", tagType, username)
    end)
end

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
        applyTag(username, action.uuid, action.type, action.reason, who)
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
    playerStatsWaiters = {}
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
    description = "Remove a tag from a player",
    arguments = {
        { name = "player", type = "string", description = "Player to untag" },
        { name = "tagtype", type = "string", description = "Tag type to remove (e.g. bc, cc, s, c)" }
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
starfish.plugin.export("fetchCheck", fetchCheck)
starfish.plugin.export("fetchSummary", fetchSummary)
starfish.plugin.export("bedwarsLevel", bedwarsLevel)

function plugin.onDisable()
    resetSession()
end
