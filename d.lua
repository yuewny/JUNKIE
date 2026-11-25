if type(getgenv) ~= "function" then
    getgenv = function()
        return _G
    end
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local CONFIG = {
    Folder = "DUMP MX",
    AutoStartSpy = true,
    DecompileTimeout = 10,
    DecompileRetryTimeout = 30,
    RequireTimeout = 5,
    InvokeTimeout = 5,
    TreeRepeatCollapse = 12,
    TreeMaxInstances = 250000,
    SerializeDepth = 6,
    SerializeMaxEntries = 80,
    ValueDepth = 10,
    ValueMaxEntries = 800,
    YieldEvery = 300,
    IncludeBindables = true,
    ListLimit = 4000,
    CallSiteLimitPerScript = 60,
    GCMinMatch = 3,
    GCMaxTables = 40,
    SpyMaxLogsPerRemote = 7,
    SpyInspectLimit = 1500,
    SpyIgnoreDuplicateArgs = true,
    SpyLogOwnCalls = false,
    SpyIgnore = {},
    SkipServices = {
        CoreGui = true,
        CorePackages = true,
        RobloxPluginGuiService = true,
        NetworkClient = true,
        Stats = true,
    },
    GetterAllow = { "^get", "state", "data", "info", "stats", "profile", "inventory", "fetch" },
    GetterDeny = {
        "buy", "purchase", "claim", "collect", "sell", "equip", "rebirth", "open", "spin",
        "reward", "teleport", "trade", "delete", "remove", "gift", "redeem", "craft",
    },
    GCKeywords = {
        "coins", "cash", "gold", "gems", "money", "wins", "rebirths", "level", "exp", "xp",
        "inventory", "pets", "eggs", "items", "stats", "data", "settings", "equipped",
        "owned", "ownedpets", "ownedauras", "ownedpasses", "trophies", "kills", "deaths",
        "multiplier", "luck", "chakra", "eyes", "zone", "quests", "codes",
    },
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local CorePackages = game:GetService("CorePackages")
local env = getgenv()

repeat
    task.wait()
until Players.LocalPlayer
local LocalPlayer = Players.LocalPlayer

if type(env.MeowXDump) == "table" and type(env.MeowXDump.Destroy) == "function" then
    pcall(env.MeowXDump.Destroy)
end

local HAS_WRITE = type(writefile) == "function"
local HAS_APPEND = type(appendfile) == "function"
local newClosure = type(newcclosure) == "function" and newcclosure or function(f)
    return f
end

local NETWORK_CLASS = { RemoteEvent = true, RemoteFunction = true, UnreliableRemoteEvent = true }
local REMOTE_CLASS = {
    RemoteEvent = true,
    RemoteFunction = true,
    UnreliableRemoteEvent = true,
    BindableEvent = true,
    BindableFunction = true,
}
local SPY_METHODS = { FireServer = true, InvokeServer = true, fireServer = true, invokeServer = true }
local KEYWORDS = {}
for _, word in ipairs({
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
    "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while", "continue",
}) do
    KEYWORDS[word] = true
end

local state = {
    alive = true,
    busy = false,
    cancel = false,
    spyOn = false,
    current = nil,
    writeFailures = 0,
}
local connections = {}
local ui = {}
local report, errors = {}, {}
local lastPayload = setmetatable({}, { __mode = "k" })

local function setStatus(text, fraction)
    print("[MeowX Dump] " .. tostring(text))
    if ui.status and ui.status.Parent then
        ui.status.Text = tostring(text)
    end
    if fraction and ui.bar and ui.bar.Parent then
        ui.bar.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
    end
end

local function globalFn(name)
    local value = env[name]
    if value == nil then
        local ok, scope = pcall(getfenv)
        if ok and type(scope) == "table" then
            value = scope[name]
        end
    end
    return value
end

local function safeName(text, limit)
    local cleaned = tostring(text):gsub("[^%w_%-%.]", "_")
    return cleaned:sub(1, limit or 80)
end

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function prop(inst, name)
    local ok, value = pcall(function()
        return inst[name]
    end)
    if ok then
        return value
    end
    return nil
end

local gameName = "Game"
do
    local ok, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    if ok and type(info) == "table" and info.Name then
        gameName = info.Name
    end
end

local ROOT = CONFIG.Folder .. "/" .. safeName(gameName, 40) .. "_" .. tostring(game.PlaceId)

local function ensureFolder(path)
    if type(makefolder) ~= "function" then
        return
    end
    if type(isfolder) == "function" and isfolder(path) then
        return
    end
    pcall(makefolder, path)
end

ensureFolder(CONFIG.Folder)
ensureFolder(ROOT)
ensureFolder(ROOT .. "/ServiceTrees")
ensureFolder(ROOT .. "/Scripts")
ensureFolder(ROOT .. "/RemoteSpy")

local function newWriter(relativePath)
    local path = ROOT .. "/" .. relativePath
    local buffer, started = {}, false
    local writer = { path = path, lines = 0 }

    function writer:flush()
        if #buffer == 0 then
            return
        end
        local chunk = table.concat(buffer, "\n") .. "\n"
        buffer = {}
        if not HAS_WRITE then
            return
        end
        local ok
        if not started then
            ok = pcall(writefile, path, chunk)
            started = true
        elseif HAS_APPEND then
            ok = pcall(appendfile, path, chunk)
        else
            local okRead, old = pcall(readfile, path)
            ok = pcall(writefile, path, (okRead and old or "") .. chunk)
        end
        if not ok then
            state.writeFailures = state.writeFailures + 1
        end
    end

    function writer:line(text)
        buffer[#buffer + 1] = text
        self.lines = self.lines + 1
        if #buffer >= 1000 then
            self:flush()
        end
    end

    function writer:close()
        self:flush()
        if not started and HAS_WRITE then
            pcall(writefile, path, "")
            started = true
        end
        return path
    end

    return writer
end

local ESCAPES = { ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ['"'] = '\\"', ["\\"] = "\\\\" }

local function quote(value, limit)
    local text = tostring(value)
    local extra = ""
    limit = limit or 400
    if #text > limit then
        extra = string.format("...(+%d)", #text - limit)
        text = text:sub(1, limit)
    end
    text = text:gsub('[%c"\\]', function(char)
        return ESCAPES[char] or string.format("\\%03d", char:byte())
    end)
    return '"' .. text .. '"' .. extra
end

local function formatNumber(n)
    if n ~= n then
        return "0/0"
    elseif n == math.huge then
        return "math.huge"
    elseif n == -math.huge then
        return "-math.huge"
    end
    if n == math.floor(n) and math.abs(n) < 1e15 then
        return string.format("%d", n)
    end
    return string.format("%.14g", n)
end

local function fullName(inst)
    local ok, name = pcall(inst.GetFullName, inst)
    return ok and name or tostring(inst)
end

local function getClass(obj)
    return obj.ClassName
end

local function luaPath(inst)
    if inst == game then
        return "game"
    end
    local chain, current = {}, inst
    while current and current ~= game do
        table.insert(chain, 1, current)
        current = current.Parent
    end
    if current ~= game or #chain == 0 then
        return "nil --[[" .. tostring(inst.Name) .. "]]"
    end
    local first = chain[1]
    local expression, startIndex
    if first == workspace then
        expression, startIndex = "workspace", 2
    elseif first == Players and chain[2] == LocalPlayer then
        expression, startIndex = 'game:GetService("Players").LocalPlayer', 3
    else
        expression, startIndex = 'game:GetService("' .. first.ClassName .. '")', 2
    end
    for i = startIndex, #chain do
        local name = chain[i].Name
        if name:match("^[%a_][%w_]*$") and not KEYWORDS[name] then
            expression = expression .. "." .. name
        else
            expression = expression .. "[" .. quote(name, 200) .. "]"
        end
    end
    return expression
end

local function describeFunction(f)
    local okName, name = pcall(debug.info, f, "n")
    local okSource, source, line = pcall(debug.info, f, "sl")
    local label = (okName and type(name) == "string" and name ~= "") and name or "anonymous"
    if okSource and source then
        return string.format("function<%s> @%s:%s", label, tostring(source), tostring(line))
    end
    return "function<" .. label .. ">"
end

local SCALARS = {}
SCALARS["string"] = function(v, lua)
    return quote(v, lua and 4000 or 400)
end
SCALARS["number"] = function(v)
    return formatNumber(v)
end
SCALARS["boolean"] = function(v)
    return tostring(v)
end
SCALARS["nil"] = function()
    return "nil"
end
SCALARS["Vector3"] = function(v)
    return string.format("Vector3.new(%s, %s, %s)", formatNumber(v.X), formatNumber(v.Y), formatNumber(v.Z))
end
SCALARS["Vector2"] = function(v)
    return string.format("Vector2.new(%s, %s)", formatNumber(v.X), formatNumber(v.Y))
end
SCALARS["Vector3int16"] = function(v)
    return string.format("Vector3int16.new(%d, %d, %d)", v.X, v.Y, v.Z)
end
SCALARS["Vector2int16"] = function(v)
    return string.format("Vector2int16.new(%d, %d)", v.X, v.Y)
end
SCALARS["CFrame"] = function(v)
    local components = { v:GetComponents() }
    for i = 1, #components do
        components[i] = formatNumber(components[i])
    end
    return "CFrame.new(" .. table.concat(components, ", ") .. ")"
end
SCALARS["Color3"] = function(v)
    return string.format("Color3.new(%s, %s, %s)", formatNumber(v.R), formatNumber(v.G), formatNumber(v.B))
end
SCALARS["UDim2"] = function(v)
    return string.format(
        "UDim2.new(%s, %s, %s, %s)",
        formatNumber(v.X.Scale), formatNumber(v.X.Offset), formatNumber(v.Y.Scale), formatNumber(v.Y.Offset)
    )
end
SCALARS["UDim"] = function(v)
    return string.format("UDim.new(%s, %s)", formatNumber(v.Scale), formatNumber(v.Offset))
end
SCALARS["BrickColor"] = function(v)
    return "BrickColor.new(" .. quote(v.Name) .. ")"
end
SCALARS["Rect"] = function(v)
    return string.format(
        "Rect.new(%s, %s, %s, %s)",
        formatNumber(v.Min.X), formatNumber(v.Min.Y), formatNumber(v.Max.X), formatNumber(v.Max.Y)
    )
end
SCALARS["Ray"] = function(v)
    return string.format(
        "Ray.new(Vector3.new(%s, %s, %s), Vector3.new(%s, %s, %s))",
        formatNumber(v.Origin.X), formatNumber(v.Origin.Y), formatNumber(v.Origin.Z),
        formatNumber(v.Direction.X), formatNumber(v.Direction.Y), formatNumber(v.Direction.Z)
    )
end
SCALARS["NumberRange"] = function(v)
    return string.format("NumberRange.new(%s, %s)", formatNumber(v.Min), formatNumber(v.Max))
end
SCALARS["NumberSequence"] = function(v)
    local points = {}
    for i, k in ipairs(v.Keypoints) do
        points[i] = string.format(
            "NumberSequenceKeypoint.new(%s, %s, %s)", formatNumber(k.Time), formatNumber(k.Value), formatNumber(k.Envelope)
        )
    end
    return "NumberSequence.new({" .. table.concat(points, ", ") .. "})"
end
SCALARS["ColorSequence"] = function(v)
    local points = {}
    for i, k in ipairs(v.Keypoints) do
        points[i] = string.format(
            "ColorSequenceKeypoint.new(%s, Color3.new(%s, %s, %s))",
            formatNumber(k.Time), formatNumber(k.Value.R), formatNumber(k.Value.G), formatNumber(k.Value.B)
        )
    end
    return "ColorSequence.new({" .. table.concat(points, ", ") .. "})"
end
SCALARS["TweenInfo"] = function(v)
    return string.format(
        "TweenInfo.new(%s, %s, %s, %s, %s, %s)",
        formatNumber(v.Time), tostring(v.EasingStyle), tostring(v.EasingDirection),
        formatNumber(v.RepeatCount), tostring(v.Reverses), formatNumber(v.DelayTime)
    )
end
SCALARS["EnumItem"] = function(v)
    return tostring(v)
end
SCALARS["Enum"] = function(v)
    return tostring(v)
end
SCALARS["DateTime"] = function(v)
    return string.format("DateTime.fromUnixTimestampMillis(%d)", v.UnixTimestampMillis)
end
SCALARS["buffer"] = function(v)
    local ok, length = pcall(function()
        return buffer.len(v)
    end)
    return "<buffer " .. (ok and length or "?") .. " byte>"
end
SCALARS["thread"] = function()
    return "<thread>"
end
SCALARS["RBXScriptSignal"] = function()
    return "<signal>"
end
SCALARS["RBXScriptConnection"] = function()
    return "<connection>"
end

local serialize

local function serializeTable(t, depth, seen, lua)
    local length = #t
    local total = 0
    for _ in pairs(t) do
        total = total + 1
        if total > CONFIG.SerializeMaxEntries then
            break
        end
    end
    local parts = {}
    if length > 0 and total == length then
        for i = 1, math.min(length, CONFIG.SerializeMaxEntries) do
            parts[#parts + 1] = serialize(t[i], depth + 1, seen, lua)
        end
        if length > CONFIG.SerializeMaxEntries then
            parts[#parts + 1] = "..."
        end
    else
        local count = 0
        for key, value in pairs(t) do
            count = count + 1
            if count > CONFIG.SerializeMaxEntries then
                parts[#parts + 1] = "..."
                break
            end
            local keyText
            if type(key) == "string" and key:match("^[%a_][%w_]*$") and not KEYWORDS[key] then
                keyText = key
            else
                keyText = "[" .. serialize(key, depth + 1, seen, lua) .. "]"
            end
            parts[#parts + 1] = keyText .. " = " .. serialize(value, depth + 1, seen, lua)
        end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

serialize = function(value, depth, seen, lua)
    depth = depth or 0
    seen = seen or {}
    local kind = typeof(value)
    local handler = SCALARS[kind]
    if handler then
        local ok, result = pcall(handler, value, lua)
        if ok then
            return result
        end
        return "<" .. kind .. ">"
    end
    if kind == "Instance" then
        if lua then
            return luaPath(value)
        end
        local ok, class = pcall(getClass, value)
        return "<" .. (ok and class or "Instance") .. ":" .. fullName(value) .. ">"
    elseif kind == "function" then
        return lua and "nil" or describeFunction(value)
    elseif kind == "table" then
        if seen[value] then
            return "<cycle>"
        end
        if depth >= CONFIG.SerializeDepth then
            return "{...}"
        end
        seen[value] = true
        local ok, result = pcall(serializeTable, value, depth, seen, lua)
        seen[value] = nil
        return ok and result or "<table>"
    end
    return "<" .. kind .. " " .. tostring(value) .. ">"
end

local function dumpValue(writer, label, value, depth, seen, indent)
    indent = indent or ""
    if typeof(value) ~= "table" then
        writer:line(indent .. label .. " = " .. serialize(value, 0, nil, false))
        return
    end
    if seen[value] then
        writer:line(indent .. label .. " = <cycle>")
        return
    end
    if depth >= CONFIG.ValueDepth then
        writer:line(indent .. label .. " = {... batas kedalaman}")
        return
    end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then
            return ta < tb
        end
        if ta == "number" or ta == "string" then
            return a < b
        end
        return tostring(a) < tostring(b)
    end)
    writer:line(indent .. label .. " = { -- " .. #keys .. " entri")
    for i, key in ipairs(keys) do
        if i > CONFIG.ValueMaxEntries then
            writer:line(indent .. "  ... (" .. (#keys - CONFIG.ValueMaxEntries) .. " entri lagi)")
            break
        end
        local keyLabel = "[" .. serialize(key, 0, nil, false) .. "]"
        dumpValue(writer, keyLabel, value[key], depth + 1, seen, indent .. "  ")
    end
    writer:line(indent .. "}")
    seen[value] = nil
end

local function callWithTimeout(timeout, fn, ...)
    local args = table.pack(...)
    local finished, success, results = false, false, nil
    task.spawn(function()
        local packed = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
        success = packed[1]
        results = table.pack(table.unpack(packed, 2, packed.n))
        finished = true
    end)
    local startedAt = os.clock()
    while not finished and os.clock() - startedAt < timeout do
        task.wait(0.05)
    end
    return finished, success, results
end

local function pace(index, every)
    if index % (every or CONFIG.YieldEvery) == 0 then
        task.wait()
    end
end

local function eachService(fn)
    for _, service in ipairs(game:GetChildren()) do
        if state.cancel then
            return
        end
        if not CONFIG.SkipServices[service.ClassName] then
            fn(service)
        end
    end
end

local function eachDescendant(root, fn)
    local ok, list = pcall(function()
        return root:GetDescendants()
    end)
    if not ok then
        return
    end
    for index, inst in ipairs(list) do
        if state.cancel then
            return
        end
        fn(inst, index)
        pace(index, 2000)
    end
end

local function collectRemotes(includeBindables)
    local result = {}
    eachService(function(service)
        eachDescendant(service, function(inst)
            local class = inst.ClassName
            if REMOTE_CLASS[class] and (includeBindables or NETWORK_CLASS[class]) then
                result[#result + 1] = inst
            end
        end)
    end)
    return result
end

local function addReport(name, writer, extra)
    report[#report + 1] = string.format("%-46s %8d baris  %s", name, writer and writer.lines or 0, extra or "")
end

local function runTask(item)
    local ok, err = pcall(item.run)
    if not ok then
        errors[#errors + 1] = item.label .. ": " .. tostring(err)
        warn("[MeowX Dump] gagal " .. item.label .. ": " .. tostring(err))
    end
    return ok
end

local EXTRA_PROPS = {
    { "ValueBase", { "Value" } },
    { "TextLabel", { "Text" } },
    { "TextButton", { "Text" } },
    { "TextBox", { "Text" } },
    { "ImageLabel", { "Image" } },
    { "ImageButton", { "Image" } },
    { "GuiObject", { "Visible" } },
    { "LayerCollector", { "Enabled" } },
    { "BasePart", { "Position", "Size", "Anchored", "CanCollide", "CanTouch", "Transparency" } },
    { "ProximityPrompt", { "ActionText", "ObjectText", "HoldDuration", "MaxActivationDistance", "Enabled", "RequiresLineOfSight" } },
    { "ClickDetector", { "MaxActivationDistance" } },
    { "Humanoid", { "Health", "MaxHealth", "WalkSpeed", "JumpPower", "JumpHeight" } },
    { "Model", { "PrimaryPart" } },
    { "Sound", { "SoundId" } },
    { "Script", { "Enabled" } },
    { "LocalScript", { "Enabled" } },
    { "Tool", { "Enabled" } },
    { "Animation", { "AnimationId" } },
    { "Decal", { "Texture" } },
    { "Texture", { "Texture" } },
    { "MeshPart", { "MeshId" } },
    { "SpecialMesh", { "MeshId" } },
}

local function describe(inst)
    local parts = { inst.ClassName .. " " .. quote(inst.Name, 120) }
    for _, entry in ipairs(EXTRA_PROPS) do
        if inst:IsA(entry[1]) then
            for _, name in ipairs(entry[2]) do
                local ok, value = pcall(function()
                    return inst[name]
                end)
                if ok then
                    parts[#parts + 1] = name .. "=" .. serialize(value, 0, nil, false)
                end
            end
        end
    end
    local okA, attributes = pcall(inst.GetAttributes, inst)
    if okA and next(attributes) then
        parts[#parts + 1] = "attrs=" .. serialize(attributes, 0, nil, false)
    end
    local okT, tags = pcall(CollectionService.GetTags, CollectionService, inst)
    if okT and #tags > 0 then
        parts[#parts + 1] = "tags=" .. serialize(tags, 0, nil, false)
    end
    return table.concat(parts, "  ")
end

local function dumpTree(root, writer)
    local written = 0
    local stack = { { root, 0 } }
    while #stack > 0 do
        if state.cancel then
            break
        end
        if written >= CONFIG.TreeMaxInstances then
            writer:line("... dipotong pada batas " .. CONFIG.TreeMaxInstances .. " instance")
            break
        end
        local item = table.remove(stack)
        local inst, depth = item[1], item[2]
        local indent = string.rep("  ", depth)
        local okLine, line = pcall(describe, inst)
        writer:line(indent .. (okLine and line or ("? " .. tostring(inst))))
        written = written + 1
        local okChildren, children = pcall(inst.GetChildren, inst)
        if okChildren then
            local kept, collapsed, order, counts = {}, {}, {}, {}
            for _, child in ipairs(children) do
                local signature = child.ClassName .. "\0" .. child.Name
                local n = (counts[signature] or 0) + 1
                counts[signature] = n
                if n <= CONFIG.TreeRepeatCollapse or #child:GetChildren() > 0 then
                    kept[#kept + 1] = child
                else
                    if not collapsed[signature] then
                        collapsed[signature] = { class = child.ClassName, name = child.Name, count = 0 }
                        order[#order + 1] = signature
                    end
                    collapsed[signature].count = collapsed[signature].count + 1
                end
            end
            for _, signature in ipairs(order) do
                local entry = collapsed[signature]
                writer:line(indent .. "  [diringkas] +" .. entry.count .. " " .. entry.class .. " " .. quote(entry.name, 80))
            end
            for i = #kept, 1, -1 do
                stack[#stack + 1] = { kept[i], depth + 1 }
            end
        end
        pace(written)
    end
    return written
end

local CAPABILITIES = {
    { "File", { "writefile", "appendfile", "readfile", "makefolder", "isfolder", "isfile", "listfiles", "delfile" } },
    { "Hook", { "hookfunction", "hookmetamethod", "newcclosure", "checkcaller", "getnamecallmethod", "setnamecallmethod", "getrawmetatable", "setreadonly", "restorefunction" } },
    { "Inspeksi", { "getgc", "getconnections", "getscripts", "getloadedmodules", "getnilinstances", "getinstances", "getsenv", "getrenv", "getgenv", "getupvalues", "getconstants", "getcallingscript", "getscriptclosure", "decompile", "saveinstance", "getfflag" } },
    { "Interaksi", { "firesignal", "fireclickdetector", "fireproximityprompt", "firetouchinterest", "setclipboard", "request", "http_request", "queue_on_teleport", "gethui", "cloneref", "compareinstances", "isexecutorclosure", "identifyexecutor", "Drawing" } },
}

local function dumpGameInfo()
    local writer = newWriter("01_GameInfo.txt")
    local okInfo, info = pcall(function()
        return MarketplaceService:GetProductInfo(game.PlaceId)
    end)
    local okExec, execName, execVersion = pcall(identifyexecutor)
    writer:line("Waktu dump       : " .. os.date("%Y-%m-%d %H:%M:%S"))
    writer:line("Nama game        : " .. gameName)
    writer:line("PlaceId          : " .. tostring(game.PlaceId))
    writer:line("GameId           : " .. tostring(game.GameId))
    writer:line("PlaceVersion     : " .. tostring(game.PlaceVersion))
    writer:line("JobId            : " .. tostring(game.JobId))
    writer:line("PrivateServerId  : " .. tostring(game.PrivateServerId))
    writer:line("Executor         : " .. (okExec and (tostring(execName) .. " " .. tostring(execVersion or "")) or "tidak diketahui"))
    if okInfo and type(info) == "table" then
        writer:line("Pembuat          : " .. tostring(info.Creator and info.Creator.Name))
        writer:line("Update terakhir  : " .. tostring(info.Updated))
        writer:line("Deskripsi        : " .. quote(info.Description or "", 600))
    end
    writer:line("Gravity          : " .. tostring(workspace.Gravity))
    writer:line("StreamingEnabled : " .. tostring(workspace.StreamingEnabled))
    writer:line("")
    writer:line("[LocalPlayer]")
    writer:line("Name             : " .. LocalPlayer.Name)
    writer:line("DisplayName      : " .. LocalPlayer.DisplayName)
    writer:line("UserId           : " .. tostring(LocalPlayer.UserId))
    writer:line("AccountAge       : " .. tostring(LocalPlayer.AccountAge))
    writer:line("Team             : " .. tostring(LocalPlayer.Team))
    writer:line("Character        : " .. (LocalPlayer.Character and fullName(LocalPlayer.Character) or "nil"))
    dumpValue(writer, "Attributes", LocalPlayer:GetAttributes(), 0, {})
    local stats = LocalPlayer:FindFirstChild("leaderstats")
    if stats then
        writer:line("")
        writer:line("[leaderstats]")
        for _, child in ipairs(stats:GetChildren()) do
            writer:line(string.format("  %-24s %-14s %s", child.Name, child.ClassName, serialize(prop(child, "Value"), 0, nil, false)))
        end
    end
    writer:line("")
    writer:line("[Pemain di server: " .. #Players:GetPlayers() .. "]")
    for _, player in ipairs(Players:GetPlayers()) do
        writer:line(string.format("  %-24s %-24s %d", player.Name, player.DisplayName, player.UserId))
    end
    writer:line("")
    writer:line("[Service]")
    for _, service in ipairs(game:GetChildren()) do
        local ok, count = pcall(function()
            return #service:GetDescendants()
        end)
        writer:line(string.format("  %-30s %s", service.ClassName, ok and (count .. " descendant") or "tidak dapat diakses"))
    end
    writer:line("")
    writer:line("[CollectionService Tags]")
    for _, tag in ipairs(CollectionService:GetAllTags()) do
        writer:line("  " .. tag .. " = " .. #CollectionService:GetTagged(tag))
    end
    addReport("01_GameInfo.txt", writer)
    writer:close()
end

local function dumpCapabilities()
    local writer = newWriter("02_ExecutorCapabilities.txt")
    local available, missing = 0, 0
    for _, group in ipairs(CAPABILITIES) do
        writer:line("[" .. group[1] .. "]")
        for _, name in ipairs(group[2]) do
            local value = globalFn(name)
            local kind = type(value)
            local status = "TIDAK ADA"
            if kind == "function" or kind == "table" then
                status = "tersedia (" .. kind .. ")"
                available = available + 1
            else
                missing = missing + 1
            end
            writer:line(string.format("  %-24s %s", name, status))
        end
        writer:line("")
    end
    writer:line("Tersedia: " .. available .. "  Tidak ada: " .. missing)
    addReport("02_ExecutorCapabilities.txt", writer)
    writer:close()
end

local function dumpRemotes()
    local writer = newWriter("03_Remotes.txt")
    local entries = {}
    for _, inst in ipairs(collectRemotes(CONFIG.IncludeBindables)) do
        entries[#entries + 1] = { path = fullName(inst), inst = inst }
    end
    table.sort(entries, function(a, b)
        return a.path < b.path
    end)
    local perClass, perName = {}, {}
    for _, entry in ipairs(entries) do
        local class = entry.inst.ClassName
        perClass[class] = (perClass[class] or 0) + 1
        perName[entry.inst.Name] = (perName[entry.inst.Name] or 0) + 1
        local usage = ":FireServer()"
        if class:find("Function") then
            usage = class:find("Bindable") and ":Invoke()" or ":InvokeServer()"
        elseif class:find("Bindable") then
            usage = ":Fire()"
        end
        writer:line(string.format("%-22s %s", class, luaPath(entry.inst) .. usage))
    end
    writer:line("")
    writer:line("[Ringkasan]")
    for class, count in pairs(perClass) do
        writer:line(string.format("  %-24s %d", class, count))
    end
    writer:line("  total                    " .. #entries)
    local duplicates = {}
    for name, count in pairs(perName) do
        if count > 1 then
            duplicates[#duplicates + 1] = name .. " x" .. count
        end
    end
    table.sort(duplicates)
    if #duplicates > 0 then
        writer:line("")
        writer:line("[Nama remote kembar]")
        for _, text in ipairs(duplicates) do
            writer:line("  " .. text)
        end
    end
    if type(getnilinstances) == "function" then
        writer:line("")
        writer:line("[Remote dengan parent nil]")
        local ok, list = pcall(getnilinstances)
        if ok then
            local shown = 0
            for _, inst in ipairs(list) do
                local okClass, class = pcall(getClass, inst)
                if okClass and REMOTE_CLASS[class] then
                    shown = shown + 1
                    writer:line(string.format("  %-22s %s", class, quote(inst.Name, 120)))
                end
            end
            writer:line("  total: " .. shown)
        end
    end
    addReport("03_Remotes.txt", writer, "(" .. #entries .. " remote)")
    writer:close()
end

local function dumpPlayerState()
    local writer = newWriter("04_PlayerState.txt")
    writer:line("[LocalPlayer]")
    for _, child in ipairs(LocalPlayer:GetChildren()) do
        if child.Name ~= "PlayerGui" and child.Name ~= "PlayerScripts" then
            dumpTree(child, writer)
        end
    end
    writer:line("")
    writer:line("[Character]")
    if LocalPlayer.Character then
        dumpTree(LocalPlayer.Character, writer)
    else
        writer:line("Character belum ada")
    end
    writer:line("")
    writer:line("[Payload terakhir RemoteEvent server -> client]")
    local any = false
    for remote, args in pairs(lastPayload) do
        any = true
        writer:line("-- " .. luaPath(remote))
        for i = 1, args.n do
            dumpValue(writer, "arg" .. i, args[i], 0, {}, "  ")
        end
    end
    if not any then
        writer:line("Belum ada payload. Aktifkan Remote Spy, mainkan sebentar, lalu jalankan ulang bagian ini.")
    end
    addReport("04_PlayerState.txt", writer)
    writer:close()
end

local function isGetter(name)
    local lower = name:lower()
    for _, denied in ipairs(CONFIG.GetterDeny) do
        if lower:find(denied, 1, true) then
            return false
        end
    end
    for _, allowed in ipairs(CONFIG.GetterAllow) do
        if lower:find(allowed) then
            return true
        end
    end
    return false
end

local function dumpStateGetters()
    local writer = newWriter("05_StateGetters.txt")
    local called = 0
    for _, remote in ipairs(collectRemotes(false)) do
        if state.cancel then
            break
        end
        if remote:IsA("RemoteFunction") and isGetter(remote.Name) then
            called = called + 1
            setStatus("InvokeServer: " .. remote.Name)
            writer:line("")
            writer:line("---- " .. luaPath(remote) .. ":InvokeServer()")
            local finished, success, results = callWithTimeout(CONFIG.InvokeTimeout, function()
                return remote:InvokeServer()
            end)
            if not finished then
                writer:line("timeout")
            elseif not success then
                writer:line("error: " .. tostring(results[1]))
            elseif results.n == 0 then
                writer:line("tanpa nilai kembalian")
            else
                for i = 1, results.n do
                    dumpValue(writer, "return" .. i, results[i], 0, {})
                end
            end
        end
    end
    if called == 0 then
        writer:line("Tidak ada RemoteFunction getter yang cocok dengan filter")
    end
    addReport("05_StateGetters.txt", writer, "(" .. called .. " dipanggil)")
    writer:close()
end

local function isShown(obj, root)
    local current = obj
    while current and current ~= root do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end
        if current:IsA("LayerCollector") and not current.Enabled then
            return false
        end
        current = current.Parent
    end
    return true
end

local function connectionCount(button)
    if type(getconnections) ~= "function" then
        return nil
    end
    local total = 0
    for _, signalName in ipairs({ "MouseButton1Click", "Activated", "MouseButton1Down" }) do
        local ok, list = pcall(function()
            return getconnections(button[signalName])
        end)
        if ok and type(list) == "table" then
            total = total + #list
        end
    end
    return total
end

local function dumpGui()
    local writer = newWriter("06_GuiTexts.txt")
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        writer:line("PlayerGui tidak ditemukan")
        addReport("06_GuiTexts.txt", writer)
        writer:close()
        return
    end
    writer:line("[ScreenGui]")
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("LayerCollector") then
            writer:line(string.format("  %-32s Enabled=%s DisplayOrder=%s", gui.Name, tostring(prop(gui, "Enabled")), tostring(prop(gui, "DisplayOrder"))))
        end
    end
    writer:line("")
    writer:line("[Teks dan Tombol]")
    local texts, buttons = 0, 0
    eachDescendant(playerGui, function(inst)
        local shown = isShown(inst, playerGui) and "tampil  " or "sembunyi"
        if inst:IsA("GuiButton") then
            buttons = buttons + 1
            local count = connectionCount(inst)
            local content = inst:IsA("TextButton") and ("Text=" .. quote(prop(inst, "Text"), 200)) or ("Image=" .. quote(prop(inst, "Image"), 120))
            writer:line(string.format("[%s] [Tombol hubungan=%s] %s  %s", shown, count and tostring(count) or "?", fullName(inst), content))
        elseif inst:IsA("TextLabel") or inst:IsA("TextBox") then
            texts = texts + 1
            local extra = inst:IsA("TextBox") and ("  Placeholder=" .. quote(prop(inst, "PlaceholderText"), 120)) or ""
            writer:line(string.format("[%s] [Teks] %s  Text=%s%s", shown, fullName(inst), quote(prop(inst, "Text"), 300), extra))
        end
    end)
    addReport("06_GuiTexts.txt", writer, "(" .. texts .. " teks, " .. buttons .. " tombol)")
    writer:close()
end

local function positionOf(inst)
    local parent = inst.Parent
    if inst:IsA("BasePart") then
        return inst.Position
    end
    if parent then
        if parent:IsA("BasePart") then
            return parent.Position
        elseif parent:IsA("Attachment") then
            return parent.WorldPosition
        elseif parent:IsA("Model") then
            local ok, pivot = pcall(function()
                return parent:GetPivot().Position
            end)
            if ok then
                return pivot
            end
        end
    end
    return nil
end

local function dumpInteractables()
    local writer = newWriter("07_Interactables.txt")
    local prompts, clicks, touches, npcs = {}, {}, {}, {}
    eachService(function(service)
        eachDescendant(service, function(inst)
            local class = inst.ClassName
            if class == "ProximityPrompt" and #prompts < CONFIG.ListLimit then
                local ok, line = pcall(function()
                    return string.format(
                        "%s  Action=%s Object=%s Hold=%s Distance=%s Enabled=%s LOS=%s Pos=%s",
                        fullName(inst), quote(inst.ActionText, 80), quote(inst.ObjectText, 80), formatNumber(inst.HoldDuration),
                        formatNumber(inst.MaxActivationDistance), tostring(inst.Enabled), tostring(inst.RequiresLineOfSight),
                        serialize(positionOf(inst), 0, nil, true)
                    )
                end)
                prompts[#prompts + 1] = ok and line or fullName(inst)
            elseif class == "ClickDetector" and #clicks < CONFIG.ListLimit then
                clicks[#clicks + 1] = string.format("%s  Distance=%s Pos=%s", fullName(inst), formatNumber(inst.MaxActivationDistance), serialize(positionOf(inst), 0, nil, true))
            elseif class == "TouchTransmitter" and #touches < CONFIG.ListLimit then
                touches[#touches + 1] = string.format("%s  Pos=%s", fullName(inst.Parent or inst), serialize(positionOf(inst), 0, nil, true))
            elseif class == "Humanoid" and #npcs < CONFIG.ListLimit then
                local model = inst.Parent
                if model and not Players:GetPlayerFromCharacter(model) then
                    npcs[#npcs + 1] = string.format(
                        "%s  Health=%s/%s WalkSpeed=%s Pos=%s",
                        fullName(model), formatNumber(inst.Health), formatNumber(inst.MaxHealth), formatNumber(inst.WalkSpeed),
                        serialize(positionOf(inst), 0, nil, true)
                    )
                end
            end
        end)
    end)
    local function section(title, list)
        writer:line("[" .. title .. " : " .. #list .. "]")
        for _, line in ipairs(list) do
            writer:line("  " .. line)
        end
        writer:line("")
    end
    section("ProximityPrompt", prompts)
    section("ClickDetector", clicks)
    section("TouchTransmitter", touches)
    section("Humanoid NPC", npcs)
    writer:line("[Instance ber-tag]")
    for _, tag in ipairs(CollectionService:GetAllTags()) do
        local tagged = CollectionService:GetTagged(tag)
        writer:line("  " .. tag .. " = " .. #tagged)
        for i = 1, math.min(#tagged, 15) do
            writer:line("    " .. fullName(tagged[i]))
        end
    end
    addReport("07_Interactables.txt", writer, string.format("(%d prompt, %d click, %d touch)", #prompts, #clicks, #touches))
    writer:close()
end

local function dumpServiceTrees()
    eachService(function(service)
        local fileName = "ServiceTrees/" .. safeName(service.ClassName) .. ".txt"
        local writer = newWriter(fileName)
        setStatus("Tree " .. service.ClassName)
        local ok, result = pcall(dumpTree, service, writer)
        if not ok then
            writer:line("ERROR: " .. tostring(result))
        end
        addReport(fileName, writer, ok and ("(" .. tostring(result) .. " instance)") or "")
        writer:close()
        task.wait()
    end)
    local nilList = globalFn("getnilinstances")
    if type(nilList) == "function" and not state.cancel then
        local writer = newWriter("ServiceTrees/_NilInstances.txt")
        local ok, list = pcall(nilList)
        if ok and type(list) == "table" then
            for index, inst in ipairs(list) do
                if index > CONFIG.TreeMaxInstances then
                    break
                end
                local okLine, line = pcall(describe, inst)
                writer:line(okLine and line or tostring(inst))
                pace(index)
            end
        end
        addReport("ServiceTrees/_NilInstances.txt", writer)
        writer:close()
    end
end

local function dumpModules()
    local writer = newWriter("08_Modules.txt")
    local roots = { ReplicatedStorage, ReplicatedFirst }
    for _, name in ipairs({ "StarterPlayer", "StarterGui", "StarterPack" }) do
        local ok, service = pcall(game.GetService, game, name)
        if ok and service then
            roots[#roots + 1] = service
        end
    end
    roots[#roots + 1] = LocalPlayer
    local list, seen = {}, {}
    local function add(inst)
        if typeof(inst) == "Instance" and not seen[inst] and inst:IsA("ModuleScript") then
            local ok, inCore = pcall(function()
                return inst:IsDescendantOf(CoreGui) or inst:IsDescendantOf(CorePackages)
            end)
            if not (ok and inCore) then
                seen[inst] = true
                list[#list + 1] = inst
            end
        end
    end
    for _, root in ipairs(roots) do
        eachDescendant(root, add)
    end
    local loaded = globalFn("getloadedmodules")
    if type(loaded) == "function" then
        pcall(function()
            for _, inst in ipairs(loaded()) do
                add(inst)
            end
        end)
    end
    writer:line("total modul: " .. #list)
    for index, module in ipairs(list) do
        if state.cancel then
            break
        end
        setStatus(string.format("Require %d/%d", index, #list))
        writer:line("")
        writer:line("---- " .. luaPath(module))
        local finished, success, results = callWithTimeout(CONFIG.RequireTimeout, require, module)
        if not finished then
            writer:line("timeout")
        elseif not success then
            writer:line("gagal require: " .. tostring(results[1]))
        else
            dumpValue(writer, "return", results[1], 0, {})
        end
        pace(index, 5)
    end
    addReport("08_Modules.txt", writer, "(" .. #list .. " modul)")
    writer:close()
end

local function dumpMemoryScan()
    local writer = newWriter("09_MemoryScan.txt")
    if type(getgc) ~= "function" then
        writer:line("getgc tidak tersedia di executor ini")
        addReport("09_MemoryScan.txt", writer)
        writer:close()
        return
    end
    local ok, objects = pcall(getgc, true)
    if not ok then
        writer:line("getgc gagal: " .. tostring(objects))
        addReport("09_MemoryScan.txt", writer)
        writer:close()
        return
    end
    local keywords = {}
    for _, key in ipairs(CONFIG.GCKeywords) do
        keywords[key] = true
    end
    local ignore = { [CONFIG] = true, [env] = true, [state] = true, [ui] = true, [lastPayload] = true }
    local found, scanned = 0, 0
    for index, object in ipairs(objects) do
        if state.cancel or found >= CONFIG.GCMaxTables then
            break
        end
        if type(object) == "table" and not ignore[object] then
            scanned = scanned + 1
            local score = 0
            local okScan = pcall(function()
                for key in pairs(object) do
                    if type(key) == "string" and keywords[key:lower()] then
                        score = score + 1
                        if score >= CONFIG.GCMinMatch then
                            break
                        end
                    end
                end
            end)
            if okScan and score >= CONFIG.GCMinMatch then
                found = found + 1
                writer:line("")
                writer:line("---- tabel #" .. found)
                dumpValue(writer, "table", object, 0, {})
            end
        end
        pace(index, 4000)
    end
    writer:line("")
    writer:line("objek GC: " .. #objects .. "  tabel dipindai: " .. scanned .. "  tabel cocok: " .. found)
    addReport("09_MemoryScan.txt", writer, "(" .. found .. " tabel)")
    writer:close()
end

local function collectScripts()
    local list, seen = {}, {}
    local function add(inst)
        if typeof(inst) ~= "Instance" or seen[inst] then
            return
        end
        local okClass, isScript = pcall(function()
            return inst:IsA("LuaSourceContainer")
        end)
        if not (okClass and isScript) then
            return
        end
        local okCore, inCore = pcall(function()
            return inst:IsDescendantOf(CoreGui) or inst:IsDescendantOf(CorePackages)
        end)
        if okCore and inCore then
            return
        end
        seen[inst] = true
        list[#list + 1] = inst
    end
    for _, getter in ipairs({ "getscripts", "getloadedmodules" }) do
        local fn = globalFn(getter)
        if type(fn) == "function" then
            pcall(function()
                for _, inst in ipairs(fn()) do
                    add(inst)
                end
            end)
        end
    end
    eachService(function(service)
        eachDescendant(service, add)
    end)
    return list
end

local function dumpScriptEnvironments()
    local writer = newWriter("10_ScriptEnvironments.txt")
    local getEnv = globalFn("getsenv")
    if type(getEnv) ~= "function" then
        writer:line("getsenv tidak tersedia di executor ini")
        addReport("10_ScriptEnvironments.txt", writer)
        writer:close()
        return
    end
    local getUp = globalFn("getupvalues")
    local getConst = globalFn("getconstants")
    local list = collectScripts()
    local dumped = 0
    for index, inst in ipairs(list) do
        if state.cancel then
            break
        end
        setStatus(string.format("Environment %d/%d", index, #list))
        local ok, senv = pcall(getEnv, inst)
        if ok and type(senv) == "table" then
            dumped = dumped + 1
            writer:line("")
            writer:line("---- " .. fullName(inst))
            local keys = {}
            for key in pairs(senv) do
                keys[#keys + 1] = key
            end
            table.sort(keys, function(a, b)
                return tostring(a) < tostring(b)
            end)
            for i, key in ipairs(keys) do
                if i > CONFIG.ValueMaxEntries then
                    writer:line("  ...")
                    break
                end
                local value = senv[key]
                if type(value) == "function" then
                    writer:line(string.format("  %-28s %s", tostring(key), describeFunction(value)))
                    if type(getUp) == "function" then
                        local okUp, upvalues = pcall(getUp, value)
                        if okUp and type(upvalues) == "table" then
                            local shown = 0
                            for upIndex, upValue in pairs(upvalues) do
                                shown = shown + 1
                                if shown > 12 then
                                    writer:line("      ...")
                                    break
                                end
                                writer:line(string.format("      upvalue[%s] = %s", tostring(upIndex), serialize(upValue, 0, nil, false):sub(1, 240)))
                            end
                        end
                    end
                    if type(getConst) == "function" then
                        local okConst, constants = pcall(getConst, value)
                        if okConst and type(constants) == "table" then
                            local strings = {}
                            for _, constant in pairs(constants) do
                                if type(constant) == "string" and #constant >= 3 and #strings < 25 then
                                    strings[#strings + 1] = quote(constant, 60)
                                end
                            end
                            if #strings > 0 then
                                writer:line("      constants: " .. table.concat(strings, ", "))
                            end
                        end
                    end
                else
                    writer:line(string.format("  %-28s %s", tostring(key), serialize(value, 0, nil, false):sub(1, 300)))
                end
            end
        end
        pace(index, 5)
    end
    writer:line("")
    writer:line("script dengan environment: " .. dumped .. " dari " .. #list)
    addReport("10_ScriptEnvironments.txt", writer, "(" .. dumped .. " script)")
    writer:close()
end

local CALLSITE_MARKERS = { "FireServer", "InvokeServer", "OnClientEvent", "OnClientInvoke" }

local function dumpScripts()
    if type(decompile) ~= "function" then
        local writer = newWriter("Scripts/_Index.txt")
        writer:line("decompile tidak tersedia di executor ini")
        addReport("Scripts/_Index.txt", writer)
        writer:close()
        return
    end
    local list = collectScripts()
    local remoteIndex = {}
    for _, remote in ipairs(collectRemotes(false)) do
        if #remote.Name >= 3 then
            local entry = remoteIndex[remote.Name]
            if not entry then
                entry = { class = remote.ClassName, paths = {}, refs = {} }
                remoteIndex[remote.Name] = entry
            end
            entry.paths[#entry.paths + 1] = fullName(remote)
        end
    end
    local index = newWriter("Scripts/_Index.txt")
    local callsites = newWriter("Scripts/_RemoteCallSites.txt")
    local references = newWriter("Scripts/_RemoteReferences.txt")
    local okCount, failCount = 0, 0
    for i, inst in ipairs(list) do
        if state.cancel then
            break
        end
        setStatus(string.format("Decompile %d/%d", i, #list))
        local path = fullName(inst)
        local finished, success, results = callWithTimeout(CONFIG.DecompileTimeout, decompile, inst)
        local source = results and results[1]
        if not (finished and success and type(source) == "string") then
            finished, success, results = callWithTimeout(CONFIG.DecompileRetryTimeout, decompile, inst)
            source = results and results[1]
        end
        if finished and success and type(source) == "string" then
            okCount = okCount + 1
            local file = string.format("Scripts/%04d_%s_%s.lua", i, inst.ClassName, safeName(path, 100))
            if HAS_WRITE and not pcall(writefile, ROOT .. "/" .. file, source) then
                state.writeFailures = state.writeFailures + 1
            end
            index:line(string.format("%04d  %-14s %7d byte  %s", i, inst.ClassName, #source, path))
            local tokens = {}
            for word in source:gmatch("[%w_]+") do
                tokens[word] = true
            end
            for literal in source:gmatch('"([^"\n]+)"') do
                tokens[literal] = true
            end
            for literal in source:gmatch("'([^'\n]+)'") do
                tokens[literal] = true
            end
            for name, entry in pairs(remoteIndex) do
                if tokens[name] then
                    entry.refs[#entry.refs + 1] = path
                end
            end
            local lineNo, written = 0, 0
            for line in (source .. "\n"):gmatch("([^\n]*)\n") do
                lineNo = lineNo + 1
                for _, marker in ipairs(CALLSITE_MARKERS) do
                    if line:find(marker, 1, true) then
                        if written == 0 then
                            callsites:line("")
                            callsites:line("[" .. inst.ClassName .. "] " .. path)
                        end
                        written = written + 1
                        if written <= CONFIG.CallSiteLimitPerScript then
                            callsites:line(string.format("  L%-6d %s", lineNo, trim(line):sub(1, 220)))
                        end
                        break
                    end
                end
            end
            if written > CONFIG.CallSiteLimitPerScript then
                callsites:line("  ... +" .. (written - CONFIG.CallSiteLimitPerScript) .. " baris lagi")
            end
        else
            failCount = failCount + 1
            index:line(string.format("%04d  %-14s GAGAL (%s)  %s", i, inst.ClassName, finished and tostring(source) or "timeout", path))
        end
        pace(i, 5)
    end
    local names = {}
    for name in pairs(remoteIndex) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local entry = remoteIndex[name]
        references:line("[" .. entry.class .. "] " .. name)
        for _, path in ipairs(entry.paths) do
            references:line("  lokasi : " .. path)
        end
        if #entry.refs == 0 then
            references:line("  dipakai: tidak ada referensi pada script yang berhasil di-decompile")
        else
            for _, path in ipairs(entry.refs) do
                references:line("  dipakai: " .. path)
            end
        end
        references:line("")
    end
    addReport("Scripts/_Index.txt", index, string.format("(%d berhasil, %d gagal) + file .lua", okCount, failCount))
    addReport("Scripts/_RemoteCallSites.txt", callsites)
    addReport("Scripts/_RemoteReferences.txt", references)
    index:close()
    callsites:close()
    references:close()
end

local spy = {
    counters = { ["C>S"] = {}, ["S>C"] = {} },
    order = {},
    hooked = {},
    total = 0,
    logged = 0,
    sequence = 0,
    startedAt = 0,
    log = nil,
    paste = nil,
    forwarding = setmetatable({}, { __mode = "k" }),
    invokeHooked = setmetatable({}, { __mode = "k" }),
}

local function counterFor(direction, remote)
    local bucket = spy.counters[direction]
    local counter = bucket[remote]
    if not counter then
        counter = {
            n = 0,
            logged = 0,
            duplicates = 0,
            signatures = {},
            class = remote.ClassName,
            name = fullName(remote),
            direction = direction,
        }
        bucket[remote] = counter
        spy.order[#spy.order + 1] = counter
    end
    return counter
end

local function shouldInspect(counter, remote)
    if CONFIG.SpyIgnore[remote.Name] then
        return false
    end
    return counter.logged < CONFIG.SpyMaxLogsPerRemote and counter.n <= CONFIG.SpyInspectLimit
end

local function formatElapsed(seconds)
    return string.format("+%02d:%05.2f", math.floor(seconds / 60), seconds % 60)
end

local function record(counter, remote, method, args, results, caller)
    local ok, err = pcall(function()
        if counter.logged >= CONFIG.SpyMaxLogsPerRemote or not spy.log then
            return
        end
        local parts = {}
        for i = 1, args.n do
            parts[i] = serialize(args[i], 0, nil, true)
        end
        local signature = table.concat(parts, ",")
        if CONFIG.SpyIgnoreDuplicateArgs then
            if counter.signatures[signature] then
                counter.duplicates = counter.duplicates + 1
                return
            end
            counter.signatures[signature] = true
        end
        counter.logged = counter.logged + 1
        spy.logged = spy.logged + 1
        spy.sequence = spy.sequence + 1
        spy.log:line(string.format(
            "[%04d] %s  %s  %s  %s  (log %d/%d, total %d)",
            spy.sequence, formatElapsed(os.clock() - spy.startedAt), counter.direction, counter.class, counter.name,
            counter.logged, CONFIG.SpyMaxLogsPerRemote, counter.n
        ))
        if caller then
            spy.log:line("       caller : " .. caller)
        end
        if counter.direction == "C>S" then
            local code = luaPath(remote) .. ":" .. method .. "(" .. table.concat(parts, ", ") .. ")"
            spy.log:line("       kode   : " .. code)
            if spy.paste then
                spy.paste:line(code)
            end
            if results then
                local returned = {}
                for i = 1, results.n do
                    returned[i] = serialize(results[i], 0, nil, true)
                end
                spy.log:line("       return : " .. table.concat(returned, ", "))
            end
        else
            spy.log:line("       args   : " .. table.concat(parts, ", "))
            if results then
                local returned = {}
                for i = 1, results.n do
                    returned[i] = serialize(results[i], 0, nil, true)
                end
                spy.log:line("       return : " .. table.concat(returned, ", "))
            end
        end
        spy.log:line("")
    end)
    if not ok then
        warn("[MeowX Dump] spy error: " .. tostring(err))
    end
end

local function forward(old, method, self, viaNamecall, ...)
    if viaNamecall and type(setnamecallmethod) == "function" then
        setnamecallmethod(method)
    end
    return old(self, ...)
end

local function forwardMarked(old, method, self, viaNamecall, ...)
    local thread = coroutine.running()
    local previous = spy.forwarding[thread]
    spy.forwarding[thread] = true
    local packed = table.pack(pcall(forward, old, method, self, viaNamecall, ...))
    spy.forwarding[thread] = previous
    if not packed[1] then
        error(packed[2], 0)
    end
    return table.unpack(packed, 2, packed.n)
end

local function spyDispatch(old, method, self, viaNamecall, ...)
    if not state.spyOn or spy.forwarding[coroutine.running()] or typeof(self) ~= "Instance" then
        return forward(old, method, self, viaNamecall, ...)
    end
    local okClass, class = pcall(getClass, self)
    if not (okClass and NETWORK_CLASS[class]) then
        return forward(old, method, self, viaNamecall, ...)
    end
    if not CONFIG.SpyLogOwnCalls and type(checkcaller) == "function" and checkcaller() then
        return forward(old, method, self, viaNamecall, ...)
    end
    local counter = counterFor("C>S", self)
    counter.n = counter.n + 1
    spy.total = spy.total + 1
    if not shouldInspect(counter, self) then
        return forwardMarked(old, method, self, viaNamecall, ...)
    end
    local caller
    if type(getcallingscript) == "function" then
        local okCaller, script = pcall(getcallingscript)
        if okCaller and script then
            caller = fullName(script)
        end
    end
    local args = table.pack(...)
    if method == "InvokeServer" or method == "invokeServer" then
        local results = table.pack(forwardMarked(old, method, self, viaNamecall, ...))
        task.spawn(record, counter, self, "InvokeServer", args, results, caller)
        return table.unpack(results, 1, results.n)
    end
    task.spawn(record, counter, self, "FireServer", args, nil, caller)
    return forwardMarked(old, method, self, viaNamecall, ...)
end

local function installNamecallHook()
    env.MeowXSpyDispatch = spyDispatch
    if env.MeowXHookInstalled then
        return true
    end
    if type(getnamecallmethod) ~= "function" then
        return false
    end
    local function makeHook(getOld)
        return newClosure(function(self, ...)
            local method = getnamecallmethod()
            local dispatch = env.MeowXSpyDispatch
            if dispatch and SPY_METHODS[method] then
                return dispatch(getOld(), method, self, true, ...)
            end
            return getOld()(self, ...)
        end)
    end
    local old
    if type(hookmetamethod) == "function" then
        local ok = pcall(function()
            old = hookmetamethod(game, "__namecall", makeHook(function()
                return old
            end))
        end)
        if ok and old then
            env.MeowXHookInstalled = true
            return true
        end
    end
    if type(getrawmetatable) == "function" and type(setreadonly) == "function" then
        local ok = pcall(function()
            local meta = getrawmetatable(game)
            old = meta.__namecall
            setreadonly(meta, false)
            meta.__namecall = makeHook(function()
                return old
            end)
            setreadonly(meta, true)
        end)
        if ok and old then
            env.MeowXHookInstalled = true
            return true
        end
    end
    return false
end

local function installFunctionHooks()
    env.MeowXSpyDispatch = spyDispatch
    if env.MeowXFunctionHooksInstalled then
        return true
    end
    if type(hookfunction) ~= "function" then
        return false
    end
    local installed = 0
    for _, spec in ipairs({
        { "RemoteEvent", "FireServer" },
        { "UnreliableRemoteEvent", "FireServer" },
        { "RemoteFunction", "InvokeServer" },
    }) do
        local ok = pcall(function()
            local sample = Instance.new(spec[1])
            local original = sample[spec[2]]
            sample:Destroy()
            local old
            old = hookfunction(original, newClosure(function(self, ...)
                local dispatch = env.MeowXSpyDispatch
                if dispatch then
                    return dispatch(old, spec[2], self, false, ...)
                end
                return old(self, ...)
            end))
        end)
        if ok then
            installed = installed + 1
        end
    end
    env.MeowXFunctionHooksInstalled = installed > 0
    return installed > 0
end

local function wrapInvoke(remote)
    if spy.invokeHooked[remote] or type(getcallbackvalue) ~= "function" then
        return
    end
    local ok, callback = pcall(getcallbackvalue, remote, "OnClientInvoke")
    if not ok or type(callback) ~= "function" then
        return
    end
    spy.invokeHooked[remote] = true
    pcall(function()
        remote.OnClientInvoke = function(...)
            local args = table.pack(...)
            local results = table.pack(callback(...))
            if state.spyOn then
                local counter = counterFor("S>C", remote)
                counter.n = counter.n + 1
                spy.total = spy.total + 1
                if shouldInspect(counter, remote) then
                    task.spawn(record, counter, remote, "OnClientInvoke", args, results, nil)
                end
            end
            return table.unpack(results, 1, results.n)
        end
    end)
end

local function hookClientEvents()
    local function connect(inst)
        local class = inst.ClassName
        if not NETWORK_CLASS[class] or spy.hooked[inst] then
            return
        end
        spy.hooked[inst] = true
        counterFor("C>S", inst)
        if class == "RemoteFunction" then
            wrapInvoke(inst)
            task.delay(1, wrapInvoke, inst)
            return
        end
        counterFor("S>C", inst)
        connections[#connections + 1] = inst.OnClientEvent:Connect(function(...)
            local args = table.pack(...)
            lastPayload[inst] = args
            if not state.spyOn then
                return
            end
            local counter = counterFor("S>C", inst)
            counter.n = counter.n + 1
            spy.total = spy.total + 1
            if shouldInspect(counter, inst) then
                task.spawn(record, counter, inst, "OnClientEvent", args, nil, nil)
            end
        end)
    end
    eachService(function(service)
        local ok, list = pcall(function()
            return service:GetDescendants()
        end)
        if ok then
            for index, inst in ipairs(list) do
                connect(inst)
                pace(index, 2000)
            end
        end
        local okConnect, connection = pcall(function()
            return service.DescendantAdded:Connect(connect)
        end)
        if okConnect then
            connections[#connections + 1] = connection
        end
    end)
    local nilList = globalFn("getnilinstances")
    if type(nilList) == "function" then
        local ok, list = pcall(nilList)
        if ok and type(list) == "table" then
            for _, inst in ipairs(list) do
                local okClass, class = pcall(getClass, inst)
                if okClass and NETWORK_CLASS[class] then
                    connect(inst)
                end
            end
        end
    end
end

local refreshSpyButton

local function spyFlush()
    if spy.log then
        spy.log:flush()
    end
    if spy.paste then
        spy.paste:flush()
    end
end

local function writeSpySummary()
    spyFlush()
    local writer = newWriter("RemoteSpy/Summary.txt")
    local rows = {}
    for _, counter in ipairs(spy.order) do
        rows[#rows + 1] = counter
    end
    table.sort(rows, function(a, b)
        return a.n > b.n
    end)
    writer:line(string.format("%-6s %-22s %8s %8s %10s  %s", "ARAH", "KELAS", "TOTAL", "DICATAT", "DUPLIKAT", "REMOTE"))
    for _, counter in ipairs(rows) do
        writer:line(string.format("%-6s %-22s %8d %8d %10d  %s", counter.direction, counter.class, counter.n, counter.logged, counter.duplicates, counter.name))
    end
    writer:line("")
    writer:line(string.format("total panggilan: %d  total dicatat: %d  remote unik: %d", spy.total, spy.logged, #rows))
    writer:close()
end

local function spySave()
    writeSpySummary()
    setStatus("Log spy tersimpan di " .. ROOT .. "/RemoteSpy")
end

local function spyStart()
    if state.spyOn then
        return
    end
    if not HAS_WRITE then
        setStatus("writefile tidak tersedia di executor ini")
        return
    end
    if not spy.log then
        spy.log = newWriter("RemoteSpy/Log.txt")
        spy.paste = newWriter("RemoteSpy/PasteReady.lua")
        spy.startedAt = os.clock()
        spy.log:line(string.format("Remote Spy | PlaceId %s | batas catatan per remote: %d | C>S client ke server, S>C server ke client", tostring(game.PlaceId), CONFIG.SpyMaxLogsPerRemote))
        spy.log:line("")
    end
    hookClientEvents()
    for _, remote in ipairs(collectRemotes(false)) do
        counterFor("C>S", remote)
        if remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
            counterFor("S>C", remote)
        end
    end
    local namecallOk = installNamecallHook()
    local functionOk = installFunctionHooks()
    local hooked = namecallOk or functionOk
    state.spyOn = true
    setStatus(hooked and "Spy aktif (C>S dan S>C)" or "Spy aktif hanya S>C (hook namecall tidak tersedia)")
    if refreshSpyButton then
        refreshSpyButton()
    end
end

local function spyStop()
    state.spyOn = false
    spySave()
    setStatus("Spy nonaktif, log tersimpan")
    if refreshSpyButton then
        refreshSpyButton()
    end
end

local function spyReset()
    spyFlush()
    spy.counters = { ["C>S"] = {}, ["S>C"] = {} }
    spy.order = {}
    spy.total, spy.logged, spy.sequence = 0, 0, 0
    spy.startedAt = os.clock()
    spy.log = newWriter("RemoteSpy/Log.txt")
    spy.paste = newWriter("RemoteSpy/PasteReady.lua")
    spy.log:line(string.format("Remote Spy | PlaceId %s | batas catatan per remote: %d | C>S client ke server, S>C server ke client", tostring(game.PlaceId), CONFIG.SpyMaxLogsPerRemote))
    spy.log:line("")
    setStatus("Penghitung dan log spy direset")
end

task.spawn(function()
    local ticks = 0
    while state.alive do
        task.wait(5)
        spyFlush()
        ticks = ticks + 1
        if state.spyOn and ticks % 6 == 0 then
            pcall(writeSpySummary)
        end
    end
end)

local TASKS = {
    { id = "info", label = "Info Game", run = dumpGameInfo },
    { id = "capabilities", label = "Kemampuan Executor", run = dumpCapabilities },
    { id = "remotes", label = "Daftar Remote", run = dumpRemotes },
    { id = "state", label = "State Pemain", run = dumpPlayerState },
    { id = "getters", label = "State Getter (InvokeServer)", run = dumpStateGetters },
    { id = "gui", label = "Teks dan Tombol GUI", run = dumpGui },
    { id = "interactables", label = "Interactables", run = dumpInteractables },
    { id = "trees", label = "Tree Service", run = dumpServiceTrees },
    { id = "modules", label = "ModuleScript (require)", run = dumpModules },
    { id = "environments", label = "Environment Script (getsenv)", run = dumpScriptEnvironments },
    { id = "memory", label = "Memory Scan (getgc)", run = dumpMemoryScan },
    { id = "scripts", label = "Decompile Script", run = dumpScripts },
}

local function writeIndex(startedAt)
    local writer = newWriter("00_Index.txt")
    writer:line(string.format("MeowX Dump | %s | PlaceId %s | %.1f detik | %s", gameName, tostring(game.PlaceId), os.clock() - startedAt, os.date("%Y-%m-%d %H:%M:%S")))
    writer:line("Folder: " .. ROOT)
    writer:line("Gagal tulis file: " .. state.writeFailures)
    writer:line("")
    for _, line in ipairs(report) do
        writer:line(line)
    end
    if #errors > 0 then
        writer:line("")
        writer:line("[ERROR]")
        for _, message in ipairs(errors) do
            writer:line("  " .. message)
        end
    end
    writer:close()
end

local function runExclusive(label, fn)
    if state.busy then
        setStatus("Masih berjalan: " .. tostring(state.current))
        return
    end
    if not HAS_WRITE then
        setStatus("writefile tidak tersedia di executor ini")
        return
    end
    state.busy, state.cancel, state.current = true, false, label
    report, errors = {}, {}
    local startedAt = os.clock()
    local ok, err = pcall(fn, startedAt)
    if not ok then
        errors[#errors + 1] = label .. ": " .. tostring(err)
        warn("[MeowX Dump] " .. label .. ": " .. tostring(err))
    end
    local cancelled = state.cancel
    state.busy, state.cancel, state.current = false, false, nil
    setStatus(string.format("%s: %s (%.1f detik)", cancelled and "Dibatalkan" or "Selesai", label, os.clock() - startedAt), 1)
end

local function dumpAll(startedAt)
    for index, item in ipairs(TASKS) do
        if state.cancel then
            break
        end
        setStatus(string.format("[%d/%d] %s", index, #TASKS, item.label), (index - 1) / #TASKS)
        runTask(item)
    end
    writeIndex(startedAt)
    if type(setclipboard) == "function" then
        pcall(setclipboard, ROOT)
    end
end

local function buildGui()
    local parent = (type(gethui) == "function" and gethui()) or CoreGui
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    local width = math.clamp(viewport.X - 24, 250, 330)
    local height = math.clamp(viewport.Y - 70, 280, 480)

    local gui = Instance.new("ScreenGui")
    gui.Name = "MeowXDumpUI"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 999
    gui.Parent = parent
    ui.gui = gui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(width, height)
    frame.Position = UDim2.fromOffset(12, 54)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(70, 60, 110)
    stroke.Thickness = 1

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 40)
    header.BackgroundTransparency = 1
    header.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -84, 1, 0)
    title.Position = UDim2.fromOffset(12, 0)
    title.BackgroundTransparency = 1
    title.Text = "MeowX Dump & Debug"
    title.TextColor3 = Color3.fromRGB(240, 240, 246)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local function headerButton(text, offset)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(30, 28)
        b.Position = UDim2.new(1, offset, 0, 6)
        b.BackgroundColor3 = Color3.fromRGB(38, 38, 52)
        b.BorderSizePixel = 0
        b.Text = text
        b.TextColor3 = Color3.fromRGB(240, 240, 246)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 16
        b.Parent = header
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        return b
    end

    local minimize = headerButton("-", -74)
    local close = headerButton("X", -40)

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -24, 0, 34)
    status.Position = UDim2.fromOffset(12, 42)
    status.BackgroundTransparency = 1
    status.Text = "Siap. Tidak ada proses yang berjalan otomatis."
    status.TextColor3 = Color3.fromRGB(190, 150, 255)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.Parent = frame
    ui.status = status

    local barBack = Instance.new("Frame")
    barBack.Size = UDim2.new(1, -24, 0, 5)
    barBack.Position = UDim2.fromOffset(12, 80)
    barBack.BackgroundColor3 = Color3.fromRGB(38, 38, 52)
    barBack.BorderSizePixel = 0
    barBack.Parent = frame
    Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 0, 1, 0)
    bar.BackgroundColor3 = Color3.fromRGB(150, 100, 255)
    bar.BorderSizePixel = 0
    bar.Parent = barBack
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
    ui.bar = bar

    local list = Instance.new("ScrollingFrame")
    list.Size = UDim2.new(1, -16, 1, -96)
    list.Position = UDim2.fromOffset(8, 92)
    list.BackgroundTransparency = 1
    list.BorderSizePixel = 0
    list.ScrollBarThickness = 4
    list.AutomaticCanvasSize = Enum.AutomaticSize.Y
    list.CanvasSize = UDim2.new()
    list.Parent = frame
    local layout = Instance.new("UIListLayout", list)
    layout.Padding = UDim.new(0, 6)

    local function section(text)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -6, 0, 20)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = Color3.fromRGB(130, 130, 150)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = list
    end

    local function button(text, callback)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -6, 0, 38)
        b.BackgroundColor3 = Color3.fromRGB(34, 34, 46)
        b.BorderSizePixel = 0
        b.Text = text
        b.TextColor3 = Color3.fromRGB(240, 240, 246)
        b.Font = Enum.Font.Gotham
        b.TextSize = 13
        b.Parent = list
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        b.Activated:Connect(function()
            task.spawn(callback, b)
        end)
        return b
    end

    section("DUMP")
    button("Dump Semua", function()
        runExclusive("Dump Semua", dumpAll)
    end)
    for _, item in ipairs(TASKS) do
        button(item.label, function()
            runExclusive(item.label, function()
                runTask(item)
                writeIndex(os.clock())
            end)
        end)
    end
    button("Batalkan Proses", function()
        if state.busy then
            state.cancel = true
            setStatus("Membatalkan proses...")
        end
    end)

    section("REMOTE SPY")
    ui.spyButton = button("Remote Spy: OFF", function()
        if state.spyOn then
            spyStop()
        else
            spyStart()
        end
    end)
    button("Simpan Log Spy", spySave)
    button("Reset Spy", spyReset)

    section("LAINNYA")
    button("Salin Path Folder", function()
        if type(setclipboard) == "function" then
            pcall(setclipboard, ROOT)
            setStatus("Path disalin: " .. ROOT)
        else
            setStatus("Path folder: " .. ROOT)
        end
    end)
    button("Tutup", function()
        if env.MeowXDump then
            env.MeowXDump.Destroy()
        end
    end)

    local minimized = false
    minimize.Activated:Connect(function()
        minimized = not minimized
        list.Visible = not minimized
        status.Visible = not minimized
        barBack.Visible = not minimized
        frame.Size = minimized and UDim2.fromOffset(width, 40) or UDim2.fromOffset(width, height)
        minimize.Text = minimized and "+" or "-"
    end)
    close.Activated:Connect(function()
        if env.MeowXDump then
            env.MeowXDump.Destroy()
        end
    end)

    local dragging, dragStart, startPosition
    connections[#connections + 1] = header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    connections[#connections + 1] = UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X, startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)

    refreshSpyButton = function()
        if ui.spyButton and ui.spyButton.Parent then
            ui.spyButton.Text = state.spyOn and "Remote Spy: ON" or "Remote Spy: OFF"
            ui.spyButton.BackgroundColor3 = state.spyOn and Color3.fromRGB(70, 48, 130) or Color3.fromRGB(34, 34, 46)
        end
    end
end

env.MeowXDump = {
    State = state,
    Root = ROOT,
    DumpAll = function()
        task.spawn(runExclusive, "Dump Semua", dumpAll)
    end,
    SpyStart = spyStart,
    SpyStop = spyStop,
    SpySave = spySave,
    SpyReset = spyReset,
    Destroy = function()
        state.alive = false
        state.spyOn = false
        state.cancel = true
        spyFlush()
        env.MeowXSpyDispatch = nil
        for _, connection in ipairs(connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        if ui.gui then
            pcall(function()
                ui.gui:Destroy()
            end)
        end
        env.MeowXDump = nil
    end,
}

local okGui, guiError = pcall(buildGui)
if not okGui then
    warn("[MeowX Dump] GUI gagal dibuat: " .. tostring(guiError))
end
if not HAS_WRITE then
    warn("[MeowX Dump] writefile tidak tersedia: hasil tidak bisa disimpan")
end
setStatus("Siap. Folder hasil: " .. ROOT)
if CONFIG.AutoStartSpy then
    task.spawn(spyStart)
end
