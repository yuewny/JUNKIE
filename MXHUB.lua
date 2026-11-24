if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local Env = (getgenv and getgenv()) or _G

local SDK_URL = "https://jnkie.com/sdk/library.lua"
local GUI_NAME = "MXHubKey"
local KEYLESS = "KEYLESS"
local PLACEHOLDER = "Paste your key here"
local WIDTH, HEIGHT = 480, 252

local MXHUB = {
    Appearance = {
        Title = "MX HUB",
        Subtitle = "KEY SYSTEM",
        Icon = "rbxassetid://105865788976884",
    },
    Links = { Discord = "", Status = "" },
    Storage = { FileName = "MXHUB_Key" },
    Shop = { Enabled = false, Title = "Donate", Link = "" },
}

local Theme = {
    Panel = Color3.fromRGB(21, 21, 23),
    PanelDark = Color3.fromRGB(12, 12, 14),
    Card = Color3.fromRGB(28, 28, 31),
    Stroke = Color3.fromRGB(46, 46, 52),
    StrokeHover = Color3.fromRGB(84, 84, 92),
    Button = Color3.fromRGB(35, 35, 39),
    ButtonHover = Color3.fromRGB(50, 50, 56),
    White = Color3.fromRGB(245, 245, 245),
    Text = Color3.fromRGB(240, 240, 242),
    Muted = Color3.fromRGB(135, 135, 144),
    Green = Color3.fromRGB(86, 204, 124),
    Red = Color3.fromRGB(240, 88, 88),
    Orange = Color3.fromRGB(240, 180, 72),
    Yellow = Color3.fromRGB(250, 214, 70),
}

local Images = {
    Key = "rbxassetid://120178273227579",
    GetKey = "rbxassetid://114756714804603",
    Submit = "rbxassetid://95391166128209",
    Discord = "rbxassetid://127606113874611",
    Donate = "rbxassetid://105962055212659",
    Copy = "rbxassetid://93903059671561",
    Shadow = "rbxassetid://6014261993",
}

local ErrorMessages = {
    KEY_INVALID = "Key not found",
    KEY_EXPIRED = "Key has expired",
    KEY_INVALIDATED = "Key was revoked",
    REVOKED = "Key was revoked",
    HWID_BANNED = "Hardware banned",
    HWID_MISMATCH = "HWID limit reached",
    ALREADY_USED = "Key already redeemed",
    SERVICE_NOT_FOUND = "Service not found",
    SERVICE_MISMATCH = "Wrong service",
    PREMIUM_REQUIRED = "Premium required",
    NETWORK = "Network error",
    ERROR = "Network error",
}

local StatusStyles = {
    ["work"] = { "Work", Theme.Green },
    ["down"] = { "Down", Theme.Red },
    ["need update"] = { "Need Update", Theme.Yellow },
}

local function compile(url)
    local chunk, err = loadstring(game:HttpGet(url))
    if not chunk then
        error(err, 0)
    end
    return chunk
end

local function idle()
    while true do
        task.wait(0.1)
    end
end

local function trimSpaces(text)
    return (text:gsub("%s+", ""))
end

local function escapeRich(value)
    return (tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function colorToRich(color)
    return string.format(
        "rgb(%d,%d,%d)",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

local function copyText(text)
    local setter = setclipboard or toclipboard
    if not setter then
        return false
    end
    return (pcall(setter, text))
end

local function executorName()
    local ok, name = pcall(function()
        return identifyexecutor and identifyexecutor()
    end)
    if ok and name then
        return tostring(name)
    end
    return "unknown"
end

local function readStatus(url)
    if type(url) ~= "string" or url == "" then
        return nil
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if not ok or type(data) ~= "table" then
        return "unknown"
    end
    return data[tostring(game.PlaceId)] or data[tostring(game.CreatorId)] or "unknown"
end

local function create(class, props, parent)
    local object = Instance.new(class)
    for key, value in pairs(props) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(parent, radius)
    return create("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

local function addStroke(parent, color)
    return create("UIStroke", {
        Color = color or Theme.Stroke,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local function tween(object, duration, props, style, direction)
    local info = TweenInfo.new(
        duration,
        style or Enum.EasingStyle.Quint,
        direction or Enum.EasingDirection.Out
    )
    local animation = TweenService:Create(object, info, props)
    animation:Play()
    return animation
end

local function addLabel(parent, text, position, size, color, textSize, font)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        Position = position,
        Size = size,
        Text = text,
        TextColor3 = color,
        TextSize = textSize,
        Font = font or Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end

local function addIcon(parent, image, position, color)
    return create("ImageLabel", {
        Position = position,
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        Image = image,
        ImageColor3 = color,
        ScaleType = Enum.ScaleType.Fit,
    }, parent)
end

local function addDivider(parent, position, size)
    return create("Frame", {
        Position = position,
        Size = size,
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
    }, parent)
end

local function bindHover(button, normal, hover, border)
    local press = create("UIScale", { Scale = 1 }, button)

    button.MouseEnter:Connect(function()
        tween(button, 0.2, { BackgroundColor3 = hover })
        if border then
            tween(border, 0.2, { Color = Theme.StrokeHover })
        end
    end)

    button.MouseLeave:Connect(function()
        tween(button, 0.2, { BackgroundColor3 = normal })
        tween(press, 0.2, { Scale = 1 })
        if border then
            tween(border, 0.2, { Color = Theme.Stroke })
        end
    end)

    button.MouseButton1Down:Connect(function()
        tween(press, 0.08, { Scale = 0.97 })
    end)

    button.MouseButton1Up:Connect(function()
        tween(press, 0.16, { Scale = 1 })
    end)
end

local function mountGui(gui)
    local mounted = pcall(function()
        gui.Parent = gethui()
    end)
    if not mounted or not gui.Parent then
        mounted = pcall(function()
            gui.Parent = CoreGui
        end)
    end
    if not mounted or not gui.Parent then
        gui.Parent = Player:WaitForChild("PlayerGui")
    end
    for _, child in ipairs(gui.Parent:GetChildren()) do
        if child ~= gui and child.Name == GUI_NAME then
            child:Destroy()
        end
    end
end

local function bindViewportScale(gui, scale)
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    local function fit()
        local view = camera.ViewportSize
        local ratio = math.min((view.X - 24) / WIDTH, (view.Y - 24) / HEIGHT)
        scale.Scale = math.clamp(ratio, 0.5, 1)
    end
    fit()
    local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
    gui.Destroying:Connect(function()
        connection:Disconnect()
    end)
end

local function buildHeader(parent, appearance)
    create("ImageLabel", {
        Position = UDim2.fromOffset(20, 14),
        Size = UDim2.fromOffset(36, 32),
        BackgroundTransparency = 1,
        Image = appearance.Icon or "",
        ScaleType = Enum.ScaleType.Fit,
    }, parent)

    local row = create("Frame", {
        Position = UDim2.fromOffset(64, 14),
        Size = UDim2.fromOffset(196, 32),
        BackgroundTransparency = 1,
    }, parent)

    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 9),
    }, row)

    local function title(text, order, color)
        return create("TextLabel", {
            LayoutOrder = order,
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(0, 24),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = text,
            TextColor3 = color or Theme.Text,
            TextSize = 16,
            Font = Enum.Font.GothamBold,
        }, row)
    end

    title(appearance.Title or "MX HUB", 1)
    create("Frame", {
        LayoutOrder = 2,
        Size = UDim2.fromOffset(1, 16),
        BackgroundColor3 = Theme.StrokeHover,
        BorderSizePixel = 0,
    }, row)
    title(appearance.Subtitle or "KEY SYSTEM", 3, Theme.Muted)

    addDivider(parent, UDim2.fromOffset(20, 58), UDim2.fromOffset(224, 1))
end

local function buildKeyField(parent, savedKey)
    addLabel(
        parent,
        "LICENSE KEY",
        UDim2.fromOffset(20, 76),
        UDim2.fromOffset(224, 14),
        Theme.Muted,
        10,
        Enum.Font.GothamBold
    )

    local frame = create("Frame", {
        Position = UDim2.fromOffset(20, 96),
        Size = UDim2.fromOffset(224, 42),
        BackgroundColor3 = Theme.Card,
        BorderSizePixel = 0,
    }, parent)
    addCorner(frame, 8)

    local border = addStroke(frame)
    local keyIcon = addIcon(frame, Images.Key, UDim2.fromOffset(12, 13), Theme.Muted)

    local box = create("TextBox", {
        Position = UDim2.fromOffset(36, 0),
        Size = UDim2.new(1, -46, 1, 0),
        BackgroundTransparency = 1,
        Text = savedKey or "",
        TextColor3 = Theme.Text,
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        PlaceholderText = PLACEHOLDER,
        PlaceholderColor3 = Theme.Muted,
        ClearTextOnFocus = false,
        ClipsDescendants = true,
    }, frame)

    local token = 0

    local function tint(color)
        tween(border, 0.25, { Color = color })
        tween(keyIcon, 0.25, { ImageColor3 = color })
    end

    local function reset()
        box.PlaceholderText = PLACEHOLDER
        box.PlaceholderColor3 = Theme.Muted
        tint(Theme.Stroke)
        tween(keyIcon, 0.25, { ImageColor3 = Theme.Muted })
    end

    local function shake()
        task.spawn(function()
            for _, offset in ipairs({ 5, -5, 3, -3, 1, 0 }) do
                tween(frame, 0.04, { Position = UDim2.fromOffset(20 + offset, 96) }, Enum.EasingStyle.Sine)
                task.wait(0.04)
            end
        end)
    end

    local function message(text, color, autoReset, shouldShake)
        token = token + 1
        local current = token
        box.Text = ""
        box.PlaceholderText = text
        box.PlaceholderColor3 = color
        tint(color)
        if shouldShake then
            shake()
        end
        if autoReset then
            task.delay(1.8, function()
                if token == current and not box:IsFocused() then
                    reset()
                end
            end)
        end
    end

    box.Focused:Connect(function()
        token = token + 1
        box.PlaceholderText = PLACEHOLDER
        box.PlaceholderColor3 = Theme.Muted
        tint(Theme.White)
    end)

    return box, message, function()
        tint(Theme.Stroke)
        tween(keyIcon, 0.25, { ImageColor3 = Theme.Muted })
    end
end

local function buildActionButton(parent, x, text, image)
    local button = create("TextButton", {
        Position = UDim2.fromOffset(x, 170),
        Size = UDim2.fromOffset(108, 40),
        BackgroundColor3 = Theme.Button,
        Text = text,
        TextColor3 = Theme.Text,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,
    }, parent)
    addCorner(button, 8)
    local border = addStroke(button)
    create("UIPadding", { PaddingLeft = UDim.new(0, 20) }, button)
    addIcon(button, image, UDim2.fromOffset(-6, 12), Theme.Text)
    bindHover(button, Theme.Button, Theme.ButtonHover, border)
    return button
end

local function buildGameCard(parent)
    addLabel(
        parent,
        "DETECTED GAME",
        UDim2.fromOffset(16, 16),
        UDim2.fromOffset(150, 14),
        Theme.Muted,
        10,
        Enum.Font.GothamBold
    )

    local card = create("Frame", {
        Position = UDim2.fromOffset(16, 34),
        Size = UDim2.fromOffset(183, 50),
        BackgroundColor3 = Theme.Card,
        BorderSizePixel = 0,
    }, parent)
    addCorner(card, 8)
    addStroke(card)

    local thumb = create("ImageLabel", {
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150",
    }, card)
    addCorner(thumb, 6)
    addStroke(thumb)

    local name = addLabel(
        card,
        "Loading...",
        UDim2.fromOffset(50, 10),
        UDim2.fromOffset(126, 14),
        Theme.Text,
        12,
        Enum.Font.GothamBold
    )
    addLabel(
        card,
        tostring(game.PlaceId),
        UDim2.fromOffset(50, 27),
        UDim2.fromOffset(126, 12),
        Theme.Muted,
        10
    )

    task.spawn(function()
        local ok, info = pcall(function()
            return MarketplaceService:GetProductInfo(game.PlaceId)
        end)
        name.Text = (ok and info and info.Name) or "Unknown game"
    end)
end

local function buildInfoRow(parent, y, key, value, color)
    local row = addLabel(
        parent,
        "",
        UDim2.fromOffset(16, y),
        UDim2.fromOffset(183, 14),
        Theme.Muted,
        11
    )
    row.RichText = true
    row.Text = string.format(
        '%s <font color="%s"><b>%s</b></font>',
        key,
        colorToRich(color),
        escapeRich(value)
    )
end

local function resolveStatusStyle(status)
    if type(status) ~= "string" then
        return { "Unknown", Theme.Muted }
    end
    local key = status:lower():gsub("[_%-]", " "):gsub("%s+", " ")
    return StatusStyles[key] or { "Unknown", Theme.Muted }
end

local function buildLinkCard(parent, y, title, link, image)
    local card = create("Frame", {
        Position = UDim2.fromOffset(16, y),
        Size = UDim2.fromOffset(183, 38),
        BackgroundColor3 = Theme.Card,
        BorderSizePixel = 0,
    }, parent)
    addCorner(card, 8)
    addStroke(card)
    addIcon(card, image, UDim2.fromOffset(12, 11), Theme.Text)

    local name = addLabel(
        card,
        title,
        UDim2.fromOffset(36, 12),
        UDim2.fromOffset(104, 14),
        Theme.Text,
        12,
        Enum.Font.GothamBold
    )

    local button = create("TextButton", {
        Position = UDim2.fromOffset(149, 6),
        Size = UDim2.fromOffset(26, 26),
        BackgroundColor3 = Theme.Button,
        Text = "",
        AutoButtonColor = false,
    }, card)
    addCorner(button, 6)
    local border = addStroke(button)
    addIcon(button, Images.Copy, UDim2.fromOffset(5, 5), Theme.Text)
    bindHover(button, Theme.Button, Theme.ButtonHover, border)

    local token = 0
    button.Activated:Connect(function()
        token = token + 1
        local current = token

        if copyText(link) then
            name.Text = "Copied!"
            tween(name, 0.2, { TextColor3 = Theme.Green })
        else
            name.Text = "Copy failed"
            tween(name, 0.2, { TextColor3 = Theme.Orange })
        end

        task.delay(1.6, function()
            if token == current then
                name.Text = title
                tween(name, 0.3, { TextColor3 = Theme.Text })
            end
        end)
    end)
end

local function buildInfoPanel(parent, hub, state)
    buildGameCard(parent)

    buildInfoRow(parent, 94, "EXECUTOR :", state.executor, Theme.Text)
    if state.status ~= nil then
        local style = resolveStatusStyle(state.status)
        buildInfoRow(parent, 112, "SCRIPT STATUS :", style[1], style[2])
    end

    addDivider(parent, UDim2.fromOffset(16, 140), UDim2.fromOffset(183, 1))

    local y = 152
    local discord = hub.Links.Discord
    if type(discord) == "string" and discord ~= "" then
        buildLinkCard(parent, y, "Discord", discord, Images.Discord)
        y = y + 42
    end

    local shop = hub.Shop
    if type(shop) == "table" and shop.Enabled and type(shop.Link) == "string" and shop.Link ~= "" then
        buildLinkCard(parent, y, shop.Title or "Donate", shop.Link, Images.Donate)
    end
end

local function showUI(hub, state)
    local finished = false

    local gui = create("ScreenGui", {
        Name = GUI_NAME,
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    mountGui(gui)

    local root = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(WIDTH, HEIGHT),
        BackgroundTransparency = 1,
    }, gui)
    bindViewportScale(gui, create("UIScale", {}, root))

    local shadow = create("ImageLabel", {
        Position = UDim2.new(0, -25, 0, -25),
        Size = UDim2.new(1, 50, 1, 50),
        BackgroundTransparency = 1,
        Image = Images.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
    }, root)

    local main = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, root)
    addCorner(main, 12)
    addStroke(main)
    create("UIGradient", {
        Color = ColorSequence.new(Theme.Panel, Theme.PanelDark),
        Rotation = 90,
    }, main)
    local mainScale = create("UIScale", { Scale = 0.95 }, main)

    local left = create("Frame", {
        Size = UDim2.fromOffset(264, HEIGHT),
        BackgroundTransparency = 1,
    }, main)
    buildHeader(left, hub.Appearance)

    local box, message, releaseField = buildKeyField(left, state.saved)
    local submit = buildActionButton(left, 20, "Submit", Images.Submit)
    local getKey = buildActionButton(left, 136, "Get a key", Images.GetKey)

    create("Frame", {
        Position = UDim2.fromOffset(264, 16),
        Size = UDim2.new(0, 1, 1, -32),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
    }, main)

    local right = create("Frame", {
        Position = UDim2.fromOffset(265, 0),
        Size = UDim2.fromOffset(215, HEIGHT),
        BackgroundTransparency = 1,
    }, main)
    buildInfoPanel(right, hub, state)

    local fetching = false
    getKey.Activated:Connect(function()
        if fetching then
            return
        end
        fetching = true
        message("Getting key link...", Theme.Muted, false, false)

        task.spawn(function()
            task.wait(0.35)
            local ok, link = pcall(state.junkie.get_key_link)
            if not ok or type(link) ~= "string" or link == "" then
                message("Failed to get key link", Theme.Red, true, true)
            elseif copyText(link) then
                message("Key link copied", Theme.Green, true, false)
            else
                message(link, Theme.Orange, true, false)
            end
            fetching = false
        end)
    end)

    local busy = false
    local function submitKey()
        if busy then
            return
        end

        local key = trimSpaces(box.Text)
        if key == "" then
            message("Key required", Theme.Orange, true, true)
            return
        end

        busy = true
        message("Checking key...", Theme.Muted, false, false)

        local valid, text = state.check(key)
        if not valid then
            message(text, Theme.Red, true, true)
            busy = false
            return
        end

        state.accept(key)
        message(text, Theme.Green, false, false)
        task.wait(0.7)
        tween(shadow, 0.3, { ImageTransparency = 1 })
        tween(mainScale, 0.3, { Scale = 0.9 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
        task.wait(0.32)
        finished = true
        gui:Destroy()
    end

    submit.Activated:Connect(submitKey)
    box.FocusLost:Connect(function(enterPressed)
        releaseField()
        if enterPressed then
            submitKey()
        end
    end)

    tween(shadow, 0.5, { ImageTransparency = 0.6 })
    tween(mainScale, 0.45, { Scale = 1 })

    while not finished and gui.Parent do
        task.wait(0.1)
    end
    return finished
end

function MXHUB:LaunchJunkie(config)
    assert(
        type(config) == "table" and config.Service and config.Identifier and config.Provider,
        "LaunchJunkie requires Service, Identifier and Provider"
    )

    local status = readStatus(self.Links and self.Links.Status)

    Env.SakuraUILoaded = true
    Env.SakuraClosed = false

    local loaded, junkie = pcall(function()
        return compile(SDK_URL)()
    end)
    if not loaded or type(junkie) ~= "table" then
        warn("[MXHUB] failed to load Junkie SDK")
        return idle()
    end

    junkie.service = config.Service
    junkie.identifier = config.Identifier
    junkie.provider = config.Provider

    local fileName = tostring((self.Storage and self.Storage.FileName) or "MXHUB_Key") .. ".txt"

    local function check(key)
        local called, result = pcall(junkie.check_key, key)
        if not called then
            return false, "Network error"
        end
        if type(result) == "boolean" then
            return result, result and "Key valid" or "Invalid key"
        end
        if type(result) ~= "table" then
            return false, "Invalid verification response"
        end
        if result.valid == true then
            return true, "Key valid"
        end

        local code = tostring(result.error or "")
        if code == "HWID_BANNED" then
            task.delay(2, function()
                pcall(Player.Kick, Player, "Hardware banned")
            end)
        end
        return false, ErrorMessages[code] or result.message or (code ~= "" and code) or "Invalid key"
    end

    local function accept(key)
        Env.SCRIPT_KEY = key
        Env.SakuraUILoaded = false
        if key ~= KEYLESS then
            pcall(function()
                if writefile then
                    writefile(fileName, key)
                end
            end)
        end
    end

    local preset = Env.SCRIPT_KEY
    if type(preset) == "string" and preset ~= "" and preset ~= KEYLESS and check(preset) then
        accept(preset)
        return true
    end

    local called, keyless = pcall(junkie.check_key, KEYLESS)
    if called and type(keyless) == "table" and keyless.valid == true then
        Env.SCRIPT_KEY = KEYLESS
        Env.SakuraUILoaded = false
        return true
    end

    local saved
    pcall(function()
        if isfile and readfile and isfile(fileName) then
            saved = trimSpaces(readfile(fileName))
        end
    end)
    if type(saved) == "string" and saved ~= "" and check(saved) then
        accept(saved)
        return true
    end

    local shown = showUI(self, {
        saved = saved,
        executor = executorName(),
        status = status,
        junkie = junkie,
        check = check,
        accept = accept,
    })
    if not shown then
        Env.SakuraClosed = true
        return idle()
    end
    return true
end

return MXHUB
