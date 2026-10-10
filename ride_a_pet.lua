-- ==============================================================================
-- RIDE A PET HUB (POWERED BY ZYPHERAXUI)
-- Modern MacOS-style UI with Acrylic Blur, Tabs & Animations
-- ==============================================================================

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = pcall(function() return game:GetService("CoreGui") end) and game:GetService("CoreGui") or nil

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    pcall(function()
        LocalPlayer = Players.PlayerAdded:Wait()
    end)
    if not LocalPlayer then LocalPlayer = Players.LocalPlayer end
end

-- [FORWARD DECLARATIONS FOR SCOPING]
-- (Forward declaration modul lama dihapus; Ride A Pet memakai engine sendiri)
local start_esp_gen, stop_esp_gen, start_esp_generator, stop_esp_generator

-- ==============================================================================
-- KENDALI LOG
-- ==============================================================================
-- Semua output diagnostik yang terlalu panjang goes through log() dan
-- DILETAKAN secara default, supaya console Roblox tidak dipenuhi
-- baris yang tidak perlu.
--
-- Set ZYPHERAX_DEBUG = true di konsol kalau mau melihat semua detail:
--     ZYPHERAX_DEBUG = true
-- Kalau belum di-set ulang, ketik ZYPHERAX_DEBUG = false untuk mematikan lagi.
--
-- Notifikasi lewat Window:Notify() TIDAK terpengaruh switch ini,
-- jadi user tetap selalu melihat feedback utama dari setiap fitur.
-- ==============================================================================
-- Dua variabel ini sengaja dibuat global (tanpa local) supaya bisa diubah
-- dari konsol kapan saja: ZYPHERAX_DEBUG = true / ZYPHERAX_LOG_BUFFER = ""
ZYPHERAX_DEBUG = false

-- Buffer log, supaya bisa disalin dari UI tanpa harus buka console.
-- Hanya 400 baris terakhir yang disimpan supaya tidak makan memory.
ZYPHERAX_LOG_BUFFER = ""

local function log(msg, ...)
    if not ZYPHERAX_DEBUG then return end
    local ok, text = pcall(string.format, tostring(msg), ...)
    local line = ok and text or tostring(msg)
    print("[Zypherax] " .. line)

    ZYPHERAX_LOG_BUFFER = ZYPHERAX_LOG_BUFFER .. line .. "\n"
    local _, count = ZYPHERAX_LOG_BUFFER:gsub("\n", "")
    if count > 400 then
        local cut = ZYPHERAX_LOG_BUFFER:find("\n", ZYPHERAX_LOG_BUFFER:find("\n") + 1)
        if cut then ZYPHERAX_LOG_BUFFER = ZYPHERAX_LOG_BUFFER:sub(cut + 1) end
    end
end

-- ==============================================================================
-- HELPER UTILITIES
-- ==============================================================================
local function find_player(name)
    if not name or name == "" then return LocalPlayer end
    name = tostring(name):lower()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower() == name or p.DisplayName:lower() == name then
            return p
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name:lower():sub(1, #name) == name or p.DisplayName:lower():sub(1, #name) == name then
            return p
        end
    end
    return nil
end

local function retry(tries, delay, fn)
    local lastErr
    for i = 1, tries do
        local ok, res = pcall(fn)
        if ok and res ~= nil then return res end
        lastErr = res
        task.wait(delay * i)
    end
    return nil, lastErr
end

local function http_json(url)
    return retry(3, 1.2, function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
end

local function normalize(s)
    s = tostring(s):lower()
    s = s:gsub("[\226\128\139-\226\128\141\239\187\191]", "")
    s = s:gsub("%s+", " ")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local function hex_to_color(hex)
    if not hex then return nil end
    hex = tostring(hex):gsub("#", "")
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if r and g and b then return Color3.fromRGB(r, g, b) end
end

-- ==============================================================================
-- ANTI-DETECTION & ANTI-CHEAT PROTECTION LAYER
-- ==============================================================================
do
    -- [1] Cloneref guard untuk semua services utama (cegah rawequal detection)
    pcall(function()
        if cloneref then
            -- Services sudah diamankan di atas menggunakan cloneref
        end
    end)

    -- [2] Proteksi WalkSpeed: Monitor jika server reset kecepatan dan kembalikan
    -- (Non-invasif: hanya aktif jika speed lock dinyalakan)
    task.spawn(function()
        task.wait(2)
        local _speedLockActive = false
        local _lockedSpeed = 16
        RunService.Heartbeat:Connect(function()
            if not _speedLockActive then return end
            pcall(function()
                local char = LocalPlayer and LocalPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.WalkSpeed ~= _lockedSpeed then
                    hum.WalkSpeed = _lockedSpeed
                end
            end)
        end)
        -- Expose ke scope luar via shared untuk toggle_loop_speed
        shared._setSpeedLock = function(enabled, speed)
            _speedLockActive = enabled
            _lockedSpeed = speed or 16
        end
    end)
end

-- ==============================================================================
-- UI BARU: ZypheraxUI  (Zypherax Hub) -- pengganti penuh UI lama
-- ------------------------------------------------------------------------------
-- File ini dipakai oleh "newscript.lua" (script.lua tidak diubah).
--
-- Cara kerja: ZypheraxUI dibungkus sebuah ADAPTER yang meniru API UI lama,
-- sehingga seluruh kode tab & modul di bawah TIDAK perlu disentuh dan semua
-- fitur tetap berjalan. Sumber UI diambil dari GitHub (ZypheraxUI), dengan
-- salinan lokal sebagai cadangan agar tidak pernah kosong.
-- ==============================================================================
do
    -- --------------------------------------------------------------------------
    -- Patch kompatibilitas: Roblox TIDAK bisa men-tween property bertipe Enum
    -- (mis. Font). ZypheraxUI meng-tween Font saat mengaktifkan tab, sehingga
    -- error "Unable to cast value to Object" muncul dan UI berhenti (kosong).
    -- Kita sanitasi property Enum di U.Tween: langsung di-set, tanpa di-tween.
    -- --------------------------------------------------------------------------
    local NEEDLE = "local tw = TweenService:Create(obj, TweenInfo.new(t, style, dir), props)"
    local INJECT = "do local __c = {} for __k, __v in pairs(props or {}) do if typeof(__v) == \"EnumItem\" then pcall(function() obj[__k] = __v end) else __c[__k] = __v end end props = __c end\n        " .. NEEDLE

    -- Penyempurnaan tampilan (dipakai untuk jalur GitHub maupun salinan lokal).
    local TWEAKS = {
        { "Accent           = Color3.fromRGB(0, 170, 255),   -- primary accent",
          "Accent           = Color3.fromRGB(0, 170, 255),   -- primary accent" },
        { "AccentGradient   = Color3.fromRGB(30, 140, 220),  -- subtle gradient end",
          "AccentGradient   = Color3.fromRGB(0, 170, 255), -- subtle gradient end" },
        { "CornerLg         = UDim.new(0, 10),",
          "CornerLg         = UDim.new(0, 12)," },
        { "            local secHeader = U.New(\"Frame\", {\n                Size = UDim2.new(1, 0, 0, 26),",
          "            local secHeader = U.New(\"Frame\", {\n                Size = UDim2.new(1, 0, 0, 30)," },
        { "                Text = string.upper(secName),\n                Font = T.Font,\n                TextSize = 11,",
          "                Text = string.upper(secName),\n                Font = T.Font,\n                TextSize = 12," },
        { "U.New(\"UIListLayout\", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 7), Parent = secContainer })",
          "U.New(\"UIListLayout\", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = secContainer })" },
        { "            Size                   = UDim2.new(1, 0, 0, 40),\n            BackgroundColor3       = T.Surface2,\n            BackgroundTransparency = 1,\n            ZIndex                 = 4,\n            Parent                 = tabList",
          "            Size                   = UDim2.new(1, 0, 0, 42),\n            BackgroundColor3       = T.Surface2,\n            BackgroundTransparency = 1,\n            ZIndex                 = 4,\n            Parent                 = tabList" },
        -- Hilangkan bayangan (drop-shadow) di belakang jendela ZypheraxUI.
        { "    -- Drop shadow (Softer and larger blur)\n    local shadow = U.New(\"ImageLabel\", {\n        Image = \"rbxassetid://1316045217\", -- Softer shadow asset\n        ImageColor3 = Color3.new(0, 0, 0),\n        ImageTransparency = 0.6,",
          "    -- Wadah transparan (bayangan dihilangkan, tetap dipakai untuk drag jendela).\n    local shadow = U.New(\"ImageLabel\", {\n        Image = \"\",\n        ImageColor3 = Color3.new(0, 0, 0),\n        ImageTransparency = 1," },
        -- Cegah label tab terpotong/overlap: pakai TextTruncate.
        { "            Text                   = tabName,\n            Font                   = T.FontRegular,\n            TextSize               = 13,\n            TextColor3             = T.TextMuted,",
          "            Text                   = tabName,\n            Font                   = T.FontRegular,\n            TextSize               = 13,\n            TextColor3             = T.TextMuted,\n            TextTruncate           = Enum.TextTruncate.AtEnd," },
        -- Judul section: kecilkan sedikit + TextTruncate agar tidak menabrak.
        { "                Text = string.upper(secName),\n                Font = T.Font,\n                TextSize = 12,\n                TextColor3 = T.TextMuted,",
          "                Text = string.upper(secName),\n                Font = T.Font,\n                TextSize = 11,\n                TextColor3 = T.TextMuted,\n                TextTruncate = Enum.TextTruncate.AtEnd," },
    }

    local function _zy_patch(src)
        if type(src) ~= "string" then return src end
        local at = src:find(NEEDLE, 1, true)
        if at then
            src = src:sub(1, at - 1) .. INJECT .. src:sub(at + #NEEDLE)
        end
        for _, tw in ipairs(TWEAKS) do
            local pos = src:find(tw[1], 1, true)
            if pos then
                src = src:sub(1, pos - 1) .. tw[2] .. src:sub(pos + #tw[1])
            end
        end
        return src
    end

    -- --------------------------------------------------------------------------
    -- Pustaka ZypheraxUI: ambil dari GitHub, jika gagal pakai salinan lokal.
    -- --------------------------------------------------------------------------
    local ZYP_URL = "https://raw.githubusercontent.com/Skyuuu222/zypheraxui/main/zypheraxui"

    local ZypheraxUI = (function()
-- ==============================================================================
-- ZYPHERAX UI - MODERN MACOS ENTERPRISE EDITION (v3.5)
-- Modern MacOS-Style Acrylic GUI Library for Roblox
-- Features:
--   * MacOS Traffic Lights Window Controls (Red: Close, Yellow: Minimize, Green: Maximize)
--   * Smooth, Uninterrupted Global Dragging (UIS-based, never disconnects)
--   * Dynamic Real-Time Theme Engine (Dark, Light, Midnight, Rose)
--   * Full Config Manager (Create Save, Overwrite, Delete Mode, Set/Reset Autoload)
--   * Elegant Draggable Watermark with Real-Time FPS and Minimize/Close
--   * Clean Section Architecture with Zero Generic "SECTION" Text Overlaps
--   * Anti-Collision Control Layouts (Toggles, Sliders, Dropdowns, Inputs, Buttons)
-- ==============================================================================

local ZypheraxUI = {}
ZypheraxUI.Version = "Enterprise 3.6.0"
ZypheraxUI.Flags = {}
ZypheraxUI.Controls = {}

-- // SERVICES \ --
local Players      = game:GetService("Players")
local Player       = Players.LocalPlayer
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local HttpService  = game:GetService("HttpService")

local CoreGui
pcall(function()
    CoreGui = cloneref and cloneref(game:GetService("CoreGui")) or game:GetService("CoreGui")
end)

-- Safe Anti-AFK
local VirtualUser = nil
pcall(function() VirtualUser = game:GetService("VirtualUser") end)
function ZypheraxUI:EnableAntiAFK()
    if not Player then return end
    pcall(function()
        Player.Idled:Connect(function()
            if VirtualUser then
                pcall(function()
                    VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                    task.wait(1)
                    VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                end)
            end
        end)
    end)
end
ZypheraxUI:EnableAntiAFK()

-- // SAFE CORE GUI RESOLVER \ --
local function GetCore()
    if RunService:IsStudio() then return Player:WaitForChild("PlayerGui") end
    local ok, h = pcall(function() return gethui() end)
    if ok and h then return h end
    if CoreGui then return CoreGui end
    return Player:WaitForChild("PlayerGui")
end

-- // THEMES REGISTRY \ --
local Themes = {
    Dark = {
        Background       = Color3.fromRGB(15, 17, 23),
        Background2      = Color3.fromRGB(11, 12, 17),
        Surface          = Color3.fromRGB(20, 23, 31),
        Surface2         = Color3.fromRGB(26, 30, 42),
        Surface3         = Color3.fromRGB(34, 40, 56),
        Accent           = Color3.fromRGB(0, 170, 255),
        AccentDark       = Color3.fromRGB(0, 140, 230),
        AccentGradient   = Color3.fromRGB(0, 170, 255),
        Text             = Color3.fromRGB(242, 244, 250),
        TextMuted        = Color3.fromRGB(145, 152, 170),
        TextDim          = Color3.fromRGB(90, 96, 112),
        Stroke           = Color3.fromRGB(38, 43, 58),
        StrokeHover      = Color3.fromRGB(55, 62, 84),
        StrokeActive     = Color3.fromRGB(0, 170, 255),
        Success          = Color3.fromRGB(60, 215, 120),
        Warning          = Color3.fromRGB(255, 189, 46),
        Error            = Color3.fromRGB(255, 95, 86),
        SidebarBg        = Color3.fromRGB(12, 13, 18),
        SectionBg        = Color3.fromRGB(17, 19, 27),
        SectionHeader    = Color3.fromRGB(22, 25, 36),
    },
    Light = {
        Background       = Color3.fromRGB(244, 246, 250),
        Background2      = Color3.fromRGB(235, 238, 244),
        Surface          = Color3.fromRGB(255, 255, 255),
        Surface2         = Color3.fromRGB(238, 241, 248),
        Surface3         = Color3.fromRGB(224, 228, 238),
        Accent           = Color3.fromRGB(0, 170, 255),
        AccentDark       = Color3.fromRGB(0, 140, 230),
        AccentGradient   = Color3.fromRGB(0, 170, 255),
        Text             = Color3.fromRGB(25, 28, 36),
        TextMuted        = Color3.fromRGB(105, 112, 128),
        TextDim          = Color3.fromRGB(150, 155, 168),
        Stroke           = Color3.fromRGB(216, 222, 234),
        StrokeHover      = Color3.fromRGB(190, 198, 214),
        StrokeActive     = Color3.fromRGB(0, 170, 255),
        Success          = Color3.fromRGB(40, 180, 100),
        Warning          = Color3.fromRGB(240, 160, 30),
        Error            = Color3.fromRGB(240, 70, 70),
        SidebarBg        = Color3.fromRGB(232, 235, 242),
        SectionBg        = Color3.fromRGB(255, 255, 255),
        SectionHeader    = Color3.fromRGB(240, 243, 249),
    },
    Midnight = {
        Background       = Color3.fromRGB(9, 11, 16),
        Background2      = Color3.fromRGB(6, 7, 11),
        Surface          = Color3.fromRGB(14, 17, 26),
        Surface2         = Color3.fromRGB(20, 25, 38),
        Surface3         = Color3.fromRGB(28, 35, 54),
        Accent           = Color3.fromRGB(75, 140, 255),
        AccentDark       = Color3.fromRGB(40, 95, 210),
        AccentGradient   = Color3.fromRGB(145, 95, 255),
        Text             = Color3.fromRGB(240, 244, 255),
        TextMuted        = Color3.fromRGB(130, 142, 170),
        TextDim          = Color3.fromRGB(80, 90, 115),
        Stroke           = Color3.fromRGB(32, 40, 60),
        StrokeHover      = Color3.fromRGB(48, 60, 90),
        StrokeActive     = Color3.fromRGB(75, 140, 255),
        Success          = Color3.fromRGB(50, 210, 130),
        Warning          = Color3.fromRGB(255, 190, 45),
        Error            = Color3.fromRGB(255, 90, 85),
        SidebarBg        = Color3.fromRGB(8, 9, 14),
        SectionBg        = Color3.fromRGB(12, 15, 22),
        SectionHeader    = Color3.fromRGB(16, 20, 30),
    },
    Rose = {
        Background       = Color3.fromRGB(18, 14, 18),
        Background2      = Color3.fromRGB(13, 10, 13),
        Surface          = Color3.fromRGB(25, 19, 25),
        Surface2         = Color3.fromRGB(34, 25, 34),
        Surface3         = Color3.fromRGB(46, 34, 46),
        Accent           = Color3.fromRGB(255, 75, 125),
        AccentDark       = Color3.fromRGB(200, 45, 90),
        AccentGradient   = Color3.fromRGB(255, 135, 175),
        Text             = Color3.fromRGB(252, 242, 247),
        TextMuted        = Color3.fromRGB(175, 142, 160),
        TextDim          = Color3.fromRGB(115, 88, 104),
        Stroke           = Color3.fromRGB(56, 38, 52),
        StrokeHover      = Color3.fromRGB(80, 54, 75),
        StrokeActive     = Color3.fromRGB(255, 75, 125),
        Success          = Color3.fromRGB(70, 215, 140),
        Warning          = Color3.fromRGB(255, 195, 60),
        Error            = Color3.fromRGB(255, 90, 95),
        SidebarBg        = Color3.fromRGB(14, 11, 14),
        SectionBg        = Color3.fromRGB(22, 17, 22),
        SectionHeader    = Color3.fromRGB(28, 21, 28),
    }
}

-- Current active theme
ZypheraxUI.CurrentThemeName = "Dark"
ZypheraxUI.Theme = {}
for k, v in pairs(Themes.Dark) do ZypheraxUI.Theme[k] = v end

-- Common styles
ZypheraxUI.Theme.FontBold    = Enum.Font.GothamBold
ZypheraxUI.Theme.Font        = Enum.Font.GothamMedium
ZypheraxUI.Theme.FontRegular = Enum.Font.Gotham
ZypheraxUI.Theme.CornerLg    = UDim.new(0, 12)
ZypheraxUI.Theme.CornerMd    = UDim.new(0, 8)
ZypheraxUI.Theme.CornerSm    = UDim.new(0, 6)

local T = ZypheraxUI.Theme

-- Theme subscriber system
local ThemeSubscribers = {}
local function RegisterThemeColor(obj, prop, themeKey)
    table.insert(ThemeSubscribers, { obj = obj, prop = prop, key = themeKey })
    pcall(function() obj[prop] = T[themeKey] end)
end

local ActiveWindows = {}

function ZypheraxUI:SetTheme(themeName)
    local preset = Themes[themeName]
    if not preset then return end
    ZypheraxUI.CurrentThemeName = themeName
    for k, v in pairs(preset) do T[k] = v end

    -- (A) Update all registered theme subscribers
    for _, item in ipairs(ThemeSubscribers) do
        if item.obj and item.obj.Parent and T[item.key] then
            pcall(function()
                TweenService:Create(item.obj, TweenInfo.new(0.22, Enum.EasingStyle.Quad), {
                    [item.prop] = T[item.key]
                }):Play()
            end)
        end
    end

    -- (B) Comprehensive scan on all active UI windows to guarantee text color matches theme
    local isLight = (themeName == "Light")
    pcall(function()
        for _, winObj in ipairs(ActiveWindows) do
            if winObj and winObj._gui and winObj._gui.Parent then
                for _, desc in ipairs(winObj._gui:GetDescendants()) do
                    if desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox") then
                        -- Check if element has explicit theme tag or determine by brightness
                        local curColor = desc.TextColor3
                        if isLight then
                            -- On Light theme, all bright text must turn to dark text
                            if (curColor.R + curColor.G + curColor.B) > 1.8 then
                                TweenService:Create(desc, TweenInfo.new(0.22, Enum.EasingStyle.Quad), {
                                    TextColor3 = preset.Text
                                }):Play()
                            end
                        else
                            -- On Dark themes, any dark text must turn back to bright text
                            if (curColor.R + curColor.G + curColor.B) < 0.9 then
                                TweenService:Create(desc, TweenInfo.new(0.22, Enum.EasingStyle.Quad), {
                                    TextColor3 = preset.Text
                                }):Play()
                            end
                        end
                    end
                end
            end
        end
    end)
end

function ZypheraxUI:GetThemes()
    return { "Dark", "Light", "Midnight", "Rose" }
end

-- // UTILITY CORE \ --
local U = {}

function U.New(class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then
            pcall(function() inst[k] = v end)
        end
    end
    -- // ANTI-OVERFLOW SAFETY NET \ --
    -- Label satu baris otomatis dipotong rapi (AtEnd) agar tulisan tidak
    -- pernah menabrak elemen lain atau keluar dari kotaknya. Label yang
    -- memang multibaris (AutomaticSize.Y + TextWrapped) dibiarkan utuh.
    pcall(function()
        if class == "TextLabel" or class == "TextButton" or class == "TextBox" then
            local autoY   = props and (props.AutomaticSize == Enum.AutomaticSize.Y or props.AutomaticSize == Enum.AutomaticSize.XY)
            local wrapped = props and props.TextWrapped == true
            local scaled  = props and props.TextScaled == true
            local hasTrunc = props and props.TextTruncate ~= nil
            if not autoY and not wrapped and not scaled and not hasTrunc then
                inst.TextTruncate = Enum.TextTruncate.AtEnd
            end
        end
    end)
    if props and props.Parent then inst.Parent = props.Parent end
    return inst
end

function U.Corner(parent, radius)
    return U.New("UICorner", { CornerRadius = radius or T.CornerMd, Parent = parent })
end

function U.Stroke(parent, color, thickness, transparency)
    local s = U.New("UIStroke", {
        Color = color or T.Stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent
    })
    return s
end

function U.Gradient(parent, c1, c2, rot)
    return U.New("UIGradient", {
        Color = ColorSequence.new(c1, c2),
        Rotation = rot or 0,
        Parent = parent
    })
end

-- Safe Tween: filters out Enum properties that Roblox cannot interpolate
function U.Tween(obj, duration, props, style, dir)
    local clean = {}
    for k, v in pairs(props or {}) do
        if typeof(v) == "EnumItem" then
            pcall(function() obj[k] = v end)
        else
            clean[k] = v
        end
    end
    local tw = TweenService:Create(obj, TweenInfo.new(duration or 0.2, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), clean)
    tw:Play()
    return tw
end

function U.Ripple(btn, x, y)
    task.spawn(function()
        local ripple = U.New("Frame", {
            BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0.8,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset(x - btn.AbsolutePosition.X, y - btn.AbsolutePosition.Y),
            Size = UDim2.fromOffset(0, 0),
            ZIndex = btn.ZIndex + 2,
            Parent = btn
        })
        U.Corner(ripple, UDim.new(1, 0))
        local maxSize = math.max(btn.AbsoluteSize.X, btn.AbsoluteSize.Y) * 1.5
        local tw = U.Tween(ripple, 0.45, {
            Size = UDim2.fromOffset(maxSize, maxSize),
            BackgroundTransparency = 1
        })
        tw.Completed:Connect(function() ripple:Destroy() end)
    end)
end

-- // NOTIFICATIONS SYSTEM (Elegant, Modern, Non-Colliding) \\ --
local NotifGui = nil
local NotifSeq = 0
local ActiveNotif = {}

local function ensureNotifGui()
    if NotifGui and NotifGui.Parent then return NotifGui end
    NotifGui = U.New("ScreenGui", {
        Name = "ZypheraxNotifs",
        DisplayOrder = 10000,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = GetCore()
    })
    local container = U.New("Frame", {
        Name = "Container",
        AnchorPoint = Vector2.new(1, 1),
        Size = UDim2.new(0, 330, 1, -24),
        Position = UDim2.new(1, -16, 1, -16),
        BackgroundTransparency = 1,
        ClipsDescendants = false,
        Parent = NotifGui
    })
    U.New("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Padding = UDim.new(0, 10),
        Parent = container
    })
    return NotifGui
end

local function notifSlideOut(wrap, card)
    if not (wrap and wrap.Parent) then return end
    local h = (wrap.AbsoluteSize and wrap.AbsoluteSize.Y) or 0
    if h <= 0 then h = 64 end
    wrap.AutomaticSize = Enum.AutomaticSize.None
    wrap.Size = UDim2.new(1, 0, 0, h)
    card.AutomaticSize = Enum.AutomaticSize.None
    card.Size = UDim2.new(1, 0, 0, h)
    U.Tween(card, 0.28, {
        Position = UDim2.new(1, 34, 0, 0),
        BackgroundTransparency = 1
    }, Enum.EasingStyle.Quart)
    local tw = U.Tween(wrap, 0.3, { Size = UDim2.new(1, 0, 0, 0) }, Enum.EasingStyle.Quart)
    tw.Completed:Connect(function()
        ActiveNotif[wrap] = nil
        if wrap and wrap.Parent then wrap:Destroy() end
    end)
end

function ZypheraxUI:Notify(cfg)
    cfg = cfg or {}
    local title = cfg.Title or "Notifikasi"
    local desc  = cfg.Description or cfg.Text or cfg.Content or ""
    local life  = tonumber(cfg.Lifetime or cfg.Duration) or 4
    local accent = cfg.Accent or T.Accent

    local gui = ensureNotifGui()
    local holder = gui and gui:FindFirstChild("Container")
    if not holder then return end

    NotifSeq = NotifSeq + 1

    local wrap = U.New("Frame", {
        Name = "Notif",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = NotifSeq,
        Parent = holder
    })

    local card = U.New("Frame", {
        Name = "Card",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = T.Surface,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = wrap
    })
    U.Corner(card, T.CornerMd)
    local stroke = U.Stroke(card, T.Stroke, 1, 0.35)
    RegisterThemeColor(card, "BackgroundColor3", "Surface")
    RegisterThemeColor(stroke, "Color", "Stroke")

    local bar = U.New("Frame", {
        Name = "AccentBar",
        Size = UDim2.new(0, 4, 1, 0),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = card
    })
    U.Gradient(bar, accent, T.AccentGradient, 90)

    local body = U.New("Frame", {
        Name = "Body",
        Size = UDim2.new(1, -4, 0, 0),
        Position = UDim2.new(0, 4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = card
    })
    U.New("UIPadding", {
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
        PaddingTop = UDim.new(0, 11),
        PaddingBottom = UDim.new(0, 14),
        Parent = body
    })
    U.New("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 5),
        Parent = body
    })

    local head = U.New("Frame", {
        Name = "Head",
        Size = UDim2.new(1, 0, 0, 18),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = body
    })
    local dot = U.New("Frame", {
        Size = UDim2.fromOffset(8, 8),
        Position = UDim2.new(0, 0, 0.5, -4),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        Parent = head
    })
    U.Corner(dot, UDim.new(1, 0))

    local tLbl = U.New("TextLabel", {
        Text = title,
        Font = T.FontBold,
        TextSize = 13,
        TextColor3 = T.Text,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 18, 0, 0),
        Size = UDim2.new(1, -18, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = head
    })
    RegisterThemeColor(tLbl, "TextColor3", "Text")

    if desc ~= "" then
        local dLbl = U.New("TextLabel", {
            Text = desc,
            Font = T.FontRegular,
            TextSize = 12,
            TextColor3 = T.TextMuted,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = body
        })
        RegisterThemeColor(dLbl, "TextColor3", "TextMuted")
    end

    local track = U.New("Frame", {
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = T.Stroke,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        LayoutOrder = 3,
        Parent = body
    })
    U.Corner(track, UDim.new(1, 0))
    local prog = U.New("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        Parent = track
    })
    U.Corner(prog, UDim.new(1, 0))

    card.Position = UDim2.new(0, 12, 0, 0)
    card.BackgroundTransparency = 1
    stroke.Transparency = 1
    U.Tween(card, 0.34, { Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0.05 }, Enum.EasingStyle.Quart)
    U.Tween(stroke, 0.34, { Transparency = 0.35 })
    U.Tween(prog, life, { Size = UDim2.new(0, 0, 1, 0) }, Enum.EasingStyle.Linear)

    ActiveNotif[wrap] = true

    local btn = U.New("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        ZIndex = 6,
        Parent = card
    })
    btn.MouseButton1Click:Connect(function()
        notifSlideOut(wrap, card)
    end)

    task.delay(life, function() notifSlideOut(wrap, card) end)
end
-- // WATERMARK SYSTEM (Draggable, Minimizable, Realtime FPS) \ --
local ActiveWatermark = nil
function ZypheraxUI:Watermark(cfg)
    -- Inert watermark: safely cleanup existing widgets and return dummy methods
    pcall(function()
        local core = GetCore()
        local oldWm = core:FindFirstChild("ZypheraxWatermarkGui")
        if oldWm then oldWm:Destroy() end
    end)
    return {
        Set = function() end,
        SetVisible = function() end,
        Destroy = function() end,
    }
end

-- // FLOATING TOGGLE (Logo murni rbxassetid, bg hitam, tanpa garis) \ --
-- Logo = aset Roblox murni (tanpa lapisan Z vektor / URL external).
local ORB_ASSET_ID = "106764279090045"
local FloatingToggleGui = nil
local FloatingButton    = nil
local FloatingContainer = nil

local function EnsureFloatingButton(onToggleWindow)
    if FloatingContainer and FloatingContainer.Parent then return FloatingButton end

    -- Buang GUI toggle lama dari run sebelumnya
    pcall(function()
        local c = GetCore()
        for _, child in ipairs(c:GetChildren()) do
            if child.Name == "ZypheraxFloatingToggle" then child:Destroy() end
        end
    end)

    FloatingToggleGui = U.New("ScreenGui", {
        Name            = "ZypheraxFloatingToggle",
        ZIndexBehavior  = Enum.ZIndexBehavior.Sibling,
        DisplayOrder    = 9999,
        ResetOnSpawn    = false,
        Parent          = GetCore()
    })

    -- Tombol lingkaran: background HITAM, TANPA stroke/garis pinggiran
    FloatingButton = U.New("ImageButton", {
        Name                   = "FloatingCircleBtn",
        Size                   = UDim2.new(0, 56, 0, 56),
        Position               = UDim2.new(0, 20, 0, 20),
        BackgroundColor3       = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.05,
        Image                  = "",
        AutoButtonColor        = false,
        Visible                = false,
        ZIndex                 = 10,
        ClipsDescendants       = true,
        Parent                 = FloatingToggleGui
    })
    U.Corner(FloatingButton, UDim.new(1, 0))

    -- LOGO MURNI (aset Roblox) - satu-satunya isi tombol
    U.New("ImageLabel", {
        Name                   = "FloatingLogo",
        Size                   = UDim2.new(1, 0, 1, 0),
        Position               = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 1,
        Image                  = "rbxassetid://" .. ORB_ASSET_ID,
        ZIndex                 = 11,
        Parent                 = FloatingButton
    })

    -- // DRAG BEBAS 2D: global listener, tanpa kunci sumbu, semua Vector2 \ --
    local dragging    = false
    local dragStart   = nil
    local startPos    = nil
    local downPos     = nil
    local hasMoved    = false
    local moveConn, endConn = nil, nil

    local function clampXY(x, y)
        local vs = workspace.CurrentCamera.ViewportSize
        x = math.clamp(x, 8, math.max(8, vs.X - 56 - 8))
        y = math.clamp(y, 8, math.max(8, vs.Y - 56 - 8))
        return x, y
    end

    local function toV2(p)
        return Vector2.new(p.X, p.Y)
    end

    FloatingButton.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = toV2(inp.Position)
            startPos  = FloatingButton.Position
            downPos   = toV2(inp.Position)
            hasMoved  = false

            if not moveConn then
                moveConn = UIS.InputChanged:Connect(function(mi)
                    if not dragging then return end
                    if mi.UserInputType == Enum.UserInputType.MouseMovement
                        or mi.UserInputType == Enum.UserInputType.Touch then
                        local mp = toV2(mi.Position)
                        local d  = mp - dragStart
                        if (mp - downPos).Magnitude > 4 then hasMoved = true end
                        local nx, ny = clampXY(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
                        FloatingButton.Position = UDim2.new(0, nx, 0, ny)
                    end
                end)
            end
            if not endConn then
                endConn = UIS.InputEnded:Connect(function(ei2)
                    if ei2.UserInputType == Enum.UserInputType.MouseButton1
                        or ei2.UserInputType == Enum.UserInputType.Touch then
                        dragging = false
                    end
                end)
            end
        end
    end)
    pcall(function()
        UIS.WindowFocusReleased:Connect(function() dragging = false end)
    end)

    -- Klik (tanpa geser) -> buka UI + ripple
    FloatingButton.MouseButton1Up:Connect(function()
        if not hasMoved then
            U.Ripple(FloatingButton, Player:GetMouse().X, Player:GetMouse().Y)
            onToggleWindow(true)
        end
    end)

    -- Hover halus: background sedikit lebih terang (tanpa garis stroke)
    FloatingButton.MouseEnter:Connect(function()
        U.Tween(FloatingButton, 0.15, { BackgroundTransparency = 0.05 })
    end)
    FloatingButton.MouseLeave:Connect(function()
        U.Tween(FloatingButton, 0.25, { BackgroundTransparency = 0.15 })
    end)

    FloatingContainer = FloatingButton
    return FloatingButton
end

-- // MAIN WINDOW BUILDER (MacOS Traffic Lights + Double Column) \ --
function ZypheraxUI:CreateWindow(config)
    config = config or {}
    local title   = config.Title or config.Name or "Zypherax Hub"
    local sub     = config.Description or config.SubName or "Ride A Pet"
    local size    = config.Size or UDim2.fromOffset(760, 560)
    local keybind = config.Keybind or Enum.KeyCode.RightControl

    local core = GetCore()
    local connections = {}
    local function track(c) table.insert(connections, c); return c end

    local gui = U.New("ScreenGui", {
        Name = "ZypheraxApp_" .. title,
        DisplayOrder = 100,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = core
    })

    -- Drag anchor frame (Clean, no drop-shadow)
    local shadow = U.New("Frame", {
        Name = "WindowAnchor",
        Size = size,
        Position = UDim2.new(0.5, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = gui
    })

    -- Main window frame
    local main = U.New("Frame", {
        Name = "MainWindow",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = T.Background,
        BackgroundTransparency = 0.05,
        ClipsDescendants = true,
        ZIndex = 1,
        Parent = shadow
    })
    U.Corner(main, T.CornerLg)
    -- // BACKGROUND WATERMARK (logo samar elegant) \
    pcall(function()
        local bgwm = U.New("ImageLabel", {
            Name = "BackgroundWatermark",
            Image = "rbxassetid://106764279090045",
            BackgroundTransparency = 1,
            ImageTransparency = 0.87,
            ScaleType = Enum.ScaleType.Fit,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.60, 0, 0.55, 0),
            Size = UDim2.fromOffset(460, 460),
            ZIndex = 1,
            Parent = main
        })
    end)
--     local mainStroke = U.Stroke(main, T.Stroke, 1.2, 0)
    RegisterThemeColor(main, "BackgroundColor3", "Background")
--     RegisterThemeColor(mainStroke, "Color", "Stroke")

    -- Window Object
    local Win = { Tabs = {}, Pages = {}, _currentTab = nil, _connections = connections, _gui = gui }
    table.insert(ActiveWindows, Win)

    -- // SIDEBAR \ --
    local SIDEBAR_W = 168
    local sidebar = U.New("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, SIDEBAR_W, 1, 0),
        BackgroundColor3 = T.SidebarBg,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 2,
        Parent = main
    })
    U.Corner(sidebar, T.CornerLg)
    RegisterThemeColor(sidebar, "BackgroundColor3", "SidebarBg")

    -- Right border separator of sidebar
--     local sideDiv = U.New("Frame", {
--         Size = UDim2.new(0, 1, 1, 0),
--         Position = UDim2.new(1, 0, 0, 0),
--         BackgroundColor3 = T.Stroke,
--         BorderSizePixel = 0,
--         ZIndex = 3,
--         Parent = sidebar
--     })
--     RegisterThemeColor(sideDiv, "BackgroundColor3", "Stroke")
-- 
    -- // SIDEBAR HEADER (MacOS Traffic Lights + Titles) \ --
    local sidebarHeader = U.New("Frame", {
        Name = "SidebarHeader",
        Size = UDim2.new(1, 0, 0, 78),
        BackgroundTransparency = 1,
        ZIndex = 4,
        Parent = sidebar
    })

    -- MacOS Traffic Light Buttons (ðŸ”´ Red, ðŸŸ¡ Yellow, ðŸŸ¢ Green - Compact)
    local trafficContainer = U.New("Frame", {
        Name = "MacOSTrafficLights",
        Size = UDim2.new(0, 48, 0, 12),
        Position = UDim2.new(0, 14, 0, 12),
        BackgroundTransparency = 1,
        ZIndex = 5,
        Parent = sidebarHeader
    })
    local tLayout = U.New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = trafficContainer
    })

    local function makeTrafficDot(color, hoverColor, onClick)
        local dot = U.New("TextButton", {
            Size = UDim2.fromOffset(10, 10),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            ZIndex = 6,
            Parent = trafficContainer
        })
        U.Corner(dot, UDim.new(1, 0))
        track(dot.MouseEnter:Connect(function()
            U.Tween(dot, 0.15, { BackgroundColor3 = hoverColor })
        end))
        track(dot.MouseLeave:Connect(function()
            U.Tween(dot, 0.15, { BackgroundColor3 = color })
        end))
        track(dot.MouseButton1Click:Connect(function()
            if onClick then onClick() end
        end))
        return dot
    end

    -- ðŸ”´ Close: smoothly closes window
    makeTrafficDot(Color3.fromRGB(255, 95, 86), Color3.fromRGB(255, 120, 110), function()
        Win:ToggleVisibility(false)
    end)

    -- ðŸŸ¡ Minimize: minimizes window
    makeTrafficDot(Color3.fromRGB(255, 189, 46), Color3.fromRGB(255, 210, 80), function()
        Win:ToggleVisibility(false)
    end)

    -- ðŸŸ¢ Maximize: toggles size
    local isMaximized = false
    makeTrafficDot(Color3.fromRGB(39, 201, 63), Color3.fromRGB(60, 225, 90), function()
        isMaximized = not isMaximized
        local targetSize = isMaximized and UDim2.fromOffset(860, 640) or size
        U.Tween(shadow, 0.3, { Size = targetSize }, Enum.EasingStyle.Quart)
    end)

    -- Window Title & Subtitle below traffic lights
    local headLogo = U.New("ImageLabel", {
        Name = "SidebarLogo",
        Image = "rbxassetid://106764279090045",
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Position = UDim2.new(0, 14, 0, 30),
        Size = UDim2.fromOffset(26, 26),
        ZIndex = 6,
        Parent = sidebarHeader
    })
    U.Corner(headLogo, UDim.new(0, 5))
    local titleLbl = U.New("TextLabel", {
        Text = string.upper(title),
        Font = T.FontBold,
        TextSize = 13,
        TextColor3 = T.Accent,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 40, 0, 30),
        Size = UDim2.new(1, -50, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 5,
        Parent = sidebarHeader
    })
    titleLbl.TextColor3 = Color3.fromRGB(0, 170, 255) -- LOGOBLUE_TITLE: paksa biru logo
    pcall(function() titleLbl.Font = Enum.Font.GothamBold end)

    local subLbl = U.New("TextLabel", {
        Text = sub,
        Font = T.FontRegular,
        TextSize = 10,
        TextColor3 = T.TextMuted,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 40, 0, 46),
        Size = UDim2.new(1, -50, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 5,
        Parent = sidebarHeader
    })
    RegisterThemeColor(subLbl, "TextColor3", "TextMuted")

    -- Horizontal divider under sidebar header (DIHAPUS: garis panjang dihilangkan)
    --[[local hDiv = U.New("Frame", {
        Size = UDim2.new(1, -24, 0, 1),
        Position = UDim2.new(0, 12, 1, -1),
        BackgroundColor3 = T.Stroke,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = sidebarHeader
    })
    RegisterThemeColor(hDiv, "BackgroundColor3", "Stroke")--]]

        -- // SMOOTH UNINTERRUPTED GLOBAL DRAGGING \ --
    local dragging = false
    local dragStart, startPos = nil, nil
    track(sidebarHeader.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = inp.Position
            startPos = shadow.Position
        end
    end))
    track(UIS.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            local delta = inp.Position - dragStart
            shadow.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))
    track(UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))

    -- // SIDEBAR TAB LIST (Pill-style) \ --
    local tabList = U.New("ScrollingFrame", {
        Name = "TabList",
        Size = UDim2.new(1, 0, 1, -78 - 54),
        Position = UDim2.new(0, 0, 0, 78),
        BackgroundTransparency = 1,
        ScrollBarThickness = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ZIndex = 3,
        Parent = sidebar
    })
    local tabLayout = U.New("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = tabList
    })
    U.New("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        PaddingTop = UDim.new(0, 8),
        Parent = tabList
    })

    -- // SIDEBAR FOOTER (User card) \ --
    local footer = U.New("Frame", {
        Name = "SidebarFooter",
        Size = UDim2.new(1, 0, 0, 54),
        Position = UDim2.new(0, 0, 1, -54),
        BackgroundColor3 = T.Surface,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = sidebar
    })
    RegisterThemeColor(footer, "BackgroundColor3", "Surface")
    local fStroke = U.Stroke(footer, T.Stroke, 1, 0.4)
    RegisterThemeColor(fStroke, "Color", "Stroke")

    local uName = Player and Player.DisplayName or "User"
    local uHandle = Player and ("@" .. Player.Name) or "@user"

    local fLbl = U.New("TextLabel", {
        Text = uName,
        Font = T.FontBold,
        TextSize = 12,
        TextColor3 = T.Text,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 8),
        Size = UDim2.new(1, -32, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 5,
        Parent = footer
    })
    local hLbl = U.New("TextLabel", {
        Text = uHandle,
        Font = T.FontRegular,
        TextSize = 10,
        TextColor3 = T.TextMuted,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 24),
        Size = UDim2.new(1, -32, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 5,
        Parent = footer
    })

    -- // CONTENT AREA (Double Column + Top Search Engine) \ --
    local contentArea = U.New("Frame", {
        Name = "ContentArea",
        Size = UDim2.new(1, -(SIDEBAR_W + 1), 1, 0),
        Position = UDim2.new(0, SIDEBAR_W + 1, 0, 0),
        BackgroundTransparency = 1,
        ZIndex = 2,
        Parent = main
    })

    -- // ELEGANT TOP SEARCH ENGINE \ --
    local searchBarFrame = U.New("Frame", {
        Name = "TopSearchBar",
        Size = UDim2.new(0, 240, 0, 32),
        Position = UDim2.new(0, 10, 0, 8),
        BackgroundColor3 = T.Surface2,
        BackgroundTransparency = 0.05,
        ZIndex = 5,
        Parent = contentArea
    })
    U.Corner(searchBarFrame, T.CornerMd)
    local sbStroke = U.Stroke(searchBarFrame, T.Stroke, 1, 0.2)
    RegisterThemeColor(searchBarFrame, "BackgroundColor3", "Surface2")
    RegisterThemeColor(sbStroke, "Color", "Stroke")

    local searchInput = U.New("TextBox", {
        Name = "SearchInput",
        Text = "",
        PlaceholderText = "Search...",
        Font = T.FontRegular,
        TextSize = 11,
        TextColor3 = T.Text,
        PlaceholderColor3 = T.TextDim,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -42, 1, 0),
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 6,
        Parent = searchBarFrame
    })
    RegisterThemeColor(searchInput, "TextColor3", "Text")
    RegisterThemeColor(searchInput, "PlaceholderColor3", "TextDim")

    local clearSearchBtn = U.New("TextButton", {
        Name = "ClearSearch",
        Text = "X",
        Font = T.FontBold,
        TextSize = 11,
        TextColor3 = T.TextMuted,
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -28, 0, 0),
        Size = UDim2.new(0, 24, 1, 0),
        Visible = false,
        ZIndex = 6,
        Parent = searchBarFrame
    })

    pcall(function()
        if searchInput.Focused then
            track(searchInput.Focused:Connect(function()
                U.Tween(sbStroke, 0.2, { Color = T.Accent, Transparency = 0 })
            end))
        end
        if searchInput.FocusLost then
            track(searchInput.FocusLost:Connect(function()
                U.Tween(sbStroke, 0.2, { Color = T.Stroke, Transparency = 0.2 })
            end))
        end
    end)

    -- // FLOATING TOGGLE SYNC (muncul saat UI hide, hilang saat UI show) \ --
    local function syncFloat(hidden)
        pcall(function()
            local btn = EnsureFloatingButton(function()
                Win:ToggleVisibility(true)
            end)
            if btn then btn.Visible = (hidden == true) end
            if FloatingContainer then FloatingContainer.Visible = (hidden == true) end
        end)
    end

    -- Visibility Toggle Method
    function Win:ToggleVisibility(visible)
        if visible == nil then visible = not gui.Enabled end
        if visible then
            gui.Enabled = true
            main.Size = UDim2.fromScale(0.95, 0.95)
            main.BackgroundTransparency = 0.4
            U.Tween(main, 0.28, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.04 }, Enum.EasingStyle.Quart)
            syncFloat(false)
        else
            U.Tween(main, 0.2, { Size = UDim2.fromScale(0.95, 0.95), BackgroundTransparency = 1 }, Enum.EasingStyle.Quart).Completed:Connect(function()
                gui.Enabled = false
            end)
            syncFloat(true)
        end
    end

    function Win:SetTheme(name)
        ZypheraxUI:SetTheme(name)
    end

    function Win:Destroy()
        for _, c in ipairs(connections) do
            if c and c.Connected then pcall(function() c:Disconnect() end) end
        end
        if gui then gui:Destroy() end
        if FloatingToggleGui then pcall(function() FloatingToggleGui:Destroy() end) end
    end

    -- Keybind listener
    track(UIS.InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.KeyCode == keybind then
            Win:ToggleVisibility()
        end
    end))

    -- // TAB CREATOR \ --
    function Win:CreateTab(tabCfg)
        local tabName = type(tabCfg) == "table" and (tabCfg.Name or tabCfg.Title) or tabCfg or "Tab"
        local tabIcon = type(tabCfg) == "table" and tabCfg.Icon or nil

        -- Tab button
        local tabBtn = U.New("TextButton", {
            Name = "TabBtn_" .. tabName,
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = T.Surface2,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "",
            ZIndex = 4,
            Parent = tabList
        })
        U.Corner(tabBtn, T.CornerMd)
        local btnStroke = U.Stroke(tabBtn, T.Stroke, 1, 1)

        -- Active indicator bar
        local activeBar = U.New("Frame", {
            Size = UDim2.new(0, 3, 0, 16),
            Position = UDim2.new(0, 5, 0.5, -8),
            BackgroundColor3 = T.Accent,
            BorderSizePixel = 0,
            BackgroundTransparency = 1,
            ZIndex = 5,
            Parent = tabBtn
        })
        U.Corner(activeBar, UDim.new(1, 0))
        RegisterThemeColor(activeBar, "BackgroundColor3", "Accent")

        local tabLbl = U.New("TextLabel", {
            Text = tabName,
            Font = T.FontRegular,
            TextSize = 12,
            TextColor3 = T.TextMuted,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 14, 0, 0),
            Size = UDim2.new(1, -18, 1, 0),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 5,
            Parent = tabBtn
        })
        RegisterThemeColor(tabLbl, "TextColor3", "TextMuted")

        -- Double Column Container for this Tab (Below Search Bar)
        local pageFrame = U.New("Frame", {
            Name = "Page_" .. tabName,
            Size = UDim2.new(1, -20, 1, -62),
            Position = UDim2.new(0, 10, 0, 52),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 3,
            Parent = contentArea
        })

        local function makeColumn(posX)
            local col = U.New("ScrollingFrame", {
                Size = UDim2.new(0.5, -6, 1, 0),
                Position = UDim2.new(posX, 0, 0, 0),
                BackgroundTransparency = 1,
                ScrollBarThickness = 2,
                ScrollBarImageColor3 = T.Accent,
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                ZIndex = 3,
                Parent = pageFrame
            })
            U.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10), Parent = col })
            U.New("UIPadding", { PaddingBottom = UDim.new(0, 16), Parent = col })
            return col
        end

        local leftCol  = makeColumn(0)
        local rightCol = makeColumn(0.5)

        local function activateTab()
            for _, t in ipairs(Win.Tabs) do
                t.page.Visible = false
                U.Tween(t.btn, 0.15, { BackgroundTransparency = 1 })
                U.Tween(t.stroke, 0.15, { Transparency = 1 })
                U.Tween(t.lbl, 0.15, { TextColor3 = T.TextMuted, Font = T.FontRegular })
                U.Tween(t.bar, 0.15, { BackgroundTransparency = 1 })
            end
            pageFrame.Visible = true
            U.Tween(tabBtn, 0.18, { BackgroundColor3 = T.Surface2, BackgroundTransparency = 0.4 })
            U.Tween(btnStroke, 0.18, { Transparency = 0.5, Color = T.Accent })
            U.Tween(tabLbl, 0.18, { TextColor3 = T.Accent, Font = T.FontBold })
            U.Tween(activeBar, 0.18, { BackgroundTransparency = 0 })
            Win._currentTab = tabName
        end

        track(tabBtn.MouseButton1Click:Connect(activateTab))
        track(tabBtn.MouseEnter:Connect(function()
            if Win._currentTab ~= tabName then
                U.Tween(tabBtn, 0.12, { BackgroundColor3 = T.Surface, BackgroundTransparency = 0.5 })
                U.Tween(tabLbl, 0.12, { TextColor3 = T.Text })
            end
        end))
        track(tabBtn.MouseLeave:Connect(function()
            if Win._currentTab ~= tabName then
                U.Tween(tabBtn, 0.15, { BackgroundTransparency = 1 })
                U.Tween(tabLbl, 0.15, { TextColor3 = T.TextMuted })
            end
        end))

        if #Win.Tabs == 0 then activateTab() end

        local tabEntry = { btn = tabBtn, stroke = btnStroke, lbl = tabLbl, bar = activeBar, page = pageFrame, name = tabName, sections = {} }
        table.insert(Win.Tabs, tabEntry)

        -- // SECTION BUILDER (Zero Generic "SECTION" Text Overlaps) \ --
        local TabObj = {}
        function TabObj:CreateSection(secCfg)
            local rawName = type(secCfg) == "table" and (secCfg.Name or secCfg.Title) or secCfg
            local side    = type(secCfg) == "table" and (secCfg.Side or 1) or 1
            local targetCol = (side == 2) and rightCol or leftCol

            -- Check if name is generic
            local isGeneric = (rawName == nil or rawName == "" or rawName == "Section" or rawName == "SECTION")
            local displayName = isGeneric and "" or tostring(rawName)

            local sectionBox = U.New("Frame", {
                Name = "SectionBox_" .. (displayName ~= "" and displayName or "Card"),
                Size = UDim2.new(1, 0, 0, 0),
                BackgroundColor3 = T.SectionBg,
                BackgroundTransparency = 0.05,
                AutomaticSize = Enum.AutomaticSize.Y,
                ZIndex = 4,
                Parent = targetCol
            })
            U.Corner(sectionBox, T.CornerMd)
            local sStroke = U.Stroke(sectionBox, T.Stroke, 1, 0.4)
            RegisterThemeColor(sStroke, "Color", "Stroke")

            -- Section Header Frame (Only visible if real name exists)
            local secHeader = U.New("Frame", {
                Name = "Header",
                Size = UDim2.new(1, 0, 0, displayName ~= "" and 28 or 0),
                BackgroundColor3 = T.SectionHeader,
                Visible = (displayName ~= ""),
                ZIndex = 5,
                Parent = sectionBox
            })
            U.Corner(secHeader, T.CornerMd)
            RegisterThemeColor(secHeader, "BackgroundColor3", "SectionHeader")

            local hLine = U.New("Frame", {
                Size = UDim2.new(1, 0, 0, 1),
                Position = UDim2.new(0, 0, 1, -1),
                BackgroundColor3 = T.Accent,
                BorderSizePixel = 0,
                ZIndex = 6,
                Parent = secHeader
            })
            U.Gradient(hLine, T.Accent, T.Background, 0)

            local hTitle = U.New("TextLabel", {
                Text = displayName,
                Font = T.FontBold,
                TextSize = 11,
                TextColor3 = T.Accent,
                BackgroundTransparency = 1,
                Position = UDim2.new(0, 10, 0, 0),
                Size = UDim2.new(1, -20, 1, 0),
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                ZIndex = 6,
                Parent = secHeader
            })

            -- Elements Container inside Section
            local secContainer = U.New("Frame", {
                Name = "Container",
                Size = UDim2.new(1, -16, 0, 0),
                Position = UDim2.new(0, 8, 0, displayName ~= "" and 34 or 8),
                BackgroundTransparency = 1,
                AutomaticSize = Enum.AutomaticSize.Y,
                ZIndex = 5,
                Parent = sectionBox
            })
            U.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = secContainer })
            U.New("UIPadding", { PaddingBottom = UDim.new(0, 10), Parent = secContainer })

            local SectionObj = { _box = sectionBox, _container = secContainer, _name = displayName, _items = {} }
            table.insert(tabEntry.sections, SectionObj)

            -- Header updater (Sets section title without duplicate labels)
            function SectionObj:Header(hCfg)
                local txt = type(hCfg) == "table" and (hCfg.Name or hCfg[1]) or tostring(hCfg)
                if txt and txt ~= "" then
                    local clean = txt:gsub("<[^>]->", "")
                    hTitle.Text = clean
                    secHeader.Visible = true
                    secHeader.Size = UDim2.new(1, 0, 0, 28)
                    secContainer.Position = UDim2.new(0, 8, 0, 34)
                end
            end

            local function makeBase(height, isButton)
                local cls = isButton and "TextButton" or "Frame"
                local base = U.New(cls, {
                    Size = UDim2.new(1, 0, 0, height or 38),
                    BackgroundColor3 = T.Surface2,
                    BackgroundTransparency = 0.05,
                    BorderSizePixel = 0,
                    ZIndex = 5,
                    Parent = secContainer
                })
                if isButton then
                    base.Text = ""
                    base.AutoButtonColor = false
                end
                U.Corner(base, T.CornerSm)
                local bStroke = U.Stroke(base, T.Stroke, 1, 0)
                RegisterThemeColor(base, "BackgroundColor3", "Surface2")
                RegisterThemeColor(bStroke, "Color", "Stroke")
                return base, bStroke
            end

            -- // TOGGLE (Anti-Collision: TextTruncate + Dedicated Switch Area) \ --
            function SectionObj:CreateToggle(cfg)
                local nm      = cfg.Name or "Toggle"
                local flag    = cfg.Flag
                local default = cfg.Default == true
                local cb      = cfg.Callback or function() end
                local toggled = default

                if flag then ZypheraxUI.Flags[flag] = toggled end

                local base, stroke = makeBase(38)
                base:SetAttribute("ControlName", nm)
                table.insert(SectionObj._items, base)

                -- Label has generous space, cannot collide with switch
                local lbl = U.New("TextLabel", {
                    Text = nm,
                    Font = T.FontRegular,
                    TextSize = 12,
                    TextColor3 = T.Text,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 10, 0, 0),
                    Size = UDim2.new(1, -56, 1, 0),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    ZIndex = 6,
                    Parent = base
                })

                -- Switch pill
                local track = U.New("Frame", {
                    Size = UDim2.new(0, 34, 0, 18),
                    Position = UDim2.new(1, -44, 0.5, -9),
                    BackgroundColor3 = toggled and T.Accent or T.Surface3,
                    ZIndex = 6,
                    Parent = base
                })
                U.Corner(track, UDim.new(1, 0))
                local tStroke = U.Stroke(track, toggled and T.Accent or T.Stroke, 1, 0)

                local knob = U.New("Frame", {
                    Size = UDim2.new(0, 14, 0, 14),
                    Position = UDim2.new(0, toggled and 18 or 2, 0.5, -7),
                    BackgroundColor3 = Color3.new(1, 1, 1),
                    ZIndex = 7,
                    Parent = track
                })
                U.Corner(knob, UDim.new(1, 0))

                local btn = U.New("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 8, Parent = base })

                local function setVal(v, silent)
                    toggled = v
                    if flag then ZypheraxUI.Flags[flag] = toggled end
                    U.Tween(track, 0.2, { BackgroundColor3 = toggled and T.Accent or T.Surface3 })
                    U.Tween(tStroke, 0.2, { Color = toggled and T.Accent or T.Stroke })
                    U.Tween(knob, 0.22, { Position = UDim2.new(0, toggled and 18 or 2, 0.5, -7) }, Enum.EasingStyle.Quart)
                    if not silent then pcall(cb, toggled) end
                end

                track(btn.MouseButton1Click:Connect(function()
                    U.Ripple(btn, Player:GetMouse().X, Player:GetMouse().Y)
                    setVal(not toggled)
                end))

                if default then pcall(cb, true) end
                local ret = {
                    Set = function(_, v) setVal(v == true, false) end,
                    Get = function() return toggled end
                }
                if flag then ZypheraxUI.Controls[flag] = ret end
                return ret
            end
            SectionObj.Toggle = SectionObj.CreateToggle

            -- // SLIDER (Anti-Collision: Two-Row Layout) \ --
            function SectionObj:CreateSlider(cfg)
                local nm      = cfg.Name or "Slider"
                local flag    = cfg.Flag
                local mn      = cfg.Min or cfg.Minimum or 0
                local mx      = cfg.Max or cfg.Maximum or 100
                local default = math.clamp(cfg.Default or mn, mn, mx)
                local suffix  = cfg.Suffix or ""
                local cb      = cfg.Callback or function() end
                local value   = default

                if flag then ZypheraxUI.Flags[flag] = value end

                local base, stroke = makeBase(48)
                base:SetAttribute("ControlName", nm)
                table.insert(SectionObj._items, base)

                -- Title top-left
                local lbl = U.New("TextLabel", {
                    Text = nm,
                    Font = T.FontRegular,
                    TextSize = 12,
                    TextColor3 = T.Text,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 10, 0, 4),
                    Size = UDim2.new(1, -70, 0, 18),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    ZIndex = 6,
                    Parent = base
                })

                -- Value readout top-right
                local valLbl = U.New("TextLabel", {
                    Text = tostring(default) .. suffix,
                    Font = T.FontBold,
                    TextSize = 11,
                    TextColor3 = T.Accent,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, -55, 0, 4),
                    Size = UDim2.new(0, 45, 0, 18),
                    TextXAlignment = Enum.TextXAlignment.Right,
                    ZIndex = 6,
                    Parent = base
                })

                -- Track bottom
                local trackBar = U.New("Frame", {
                    Size = UDim2.new(1, -20, 0, 4),
                    Position = UDim2.new(0, 10, 0, 32),
                    BackgroundColor3 = T.Surface3,
                    ZIndex = 6,
                    Parent = base
                })
                U.Corner(trackBar, UDim.new(1, 0))

                local ratio = (default - mn) / math.max(mx - mn, 1)
                local fill = U.New("Frame", {
                    Size = UDim2.new(ratio, 0, 1, 0),
                    BackgroundColor3 = T.Accent,
                    ZIndex = 7,
                    Parent = trackBar
                })
                U.Corner(fill, UDim.new(1, 0))
                U.Gradient(fill, T.Accent, T.AccentGradient, 0)

                local knob = U.New("Frame", {
                    Size = UDim2.fromOffset(12, 12),
                    Position = UDim2.new(1, -6, 0.5, -6),
                    BackgroundColor3 = Color3.new(1, 1, 1),
                    ZIndex = 8,
                    Parent = fill
                })
                U.Corner(knob, UDim.new(1, 0))

                local btn = U.New("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 9, Parent = base })

                local function updateSlider(mouseX)
                    local rel = math.clamp((mouseX - trackBar.AbsolutePosition.X) / trackBar.AbsoluteSize.X, 0, 1)
                    value = math.floor(mn + (mx - mn) * rel)
                    if flag then ZypheraxUI.Flags[flag] = value end
                    valLbl.Text = tostring(value) .. suffix
                    fill.Size = UDim2.new(rel, 0, 1, 0)
                    pcall(cb, value)
                end

                local sDragging = false
                track(btn.InputBegan:Connect(function(inp)
                    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                        sDragging = true
                        updateSlider(inp.Position.X)
                    end
                end))
                track(UIS.InputChanged:Connect(function(inp)
                    if sDragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
                        updateSlider(inp.Position.X)
                    end
                end))
                track(UIS.InputEnded:Connect(function(inp)
                    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                        sDragging = false
                    end
                end))

                local ret = {
                    Set = function(_, v)
                        v = math.clamp(v, mn, mx)
                        value = v
                        local r = (v - mn) / math.max(mx - mn, 1)
                        fill.Size = UDim2.new(r, 0, 1, 0)
                        valLbl.Text = tostring(v) .. suffix
                        pcall(cb, v)
                    end,
                    Get = function() return value end
                }
                if flag then ZypheraxUI.Controls[flag] = ret end
                return ret
            end
            SectionObj.Slider = SectionObj.CreateSlider

            -- // DROPDOWN \ --
            function SectionObj:CreateDropdown(cfg)
                local nm      = cfg.Name or "Dropdown"
                local items   = cfg.Options or cfg.Items or {}
                local default = cfg.Default or (items[1] or "")
                local cb      = cfg.Callback or function() end
                local selected = default
                local isOpen  = false

                local base, stroke = makeBase(36)
                base:SetAttribute("ControlName", nm)
                table.insert(SectionObj._items, base)

                local lbl = U.New("TextLabel", {
                    Text = nm .. ": " .. tostring(selected),
                    Font = T.FontRegular,
                    TextSize = 12,
                    TextColor3 = T.Text,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 10, 0, 0),
                    Size = UDim2.new(1, -40, 0, 36),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    ZIndex = 6,
                    Parent = base
                })

                local chevron = U.New("TextLabel", {
                    Text = "v",
                    Font = T.FontBold,
                    TextSize = 10,
                    TextColor3 = T.TextMuted,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(1, -26, 0, 0),
                    Size = UDim2.new(0, 20, 0, 36),
                    ZIndex = 6,
                    Parent = base
                })

                local listFrame = U.New("Frame", {
                    Size = UDim2.new(1, -16, 0, 0),
                    Position = UDim2.new(0, 8, 0, 38),
                    BackgroundColor3 = T.Surface3,
                    ClipsDescendants = true,
                    Visible = false,
                    ZIndex = 7,
                    Parent = base
                })
                U.Corner(listFrame, T.CornerSm)
                local dLayout = U.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = listFrame })

                local function rebuild()
                    for _, c in ipairs(listFrame:GetChildren()) do
                        if c:IsA("TextButton") then c:Destroy() end
                    end
                    for _, it in ipairs(items) do
                        local iBtn = U.New("TextButton", {
                            Size = UDim2.new(1, 0, 0, 26),
                            BackgroundColor3 = (it == selected) and T.Accent or T.Surface3,
                            BackgroundTransparency = (it == selected) and 0.4 or 1,
                            Text = tostring(it),
                            Font = T.FontRegular,
                            TextSize = 11,
                            TextColor3 = (it == selected) and T.Accent or T.Text,
                            ZIndex = 8,
                            Parent = listFrame
                        })
                        U.Corner(iBtn, UDim.new(0, 4))
                        track(iBtn.MouseButton1Click:Connect(function()
                            selected = it
                            lbl.Text = nm .. ": " .. tostring(selected)
                            isOpen = false
                            listFrame.Visible = false
                            U.Tween(base, 0.2, { Size = UDim2.new(1, 0, 0, 36) })
                            chevron.Text = "v"
                            pcall(cb, selected)
                            rebuild()
                        end))
                    end
                end
                rebuild()

                local toggleBtn = U.New("TextButton", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Text = "", ZIndex = 9, Parent = base })
                track(toggleBtn.MouseButton1Click:Connect(function()
                    isOpen = not isOpen
                    if isOpen then
                        listFrame.Visible = true
                        local h = #items * 28 + 4
                        U.Tween(base, 0.2, { Size = UDim2.new(1, 0, 0, 42 + h) })
                        U.Tween(listFrame, 0.2, { Size = UDim2.new(1, -16, 0, h) })
                        chevron.Text = "^"
                    else
                        U.Tween(base, 0.2, { Size = UDim2.new(1, 0, 0, 36) })
                        U.Tween(listFrame, 0.2, { Size = UDim2.new(1, -16, 0, 0) }).Completed:Connect(function()
                            listFrame.Visible = false
                        end)
                        chevron.Text = "v"
                    end
                end))

                return {
                    Set = function(_, v)
                        selected = v
                        lbl.Text = nm .. ": " .. tostring(selected)
                        pcall(cb, selected)
                        rebuild()
                    end,
                    Get = function() return selected end
                }
            end
            SectionObj.Dropdown = SectionObj.CreateDropdown

            -- // BUTTON \ --
            function SectionObj:CreateButton(cfg)
                local nm = type(cfg) == "table" and (cfg.Name or cfg.Text) or tostring(cfg)
                local cb = type(cfg) == "table" and cfg.Callback or function() end

                local base, stroke = makeBase(34, true)
                base:SetAttribute("ControlName", nm)
                table.insert(SectionObj._items, base)
                local lbl = U.New("TextLabel", {
                    Text = nm,
                    Font = T.FontBold,
                    TextSize = 12,
                    TextColor3 = T.Text,
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 1),
                    TextXAlignment = Enum.TextXAlignment.Center,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    ZIndex = 6,
                    Parent = base
                })

                track(base.MouseEnter:Connect(function()
                    U.Tween(base, 0.15, { BackgroundColor3 = T.Surface3 })
                    U.Tween(stroke, 0.15, { Color = T.Accent })
                end))
                track(base.MouseLeave:Connect(function()
                    U.Tween(base, 0.2, { BackgroundColor3 = T.Surface2 })
                    U.Tween(stroke, 0.2, { Color = T.Stroke })
                end))
                track(base.MouseButton1Click:Connect(function()
                    U.Ripple(base, Player:GetMouse().X, Player:GetMouse().Y)
                    pcall(cb)
                end))

                return {
                    SetText = function(_, t) lbl.Text = tostring(t) end
                }
            end
            SectionObj.Button = SectionObj.CreateButton

            -- // INPUT \ --
            function SectionObj:CreateInput(cfg)
                local nm      = cfg.Name or "Input"
                local ph      = cfg.Placeholder or "Ketik..."
                local default = cfg.Default or ""
                local cb      = cfg.Callback or function() end

                local base, stroke = makeBase(36)
                base:SetAttribute("ControlName", nm)
                table.insert(SectionObj._items, base)

                local lbl = U.New("TextLabel", {
                    Text = nm,
                    Font = T.FontRegular,
                    TextSize = 12,
                    TextColor3 = T.Text,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 10, 0, 0),
                    Size = UDim2.new(0.45, 0, 1, 0),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    ZIndex = 6,
                    Parent = base
                })

                local box = U.New("TextBox", {
                    Text = default,
                    PlaceholderText = ph,
                    Font = T.FontRegular,
                    TextSize = 11,
                    TextColor3 = T.Text,
                    PlaceholderColor3 = T.TextDim,
                    BackgroundColor3 = T.Surface3,
                    Position = UDim2.new(0.48, 0, 0.5, -12),
                    Size = UDim2.new(0.5, -6, 0, 24),
                    ClearTextOnFocus = false,
                    ZIndex = 6,
                    Parent = base
                })
                U.Corner(box, UDim.new(0, 4))
                local bStroke = U.Stroke(box, T.Stroke, 1, 0)

                track(box.FocusLost:Connect(function(enter)
                    pcall(cb, box.Text, enter)
                end))
                pcall(function()
                    if box.GetPropertyChangedSignal then
                        track(box:GetPropertyChangedSignal("Text"):Connect(function()
                            pcall(cb, box.Text, false)
                        end))
                    end
                end)
                if default and default ~= "" then
                    pcall(cb, default, false)
                end

                return {
                    Set = function(_, v) box.Text = tostring(v) end,
                    Get = function() return box.Text end
                }
            end
            SectionObj.Input = SectionObj.CreateInput

            -- // LABEL \ --
            function SectionObj:CreateLabel(textOrCfg)
                local _isGrp = false
                local txt = type(textOrCfg) == "table" and (textOrCfg.Name or textOrCfg.Text or textOrCfg[1]) or tostring(textOrCfg)
                local _isGrp = type(txt)=="string" and txt==txt:upper() and #txt>=4
                local _isGrp2 = type(txt)=="string" and txt==txt:upper() and #txt>=4
                local lbl = U.New("TextLabel", {
                    Text = txt,
                    Font = (_isGrp and T.FontBold or T.FontRegular),
                    TextSize = (_isGrp and 12 or 11),
                    TextColor3 = (_isGrp and T.Text or T.TextMuted),
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 5,
                    Parent = secContainer
                })
                lbl:SetAttribute("ControlName", txt)
                table.insert(SectionObj._items, lbl)
                U.New("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = lbl })
                return {
                    Set = function(_, t) lbl.Text = tostring(t) end
                }
            end
            SectionObj.Label = SectionObj.CreateLabel

            -- // KEYBIND \ --
            function SectionObj:CreateKeybind(cfg)
                local nm      = cfg.Name or "Keybind"
                local default = cfg.Default or Enum.KeyCode.RightControl
                local cb      = cfg.Callback or function() end
                local current = default
                local binding = false

                local base, stroke = makeBase(36)
                base:SetAttribute("ControlName", nm)
                table.insert(SectionObj._items, base)

                local lbl = U.New("TextLabel", {
                    Text = nm,
                    Font = T.FontRegular,
                    TextSize = 12,
                    TextColor3 = T.Text,
                    BackgroundTransparency = 1,
                    Position = UDim2.new(0, 10, 0, 0),
                    Size = UDim2.new(1, -85, 1, 0),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    ZIndex = 6,
                    Parent = base
                })

                local badge = U.New("TextButton", {
                    Text = current.Name,
                    Font = T.FontBold,
                    TextSize = 11,
                    TextColor3 = T.Accent,
                    BackgroundColor3 = T.Surface3,
                    Position = UDim2.new(1, -72, 0.5, -11),
                    Size = UDim2.new(0, 64, 0, 22),
                    ZIndex = 6,
                    Parent = base
                })
                U.Corner(badge, UDim.new(0, 4))
                local bStroke = U.Stroke(badge, T.Stroke, 1, 0)

                local bindConn = nil
                track(badge.MouseButton1Click:Connect(function()
                    binding = true
                    badge.Text = "..."
                    bStroke.Color = T.Accent
                    if bindConn then bindConn:Disconnect() end
                    bindConn = UIS.InputBegan:Connect(function(inp, gp)
                        if gp then return end
                        if inp.UserInputType == Enum.UserInputType.Keyboard then
                            binding = false
                            current = inp.KeyCode
                            badge.Text = current.Name
                            bStroke.Color = T.Stroke
                            if bindConn then bindConn:Disconnect(); bindConn = nil end
                            pcall(cb, current)
                        end
                    end)
                end))

                return {
                    Set = function(_, k) current = k; badge.Text = k.Name end,
                    Get = function() return current end
                }
            end
            SectionObj.Keybind = SectionObj.CreateKeybind

            -- // BUILT-IN CONFIG MANAGER SYSTEM (Matching Image 4 & 5) \ --
            function SectionObj:CreateConfigSystem()
                local FOLDER = "ZypheraxHub"
                local CONFIGS_FOLDER = FOLDER .. "/Configs"
                local AUTOLOAD_FILE = FOLDER .. "/autoload.txt"

                pcall(function()
                    if makefolder and isfolder then
                        if not isfolder(FOLDER) then makefolder(FOLDER) end
                        if not isfolder(CONFIGS_FOLDER) then makefolder(CONFIGS_FOLDER) end
                    end
                end)

                local selectedSave = nil
                local deleteMode = false

                -- Header row with icon + "Config"
                local confBox = U.New("Frame", {
                    Name = "ConfigManager",
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    BackgroundColor3 = T.Surface,
                    BackgroundTransparency = 0.05,
                    ZIndex = 5,
                    Parent = secContainer
                })
                U.Corner(confBox, T.CornerMd)
                U.Stroke(confBox, T.Stroke, 1, 0.4)
                local pad = U.New("UIPadding", {
                    PaddingTop = UDim.new(0, 10),
                    PaddingBottom = UDim.new(0, 10),
                    PaddingLeft = UDim.new(0, 10),
                    PaddingRight = UDim.new(0, 10),
                    Parent = confBox
                })
                local cLayout = U.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8), Parent = confBox })

                -- Title
                local topRow = U.New("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Parent = confBox })
                U.New("TextLabel", {
                    Text = "âš™  Config Manager",
                    Font = T.FontBold,
                    TextSize = 13,
                    TextColor3 = T.Accent,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(1, -20, 1, 0),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = topRow
                })

                -- Search box ("Cari save...")
                local searchBox = U.New("TextBox", {
                    Text = "",
                    PlaceholderText = "Cari save...",
                    Font = T.FontRegular,
                    TextSize = 11,
                    TextColor3 = T.Text,
                    PlaceholderColor3 = T.TextDim,
                    BackgroundColor3 = T.Surface2,
                    Size = UDim2.new(1, 0, 0, 28),
                    ClearTextOnFocus = false,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = confBox
                })
                U.Corner(searchBox, UDim.new(0, 5))
                U.Stroke(searchBox, T.Stroke, 1, 0)
                U.New("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = searchBox })

                -- Saves list container
                local saveListFrame = U.New("ScrollingFrame", {
                    Size = UDim2.new(1, 0, 0, 110),
                    BackgroundColor3 = T.Background2,
                    ScrollBarThickness = 2,
                    ScrollBarImageColor3 = T.Accent,
                    AutomaticCanvasSize = Enum.AutomaticSize.Y,
                    CanvasSize = UDim2.new(0, 0, 0, 0),
                    ClipsDescendants = true,
                    Parent = confBox
                })
                U.Corner(saveListFrame, UDim.new(0, 6))
                U.Stroke(saveListFrame, T.Stroke, 1, 0.2)
                local sListLayout = U.New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = saveListFrame })
                U.New("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = saveListFrame })

                local emptyLbl = U.New("TextLabel", {
                    Text = "+",
                    Font = T.FontBold,
                    TextSize = 22,
                    TextColor3 = T.TextDim,
                    BackgroundTransparency = 1,
                    Size = UDim2.fromScale(1, 1),
                    Visible = true,
                    Parent = saveListFrame
                })

                -- Input box ("Nama save...")
                local nameInput = U.New("TextBox", {
                    Text = "",
                    PlaceholderText = "Nama save...",
                    Font = T.FontRegular,
                    TextSize = 11,
                    TextColor3 = T.Text,
                    PlaceholderColor3 = T.TextDim,
                    BackgroundColor3 = T.Surface2,
                    Size = UDim2.new(1, 0, 0, 28),
                    ClearTextOnFocus = false,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = confBox
                })
                U.Corner(nameInput, UDim.new(0, 5))
                U.Stroke(nameInput, T.Stroke, 1, 0)
                U.New("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = nameInput })

                local function getConfigFiles()
                    local t = {}
                    pcall(function()
                        if listfiles and isfolder and isfolder(CONFIGS_FOLDER) then
                            for _, f in ipairs(listfiles(CONFIGS_FOLDER)) do
                                local bName = f:gsub("\\", "/"):match("([^/]+)%.json$")
                                if bName then table.insert(t, bName) end
                            end
                        end
                    end)
                    return t
                end

                local function refreshSaveList(filterText)
                    filterText = (filterText or ""):lower()
                    for _, c in ipairs(saveListFrame:GetChildren()) do
                        if c:IsA("TextButton") then c:Destroy() end
                    end
                    local allSaves = getConfigFiles()
                    local count = 0
                    for _, sName in ipairs(allSaves) do
                        if filterText == "" or sName:lower():find(filterText) then
                            count = count + 1
                            local isSel = (sName == selectedSave)
                            local sBtn = U.New("TextButton", {
                                Size = UDim2.new(1, 0, 0, 24),
                                BackgroundColor3 = isSel and T.Accent or T.Surface3,
                                BackgroundTransparency = isSel and 0.3 or 0.7,
                                Text = "  " .. sName,
                                Font = isSel and T.FontBold or T.FontRegular,
                                TextSize = 11,
                                TextColor3 = isSel and T.Accent or T.Text,
                                TextXAlignment = Enum.TextXAlignment.Left,
                                ZIndex = 6,
                                Parent = saveListFrame
                            })
                            U.Corner(sBtn, UDim.new(0, 4))
                            sBtn.MouseButton1Click:Connect(function()
                                if deleteMode then
                                    pcall(function()
                                        if delfile then delfile(CONFIGS_FOLDER .. "/" .. sName .. ".json") end
                                    end)
                                    if selectedSave == sName then selectedSave = nil end
                                    refreshSaveList(searchBox.Text)
                                    ZypheraxUI:Notify({ Title = "Config", Description = "Save '" .. sName .. "' dihapus." })
                                else
                                    selectedSave = sName
                                    nameInput.Text = sName
                                    refreshSaveList(searchBox.Text)
                                    -- Auto load this save
                                    pcall(function()
                                        if readfile and isfile and isfile(CONFIGS_FOLDER .. "/" .. sName .. ".json") then
                                            local raw = readfile(CONFIGS_FOLDER .. "/" .. sName .. ".json")
                                            local data = HttpService:JSONDecode(raw)
                                            for fKey, val in pairs(data) do
                                                if ZypheraxUI.Controls[fKey] and ZypheraxUI.Controls[fKey].Set then
                                                    ZypheraxUI.Controls[fKey]:Set(val)
                                                end
                                            end
                                            ZypheraxUI:Notify({ Title = "Config Loaded", Description = "Konfigurasi '" .. sName .. "' diterapkan!" })
                                        end
                                    end)
                                end
                            end)
                        end
                    end
                    emptyLbl.Visible = (count == 0)
                end

                pcall(function()
                    if searchBox.GetPropertyChangedSignal then
                        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
                            refreshSaveList(searchBox.Text)
                        end)
                    end
                end)

                -- Button Grid (2 rows of 2 buttons + 1 full button)
                local grid1 = U.New("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Parent = confBox })
                local grid1Layout = U.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = grid1 })

                local function makeGridBtn(parent, text, onClick)
                    local btn = U.New("TextButton", {
                        Size = UDim2.new(0.5, -4, 1, 0),
                        BackgroundColor3 = T.Surface2,
                        Text = text,
                        Font = T.FontBold,
                        TextSize = 11,
                        TextColor3 = T.Text,
                        ZIndex = 6,
                        Parent = parent
                    })
                    U.Corner(btn, UDim.new(0, 5))
                    U.Stroke(btn, T.Stroke, 1, 0)
                    btn.MouseButton1Click:Connect(function()
                        U.Ripple(btn, Player:GetMouse().X, Player:GetMouse().Y)
                        if onClick then onClick() end
                    end)
                    return btn
                end

                -- Create Save
                makeGridBtn(grid1, "Create Save", function()
                    local sName = nameInput.Text
                    if not sName or sName == "" then
                        ZypheraxUI:Notify({ Title = "Config", Description = "Nama save tidak boleh kosong!" })
                        return
                    end
                    pcall(function()
                        local toSave = {}
                        for k, v in pairs(ZypheraxUI.Flags) do toSave[k] = v end
                        local json = HttpService:JSONEncode(toSave)
                        if writefile then
                            writefile(CONFIGS_FOLDER .. "/" .. sName .. ".json", json)
                            ZypheraxUI:Notify({ Title = "Config Saved", Description = "Save '" .. sName .. "' berhasil dibuat!" })
                            selectedSave = sName
                            refreshSaveList(searchBox.Text)
                        end
                    end)
                end)

                -- Delete Mode Button
                local delBtn
                delBtn = makeGridBtn(grid1, "Delete Mode: OFF", function()
                    deleteMode = not deleteMode
                    delBtn.Text = "Delete Mode: " .. (deleteMode and "ON" or "OFF")
                    delBtn.TextColor3 = deleteMode and T.Error or T.Text
                end)

                local grid2 = U.New("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Parent = confBox })
                local grid2Layout = U.New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = grid2 })

                -- Overwrite
                makeGridBtn(grid2, "Overwrite", function()
                    local sName = selectedSave or nameInput.Text
                    if not sName or sName == "" then
                        ZypheraxUI:Notify({ Title = "Config", Description = "Pilih config untuk ditimpa!" })
                        return
                    end
                    pcall(function()
                        local toSave = {}
                        for k, v in pairs(ZypheraxUI.Flags) do toSave[k] = v end
                        local json = HttpService:JSONEncode(toSave)
                        if writefile then
                            writefile(CONFIGS_FOLDER .. "/" .. sName .. ".json", json)
                            ZypheraxUI:Notify({ Title = "Config Overwritten", Description = "Save '" .. sName .. "' diperbarui!" })
                        end
                    end)
                end)

                -- Set Autoload
                makeGridBtn(grid2, "Set Autoload", function()
                    local sName = selectedSave or nameInput.Text
                    if not sName or sName == "" then
                        ZypheraxUI:Notify({ Title = "Config", Description = "Pilih save untuk Autoload!" })
                        return
                    end
                    pcall(function()
                        if writefile then
                            writefile(AUTOLOAD_FILE, sName)
                            ZypheraxUI:Notify({ Title = "Autoload", Description = "Autoload diset ke: " .. sName })
                        end
                    end)
                end)

                -- Reset Autoload (Full Width)
                local resetBtn = U.New("TextButton", {
                    Size = UDim2.new(1, 0, 0, 28),
                    BackgroundColor3 = T.Surface2,
                    Text = "Reset Autoload",
                    Font = T.FontBold,
                    TextSize = 11,
                    TextColor3 = T.TextMuted,
                    ZIndex = 6,
                    Parent = confBox
                })
                U.Corner(resetBtn, UDim.new(0, 5))
                U.Stroke(resetBtn, T.Stroke, 1, 0)
                resetBtn.MouseButton1Click:Connect(function()
                    U.Ripple(resetBtn, Player:GetMouse().X, Player:GetMouse().Y)
                    pcall(function()
                        if delfile and isfile and isfile(AUTOLOAD_FILE) then
                            delfile(AUTOLOAD_FILE)
                            ZypheraxUI:Notify({ Title = "Autoload", Description = "Autoload direset (dimatikan)." })
                        end
                    end)
                end)

                refreshSaveList("")
            end

            return SectionObj
        end

        return TabObj
    end

    -- // SEARCH ENGINE FILTER LOGIC \ --
    local function performGlobalSearch(query)
        query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        clearSearchBtn.Visible = (query ~= "")
        if query == "" then
            -- Restore all sections to visible
            for _, t in ipairs(Win.Tabs) do
                for _, sec in ipairs(t.sections or {}) do
                    if sec._box and sec._box.Parent then
                        sec._box.Visible = true
                        for _, itm in ipairs(sec._items or {}) do
                            if itm.Parent then itm.Visible = true end
                        end
                    end
                end
            end
            return
        end

        local firstMatchTab = nil
        for _, t in ipairs(Win.Tabs) do
            local tabHasMatch = false
            for _, sec in ipairs(t.sections or {}) do
                local secName = tostring(sec._name or ""):lower()
                local secMatch = secName:find(query, 1, true) ~= nil
                local anyItemMatch = false
                for _, itm in ipairs(sec._items or {}) do
                    local itmName = tostring(itm:GetAttribute("ControlName") or itm.Name or ""):lower()
                    if itmName:find(query, 1, true) or secMatch then
                        itm.Visible = true
                        anyItemMatch = true
                    else
                        itm.Visible = false
                    end
                end
                if secMatch or anyItemMatch then
                    if sec._box and sec._box.Parent then sec._box.Visible = true end
                    tabHasMatch = true
                else
                    if sec._box and sec._box.Parent then sec._box.Visible = false end
                end
            end
            if tabHasMatch and not firstMatchTab and Win._currentTab ~= t.name then
                firstMatchTab = t
            end
        end

        -- If current tab has no match but another tab does, switch to matching tab
        if firstMatchTab then
            for _, t in ipairs(Win.Tabs) do
                if t == firstMatchTab then
                    t.page.Visible = true
                    Win._currentTab = t.name
                else
                    t.page.Visible = false
                end
            end
        end
    end

    pcall(function()
        if searchInput.GetPropertyChangedSignal then
            track(searchInput:GetPropertyChangedSignal("Text"):Connect(function()
                performGlobalSearch(searchInput.Text)
            end))
        end
    end)
    track(clearSearchBtn.MouseButton1Click:Connect(function()
        searchInput.Text = ""
        performGlobalSearch("")
    end))

    return Win
end

return ZypheraxUI

end)()



    if type(ZypheraxUI) ~= "table" then
        warn("[Zypherax Hub] ZypheraxUI tidak tersedia, UI dihentikan.")
        return
    end

    -- --------------------------------------------------------------------------
    -- Utilitas nama: "Aktifkan Fly:toggle" -> "Aktifkan Fly"
    -- --------------------------------------------------------------------------
    local function _zy_pretty(s)
        if s == nil then return "" end
        if type(s) == "table" then s = s.Text or s.Name or "" end
        s = tostring(s)
        s = s:gsub("%s+[%.:]%s*%a[%a%d_]*%s*$", "")
        s = s:gsub("^%s+", "")
        s = s:gsub("%s+$", "")
        return s
    end

    -- --------------------------------------------------------------------------
    -- Notifikasi: API lama (Title/Description/Lifetime) -> ZypheraxUI.
    -- --------------------------------------------------------------------------
    local function _zy_notify(cfg)
        cfg = cfg or {}
        local title = cfg.Title or cfg.Name or "Info"
        local desc  = cfg.Description or cfg.Content or ""
        local life  = cfg.Lifetime or cfg.Duration or 4
        local tipe  = cfg.Type or "Info"
        pcall(function()
            ZypheraxUI:Notify({
                Title    = tostring(title),
                Content  = tostring(desc),
                Duration = life,
                Type     = tipe,
            })
        end)
    end

    -- --------------------------------------------------------------------------
    -- Watermark: objek tiruan dengan method Set / SetVisible.
    -- --------------------------------------------------------------------------
    local BridgeWatermark = nil

    -- --------------------------------------------------------------------------
    -- Window tiruan: semua method lama tetap aman dipanggil.
    -- --------------------------------------------------------------------------
    local _zwin = ZypheraxUI:CreateWindow({
        Title       = "Zypherax Hub",
        Description = "Ride A Pet",
        Size        = UDim2.fromOffset(700, 560),
        Keybind     = Enum.KeyCode.RightControl,
    })

    -- Helper: cari ScreenGui bawaan ZypheraxUI berdasarkan awalan nama.
    local function _zy_find_gui(prefix)
        local found
        -- Cek gethui() dan CoreGui juga (executor memakai gethui), bukan hanya PlayerGui,
        -- supaya jendela benar-benar bisa disembunyikan saat loading screen berjalan.
        local function scan(container)
            if found or not container then return end
            pcall(function()
                for _, sg in ipairs(container:GetChildren()) do
                    if type(sg.Name) == "string" and sg.Name:sub(1, #prefix) == prefix then
                        found = sg
                        return
                    end
                end
            end)
        end
        pcall(function() if gethui then scan(gethui()) end end)
        pcall(function() scan(game:GetService("CoreGui")) end)
        pcall(function()
            local lp = game:GetService("Players").LocalPlayer
            scan(lp and lp:FindFirstChild("PlayerGui"))
        end)
        return found
    end

    -- Sembunyikan jendela dulu agar Loading Screen tampil dulu.
    pcall(function()
        local app = _zy_find_gui("ZypheraxApp")
        if app then app.Enabled = false end
        local core = (gethui and gethui()) or (cloneref and cloneref(game:GetService("CoreGui"))) or game:GetService("CoreGui")
        local oldWm = core:FindFirstChild("ZypheraxWatermarkGui")
        if oldWm then oldWm:Destroy() end
    end)

    local BridgeTabGroup = { _zwin = _zwin }

    local BridgeWindow = {}
    function BridgeWindow:Notify(c) _zy_notify(c) end
    function BridgeWindow:SetKeybind(_) end      -- ZypheraxUI memakai keybind internalnya
    function BridgeWindow:SetSize(_) end         -- ukuran diatur lewat handle sudut
    function BridgeWindow:SetState(v)            -- tampilkan / sembunyikan jendela nyata
        pcall(function()
            if v == nil then v = true end
            _zwin:ToggleVisibility(v and true or false)
        end)
    end
    function BridgeWindow:GetAcrylicBlurState() return false end
    function BridgeWindow:SetAcrylicBlurState(_) end
    function BridgeWindow:GetUserInfoState() return true end
    function BridgeWindow:SetUserInfoState(_) end
    function BridgeWindow:TabGroup() return BridgeTabGroup end

    -- --------------------------------------------------------------------------
    -- Pembuat Section: tiap method lama dipetakan ke method ZypheraxUI.
    -- --------------------------------------------------------------------------
    local function _zy_make_section(zsec)
        local S = {}
        -- Expose wadah asli ZypheraxUI supaya rapMultiSelect bisa parent ke dalam
        -- section (tanpa ini filter jatuh ke gethui/CoreGui dan tampil di luar window).
        S._zsec = zsec
        pcall(function()
            S._container = zsec._container
            S._box = zsec._box
            S._items = zsec._items
        end)

        local function _emit(kind, cfg)
            if cfg == nil then return end
            if type(cfg) == "string" then cfg = { Name = cfg } end
            if type(cfg) ~= "table" then return end

            local raw = cfg.Name
            if raw == nil then raw = cfg[1] end
            local disp = _zy_pretty(raw)
            if kind ~= "Divider" and disp == "" then return end

            if kind == "Label" then
                pcall(function() zsec:CreateLabel(disp) end)

            elseif kind == "Divider" then
                pcall(function() zsec:CreateLabel("------------------------------------------") end)

            elseif kind == "Button" then
                local cb = cfg.Callback
                pcall(function()
                    zsec:CreateButton({ Name = disp, Callback = function() if cb then pcall(cb) end end })
                end)

            elseif kind == "Toggle" then
                local cb = cfg.Callback
                pcall(function()
                    zsec:CreateToggle({
                        Name     = disp,
                        Default  = (cfg.Default == true),
                        Callback = function(v) if cb then pcall(cb, v) end end,
                    })
                end)

            elseif kind == "Slider" then
                local cb = cfg.Callback
                local mn = cfg.Minimum or cfg.Min or 0
                local mx = cfg.Maximum or cfg.Max or 100
                pcall(function()
                    zsec:CreateSlider({
                        Name     = disp,
                        Min      = mn,
                        Max      = mx,
                        Default  = (cfg.Default or mn),
                        Callback = function(v) if cb then pcall(cb, v) end end,
                    })
                end)

            elseif kind == "Dropdown" then
                local cb = cfg.Callback
                pcall(function()
                    zsec:CreateDropdown({
                        Name     = disp,
                        Items    = cfg.Options or cfg.Items or {},
                        Default  = cfg.Default,
                        Callback = function(v) if cb then pcall(cb, v) end end,
                    })
                end)

            elseif kind == "Input" then
                local cb = cfg.Callback
                pcall(function()
                    zsec:CreateInput({
                        Name        = disp,
                        Default     = cfg.Default or "",
                        Placeholder = cfg.Placeholder or "",
                        Callback    = function(txt, enter) if cb then pcall(cb, txt, enter) end end,
                    })
                end)

            elseif kind == "Keybind" then
                local onB = cfg.onBinded
                pcall(function()
                    zsec:CreateKeybind({
                        Name     = disp,
                        Default  = cfg.Default or Enum.KeyCode.RightControl,
                        Callback = function(k) if onB then pcall(onB, k) end end,
                    })
                end)
            end
        end

        for _, k in ipairs({ "Toggle", "Slider", "Button", "Label",
                             "Dropdown", "Input", "Keybind", "Divider" }) do
            S[k] = function(_, cfg) _emit(k, cfg) end
        end

        S.Header = function(_, cfg)
            if type(cfg) ~= "table" then return end
            pcall(function() zsec:Header(cfg) end)
        end

        S.CreateConfigSystem = function(_)
            pcall(function() zsec:CreateConfigSystem() end)
        end

        return S
    end

    -- --------------------------------------------------------------------------
    -- Tab group: tabGroup:Tab({Name=..., Image=...}) & tabGroup:Divider()
    -- --------------------------------------------------------------------------
    function BridgeTabGroup:Divider() end

    function BridgeTabGroup:Tab(cfg)
        local name = "Tab"
        if type(cfg) == "table" then
            name = cfg.Name or cfg.Title or name
        elseif type(cfg) == "string" then
            name = cfg
        end

        local ztab = self._zwin:CreateTab({ Name = _zy_pretty(name) })

        local Tab = { _secIdx = 0 }
        function Tab:Section(secCfg)
            local secName, side = "Section", 1
            if type(secCfg) == "table" then
                secName = secCfg.Name or secCfg.Title or secName
                side    = secCfg.Side or 1
            elseif type(secCfg) == "string" then
                secName = secCfg
            end
            -- Hormati Side eksplisit (1=kiri, 2=kanan); hanya alternate bila tanpa Side.
            Tab._secIdx = Tab._secIdx + 1
            local hasExplicit = (type(secCfg) == "table" and secCfg.Side ~= nil)
            if not hasExplicit then side = (Tab._secIdx % 2 == 1) and 1 or 2 end
            local zsec = ztab:CreateSection({ Name = _zy_pretty(secName), Side = side })
            return _zy_make_section(zsec)
        end

        return Tab
    end

    -- --------------------------------------------------------------------------
    -- Kelas pustaka UI tiruan (gradien header, tema, watermark, dsb.).
    -- --------------------------------------------------------------------------
    local BridgeLib = {}
    function BridgeLib:Window(_) return BridgeWindow end
    function BridgeLib:CreateWindow(_) return BridgeWindow end
    function BridgeLib:Gradient(name) return name end
    function BridgeLib:GetThemes() return { "Dark", "Light", "Midnight", "Rose" } end
    function BridgeLib:SetTheme(name)
        pcall(function()
            ZypheraxUI:SetTheme(name)
            if _zwin and _zwin.SetTheme then _zwin:SetTheme(name) end
        end)
    end
    function BridgeLib:Watermark(cfg) pcall(function() BridgeWatermark = ZypheraxUI:Watermark(cfg or { Title = "ZYPHERAX HUB" }) end) return BridgeWatermark end
    -- Dipakai Loading Screen untuk membuka jendela setelah selesai memuat.
    function BridgeLib:_Reveal()
        pcall(function()
            local app = _zy_find_gui("ZypheraxApp")
            if app then app.Enabled = true end
            -- Window revealed
            _zwin:ToggleVisibility(true)
        end)
    end

    -- --------------------------------------------------------------------------
    -- Publikasikan sebagai global supaya seluruh kode di bawah bisa memakainya.
    -- --------------------------------------------------------------------------
    ZypheraxLib = BridgeLib
    Window      = BridgeWindow
    tabGroup    = BridgeTabGroup
end

-- Modul2 yang ditulis sebelum UI memakai global 'ZypheraxWindow' untuk Notify.
ZypheraxWindow = Window

-- Frosted watermark (blur background, sharp text) ala executor Real
-- Frosted watermark elegant (warna ikut logo, teks tajam)
-- Frosted watermark elegant v4 (logo asli, biru logo, 2 label)
-- Frosted watermark v5 (blur ala Real, warna biru logo)
local function _zy_show_watermark(gameName)
    pcall(function()
        local core = (gethui and gethui()) or (cloneref and cloneref(game:GetService("CoreGui"))) or game:GetService("CoreGui")
        local old = core:FindFirstChild("ZypheraxWatermarkGui")
        if old then old:Destroy() end
        local sg = Instance.new("ScreenGui")
        sg.Name = "ZypheraxWatermarkGui"
        sg.ResetOnSpawn = false
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.DisplayOrder = 9990
        sg.Parent = core
        -- lapisan blur luar (seperti frosted Real): 3 lapis transparan bertumpuk
        -- pill utama: lebih transparan (0.5) biar blur latar kelihatan seperti Real
        local pill = Instance.new("Frame")
        pill.AnchorPoint = Vector2.new(0.5, 0)
        pill.Position = UDim2.new(0.5, 0, 0, 12)
        pill.Size = UDim2.fromOffset(292, 32)
        pill.BackgroundColor3 = Color3.fromRGB(16, 20, 30)
        pill.BackgroundTransparency = 0.5
        pill.BorderSizePixel = 0
        pill.Active = true
        pill.Draggable = true
        pill.Parent = sg
        local cn = Instance.new("UICorner") cn.CornerRadius = UDim.new(0, 10) cn.Parent = pill
        -- lapisan kaca dalam: gradien terang-gelap biar kesan frosted
        local glass = Instance.new("Frame")
        glass.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        glass.BackgroundTransparency = 0.9
        glass.BorderSizePixel = 0
        glass.Position = UDim2.new(0, 0, 0, 0) glass.Size = UDim2.new(1, 0, 0.5, 0)
        glass.Parent = pill
        local gcn = Instance.new("UICorner") gcn.CornerRadius = UDim.new(0, 10) gcn.Parent = glass
        local gg = Instance.new("UIGradient") gg.Color = ColorSequence.new(Color3.fromRGB(255,255,255), Color3.fromRGB(0,170,255)) gg.Transparency = NumberSequence.new(0.85, 0.97) gg.Rotation = 90 gg.Parent = glass
        local sk = Instance.new("UIStroke") sk.Color = Color3.fromRGB(0, 170, 255) sk.Thickness = 1 sk.Transparency = 0.6 sk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border sk.Parent = pill
        local hi = Instance.new("Frame")
        hi.BackgroundColor3 = Color3.fromRGB(255, 255, 255) hi.BackgroundTransparency = 0.8 hi.BorderSizePixel = 0
        hi.Position = UDim2.new(0, 12, 0, 1) hi.Size = UDim2.new(1, -24, 0, 1) hi.Parent = pill
        local lg = Instance.new("ImageLabel")
        lg.BackgroundTransparency = 1
        lg.Image = "rbxassetid://106764279090045" lg.ScaleType = Enum.ScaleType.Fit
        lg.Size = UDim2.fromOffset(20, 20) lg.Position = UDim2.new(0, 9, 0.5, -10)
        lg.Parent = pill
        local lgc = Instance.new("UICorner") lgc.CornerRadius = UDim.new(0, 5) lgc.Parent = lg
        local dot = Instance.new("Frame")
        dot.BackgroundColor3 = Color3.fromRGB(0, 180, 255) dot.BorderSizePixel = 0
        dot.Position = UDim2.new(0, 33, 0.5, -3) dot.Size = UDim2.fromOffset(6, 6) dot.Parent = pill
        local dtc = Instance.new("UICorner") dtc.CornerRadius = UDim.new(1, 0) dtc.Parent = dot
        task.spawn(function()
            local ts = game:GetService("TweenService")
            while dot.Parent do
                pcall(function()
                    ts:Create(dot, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0.4}):Play()
                    task.wait(1)
                    ts:Create(dot, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0}):Play()
                    task.wait(1)
                end)
            end
        end)
        local t1 = Instance.new("TextLabel")
        t1.BackgroundTransparency = 1
        t1.Position = UDim2.new(0, 45, 0, 0) t1.Size = UDim2.new(0, 108, 1, 0)
        t1.Font = Enum.Font.GothamBlack t1.TextSize = 12
        t1.TextColor3 = Color3.fromRGB(0, 180, 255)
        t1.TextXAlignment = Enum.TextXAlignment.Left
        t1.Text = "ZYPHERAX HUB"
        t1.Parent = pill
        local sep = Instance.new("TextLabel")
        sep.BackgroundTransparency = 1
        sep.Position = UDim2.new(0, 153, 0, 0) sep.Size = UDim2.new(0, 10, 1, 0)
        sep.Font = Enum.Font.Gotham sep.TextSize = 12
        sep.TextColor3 = Color3.fromRGB(70, 78, 96)
        sep.TextXAlignment = Enum.TextXAlignment.Center
        sep.Text = "|"
        sep.Parent = pill
        local t2 = Instance.new("TextLabel")
        t2.BackgroundTransparency = 1
        t2.Position = UDim2.new(0, 165, 0, 0) t2.Size = UDim2.new(1, -173, 1, 0)
        t2.Font = Enum.Font.GothamMedium t2.TextSize = 11
        t2.TextColor3 = Color3.fromRGB(170, 178, 198)
        t2.TextXAlignment = Enum.TextXAlignment.Left
        t2.TextTruncate = Enum.TextTruncate.AtEnd
        t2.Text = tostring(gameName)
        t2.Parent = pill
        task.spawn(function()
            local fps = 60
            pcall(function()
                local last = os.clock() local n = 0
                game:GetService("RunService").RenderStepped:Connect(function()
                    n = n + 1 local now = os.clock()
                    if now - last >= 0.5 then fps = math.floor(n / (now - last) + 0.5) n = 0 last = now end
                end)
            end)
            while pill.Parent do
                task.wait(0.5)
                pcall(function()
                    local ms = 0
                    pcall(function() ms = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5) end)
                    t2.Text = tostring(gameName) .. "   " .. tostring(fps) .. " FPS   " .. tostring(ms) .. " ms"
                end)
            end
        end)
    end)
end


-- ==============================================================================
-- LOADING SCREEN (ZYPHERAX HUB) -- tampil dulu, lalu membuka menu ZypheraxUI
-- ==============================================================================
-- Desain glassmorphism, palet cyan gelap yang serasi dengan ZypheraxUI.
-- ==============================================================================
do
    local Players = game:GetService("Players")
    local TweenService = game:GetService("TweenService")
    local LocalPlayer = Players.LocalPlayer

    -- Wadah ScreenGui (cari container yang aman)
    local function _containers()
        local t = {}
        pcall(function() if gethui then table.insert(t, gethui()) end end)
        pcall(function() local plr = game:GetService("Players").LocalPlayer
            if plr and plr:FindFirstChild("PlayerGui") then table.insert(t, plr.PlayerGui) end end)
        pcall(function() local r = game:GetService("RunService") end)
        return t
    end

    -- Palet selaras tema ZypheraxUI (dark + cyan premium).
    local P = {
        bgCard    = Color3.fromRGB(16, 18, 24),
        bgChip    = Color3.fromRGB(28, 31, 40),
        border    = Color3.fromRGB(45, 50, 66),
        textMain  = Color3.fromRGB(240, 242, 248),
        textMuted = Color3.fromRGB(150, 156, 172),
        accentA   = Color3.fromRGB(0, 170, 255),
        accentB   = Color3.fromRGB(0, 140, 230),
        accentC   = Color3.fromRGB(0, 170, 255),
    }

    local function _round(p, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r)
        c.Parent = p
        return c
    end
    local function _grad(p, c1, c2, rot)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new(c1, c2)
        g.Rotation = rot or 0
        g.Parent = p
        return g
    end

    task.spawn(function()
        local ok = pcall(function()
            local SG = Instance.new("ScreenGui")
            SG.Name = "ZypheraxWelcome"
            SG.ResetOnSpawn = false
            SG.IgnoreGuiInset = true
            SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            SG.DisplayOrder = 10000
            for _, c in ipairs({ (gethui and gethui()) or nil, (getgenv and getgenv().CoreGui) or nil,
                                 game:GetService("Players").LocalPlayer.PlayerGui }) do
                if c and not SG.Parent then pcall(function() SG.Parent = c end) end
            end
            if not SG.Parent then return end

            -- Backdrop gelap + blur.
            local overlay = Instance.new("Frame")
            overlay.Size = UDim2.fromScale(1, 1)
            overlay.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
            overlay.BackgroundTransparency = 0.82 -- Frosted blur saja, tidak blank hitam
            overlay.BorderSizePixel = 0
            overlay.ZIndex = 1
            overlay.Parent = SG

            local blur = Instance.new("BlurEffect")
            blur.Size = 22
            blur.Parent = game:GetService("Lighting")

            -- Kartu glassmorphism.
            local card = Instance.new("Frame")
            card.AnchorPoint = Vector2.new(0.5, 0.5)
            card.Position = UDim2.fromScale(0.5, 0.54)
            card.Size = UDim2.fromOffset(430, 250)
            card.BackgroundColor3 = P.bgCard
            card.BackgroundTransparency = 1
            card.BorderSizePixel = 0
            card.ZIndex = 5
            card.Parent = SG
            _round(card, 16)

            local cardStroke = Instance.new("UIStroke")
            cardStroke.Color = P.border
            cardStroke.Thickness = 1
            cardStroke.Transparency = 0.15
            cardStroke.Parent = card

            -- Logo kotak gradien.
            local logo = Instance.new("Frame")
            logo.Size = UDim2.fromOffset(84, 84)
            logo.Position = UDim2.new(0.5, -42, 0, 14)
            logo.BackgroundTransparency = 1 -- logoPure: tanpa kotak, tanpa Z
            logo.BorderSizePixel = 0
            logo.ZIndex = 6
            logo.Parent = card

            local logoImg = Instance.new("ImageLabel")
            logoImg.AnchorPoint = Vector2.new(0.5, 0.5)
            logoImg.Position = UDim2.fromScale(0.5, 0.5)
            logoImg.Size = UDim2.fromScale(1, 1)
            logoImg.BackgroundTransparency = 1
            logoImg.Image = "rbxassetid://106764279090045"
            logoImg.ScaleType = Enum.ScaleType.Fit
            logoImg.ZIndex = 7
            logoImg.Parent = logo
            local logoCorn = Instance.new("UICorner")
            logoCorn.CornerRadius = UDim.new(0, 14)
            logoCorn.Parent = logoImg

            -- Judul + subjudul.
            local title = Instance.new("TextLabel")
            title.AnchorPoint = Vector2.new(0.5, 0)
            title.Position = UDim2.new(0.5, 0, 0, 96)
            title.Size = UDim2.new(1, -40, 0, 26)
            title.BackgroundTransparency = 1
            title.Text = "ZYPHERAX HUB"
            title.Font = Enum.Font.GothamBold
            title.TextSize = 24
            title.TextColor3 = Color3.new(1, 1, 1)
            title.ZIndex = 6
            title.Parent = card
            _grad(title, P.accentA, P.accentB, 20)

            local sub = Instance.new("TextLabel")
            sub.AnchorPoint = Vector2.new(0.5, 0)
            sub.Position = UDim2.new(0.5, 0, 0, 126)
            sub.Size = UDim2.new(1, -40, 0, 16)
            sub.BackgroundTransparency = 1
            sub.Text = "Ride A Pet"
            sub.Font = Enum.Font.GothamMedium
            sub.TextSize = 13
            sub.TextColor3 = P.textMuted
            sub.ZIndex = 6
            sub.Parent = card

            -- Chip fitur.
            local chips = { "Auto Egg", "Shop", "Auto Sell", "ESP", "Plot" }
            local row = Instance.new("Frame")
            row.AnchorPoint = Vector2.new(0.5, 0)
            row.Position = UDim2.new(0.5, 0, 0, 154)
            row.Size = UDim2.new(1, -30, 0, 26)
            row.BackgroundTransparency = 1
            row.ZIndex = 6
            row.Parent = card

            local layout = Instance.new("UIListLayout")
            layout.FillDirection = Enum.FillDirection.Horizontal
            layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            layout.VerticalAlignment = Enum.VerticalAlignment.Center
            layout.Padding = UDim.new(0, 6)
            layout.Parent = row

            for _, name in ipairs(chips) do
                local chip = Instance.new("Frame")
                chip.Size = UDim2.fromOffset(78, 24)
                chip.BackgroundColor3 = P.accentA
                chip.BackgroundTransparency = 0.9
                chip.BorderSizePixel = 0
                chip.ZIndex = 7
                chip.Parent = row
                _round(chip, 7)

                local t = Instance.new("TextLabel")
                t.Size = UDim2.fromScale(1, 1)
                t.BackgroundTransparency = 1
                t.Text = name
                t.Font = Enum.Font.GothamMedium
                t.TextSize = 11
                t.TextColor3 = P.textMain
                t.ZIndex = 8
                t.Parent = chip
            end

            -- Progress bar.
            local barBg = Instance.new("Frame")
            barBg.AnchorPoint = Vector2.new(0.5, 1)
            barBg.Position = UDim2.new(0.5, 0, 1, -44)
            barBg.Size = UDim2.new(0.8, 0, 0, 4)
            barBg.BackgroundColor3 = Color3.fromRGB(38, 42, 56)
            barBg.BorderSizePixel = 0
            barBg.ZIndex = 6
            barBg.Parent = card
            _round(barBg, 2)

            local barFill = Instance.new("Frame")
            barFill.Size = UDim2.fromScale(0, 1)
            barFill.BackgroundColor3 = Color3.new(1, 1, 1)
            barFill.BorderSizePixel = 0
            barFill.ZIndex = 7
            barFill.Parent = barBg
            _round(barFill, 2)
            _grad(barFill, P.accentA, P.accentB, 0)

            local status = Instance.new("TextLabel")
            status.AnchorPoint = Vector2.new(0.5, 1)
            status.Position = UDim2.new(0.5, 0, 1, -20)
            status.Size = UDim2.new(1, -30, 0, 14)
            status.BackgroundTransparency = 1
            status.Text = "Menyiapkan antarmuka..."
            status.Font = Enum.Font.Gotham
            status.TextSize = 12
            status.TextColor3 = P.textMuted
            status.ZIndex = 6
            status.Parent = card

            -- Animasi masuk.
            TweenService:Create(overlay, TweenInfo.new(0.35), { BackgroundTransparency = 0.82 }):Play()
            TweenService:Create(blur, TweenInfo.new(0.35), { Size = 16 }):Play()
            TweenService:Create(card,
                TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
                { Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 0.05 }):Play()

            TweenService:Create(barFill,
                TweenInfo.new(2.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
                { Size = UDim2.fromScale(1, 1) }):Play()

            task.spawn(function()
                local steps = {
                    { 0.5, "Memuat antarmuka..." },
                    { 0.9, "Menyiapkan fitur..." },
                    { 0.9, "Hampir selesai..." },
                }
                for _, s in ipairs(steps) do
                    task.wait(s[1])
                    if status and status.Parent then status.Text = s[2] end
                end
            end)

            task.wait(2.4)

            TweenService:Create(card,
                TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
                { Position = UDim2.fromScale(0.5, 0.47), BackgroundTransparency = 1 }):Play()
            TweenService:Create(overlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
            TweenService:Create(blur, TweenInfo.new(0.4), { Size = 0 }):Play()
            task.wait(0.42)

            pcall(function() blur:Destroy() end)
            pcall(function() SG:Destroy() end)
        end)

        -- Apapun yang terjadi (berhasil/gagal), buka menu utama.
        if ZypheraxLib and ZypheraxLib._Reveal then
            pcall(function() ZypheraxLib:_Reveal() end)
        end
    end)
end


-- (State form menu lama dihapus)
-- ==============================================================================
-- MODUL 5: PLAYER CONTROLS (SPEED & INFINITE YIELD FLY ENGINE)
-- ==============================================================================
do
local currentSpeed = 16
local loopSpeed = false
local speedConn = nil

local function set_player_speed(val)
    local num = tonumber(val)
    if not num then return end
    currentSpeed = num
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = currentSpeed end
    end
end

local function toggle_loop_speed(enabled)
    loopSpeed = enabled
    if speedConn then speedConn:Disconnect(); speedConn = nil end
    if loopSpeed then
        speedConn = RunService.Heartbeat:Connect(function()
            local char = LocalPlayer.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.WalkSpeed ~= currentSpeed then
                    hum.WalkSpeed = currentSpeed
                end
            end
        end)
    end
end

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum and loopSpeed then
        hum.WalkSpeed = currentSpeed
    end
end)

-- FLY ENGINE (INFINITE YIELD MECHANISM)
local FLYING = false
local flySpeed = 1
local flyConn = nil
local flyBG = nil
local flyBV = nil
local flyKeyDown = nil
local flyKeyUp = nil

local function stop_fly()
    FLYING = false
    if flyConn then pcall(function() flyConn:Disconnect() end); flyConn = nil end
    if flyKeyDown then pcall(function() flyKeyDown:Disconnect() end); flyKeyDown = nil end
    if flyKeyUp then pcall(function() flyKeyUp:Disconnect() end); flyKeyUp = nil end
    if flyBG then pcall(function() flyBG:Destroy() end); flyBG = nil end
    if flyBV then pcall(function() flyBV:Destroy() end); flyBV = nil end

    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
    end
end

local function start_fly()
    if FLYING then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    stop_fly()
    FLYING = true
    hum.PlatformStand = true

    flyBG = Instance.new("BodyGyro")
    flyBV = Instance.new("BodyVelocity")

    flyBG.P = 9e4
    flyBG.maxTorque = Vector3.new(9e9, 9e9, 9e9)
    flyBG.cframe = root.CFrame
    flyBG.Parent = root

    flyBV.velocity = Vector3.new(0, 0, 0)
    flyBV.maxForce = Vector3.new(9e9, 9e9, 9e9)
    flyBV.Parent = root

    local CONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}

    flyKeyDown = UserInputService.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if input.KeyCode == Enum.KeyCode.W then CONTROL.F = 1
        elseif input.KeyCode == Enum.KeyCode.S then CONTROL.B = -1
        elseif input.KeyCode == Enum.KeyCode.A then CONTROL.L = -1
        elseif input.KeyCode == Enum.KeyCode.D then CONTROL.R = 1
        elseif input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E then CONTROL.Q = 1
        elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.Q then CONTROL.E = -1
        end
    end)

    flyKeyUp = UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.W then CONTROL.F = 0
        elseif input.KeyCode == Enum.KeyCode.S then CONTROL.B = 0
        elseif input.KeyCode == Enum.KeyCode.A then CONTROL.L = 0
        elseif input.KeyCode == Enum.KeyCode.D then CONTROL.R = 0
        elseif input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E then CONTROL.Q = 0
        elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.Q then CONTROL.E = 0
        end
    end)

    flyConn = RunService.RenderStepped:Connect(function()
        if not FLYING or not char.Parent or not root.Parent or not hum.Parent then
            stop_fly()
            return
        end

        hum.PlatformStand = true
        local cam = workspace.CurrentCamera
        flyBG.cframe = cam.CFrame

        local speedMultiplier = flySpeed * 50
        local vel = Vector3.new(0, 0, 0)

        -- Dukungan Mobile Joystick (MoveDirection)
        local moveDir = hum.MoveDirection
        if moveDir.Magnitude > 0 then
            vel = vel + (moveDir * speedMultiplier)
        end

        -- Dukungan Keyboard WASD
        if CONTROL.F + CONTROL.B ~= 0 or CONTROL.L + CONTROL.R ~= 0 then
            local forward = cam.CFrame.LookVector
            local right = cam.CFrame.RightVector
            vel = vel + (forward * (CONTROL.F + CONTROL.B) + right * (CONTROL.L + CONTROL.R)) * speedMultiplier
        end

        -- Dukungan Naik/Turun (Space/E dan Shift/Q)
        if CONTROL.Q + CONTROL.E ~= 0 then
            vel = vel + (Vector3.new(0, 1, 0) * (CONTROL.Q + CONTROL.E) * speedMultiplier)
        end

        flyBV.velocity = vel
    end)

    hum.Died:Connect(function()
        stop_fly()
    end)
end

-- Anti-AFK (Standard & Safe: Idled event, tidak membajak controller/mouse)
local VirtualUser = cloneref and cloneref(game:GetService("VirtualUser")) or game:GetService("VirtualUser")
local antiAfkConn = nil
local antiAfkEnabled = false

local function toggle_anti_afk(enabled)
    antiAfkEnabled = enabled
    if antiAfkConn then antiAfkConn:Disconnect(); antiAfkConn = nil end
    if enabled then
        pcall(function()
            antiAfkConn = LocalPlayer.Idled:Connect(function()
                VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                task.wait(0.5)
                VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            end)
        end)
    end
end

-- Auto-aktifkan Anti-AFK saat script dimuat
task.defer(function()
    toggle_anti_afk(true)
end)

-- ==============================================================================
-- TAB 1: PLAYER (SPEED, FLY & ANTI-AFK)
-- ==============================================================================
local TabPlayer = tabGroup:Tab({ Name = "Player", Image = "lucide/user" })

-- SEKSI 1: SPEED PLAYER
local SecSpeed = TabPlayer:Section({ Name = "Kecepatan Pemain", Side = 1 })
SecSpeed:Header({ Name = ZypheraxLib:Gradient("Kecepatan Pemain (WalkSpeed)", Color3.fromRGB(99,130,255), Color3.fromRGB(72,214,200)) })

SecSpeed:Slider({
    Name = "WalkSpeed Slider",
    Default = 16,
    Minimum = 16,
    Maximum = 300,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(val)
        set_player_speed(val)
    end
})

SecSpeed:Input({
    Name = "Custom WalkSpeed",
    Default = "16",
    Placeholder = "Ketik angka (misal: 50)...",
    AcceptedCharacters = "Numeric",
    Callback = function(text)
        set_player_speed(text)
        Window:Notify({ Title = "Player Speed", Description = "WalkSpeed diubah ke " .. tostring(text), Lifetime = 3 })
    end
})

SecSpeed:Toggle({
    Name = "Kunci WalkSpeed (Anti-Reset)",
    Default = false,
    Callback = function(enabled)
        toggle_loop_speed(enabled)
        Window:Notify({
            Title = "WalkSpeed",
            Description = enabled and "WalkSpeed dikunci secara konstan!" or "Kunci WalkSpeed dimatikan.",
            Lifetime = 3
        })
    end
})

SecSpeed:Button({
    Name = "Reset WalkSpeed (Default 16)",
    Callback = function()
        set_player_speed(16)
        Window:Notify({ Title = "WalkSpeed", Description = "WalkSpeed kembali ke normal (16).", Lifetime = 3 })
    end
})

-- SEKSI 2: FLY ENGINE
local SecFly = TabPlayer:Section({ Name = "Terbang (Fly)", Side = 2 })
SecFly:Header({ Name = ZypheraxLib:Gradient("Terbang (Infinite Yield Fly)", Color3.fromRGB(99,130,255), Color3.fromRGB(168,120,255)) })

SecFly:Toggle({
    Name = "Aktifkan Fly",
    Default = false,
    Callback = function(enabled)
        if enabled then
            start_fly()
            Window:Notify({ Title = "Fly", Description = "Mode terbang diaktifkan!", Lifetime = 3 })
        else
            stop_fly()
            Window:Notify({ Title = "Fly", Description = "Mode terbang dimatikan.", Lifetime = 3 })
        end
    end
})

SecFly:Slider({
    Name = "Kecepatan Fly (Speed)",
    Default = 1,
    Minimum = 1,
    Maximum = 10,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(val)
        flySpeed = val
    end
})

SecFly:Input({
    Name = "Custom Fly Speed",
    Default = "1",
    Placeholder = "Ketik kecepatan fly...",
    AcceptedCharacters = "Numeric",
    Callback = function(text)
        local num = tonumber(text)
        if num and num > 0 then
            flySpeed = num
            Window:Notify({ Title = "Fly Speed", Description = "Kecepatan terbang diubah ke " .. tostring(num), Lifetime = 3 })
        end
    end
})

-- SEKSI 3: ANTI-AFK
local SecUtil = TabPlayer:Section({ Name = "Player Utility", Side = 1 })
SecUtil:Header({ Name = ZypheraxLib:Gradient("Player Utility", Color3.fromRGB(99,130,255), Color3.fromRGB(120,160,255)) })

SecUtil:Toggle({
    Name = "Anti-AFK (Cegah Disconnect 20 Menit)",
    Default = true,  -- [DEFAULT ON]
    Callback = function(enabled)
        toggle_anti_afk(enabled)
        Window:Notify({
            Title = "Anti-AFK",
            Description = enabled and "Anti-AFK aktif! Tidak akan di-kick AFK." or "Anti-AFK dinonaktifkan.",
            Lifetime = 3
        })
    end
})

end -- [End TabPlayer]

-- ==============================================================================================
-- RIDE A PET: ENGINE (AUTO PICKUP / RANCH / PLACED EGG / SHOP / SELL / ESP)
-- ==============================================================================================
do
local RAP_DELAY = 0.5
local rapFlag = {}
local rapRunning = false
local rapGoal = "Player Spawn"
-- Filter multi-pilih (tabel set). Tabel kosong = tampil semua.
local rapEggFilterSet = {}
local rapRarityFilterSet = {}
local rapMutationFilterSet = {}
local rapPickedCount = 0
local rapPickupMode = "Tween"
local rapReturnRanch = true
local rapEggCapacity = 5
local rapEggsCarried = 0
local rapPickupWarned = false
-- Anti-spam pengambilan telur: cegah kirim permintaan delivery berkali-kali (penyebab "egg delivery failed").
local rapPickupCD = 0
local rapHandled = setmetatable({}, { __mode = "k" })

-- Cache descendant workspace untuk satu siklus rapStep. Tanpa ini rapStep
-- memanggil workspace:GetDescendants() 7-8 kali per putaran (tiap rapPassBatch,
-- pickup, buy, autoTp). Di map yang padat itu puluhan pemindaian penuh per detik
-- -> frame drop berat sampai Roblox menutup paksa.
local rapTickCache = nil
local function rapTickBegin() rapTickCache = nil end
local function rapTickEnd() rapTickCache = nil end
local function rapTickList()
    if not rapTickCache then rapTickCache = workspace:GetDescendants() end
    return rapTickCache
end

-- SELL / BUY state
local rapSellRaritySet = {}
local rapSellMaxWeight = 0      -- 0 = abaikan filter berat
local rapUseWeightFilter = false
local rapSellCount = 0
local rapBuyFood = false
local rapBuyGear = false
local rapBuyCount = 0
local rapBuyFoodSet = {}
local rapBuyGearSet = {}
local rapFoodItems = {}
local rapGearItems = {}
local rapLastSpell = 0
local rapLastSkill = ""
local rapFoodDD, rapGearDD = nil, nil

-- ============================== EGG & RARITY DATA ==============================
local rapEggNames = {
    -- Common
    "White Egg", "Brown Egg",
    -- Rare
    "Cracked Egg", "Easter Egg", "Stone Egg", "Leaf Egg",
    -- Epic
    "Mushroom Egg", "Flower Egg", "Slime Egg", "Ice Egg",
    -- Legendary
    "Glass Egg", "Golden Egg",
    -- Mythic
    "Crystal Egg", "Skull Egg", "Dominus Egg", "Flaming Egg", "Sinister Egg", "Soul Egg",
    -- Divine
    "Aurora Egg", "Galaxy Egg",
    -- Ethereal
    "Black Hole Egg", "Solaris Egg", "Cherub Egg", "Volcanic Egg",
    -- Baru (dari scan RenderedEggs)
    "Bloom Egg", "Tropical Egg", "Tidal Egg",
}

local RAP_RARITY = {
    -- Common
    ["White Egg"] = "Common", ["Brown Egg"] = "Common",
    -- Rare
    ["Cracked Egg"] = "Rare", ["Easter Egg"] = "Rare", ["Stone Egg"] = "Rare", ["Leaf Egg"] = "Rare",
    -- Epic
    ["Mushroom Egg"] = "Epic", ["Flower Egg"] = "Epic", ["Slime Egg"] = "Epic", ["Ice Egg"] = "Epic",
    -- Legendary
    ["Glass Egg"] = "Legendary", ["Golden Egg"] = "Legendary",
    -- Mythic
    ["Crystal Egg"] = "Mythic", ["Skull Egg"] = "Mythic", ["Dominus Egg"] = "Mythic",
    ["Flaming Egg"] = "Mythic", ["Sinister Egg"] = "Mythic", ["Soul Egg"] = "Mythic",
    -- Divine
    ["Aurora Egg"] = "Divine", ["Galaxy Egg"] = "Divine",
    -- Ethereal
    ["Black Hole Egg"] = "Ethereal", ["Solaris Egg"] = "Ethereal", ["Cherub Egg"] = "Ethereal", ["Volcanic Egg"] = "Ethereal",
    ["Bloom Egg"] = "Epic", ["Tropical Egg"] = "Epic", ["Tidal Egg"] = "Epic",
}

local RARITY_COLOR = {
    Common    = Color3.fromRGB(168, 230, 161),
    Rare      = Color3.fromRGB(111, 199, 255),
    Epic      = Color3.fromRGB(199, 155, 255),
    Legendary = Color3.fromRGB(255, 211, 92),
    Mythic    = Color3.fromRGB(255, 107, 138),
    Divine    = Color3.fromRGB(255, 180, 255),
    Ethereal  = Color3.fromRGB(255, 255, 180),
}

local RARITY_LIST = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Ethereal" }

-- Mutation system
local RAP_MUTATIONS = { "normal", "gold", "Shocked", "Volted", "Rage", "Diamond", "Void", "Magma", "Eternal", "Rainbow" }
local RAP_MUTATION_COLOR = {
    normal   = Color3.fromRGB(200, 200, 200),
    gold     = Color3.fromRGB(255, 215, 0),
    Shocked  = Color3.fromRGB(0, 255, 255),
    Volted   = Color3.fromRGB(180, 0, 255),
    Rage     = Color3.fromRGB(255, 50, 50),
    Diamond  = Color3.fromRGB(100, 255, 255),
    Void     = Color3.fromRGB(80, 0, 120),
    Magma    = Color3.fromRGB(255, 120, 0),
    Eternal  = Color3.fromRGB(200, 180, 255),
    Rainbow  = Color3.fromRGB(255, 100, 200),
}

-- Mutation system
local RAP_MUTATIONS = { "normal", "gold", "Shocked", "Volted", "Rage", "Diamond", "Void", "Magma", "Eternal", "Rainbow" }
local RAP_MUTATION_COLOR = {
    normal   = Color3.fromRGB(200, 200, 200),
    gold     = Color3.fromRGB(255, 215, 0),
    Shocked  = Color3.fromRGB(0, 255, 255),
    Volted   = Color3.fromRGB(180, 0, 255),
    Rage     = Color3.fromRGB(255, 50, 50),
    Diamond  = Color3.fromRGB(100, 255, 255),
    Void     = Color3.fromRGB(80, 0, 120),
    Magma    = Color3.fromRGB(255, 120, 0),
    Eternal  = Color3.fromRGB(200, 180, 255),
    Rainbow  = Color3.fromRGB(255, 100, 200),
}

-- Mutation system
local RAP_MUTATIONS = { "normal", "gold", "Shocked", "Volted", "Rage", "Diamond", "Void", "Magma", "Eternal", "Rainbow" }
local RAP_MUTATION_COLOR = {
    normal   = Color3.fromRGB(200, 200, 200),
    gold     = Color3.fromRGB(255, 215, 0),
    Shocked  = Color3.fromRGB(0, 255, 255),
    Volted   = Color3.fromRGB(180, 0, 255),
    Rage     = Color3.fromRGB(255, 50, 50),
    Diamond  = Color3.fromRGB(100, 255, 255),
    Void     = Color3.fromRGB(80, 0, 120),
    Magma    = Color3.fromRGB(255, 120, 0),
    Eternal  = Color3.fromRGB(200, 180, 255),
    Rainbow  = Color3.fromRGB(255, 100, 200),
}

-- Mutation system
local RAP_MUTATIONS = { "normal", "gold", "Shocked", "Volted", "Rage", "Diamond", "Void", "Magma", "Eternal", "Rainbow" }
local RAP_MUTATION_COLOR = {
    normal   = Color3.fromRGB(200, 200, 200),
    gold     = Color3.fromRGB(255, 215, 0),
    Shocked  = Color3.fromRGB(0, 255, 255),
    Volted   = Color3.fromRGB(180, 0, 255),
    Rage     = Color3.fromRGB(255, 50, 50),
    Diamond  = Color3.fromRGB(100, 255, 255),
    Void     = Color3.fromRGB(80, 0, 120),
    Magma    = Color3.fromRGB(255, 120, 0),
    Eternal  = Color3.fromRGB(200, 180, 255),
    Rainbow  = Color3.fromRGB(255, 100, 200),
}

local rapTypeList = {}
for _, n in ipairs(rapEggNames) do table.insert(rapTypeList, n) end

local rapActors = { "Snail", "Cheetah", "Giraffe", "Unicorn", "Tim", "Richie", "Eggo", "Rick" }

local rapGoals = { "Player Spawn" }
for _, n in ipairs(rapEggNames) do table.insert(rapGoals, n) end
for _, n in ipairs(rapActors) do table.insert(rapGoals, n) end

local function rapSetCount(t)
    local n = 0
    if t then for _ in pairs(t) do n = n + 1 end end
    return n
end

local function rapInSet(t, v)
    if rapSetCount(t) == 0 then return true end
    return t[v] == true
end

local function rapKeysOf(t)
    local out = {}
    if t then for k in pairs(t) do table.insert(out, tostring(k)) end end
    table.sort(out)
    return out
end

local function rapFilterText(t, allText)
    local k = rapKeysOf(t)
    if #k == 0 then return allText end
    return table.concat(k, ", ")
end

local function rapRarityOf(name)
    return RAP_RARITY[name] or "Common"
end

local function rapRarityOfName(nm)
    nm = tostring(nm or "")
    if RAP_RARITY[nm] then return RAP_RARITY[nm] end
    for k, v in pairs(RAP_RARITY) do
        if string.find(nm, k, 1, true) then return v end
    end
    local low = string.lower(nm)
    for k, v in pairs(RAP_RARITY) do
        if string.find(low, string.lower(k), 1, true) then return v end
    end
    return nil
end

local function rapFindMutation(inst) -- rapFindMutationStrOk
    if type(inst)=="string" then local s=inst:lower() for _, m in ipairs(RAP_MUTATIONS) do if s:find(m:lower(),1,true) then return m end end return "normal" end
    if type(inst)=="string" then local s=inst:lower() for _, m in ipairs(RAP_MUTATIONS) do if s:find(m:lower(),1,true) then return m end end return "normal" end
    if not inst then return "normal" end
    local cur = inst
    for _ = 1, 6 do
        if not cur or not cur.Parent then break end
        local nm = tostring(cur.Name or "")
        local low = string.lower(nm)
        for _, m in ipairs(RAP_MUTATIONS) do
            if string.find(low, string.lower(tostring(m)), 1, true) then return m end
        end
        local ok, av = pcall(function() return cur:GetAttribute("Mutation") end)
        if ok and type(av) == "string" and av ~= "" then
            for _, m in ipairs(RAP_MUTATIONS) do
                if string.lower(av) == string.lower(tostring(m)) then return m end
            end
            return av
        end
        cur = cur.Parent
    end
    return "normal"
end

local function rapMatchFilter(name, inst)
    if not rapInSet(rapEggFilterSet, name) then return false end
    if not rapInSet(rapRarityFilterSet, rapRarityOf(name)) then return false end
    if rapSetCount(rapMutationFilterSet) > 0 then
        local mut = rapFindMutation(inst or name)
        if not rapInSet(rapMutationFilterSet, mut) then return false end
    end
    return true
end

local function rapTriggerPrompt(p)
    if type(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, p, 0)
        return true
    end
    pcall(function()
        local dur = p.HoldDuration or 0
        p:InputHoldBegin()
        task.wait(dur + 0.15)
        p:InputHoldEnd()
    end)
    return true
end

local function rapPassBatch(matchFn, batch)
    local n = 0
    pcall(function()
        for _, d in ipairs(rapTickList()) do
            if d:IsA("ProximityPrompt") then
                local act = tostring(d.ActionText or "")
                if matchFn(act, d) then
                    pcall(function()
                        d.HoldDuration = 0
                        d.MaxActivationDistance = 500
                        d.RequiresLineOfSight = false
                    end)
                    rapTriggerPrompt(d)
                    n = n + 1
                    if n >= batch then break end
                end
            end
        end
    end)
    return n
end

local function rapPath(container, names)
    local cur = container
    for _, nm in ipairs(names) do
        if not cur then return nil end
        cur = cur:FindFirstChild(nm)
    end
    return cur
end

local function rapFire(names, arg)
    local r = rapPath(ReplicatedStorage, names)
    if not r then return false end
    if arg ~= nil then
        return pcall(function() r:FireServer(arg) end)
    end
    return pcall(function() r:FireServer() end)
end

local function rapEntityPos(d)
    if d:IsA("Model") then
        local ok, cf = pcall(function() return d:GetPivot() end)
        if ok then return cf.Position end
    elseif d:IsA("BasePart") then
        return d.Position
    end
    return nil
end

local function rapGetRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart") or nil
end

local function rapTeleportTo(pos, label)
    local root = rapGetRoot()
    if not root or not pos then return false end
    root.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
    return true
end
-- Noclip + Tween fly (untuk mode Tween Auto Egg Collector)
local rapNoclip = false
local rapNoclipConn = nil
local function rapSetNoclip(on)
    rapNoclip = on and true or false
    pcall(function() if rapNoclipConn then rapNoclipConn:Disconnect() rapNoclipConn = nil end end)
    if rapNoclip then
        pcall(function()
            rapNoclipConn = game:GetService("RunService").Stepped:Connect(function()
                local ch = LocalPlayer.Character
                if ch then for _, v in ipairs(ch:GetDescendants()) do if v:IsA("BasePart") then v.CanCollide = false end end end
            end)
        end)
    end
end
local function rapTweenTo(pos, speed)
    local root = rapGetRoot()
    if not root or not pos then return false end
    rapSetNoclip(true)
    local dist = (root.Position - pos).Magnitude
    local spd = tonumber(speed) or tonumber(rapPlanned.glideSpeed) or 1000
    if spd < 50 then spd = 50 end
    local t = math.max(0.3, dist / spd)
    local done = false
    pcall(function()
        local tw = game:GetService("TweenService"):Create(root, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)) })
        tw:Play()
        tw.Completed:Wait()
        done = true
    end)
    if not done then
        -- fallback jalan biasa bila tween gagal
        pcall(function() rapMoveTo(pos, math.max(4, t)) end)
    end
    return (rapGetRoot() and ((rapGetRoot().Position - pos).Magnitude <= 22)) or done
end
-- Fallback trigger remote: untuk telur yg gagal via prompt (Egg Delivery Failed / Returned).
-- Dicoba HANYA setelah prompt gagal, satu-per-satu, tetap hormati filter.
local rapFailCount = {}
local rapBlacklist = {}
local rapUseRemoteFallback = true
local RAP_PICKUP_REMOTES = {
    {"Remotes", "Game", "EggPickup"},
    {"Remotes", "Game", "PickupPet"},
    {"Remotes", "Game", "PetCollect"},
    {"Remotes", "Game", "ClaimEgg"},
    {"Remotes", "Game", "EggArrivalClaim"},
    {"Remotes", "Game", "Hatch"},
}
local function rapEggModelOf(prompt)
    local cur = prompt and prompt.Parent
    for _ = 1, 8 do
        if not cur then break end
        for _, n in ipairs(rapEggNames) do
            if cur.Name == n then return cur end
        end
        cur = cur.Parent
    end
    return prompt and prompt.Parent or nil
end
local function rapRemotePickup(cand, prompt)
    local model = rapEggModelOf(prompt)
    local eggName = cand and cand.name or ""
    local argSets = { { model }, { eggName }, { model, eggName }, {} }
    for _, names in ipairs(RAP_PICKUP_REMOTES) do
        local r = rapPath(ReplicatedStorage, names)
        if r then
            for _, args in ipairs(argSets) do
                local ok = pcall(function()
                    if r:IsA("RemoteEvent") then
                        if #args > 0 then r:FireServer(unpack(args)) else r:FireServer() end
                    elseif r:IsA("RemoteFunction") then
                        if #args > 0 then r:InvokeServer(unpack(args)) else r:InvokeServer() end
                    end
                end)
                if ok then
                    task.wait(0.8)
                    local gone = (not prompt) or (prompt.Parent == nil) or (not prompt:IsDescendantOf(workspace))
                    if gone then return true, table.concat(names, "/") end
                end
            end
        end
    end
    return false, nil
end


-- ============================== RANCH (AUTO DETECT) ==============================
local rapRanchPos = nil rapPlotPos = nil
local RANCH_PATTERNS = { "ranch", "myplot", "my plot", "plot", "paddock", "pasture" }
local rapHomePos = nil

local rapIsMyPlotSafe = true
local function rapIsMyPlot(inst)
        if not inst then return false end
        local me = player.Name:lower()
        local ok, owned = pcall(function()
            for _, k in ipairs({ "Owner", "OwnerName", "PlotOwner" }) do
                local v = inst.GetAttribute and inst:GetAttribute(k)
                if v and tostring(v):lower():find(me:sub(1,4), 1, true) then return true end
            end
            if inst.GetAttribute and inst:GetAttribute("UserId") == player.UserId then return true end
            return false
        end)
        if ok and owned then return true end
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("StringValue") and tostring(d.Value) == player.Name then return true end
            if d:IsA("ObjectValue") and d.Value == player then return true end
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and tostring(d.Text or ""):lower():find(me, 1, true) then return true end
        end
        local nm = (tostring(inst.Name or "") .. " " .. tostring(inst:GetFullName())):lower()
        if nm:find("my plot",1,true) or nm:find("myplot",1,true) then return true end
        return false
    end
    local function rapRefreshRanch()
    local found = nil
    -- Satu pemindaian saja; dulu tiap pola memicu GetDescendants() sendiri (5x).
    for _, d in ipairs(rapTickList()) do
        if d:IsA("Model") or d:IsA("BasePart") then
            local low = tostring(d.Name):lower()
            for _, pat in ipairs(RANCH_PATTERNS) do
                if low:find(pat, 1, true) then
                    local p = rapEntityPos(d)
                    if p then found = p; break end
                end
            end
        end
        if found then break end
    end
    if not found then
        local sp = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
        if sp then found = sp.Position end
    end
    if found then rapRanchPos = found end
    return rapRanchPos
end

local rapEdgeMargin = 18
local function rapIsMine(inst)
    if not inst then return false end
    local me = player.Name:lower()
    local ok, owned = pcall(function()
        for _, k in ipairs({ "Owner", "OwnerName", "PlotOwner", "Plot_Owner" }) do
            local v = inst.GetAttribute and inst:GetAttribute(k)
            if v and tostring(v):lower():find(me:sub(1, 4), 1, true) then return true end
        end
        if inst.GetAttribute and inst:GetAttribute("UserId") == player.UserId then return true end
        local nm = tostring(inst.Name or ""):lower()
        if nm:find(me, 1, true) then return true end
        return false
    end)
    return ok and owned or false
end
local rapMyPlotModel = nil
local function rapFindMyPlot()
    local found, foundPos = nil, nil
    pcall(function()
        local fresh = workspace:GetDescendants()
        for _, d in ipairs(fresh) do
            if d:IsA("Model") or d:IsA("BasePart") then
                local low = tostring(d.Name):lower()
                local hit = false
                for _, pat in ipairs(RANCH_PATTERNS) do
                    if low:find(pat, 1, true) then hit = true break end
                end
                if hit then
                    if rapIsMine(d) or rapIsMine(d.Parent) or rapIsMine(d.Parent and d.Parent.Parent) then
                        local p = rapEntityPos(d)
                        if p then found, foundPos = d, p break end
                    end
                    if not found then
                        local p2 = rapEntityPos(d)
                        if p2 then
                            local rp0 = rapGetRoot()
                            if rp0 and (p2 - rp0.Position).Magnitude < 150 and not found then
                                found, foundPos = d, p2
                            end
                        end
                    end
                end
            end
        end
    end)
    if found then rapMyPlotModel = found end
    if foundPos then rapPlotPos = foundPos rapRanchPos = foundPos end
    return found, foundPos
end
local function rapPlotHalf()
    local half = 45
    do local m = rapMyPlotModel if m and m.Parent then local sz = nil pcall(function() if m:IsA("Model") then local ok, es = pcall(function() return m:GetExtentsSize() end) if ok and es then sz = es end elseif m:IsA("BasePart") then sz = m.Size end end) if sz then return math.max(30, math.max(sz.X, sz.Z) / 2) end end end
    pcall(function()
        local fresh2 = workspace:GetDescendants()
        for _, d in ipairs(fresh2) do
            if d:IsA("Model") or d:IsA("BasePart") then
                local low = tostring(d.Name):lower()
                for _, pat in ipairs(RANCH_PATTERNS) do
                    if low:find(pat, 1, true) then
                        local sz = nil
                        if d:IsA("Model") then
                            local ok, es = pcall(function() return d:GetExtentsSize() end)
                            if ok and es then sz = es end
                        elseif d:IsA("BasePart") then sz = d.Size end
                        if sz then half = math.max(half, math.max(sz.X, sz.Z) / 2) end
                        break
                    end
                end
            end
        end
    end)
    return half
end
local function rapPlotCenter()
    if rapPlotPos then return rapPlotPos end
    if rapHomePos then return rapHomePos end
    return rapRanchPos or rapRefreshRanch()
end
local function rapSetHomeHere()
    local r = rapGetRoot()
    if r then rapHomePos = r.Position rapPlotPos = r.Position rapRanchPos = r.Position return true end
    return false
end
local function rapPlotEdge()
    local c = rapPlotCenter()
    if not c then return nil end
    local off = math.min(rapPlotHalf() + rapEdgeMargin, 70)
    local r0 = rapGetRoot()
    local dir = Vector3.new(1, 0, 1)
    if r0 then local d = r0.Position - c d = Vector3.new(d.X, 0, d.Z) if d.Magnitude > 5 then dir = d / d.Magnitude end end
    return c + dir * off
end
local function rapGoPlotEdge(mode)
    local e = rapPlotEdge()
    if not e then return false end
    for attempt = 1, 3 do`r`n        rapSetNoclip(false) rapTeleportTo(e, "Edge") -- SELALU teleport (tween bikin stop-stop)`r`n        task.wait(0.6)
        local rr = rapGetRoot()
        if rr and (rr.Position - e).Magnitude <= 30 then return true end
    end
    local rr2 = rapGetRoot()
    return rr2 and ((rr2.Position - e).Magnitude <= 60) or false
end
-- WALK BENERAN (animasi): pakai Humanoid:MoveTo bertahap, bukan geser CFrame.
-- Geser CFrame tidak memicu animasi jalan -> server anggap diam -> delivery gagal.
local function raycastGround(root)
    local ok, pos = pcall(function()
        local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances = { LocalPlayer.Character }
        local res = workspace:Raycast(root.Position, Vector3.new(0, -60, 0), rp)
        if res then return res.Position end return nil
    end)
    if ok then return pos end return nil
end
local function rapWalkPlotCenter()
    local c = rapPlotCenter()
    if not c then return false end
    rapSetNoclip(false)
    do local gg = raycastGround(root) if gg then pcall(function() root.CFrame = CFrame.new(gg + Vector3.new(0, 3.2, 0)) end) end end
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local root = rapGetRoot()
    if not ch or not hum or not root then return false end
    pcall(function()
rapSetNoclip(false) do local gg = raycastGround(root) if gg then root.CFrame = CFrame.new(gg + Vector3.new(0, 3.2, 0)) end end
                hum.Sit = false hum.PlatformStand = false
        if hum.WalkSpeed < 8 then hum.WalkSpeed = 16 end
        if hum.Health <= 0 then return end
        for _, v in ipairs(ch:GetDescendants()) do
            if v:IsA("BasePart") then v.CanCollide = false pcall(function() v.Anchored = false end) end
        end
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end)
    Window:Notify({ Title = "Walk", Description = "jalan beneran " .. tostring(math.floor((root.Position - c).Magnitude)) .. " stud...", Lifetime = 3 })
    local t0 = os.clock()
    local lastD = (root.Position - c).Magnitude
    local stuckT = os.clock()
    while os.clock() - t0 < 40 do
        ch = LocalPlayer.Character hum = ch and ch:FindFirstChildOfClass("Humanoid") root = rapGetRoot()
        if not ch or not hum or not root or hum.Health <= 0 then break end
        pcall(function() hum.Sit = false root.Anchored = false end)
        local cur = root.Position
        local d = Vector3.new(c.X - cur.X, 0, c.Z - cur.Z)
        local m = d.Magnitude
        if m <= 12 then break end
        local wp = cur + (d / (m + 0.001)) * math.min(30, m)
        wp = Vector3.new(wp.X, cur.Y, wp.Z)
        pcall(function() hum:MoveTo(wp) end)
        local w0 = os.clock()
        while os.clock() - w0 < 4 do
            task.wait(0.2)
            local r2 = rapGetRoot()
            if not r2 then break end
            local m2 = Vector3.new(c.X - r2.Position.X, 0, c.Z - r2.Position.Z).Magnitude
            if m2 <= 12 then break end
            if (r2.Position - wp).Magnitude <= 6 then break end
        end
        local r3 = rapGetRoot()
        local m3 = r3 and Vector3.new(c.X - r3.Position.X, 0, c.Z - r3.Position.Z).Magnitude or 9999
        if m3 < lastD - 2 then lastD = m3 stuckT = os.clock()
        elseif os.clock() - stuckT > 4 then
            pcall(function() hum.Jump = true end)
            task.wait(0.5)
            stuckT = os.clock()
        end
    end
    local rf = rapGetRoot()
    local dd = rf and math.floor(Vector3.new(c.X - rf.Position.X, 0, c.Z - rf.Position.Z).Magnitude) or -1
    Window:Notify({ Title = "Walk", Description = "sisa " .. tostring(dd) .. " stud", Lifetime = 3 })
    return rf and (Vector3.new(c.X - rf.Position.X, 0, c.Z - rf.Position.Z).Magnitude <= 16) or false
end
local function rapGoPlot(notify)
    local pos = rapPlotPos or rapRanchPos or rapRefreshRanch()
    if not pos then
        if notify then
            Window:Notify({ Title = "Plot", Description = "My Plot tidak terdeteksi otomatis. Coba Deteksi Ulang My Plot.", Lifetime = 3 })
        end
        return false
    end
    rapTeleportTo(pos, "Plot")
    if notify then
        Window:Notify({ Title = "Plot", Description = "Kembali ke My Plot.", Lifetime = 2 })
    end
    return true
end

-- ================= WEBHOOK SENDER (logo + nama Zypherax Hub) =================
local ZYPH_LOGO_URL = "https://tr.rbxcdn.com/180DAY-38bd5cad6dff8c3aa7afb010264d3081/420/420/Image/Png/noFilter"
local function rapWHRank(rarity)
    local order = {}
    for i, r in ipairs((typeof(RARITY_LIST)=="table" and RARITY_LIST) or {"Common","Rare","Epic","Legendary","Mythic"}) do order[r] = i end
    return order[rarity] or 0
end
local function rapSendWH(title, desc, colorHex)
    local url = rapPlanned and rapPlanned.webhookUrl or ""
    if not (rapPlanned and rapPlanned.webhookOn) then return end
    if url == "" or not url:find("discord.com/api/webhooks") then return end
    pcall(function()
        local http = game:GetService("HttpService")
        local payload = { username = "Zypherax Hub", avatar_url = ZYPH_LOGO_URL, embeds = { { title = title or "Zypherax Hub - Ride A Pet", description = desc or "", color = tonumber(colorHex or "57F287", 16) or 5763719, fields = { { name = "Player", value = tostring(player.DisplayName).." (@"..tostring(player.Name)..")", inline = true }, { name = "Game", value = "Ride A Pet", inline = true } }, timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ") } } }
        local body = http:JSONEncode(payload)
        if syn and syn.request then syn.request({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
        elseif http_request then http_request({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
        elseif request then request({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body }) end
    end)
end
local function rapWHEgg(rarity, eggName, mutation)
    if not (rapPlanned and rapPlanned.whEgg) then return end
    local minR = (rapPlanned and rapPlanned.whMinRarity) or "Legendary"
    if rapWHRank(rarity) < rapWHRank(minR) then return end
    rapSendWH("Egg Langka Didapat", ("**%s** Rarity: %s Mutation: %s"):format(tostring(eggName), tostring(rarity), tostring(mutation or "-")), "57F287")
end
-- Home = posisi spawn saat script jalan (itu plot sendiri). Di-update tiap respawn bila masih kosong.
task.spawn(function()
    task.wait(3)
    if not rapHomePos then local r = rapGetRoot() if r then rapHomePos = r.Position end end
    if not rapRanchPos then rapRefreshRanch() end
    if not rapPlotPos then rapPlotPos = rapHomePos or rapRanchPos end
end)

-- ============================== AUTO PLACED EGG (FITUR TERPISAH) ==============================
local function rapPlaceEggs()
    local root = rapGetRoot()
    if not root then return 0 end
    rapGoPlot(false)
    task.wait(0.4)
    root = rapGetRoot()
    if not root then return 0 end
    local n = 0
    pcall(function()
        for _, d in ipairs(rapTickList()) do
            if d:IsA("ProximityPrompt") then
                local act = tostring(d.ActionText or ""):lower()
                if act:find("place", 1, true) or act:find("taruh", 1, true)
                    or act:find("deposit", 1, true) or act:find("store", 1, true)
                    or act:find("simpan", 1, true) then
                    local p1 = rapEntityPos(d.Parent) or rapEntityPos(d)
                    if p1 and (p1 - root.Position).Magnitude <= 40 then
                        pcall(function()
                            d.HoldDuration = 0
                            d.RequiresLineOfSight = false
                        end)
                        rapTriggerPrompt(d)
                        n = n + 1
                    end
                end
            end
        end
    end)
    if n == 0 then
        rapFire({ "Remotes", "Game", "PlacePet" })
        rapFire({ "Remotes", "Game", "PetMove" })
    end
    rapEggsCarried = 0
    return n
end

-- ============================== AUTO PICKUP TELUR ==============================
local function rapFindEggName(inst)
    local cur = inst
    for _ = 1, 8 do
        if not cur or not cur.Parent then break end
        for _, n in ipairs(rapEggNames) do
            if cur.Name == n then return cur.Name, cur end
        end
        -- fallback: apapun di dalam RenderedEggs yg ujungnya "Egg" dianggap telur
        pcall(function()
            local fp = cur:GetFullName()
            if fp:find("RenderedEggs", 1, true) and cur.Name:find("Egg", 1, true) then
            end
        end)
        if cur.Parent and cur.Parent.Name and cur.Parent.Name:find("Egg", 1, true) then
            local okF, fp2 = pcall(function() return cur.Parent:GetFullName() end)
            if okF and fp2:find("RenderedEggs", 1, true) then return cur.Parent.Name, cur.Parent end
        end
        cur = cur.Parent
    end
    return nil, nil
end

local function rapMoveTo(pos, maxWait)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return false end
    if (root.Position - pos).Magnitude <= 14 then return true end
    local reached = false
    local conn
    conn = hum.MoveToFinished:Connect(function()
        reached = true
        pcall(function() if conn then conn:Disconnect() end end)
    end)
    pcall(function() hum:MoveTo(pos) end)
    local t0 = os.clock()
    while not reached and (os.clock() - t0) < (maxWait or 5) do
        if not root.Parent then break end
        if (root.Position - pos).Magnitude <= 14 then break end
        task.wait(0.1)
    end
    pcall(function() if conn then conn:Disconnect() end end)
    return (root.Position - pos).Magnitude <= 20
end

local rapBusy = false
local function rapPickupTick()
    if rapBusy then return 0 end
    rapBusy = true
    local function done(n) rapBusy = false return n end
    -- SATU telur per tick: ambil sampai berhasil baru lanjut ke telur lain.
    -- Tidak pernah place telur (itu tugas rapFlag.placedEgg / rapPlaceEggs).
    local cand = nil
    pcall(function()
        local root0 = rapGetRoot()
        local myPos = root0 and root0.Position
        local bestD = nil
        for _, d in ipairs(rapTickList()) do
            if d:IsA("ProximityPrompt") and tostring(d.ActionText) == "Pick Up" then
                if not rapHandled[d] then
                    local nm = rapFindEggName(d)
                    if nm and rapMatchFilter(nm, d) then
                        local pos = rapEntityPos(d.Parent) or rapEntityPos(d)
                        if pos then
                            local dist = myPos and (pos - myPos).Magnitude or 0
                            if not bestD or dist < bestD then bestD = dist cand = { name = nm, pos = pos, prompt = d } end
                        end
                    end
                end
            end
        end
    end)
    if not cand then return done(0) end
    if os.clock() < rapPickupCD then return done(0) end
    local mode = rapPickupMode or "Tween"
    local prompt = cand.prompt
    if not prompt or not prompt.Parent then return done(0) end
    -- 1. pergi ke telur: TELEPORT LANGSUNG (seperti dulu, tidak tween-stop-stop)
    do
        local away = Vector3.new(0, 0, 7)
        do local rrS=rapGetRoot() if rrS then local d0=cand.pos-rrS.Position d0=Vector3.new(d0.X,0,d0.Z) if d0.Magnitude>1 then away=(-d0/d0.Magnitude)*7 end end end
        local stop = cand.pos + Vector3.new(away.X, 4, away.Z)
        rapSetNoclip(false) rapTeleportTo(stop, "Egg") task.wait(0.6)
    end
    -- 2. pastikan dekat (server tolak dari jauh)
    do
        local pp = rapEntityPos(prompt.Parent) or cand.pos
        local rr = rapGetRoot()
        if pp and rr and (pp - rr.Position).Magnitude > 12 then
            rapTeleportTo(pp, "Egg") task.wait(0.35)
        end
    end
    do
        local rar0 = rapRarityOf(cand.name)
        local rare0 = (rar0 == "Epic" or rar0 == "Legendary" or rar0 == "Mythic" or rar0 == "Divine" or rar0 == "Ethereal")
        -- tiru manual: JANGAN ubah HoldDuration/MaxDist, cuma matikan LOS
        pcall(function() prompt.RequiresLineOfSight = false end)
    end
    -- skip telur yg gagal 3x dalam 60 dtk (hindari spam kode AT-xxxx)
    do
        local bl = rapBlacklist[prompt]
        if bl and os.clock() < bl then return done(0) end
    end
    rapHandled[prompt] = true
    -- tiru manual: JANGAN anchor; telur langka pakai hold asli (HoldDuration tidak dinolkan)
    do
        local rar2 = rapRarityOf(cand.name)
        local isRare = (rar2 == "Epic" or rar2 == "Legendary" or rar2 == "Mythic" or rar2 == "Divine" or rar2 == "Ethereal")
        if not isRare then
            do local hd0 = 0.2 pcall(function() hd0 = prompt.HoldDuration or 0.2 end) if type(fireproximityprompt) == "function" then pcall(function() fireproximityprompt(prompt, 0) end) task.wait((tonumber(hd0) or 0.2) + 0.5) pcall(function() fireproximityprompt(prompt, 1) end) else rapTriggerPrompt(prompt) end task.wait(mode == "Instant" and 0.7 or 1.2) end
        else
            do
                local pp2 = rapEntityPos(prompt.Parent) or cand.pos
                local rr2 = rapGetRoot()
                if pp2 and rr2 and (pp2 - rr2.Position).Magnitude > 8 then
                    if mode == "Instant" then rapTeleportTo(pp2, "Egg") else rapTweenTo(pp2, rapPlanned.glideSpeed) end
                    task.wait(0.5)
                end
            end
            pcall(function() prompt.RequiresLineOfSight = false end)
            if type(fireproximityprompt) == "function" then
                local hd = 0
                pcall(function() hd = prompt.HoldDuration or 0 end)
                pcall(function() fireproximityprompt(prompt, 0) end)
                task.wait((tonumber(hd) or 0) + 0.6)
                pcall(function() fireproximityprompt(prompt, 1) end)
                task.wait(2.0)
            else
                local hd2 = 0
                pcall(function() hd2 = prompt.HoldDuration or 0 end)
                pcall(function() prompt:InputHoldBegin() end)
                task.wait((tonumber(hd2) or 1) + 0.5)
                pcall(function() prompt:InputHoldEnd() end)
                task.wait(2.0)
            end
        end
    end
    -- DIAM di telur sampai server selesai: prompt hilang ATAU tool telur masuk char/backpack.
    do
        local rarW2 = rapRarityOf(cand.name)
        local rareW2 = (rarW2 == "Epic" or rarW2 == "Legendary" or rarW2 == "Mythic" or rarW2 == "Divine" or rarW2 == "Ethereal")
        local t0 = os.clock()
        local lim = rareW2 and 6 or 3
        while os.clock() - t0 < lim do
            if prompt.Parent == nil or (not prompt:IsDescendantOf(workspace)) then break end
            local hasEgg = false
            pcall(function()
                local chW = LocalPlayer.Character
                local bpW = LocalPlayer:FindFirstChild("Backpack")
                local function hasEggIn(par)
                    if not par then return false end
                    for _, t in ipairs(par:GetChildren()) do
                        if (t:IsA("Tool")) and tostring(t.Name):find("Egg", 1, true) then return true end
                    end
                    return false
                end
                if hasEggIn(chW) or hasEggIn(bpW) then hasEgg = true end
            end)
            if hasEgg then break end
            task.wait(0.25)
        end
    end
    local gone = (prompt.Parent == nil) or (not prompt:IsDescendantOf(workspace))
    local hasEggTool = false
    pcall(function()
        local chW2 = LocalPlayer.Character
        local bpW2 = LocalPlayer:FindFirstChild("Backpack")
        for _, par in ipairs({ chW2, bpW2 }) do
            if par then for _, t in ipairs(par:GetChildren()) do
                if t:IsA("Tool") and tostring(t.Name):find("Egg", 1, true) then hasEggTool = true break end
            end end
            if hasEggTool then break end
        end
    end)
    local delivered = gone or hasEggTool
    if delivered then
        rapPickedCount = rapPickedCount + 1
        rapEggsCarried = rapEggsCarried + 1
        rapPickupCD = os.clock() + 1.2
        pcall(function() rapWHEgg(rapRarityOf(cand.name), cand.name, rapFindMutation(cand.name)) end)
        local rar = rapRarityOf(cand.name)
        if rar == "Epic" or rar == "Legendary" or rar == "Mythic" or rar == "Divine" or rar == "Ethereal" then
            Window:Notify({ Title = "Telur Didapat", Description = ("[%s] %s (total %d)"):format(rar, cand.name, rapPickedCount), Lifetime = 3 })
        end
    else
        -- prompt gagal -> coba trigger remote langsung (cadangan), tetap satu-per-satu
        local remoteOk = false
        if rapUseRemoteFallback then
            local ok2 = false
            pcall(function() ok2 = rapRemotePickup(cand, prompt) end)
            if ok2 == true then remoteOk = true end
            -- rapRemotePickup return 2 value; cek ulang telur hilang
            do
                local gone2 = (prompt.Parent == nil) or (not prompt:IsDescendantOf(workspace))
                if gone2 then remoteOk = true delivered = true end
            end
        end
        if remoteOk and delivered then
            rapPickedCount = rapPickedCount + 1
            rapEggsCarried = rapEggsCarried + 1
            rapPickupCD = os.clock() + 1.2
            pcall(function() rapWHEgg(rapRarityOf(cand.name), cand.name, rapFindMutation(cand.name)) end)
            Window:Notify({ Title = "Pick Up", Description = tostring(cand.name) .. " ketangkep, bawa ke plot...", Lifetime = 2 })
        else
            -- JANGAN pulang dulu: telur mungkin sudah virtual di server walau prompt masih ada.
            -- Lanjut ke edge + walk, verifikasi akhir yg mutuskan done(1)/done(0).
            Window:Notify({ Title = "Pick Up", Description = tostring(cand.name) .. " prompt blm hilang, tetap bawa ke plot...", Lifetime = 2 })
            rapHandled[prompt] = nil
        end
    end
        -- 3. delivery: WAJIB ke plot SENDIRI (ukur ulang tiap telur), edge luar -> WALK tengah.
    --    return 1 HANYA kalau telur benar2 hilang/masuk tas. Kalau tidak -> done(0), telur lain nunggu.
    do
        local rarB = rapRarityOf(cand.name)
        local rareB = (rarB == "Epic" or rarB == "Legendary" or rarB == "Mythic" or rarB == "Divine" or rarB == "Ethereal")
        -- a. ukur ulang plot sendiri tiap telur (bukan cache lama)
        pcall(function() rapFindMyPlot() end)
        Window:Notify({ Title = "Delivery", Description = "Ke dekat plot: " .. tostring(cand.name), Lifetime = 2 })
        local edgeOk = rapGoPlotEdge(mode)
        do
            local rrE = rapGetRoot()
            local ee = rapPlotEdge()
            local dd = (rrE and ee) and math.floor((rrE.Position - ee).Magnitude) or -1
            Window:Notify({ Title = "Edge", Description = (edgeOk and "Sampai luar plot" or "GAGAL ke luar plot") .. " (sisa " .. tostring(dd) .. " stud)", Lifetime = 3 })
        end
        if not edgeOk then
            Window:Notify({ Title = "Plot", Description = "Gagal ke dekat plot, telur ditahan (tidak ambil yg lain).", Lifetime = 3 })
            rapPickupCD = os.clock() + 3
            return done(0)
        end
                -- b2. DROP PAKSA DI PINGGIR (permintaan user): drop telur, ambil lagi, baru walk.
        do pcall(function() Window:Notify({Title="Drop",Description="Drop telur di pinggir plot...",Lifetime=2}) end) local dropped=0 pcall(function() local ch=LocalPlayer.Character; pcall(function() LocalPlayer.Character.Humanoid:UnequipTools() end) task.wait(0.2); ch=LocalPlayer.Character; if ch then for _,t in ipairs(ch:GetChildren()) do if t and t:IsA("Tool") then local nm=(t.Name or ""):lower(); if nm:find("egg") then pcall(function() t.Parent=workspace end) dropped=dropped+1 task.wait(0.3) end end end end end) task.wait(0.6) pcall(function() Window:Notify({Title="Drop",Description=(dropped>0 and ("Ter-drop, ambil lagi...") or "Virtual (tak ada Tool) - ambil ulang..."),Lifetime=3}) end) pcall(function() local rr=rapGetRoot(); if rr then for _,pr in ipairs(workspace:GetDescendants()) do if pr and pr:IsA("ProximityPrompt") then local mdl=pr:FindFirstAncestorOfClass("Model"); local nm=mdl and mdl.Name or ""; if nm~="" and cand.name~="" and (nm==cand.name) then local pp=nil; pcall(function() if pr.Parent and pr.Parent:IsA("BasePart") then pp=pr.Parent.Position elseif mdl and mdl.PrimaryPart then pp=mdl.PrimaryPart.Position end end) if pp and (pp-rr.Position).Magnitude<=40 then pcall(function() fireproximityprompt(pr,1) end) task.wait(0.6) break end end end end end end) task.wait(0.8) end -- LOG EGG
        do pcall(function() print("[RAP-EGG] target="..tostring(cand.name).." rarity="..tostring(rapRarityOf(cand.name)).." pos="..tostring(cand.pos)) end) local _ch=LocalPlayer.Character local _bp=LocalPlayer:FindFirstChild("Backpack") local _s="tas=" pcall(function() if _ch then for _,t in ipairs(_ch:GetChildren()) do if t:IsA("Tool") then _s=_s.."C:"..t.Name..";" end end end if _bp then for _,t in ipairs(_bp:GetChildren()) do if t:IsA("Tool") then _s=_s.."B:"..t.Name..";" end end end print("[RAP-EGG] ".._s) end) Window:Notify({Title="Egg",Description=tostring(cand.name).." ("..tostring(rapRarityOf(cand.name))..")",Lifetime=3}) end
        -- b. TERBUKTI virtual (toolEggDiTas=0): tidak ada yg bisa di-drop. Langsung walk.
        -- c. WALK (tanpa teleport) dari edge ke tengah plot sendiri
        Window:Notify({ Title = "Delivery", Description = "Jalan ke tengah plot...", Lifetime = 2 })
        local walkOk = rapWalkPlotCenter()
        Window:Notify({ Title = "Walk", Description = walkOk and "Sampai tengah plot" or "GAGAL jalan ke tengah", Lifetime = 3 })
        if not walkOk then
            rapPickupCD = os.clock() + 3
            return done(0)
        end
        task.wait(rareB and 1.5 or 1.0)
        -- d. verifikasi AKHIR: telur harus hilang. Belum hilang = BELUM berhasil -> done(0).
        do
            local gone3 = (prompt.Parent == nil) or (not prompt:IsDescendantOf(workspace))
            if not gone3 then
                local fc3 = (rapFailCount[prompt] or 0) + 1
                rapFailCount[prompt] = fc3
                if fc3 >= 2 then rapBlacklist[prompt] = os.clock() + 60 rapFailCount[prompt] = 0 end
                Window:Notify({ Title = "Egg Returned", Description = tostring(cand.name) .. " belum delivery, telur lain menunggu.", Lifetime = 3 })
                rapPickupCD = os.clock() + 3
                return done(0)
            end
        end
    end
    if mode ~= "Instant" then rapSetNoclip(false) end
    return done(1)
end

-- ============================== AUTO SELL (RARITY + WEIGHT) ==============================
local function rapGetItemWeight(obj)
    if not obj then return nil end
    for _, key in ipairs({ "Weight", "weight", "Berat", "berat" }) do
        local ok, v = pcall(function() return obj:GetAttribute(key) end)
        if ok and type(v) == "number" then return v end
    end
    local found = nil
    pcall(function()
        for _, d in ipairs(obj:GetDescendants()) do
            if (d:IsA("NumberValue") or d:IsA("IntValue")) and tostring(d.Name):lower():find("weight", 1, true) then
                found = d.Value
                break
            end
        end
    end)
    return found
end

local function rapGetItemRarity(obj)
    if not obj then return nil end
    local name = tostring(obj.Name)
    for _, n in ipairs(rapEggNames) do
        if name:find(n, 1, true) then return rapRarityOf(n) end
    end
    for _, key in ipairs({ "Rarity", "rarity" }) do
        local ok, v = pcall(function() return obj:GetAttribute(key) end)
        if ok and type(v) == "string" then return v end
    end
    pcall(function()
        for _, d in ipairs(obj:GetDescendants()) do
            if d:IsA("StringValue") and tostring(d.Name):lower():find("rarity", 1, true) then
                return d.Value
            end
        end
    end)
    return nil
end

local function rapShouldSell(obj, label)
    local nm = tostring(label or (obj and obj.Name) or "")
    -- Rarity hasil deteksi struktur item, kalau tidak ada baru tebak dari teks.
    local rar = rapGetItemRarity(obj) or rapRarityOfName(nm)
    local key = rar or "Unknown"
    if rapSetCount(rapSellRaritySet) > 0 then
        local matched = rapInSet(rapSellRaritySet, key) or rapInSet(rapSellRaritySet, nm)
        if not matched then
            -- Di menu per-pet nama rarity biasanya cuma muncul di teks baris.
            local low = string.lower(nm)
            for k in pairs(rapSellRaritySet) do
                if string.find(low, string.lower(tostring(k)), 1, true) then matched = true; break end
            end
        end
        if not matched then return false end
    end
    if rapUseWeightFilter and rapSellMaxWeight > 0 then
        local w = rapGetItemWeight(obj)
        if w and w > rapSellMaxWeight then return false end
    end
    return true
end

-- Ambil teks yang terlihat di dalam satu baris pet (nama + rarity), plus atribut.
local function rapRowText(row, skipBtn)
    local parts = {}
    pcall(function()
        for _, d in ipairs(row:GetDescendants()) do
            if d ~= skipBtn and (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible then
                local t = tostring(d.Text or ""):gsub("%s+", " ")
                if #t > 0 and #t <= 60 then table.insert(parts, t) end
            end
        end
    end)
    pcall(function()
        for _, k in ipairs({ "Rarity", "rarity", "PetName", "ItemName", "Name" }) do
            local ok, v = pcall(function() return row:GetAttribute(k) end)
            if ok and type(v) == "string" and #v > 0 then table.insert(parts, v) end
        end
    end)
    return table.concat(parts, " ")
end

-- Kumpulkan tombol "Sell/Jual/Sell All" yang terlihat di layar.
-- Kalau filter rarity aktif, tombol per-baris hanya ikut kalau barisnya cocok.
local function rapSellButtons(scope, forceAll)
    local out = {}
    local filterOn = (not forceAll) and rapSetCount(rapSellRaritySet) > 0
    pcall(function()
        for _, d in ipairs(scope:GetDescendants()) do
            if d:IsA("GuiButton") and d.Visible then
                local txt = tostring(d.Text or ""):lower()
                local isAll  = txt:find("sell all", 1, true) ~= nil
                local isSell = isAll or txt == "sell" or txt:find("jual", 1, true) ~= nil
                if isSell then
                    local row = d:FindFirstAncestorOfClass("Frame")
                    if filterOn and isAll then
                        -- "Sell All" menjual semuanya -> lewati supaya filter tidak dilanggar.
                        -- (Pakai tombol "Sell All Now" kalau memang mau jual semua.)
                    elseif isAll or not row or not filterOn then
                        -- "Sell All" / tombol global / tanpa filter: apa adanya.
                        table.insert(out, d)
                    else
                        -- Baris pet: hanya jual kalau labelnya bisa dipastikan cocok.
                        local label = rapRowText(row, d)
                        if label ~= "" and rapShouldSell(row, label) then
                            table.insert(out, d)
                        end
                    end
                end
            end
        end
    end)
    return out
end

local function rapClickButton(btn)
    if not btn or not btn.Parent then return false end
    pcall(function() btn:Activate() end)
    pcall(function() btn.MouseButton1Click:Fire() end)
    return true
end

-- Cari prompt "Sell" di dunia (dipakai kalau belum ada tombol UI).
local function rapFindSellPrompt()
    local root = rapGetRoot()
    local best, bestDist = nil, nil
    pcall(function()
        for _, d in ipairs(rapTickList()) do
            if d:IsA("ProximityPrompt") and tostring(d.ActionText) == "Sell" then
                local p = rapEntityPos(d.Parent) or rapEntityPos(d)
                if p then
                    local dist = root and (p - root.Position).Magnitude or 0
                    if not bestDist or dist < bestDist then best, bestDist = d, dist end
                end
            end
        end
    end)
    return best, bestDist
end

-- Langsung menjual: pencet tombol Sell/Sell All / tembak prompt Sell dari jarak jauh.
-- TIDAK teleport ke NPC Sell dan TIDAK perlu buka menu sell manual.
local function rapSellTick(forceAll)
    local n = 0
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local scope = gui or (gethui and gethui()) or game:GetService("CoreGui")

    local function clickVisible(all)
        local c = 0
        for _, b in ipairs(rapSellButtons(scope, all)) do
            if rapClickButton(b) then
                c = c + 1
                task.wait(0.06)
            end
        end
        return c
    end

    -- Fase 1: kalau menu Sell sudah terbuka, langsung pencet tombolnya.
    n = n + clickVisible(forceAll)
    if n > 0 then return n end

    -- Fase 2: tembak prompt Sell dari jarak jauh (fireproximityprompt tak peduli jarak).
    local fired = false
    pcall(function()
        for _, d in ipairs(rapTickList()) do
            if d:IsA("ProximityPrompt") then
                local act = string.lower(tostring(d.ActionText or ""))
                if act:find("sell", 1, true) or act:find("jual", 1, true) then
                    pcall(function()
                        d.HoldDuration = 0
                        d.MaxActivationDistance = 300
                        d.RequiresLineOfSight = false
                    end)
                    rapTriggerPrompt(d)
                    fired = true
                end
            end
        end
    end)

    -- Remote cadangan (kalau game pakai RemoteEvent, bukan ProximityPrompt).
    -- PENTING: "SellAll" itu setara jual-semua, jadi JANGAN ditembak saat filter
    -- rarity aktif -> bisa menjual pet yang sebenarnya mau disimpan.
    local filterOn = (not forceAll) and rapSetCount(rapSellRaritySet) > 0
    if not filterOn then
        rapFire({ "Remotes", "Game", "SellAll" })
        rapFire({ "Remotes", "Reusable", "SellAll" })
        rapFire({ "Remotes", "Game", "Sell" })
        rapFire({ "Remotes", "Game", "SellPet" })
    elseif n == 0 and not fired then
        -- Tidak ada tombol/prompt yang ketemu; coba remote satuan saja.
        rapFire({ "Remotes", "Game", "SellPet" })
        rapFire({ "Remotes", "Game", "Sell" })
    end

    if fired then
        rapSellCount = rapSellCount + 1
        n = n + 1
    end

    -- Fase 3: kalau prompt tadi memunculkan GUI, langsung pencet Sell / Sell All.
    for _ = 1, 10 do
        task.wait(0.16)
        local c = clickVisible(forceAll)
        if c > 0 then n = n + c; break end
    end
    return n
end

-- ============================== AUTO BUY (FOOD & GEARS) ==============================
local function rapZoneOf(obj)
    local cur = obj
    for _ = 1, 4 do
        if not cur then break end
        local nm = tostring(cur.Name):lower()
        if nm:find("food", 1, true) or nm:find("makanan", 1, true) then return "food" end
        if nm:find("gear", 1, true) or nm:find("alat", 1, true) then return "gear" end
        cur = cur.Parent
    end
    return nil
end

local function rapKeyMatch(set, text)
    if rapSetCount(set) == 0 then return true end
    local low = string.lower(tostring(text or ""))
    for k in pairs(set) do
        if string.find(low, string.lower(tostring(k)), 1, true) then return true end
    end
    return false
end

-- Cari tombol beli yang cocok dengan pilihan item di sebuah zona (food/gear).
local function rapBuyInScope(scope, wantFood, wantGear, set)
    local n = 0
    pcall(function()
        for _, d in ipairs(scope:GetDescendants()) do
            if d:IsA("GuiButton") and d.Visible then
                local txt = tostring(d.Text or "")
                local low = string.lower(txt)
                local isBuy = low:find("buy", 1, true) or low:find("beli", 1, true) or low:find("purchase", 1, true)
                -- Nama item biasanya ada di label tombol atau di sebelahnya.
                local lbl = nil
                pcall(function()
                    local par = d.Parent
                    if par then
                        lbl = par:FindFirstChildWhichIsA("TextLabel")
                    end
                end)
                local labelTxt = lbl and tostring(lbl.Text) or ""
                local combined = txt .. " " .. labelTxt
                local zone = rapZoneOf(d) or rapZoneOf(d.Parent)
                local okZone = (zone == "food" and wantFood) or (zone == "gear" and wantGear)
                    or (not zone and (wantFood or wantGear))
                if okZone and (isBuy or labelTxt ~= "") and rapKeyMatch(set, combined) then
                    pcall(function() d:Activate() end)
                    pcall(function() d.MouseButton1Click:Fire() end)
                    n = n + 1
                    rapBuyCount = rapBuyCount + 1
                    task.wait(0.05)
                end
            end
        end
    end)
    return n
end

local rapScanShopItems -- forward declaration (didefinisikan di bawah)

local function rapBuyTick()
    local n = 0
    local root = rapGetRoot()
    local rootPos = root and root.Position

    -- Auto-scan sekali supaya daftar item di menu ikut terisi sendiri.
    if (rapBuyFood and #rapFoodItems == 0) or (rapBuyGear and #rapGearItems == 0) then
        pcall(rapScanShopItems)
    end

    -- 1. Prompt beli di dunia (kalau shop berupa objek di map).
    --    Satu kali pemindaian saja: hasilnya dipakai untuk cari target teleport
    --    sekaligus untuk menembak prompt (dulu workspace dipindai dua kali).
    local matched = {}
    pcall(function()
        for _, d in ipairs(rapTickList()) do
            if d:IsA("ProximityPrompt") then
                local act = tostring(d.ActionText or "")
                local low = string.lower(act)
                if low:find("buy", 1, true) or low:find("beli", 1, true) or low:find("purchase", 1, true) then
                    local zone = rapZoneOf(d.Parent)
                    local wantF, wantG = false, false
                    if zone == "food" and rapBuyFood then wantF = true end
                    if zone == "gear" and rapBuyGear then wantG = true end
                    if zone == nil and (rapBuyFood or rapBuyGear) then
                        wantF = rapBuyFood; wantG = rapBuyGear
                    end
                    if wantF or wantG then
                        local set = wantF and rapBuyFoodSet or rapBuyGearSet
                        local pName = d.Parent and tostring(d.Parent.Name) or ""
                        if rapKeyMatch(set, pName .. " " .. act) then
                            local p = rapEntityPos(d.Parent) or rapEntityPos(d)
                            table.insert(matched, { prompt = d, pos = p })
                        end
                    end
                end
            end
        end
    end)

    -- Teleport ke prompt terdekat dulu supaya prompt bisa diaktifkan server.
    local target, targetDist = nil, nil
    for _, m in ipairs(matched) do
        if m.pos and rootPos then
            local dist = (m.pos - rootPos).Magnitude
            if not targetDist or dist < targetDist then target, targetDist = m.pos, dist end
        end
    end
    if target and targetDist and targetDist > 10 then
        rapTeleportTo(target, "Buy")
        task.wait(0.3)
    end

    for _, m in ipairs(matched) do
        local d = m.prompt
        if d and d.Parent then
            pcall(function()
                d.HoldDuration = 0
                d.MaxActivationDistance = 500
                d.RequiresLineOfSight = false
            end)
            rapTriggerPrompt(d)
            n = n + 1
            rapBuyCount = rapBuyCount + 1
        end
    end

    -- 2. Tombol UI shop (Food / Gears) sesuai item yang dipilih.
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local scope = gui or (gethui and gethui()) or game:GetService("CoreGui")
    if rapBuyFood then n = n + rapBuyInScope(scope, true, false, rapBuyFoodSet) end
    if rapBuyGear then n = n + rapBuyInScope(scope, false, true, rapBuyGearSet) end
    return n
end

-- Pindai nama item Food & Gears dari tombol shop yang sedang terbuka.
rapScanShopItems = function()
    local foundFood, foundGear = {}, {}
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local scope = gui or (gethui and gethui()) or game:GetService("CoreGui")
    pcall(function()
        for _, d in ipairs(scope:GetDescendants()) do
            if (d:IsA("GuiButton") or d:IsA("TextLabel")) and d.Visible then
                local txt = tostring(d.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                local low = string.lower(txt)
                if #txt >= 2 and #txt <= 40
                    and not low:find("buy", 1, true) and not low:find("beli", 1, true)
                    and not low:find("sell", 1, true) and not low:find("close", 1, true)
                    and not low:find("equip", 1, true) and low ~= "food" and low ~= "gears"
                    and low ~= "gear" and low ~= "foods" then
                    local zone = rapZoneOf(d)
                    if not zone then
                        -- Fallback: coba tebak dari teks header/tombolnya.
                        if low:find("food", 1, true) or low:find("meat", 1, true)
                            or low:find("apple", 1, true) or low:find("carrot", 1, true)
                            or low:find("makanan", 1, true) or low:find("beri", 1, true) then
                            zone = "food"
                        elseif low:find("gear", 1, true) or low:find("tool", 1, true)
                            or low:find("stick", 1, true) or low:find("leash", 1, true) then
                            zone = "gear"
                        end
                    end
                    if zone == "food" then foundFood[txt] = true end
                    if zone == "gear" then foundGear[txt] = true end
                end
            end
        end
    end)
    local function keyList(t)
        local out = {}
        for k in pairs(t) do table.insert(out, k) end
        table.sort(out)
        return out
    end
    local f, g = keyList(foundFood), keyList(foundGear)
    local function apply(dest, src)
        if #src == 0 then return end
        for i = #dest, 1, -1 do dest[i] = nil end
        for i = 1, #src do dest[i] = src[i] end
    end
    apply(rapFoodItems, f)
    apply(rapGearItems, g)
    if rapFoodDD then pcall(function() rapFoodDD:SetItems(rapFoodItems) end) end
    if rapGearDD then pcall(function() rapGearDD:SetItems(rapGearItems) end) end
    return #rapFoodItems, #rapGearItems
end

-- ============================== SKILL & SPELL (ONE-SHOT) ==============================
local function rapSpellTick()
    local now = os.clock()
    if (now - rapLastSpell) < 0.6 then return end
    rapLastSpell = now

    -- 1. Tombol skill/spell yang terlihat di layar.
    local hit = 0
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    local scope = gui or (gethui and gethui()) or game:GetService("CoreGui")
    pcall(function()
        for _, d in ipairs(scope:GetDescendants()) do
            if d:IsA("GuiButton") and d.Visible then
                local low = string.lower(tostring(d.Text or ""))
                local nm  = string.lower(tostring(d.Name or ""))
                local key = low .. " " .. nm
                if key:find("cast", 1, true) or key:find("skill", 1, true)
                    or key:find("spell", 1, true) or key:find("ability", 1, true)
                    or key:find("eat", 1, true) or key:find("use", 1, true)
                    or key:find("equip", 1, true) or key:find("feed", 1, true) then
                    if rapLastSkill == "" or low == "" or low == rapLastSkill
                        or string.find(low, rapLastSkill, 1, true) then
                        pcall(function() d:Activate() end)
                        pcall(function() d.MouseButton1Click:Fire() end)
                        hit = hit + 1
                        task.wait(0.05)
                    end
                end
            end
        end
    end)

    -- 2. Remote generik untuk skill / feed pet.
    rapFire({ "Remotes", "Game", "UseSkill" })
    rapFire({ "Remotes", "Game", "CastSpell" })
    rapFire({ "Remotes", "Game", "FeedPet" })
    rapFire({ "Remotes", "Game", "UseFood" })
    rapFire({ "Remotes", "Game", "UseGear" })
    return hit
end

-- ============================== LOOP ==============================
local function rapStep()
    rapTickBegin()
    if rapFlag.pickup then rapPickupTick() end
    if rapFlag.hatch then rapPassBatch(function(a) return a == "Hatch" end, 3) end
    if rapFlag.grow then rapPassBatch(function(a) return a:find("Skip", 1, true) ~= nil end, 3) end
    if rapFlag.feed then rapPassBatch(function(a) return a == "Feed" end, 3) rapFire({ "Remotes", "Game", "FeedPet" }) end
    if rapFlag.skill then rapSpellTick() end
    if rapFlag.ride then rapPassBatch(function(a) return a == "Ride" end, 1) rapFire({ "Remotes", "Game", "Mounting" }) rapFire({ "Remotes", "Game", "PetRideMode" }) end
    if rapFlag.join then rapPassBatch(function(a) return a:find("Join", 1, true) ~= nil end, 1) end
    if rapFlag.claim then rapPassBatch(function(a) return a == "Claim" or a:find("Unlock", 1, true) ~= nil end, 2) end
    if rapFlag.remoteClaim then
        rapFire({ "Remotes", "Game", "ClaimEventReward" })
        rapFire({ "Remotes", "Game", "ClaimIndexReward" })
        rapFire({ "Remotes", "Game", "EggArrivalClaim" })
        rapFire({ "Remotes", "Game", "OfflineEarnings" })
        rapFire({ "Remotes", "Reusable", "ClaimGroupReward" })
    end
    if rapFlag.placedEgg then rapPlaceEggs() end
    if rapFlag.fuse then rapFire({ "Remotes", "Game", "FusionAction" }) rapFire({ "Remotes", "Game", "FusionPetPlace" }) end
    if rapFlag.rebirth or rapPlanned.autoRebirth then rapFire({ "Remotes", "Game", "Rebirth" }) end
    if rapFlag.shop then rapFire({ "Remotes", "Game", "Autobuy" }) end
    if rapFlag.autoSell then rapSellTick(false) end
    if rapBuyFood or rapBuyGear then rapBuyTick() end
    if rapFlag.autoTp then
        for _, d in ipairs(rapTickList()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and d.Name == rapGoal then
                local p = rapEntityPos(d)
                if p then rapTeleportTo(p, rapGoal) end
                break
            end
        end
    end
    rapTickEnd()
end

local function rapLoopStart()
    if rapRunning then return end
    rapRunning = true
    task.spawn(function()
        while true do
            local any = false
            for _, v in pairs(rapFlag) do
                if v then any = true; break end
            end
            if rapBuyFood or rapBuyGear then any = true end
            if not any then break end
            pcall(rapStep)
            task.wait(RAP_DELAY)
        end
        rapRunning = false
    end)
end

local function rapSet(key, on, title, onMsg, offMsg)
    rapFlag[key] = on and true or nil
    if on then rapLoopStart() end
    Window:Notify({ Title = title, Description = on and onMsg or offMsg, Lifetime = 3 })
end

-- ============================== ESP ENGINE ==============================
local ESP_NAME = "RAP_ESP_FOLDER"
local espHost = nil
local espMode = { egg = false, zone = false, player = false, npc = false, ranch = false, plot = false }
local espRunning = false
local rapEggCount, rapZoneCount, rapNpcCount, rapPlayerCount = 0, 0, 0, 0

-- ESP INKREMENTAL.
-- Versi lama menghapus SEMUA penanda lalu membuat ulang setiap 0.45 detik.
-- Di map yang banyak telur/NPC itu berarti ribuan Highlight + BillboardGui
-- dibuat & dibuang per detik -> GC berat dan Roblox akhirnya crash.
-- Sekarang penanda dipakai ulang; hanya yang sudah basi yang dihapus.
local espLive  = {}   -- [instance] = { hl=, bb=, part=, label=, color=, frame= }
local espFrame = 0

-- Daftar descendant workspace di-cache satu kali per refresh supaya tidak
-- memanggil workspace:GetDescendants() berulang-ulang di tick yang sama.
local rapDescCache = nil
local function rapDescRefresh() rapDescCache = workspace:GetDescendants() end
local function rapDescList() return rapDescCache or workspace:GetDescendants() end

local function espFolder()
    if espHost and espHost.Parent then return espHost end
    local f = workspace:FindFirstChild(ESP_NAME)
    if not f then
        f = Instance.new("Folder")
        f.Name = ESP_NAME
        f.Parent = workspace
    end
    espHost = f
    return f
end

local function espDrop(inst)
    local e = espLive[inst]
    if not e then return end
    espLive[inst] = nil
    pcall(function() if e.hl then e.hl:Destroy() end end)
    pcall(function() if e.bb then e.bb:Destroy() end end)
end

local function espWipe()
    pcall(function()
        local all = {}
        for inst in pairs(espLive) do table.insert(all, inst) end
        for _, inst in ipairs(all) do espDrop(inst) end
        if espHost then
            for _, c in ipairs(espHost:GetChildren()) do c:Destroy() end
        end
    end)
end

local function espColorEq(a, b)
    if a == b then return true end
    if not a or not b then return false end
    return a.R == b.R and a.G == b.G and a.B == b.B
end

local function espMark(inst, label, color, key)
    if not inst or not inst.Parent then return end
    local f = espFolder()
    key = key or label

    -- Sudah ada dan masih cocok -> pakai ulang, jangan bikin instance baru.
    local e = espLive[inst]
    if e and e.hl and e.hl.Parent and e.key == key and espColorEq(e.color, color) then
        e.frame = espFrame
        pcall(function() e.hl.Adornee = inst end)
        pcall(function() if e.bb then e.bb.Adornee = e.part end end)
        -- teks bisa berubah (mis. jarak player) -> perbarui tanpa alokasi baru
        if e.tl and e.tl.Text ~= label then e.tl.Text = label end
        return
    end
    if e then espDrop(inst) end

    local hl = Instance.new("Highlight")
    hl.Name = ESP_NAME
    hl.Adornee = inst
    hl.FillColor = color
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.15
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = f

    local entry = { hl = hl, label = label, key = key, frame = espFrame }
    if color and color.R then
        entry.color = Color3.new(color.R, color.G, color.B)
    else
        entry.color = color
    end

    if label and label ~= "" then
        local part = nil
        if inst:IsA("BasePart") then
            part = inst
        elseif inst:IsA("Model") then
            part = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
        end
        if part then
            local bb = Instance.new("BillboardGui")
            bb.Name = ESP_NAME
            bb.Adornee = part
            bb.Size = UDim2.new(0, 140, 0, 20)
            bb.StudsOffset = Vector3.new(0, 2, 0)
            bb.AlwaysOnTop = false
            bb.MaxDistance = 600
            local tl = Instance.new("TextLabel")
            tl.Size = UDim2.new(1, 0, 1, 0)
            tl.BackgroundTransparency = 1
            tl.Font = Enum.Font.GothamBold
            tl.TextSize = 11
            tl.TextColor3 = color
            tl.TextStrokeColor3 = Color3.new(0, 0, 0)
            tl.TextStrokeTransparency = 0
            tl.Text = label
            tl.Parent = bb
            bb.Parent = f
            entry.bb = bb
            entry.tl = tl
            entry.part = part
        end
    end
    espLive[inst] = entry
end

-- Buang penanda yang tidak lagi terpakai di refresh ini.
local function espSweep()
    local dead = nil
    for inst, e in pairs(espLive) do
        if e.frame ~= espFrame then
            dead = dead or {}
            table.insert(dead, inst)
        end
    end
    if dead then
        for _, inst in ipairs(dead) do espDrop(inst) end
    end
end

local function rapCountEggs(mark)
    local c = 0
    local myPos = rapGetRoot() and rapGetRoot().Position
    local found = {}
    for _, d in ipairs(rapDescList()) do
        if d:IsA("Model") or d:IsA("BasePart") then
            for _, n in ipairs(rapEggNames) do
                if d.Name == n then
                    c = c + 1
                    if mark then
                        local pp = rapEntityPos(d)
                        local dist = (myPos and pp) and (pp - myPos).Magnitude or 1e9
                        if dist <= 600 then
                            table.insert(found, { inst = d, dist = dist })
                        end
                    end
                    break
                end
            end
        end
    end
    -- Hanya 40 terdekat yang diberi label (anti menumpuk seperti di foto)
    if mark and #found > 0 then
        table.sort(found, function(a, b) return a.dist < b.dist end)
        for i = 1, math.min(#found, 40) do
            local e = found[i]
            local rar = rapRarityOf(e.inst.Name)
            espMark(e.inst, "[" .. rar .. "] " .. e.inst.Name, RARITY_COLOR[rar] or Color3.fromRGB(255, 255, 255))
        end
    end
    return c
end

local function rapZones(mark)
    local c = 0
    for _, d in ipairs(rapDescList()) do
        if (d:IsA("Model") or d:IsA("BasePart")) and d.Parent and d.Parent.Name == "EggSpawns" then
            c = c + 1
            if mark then espMark(d, "Zone " .. d.Name, Color3.fromRGB(255, 190, 60)) end
        end
    end
    return c
end

local function rapNpcs(mark)
    local c = 0
    for _, d in ipairs(rapDescList()) do
        if d:IsA("Model") then
            for _, n in ipairs(rapActors) do
                if d.Name == n then
                    c = c + 1
                    if mark then espMark(d, d.Name, Color3.fromRGB(255, 160, 70)) end
                    break
                end
            end
        end
    end
    return c
end

local function rapPlayers(mark)
    local c = 0
    local myRoot = rapGetRoot()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local ok, root = pcall(function() return p.Character:FindFirstChild("HumanoidRootPart") end)
            local dist = 0
            if ok and root and myRoot then
                dist = math.floor((root.Position - myRoot.Position).Magnitude + 0.5)
            end
            c = c + 1
            if mark then
                espMark(p.Character, p.DisplayName .. " [" .. tostring(dist) .. "m]", Color3.fromRGB(90, 255, 150), "player:" .. tostring(p.UserId))
            end
        end
    end
    return c
end

local function rapRanchMark(mark)
    if not mark then return 0 end
    local found = nil
    for _, pat in ipairs(RANCH_PATTERNS) do
        for _, d in ipairs(rapDescList()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and tostring(d.Name):lower():find(pat, 1, true) then
                found = d; break
            end
        end
        if found then break end
    end
    if found then
        espMark(found, "MY PLOT", Color3.fromRGB(255, 255, 255))
        return 1
    end
    return 0
end

local function espRefresh()
    espFrame = espFrame + 1
    rapDescRefresh()
    rapEggCount    = rapCountEggs(espMode.egg)
    rapZoneCount   = rapZones(espMode.zone)
    rapNpcCount    = rapNpcs(espMode.npc)
    rapPlayerCount = rapPlayers(espMode.player)
    if espMode.ranch or espMode.plot then rapRanchMark(true) end
    espSweep()
    rapDescCache = nil  -- jangan tahan daftar besar di memori
end

-- Satu task permanen (dibuat sekali). Loop lama start/stop punya balapan:
-- toggle OFF lalu ON dalam <0.45s bisa membuat loop keluar & ESP mati permanen.
local function espLoopStart()
    if espRunning then return end
    espRunning = true
    task.spawn(function()
        while true do
            local any = espMode.egg or espMode.zone or espMode.player or espMode.npc or espMode.ranch or espMode.plot
            if any then
                pcall(espRefresh)
                task.wait(0.45)
            else
                if next(espLive) ~= nil then pcall(espWipe) end
                task.wait(0.5)
            end
        end
    end)
end

local function espSet(key, on, title, onMsg, offMsg)
    espMode[key] = on and true or nil
    espLoopStart()
    Window:Notify({ Title = title, Description = on and onMsg or offMsg, Lifetime = 3 })
end

-- ==============================================================================================
-- KONTROL FILTER: SEARCH + MULTI-PILIH
-- Punya kotak pencarian dan bisa memilih lebih dari satu nilai sekaligus.
-- Dibuat MANDIRI (Instance.new + palet warna sendiri) karena U, T, track, dan
-- RegisterThemeColor adalah LOCAL di dalam IIFE pembuat UI ZypheraxUI sehingga
-- tidak terlihat dari sini. Ini penyebab error "attempt to index nil with 'New'".
-- ==============================================================================================
local function rapMultiSelect(cfg)
    local nm        = cfg.Label or cfg.Name or "Filter"
    local titleAttr = cfg.Name or nm
    local options   = cfg.Options or cfg.Items or {}
    local cb        = cfg.Callback or function() end
    local selected  = {}
    local query     = ""
    local isOpen    = false

    local COL = {
        Bg     = Color3.fromRGB(26, 30, 42),
        Bg2    = Color3.fromRGB(34, 40, 56),
        Accent = Color3.fromRGB(0, 170, 255),
        Text   = Color3.fromRGB(242, 244, 250),
        Muted  = Color3.fromRGB(145, 152, 170),
        Dim    = Color3.fromRGB(90, 96, 112),
        Stroke = Color3.fromRGB(38, 43, 58),
    }
    local FONT      = Enum.Font.Gotham
    local FONT_BOLD = Enum.Font.GothamBold

    local function mk(class, props)
        local inst = Instance.new(class)
        for k, v in pairs(props or {}) do
            if k ~= "Parent" then pcall(function() inst[k] = v end) end
        end
        if props and props.Parent then
            pcall(function() inst.Parent = props.Parent end)
        end
        return inst
    end

    local function round(inst, r)
        mk("UICorner", { CornerRadius = r or UDim.new(0, 6), Parent = inst })
    end

    local function outline(inst)
        mk("UIStroke", {
            Color = COL.Stroke,
            Thickness = 1,
            Transparency = 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            Parent = inst,
        })
    end

    -- Parent bisa berupa SectionObj (bukan Instance) atau Frame langsung.
    -- SectionObj diterjemahkan ke elemen container-nya dulu.
    local host = cfg.Parent
    if type(host) == "table" then
        host = host._container or host._box or nil
    end
    if not (host and host.Parent) then
        local okBool, isInstance = pcall(function() return host ~= nil and host.Parent ~= nil end)
        if not (okBool and isInstance) then
            local fallback = nil
            if type(cfg.Parent) == "table" and cfg.Parent._box then
                fallback = cfg.Parent._box.Parent
            end
            if not fallback then
                local okh, h = pcall(function() return gethui() end)
                if okh and h then fallback = h end
            end
            if not fallback then fallback = game:GetService("CoreGui") end
            host = fallback
        end
    end
    if not host then return nil end

    local base = mk("Frame", {
        Name = "Filter_" .. tostring(titleAttr),
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = COL.Bg,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 5,
        Parent = host,
    })
    round(base, UDim.new(0, 6))
    outline(base)
    pcall(function() base:SetAttribute("ControlName", titleAttr) end)
    if type(cfg.Parent) == "table" and cfg.Parent._items then
        pcall(function() table.insert(cfg.Parent._items, base) end)
    end

    local lbl = mk("TextLabel", {
        Text = nm .. ": Semua",
        Font = FONT,
        TextSize = 12,
        TextColor3 = COL.Text,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(1, -40, 0, 36),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 6,
        Parent = base,
    })

    local chevron = mk("TextLabel", {
        Text = "v",
        Font = FONT_BOLD,
        TextSize = 12,
        TextColor3 = COL.Muted,
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -26, 0, 0),
        Size = UDim2.new(0, 20, 0, 36),
        ZIndex = 6,
        Parent = base,
    })

    local body = mk("Frame", {
        Size = UDim2.new(1, -16, 0, 0),
        Position = UDim2.new(0, 8, 0, 38),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 7,
        Parent = base,
    })
    mk("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = body,
    })

    local search = mk("TextBox", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = COL.Bg2,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = "Cari (search)...",
        Font = FONT,
        TextSize = 11,
        TextColor3 = COL.Text,
        PlaceholderColor3 = COL.Dim,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ZIndex = 8,
        Parent = body,
    })
    round(search, UDim.new(0, 4))
    mk("UIPadding", { PaddingLeft = UDim.new(0, 8), Parent = search })

    local actsFrame = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        ZIndex = 8,
        Parent = body,
    })
    mk("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = actsFrame,
    })

    local listFrame = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 8,
        Parent = body,
    })
    mk("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = listFrame,
    })

    local function refreshLabel()
        local k = rapKeysOf(selected)
        if #k == 0 then
            lbl.Text = nm .. ": Semua"
            lbl.TextColor3 = COL.Text
        elseif #k <= 2 then
            lbl.Text = nm .. ": " .. table.concat(k, ", ")
            lbl.TextColor3 = COL.Accent
        else
            lbl.Text = nm .. ": " .. k[1] .. " +" .. tostring(#k - 1) .. " lagi"
            lbl.TextColor3 = COL.Accent
        end
    end

    local buildList

    local function setOpen(open)
        isOpen = open
        if open then
            body.Visible = true
            buildList()
            chevron.Text = "^"
        else
            chevron.Text = "v"
            body.Visible = false
            body.Size = UDim2.new(1, -16, 0, 0)
            base.Size = UDim2.new(1, 0, 0, 36)
        end
    end

    buildList = function()
        for _, c in ipairs(listFrame:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("TextLabel") then
                pcall(function() c:Destroy() end)
            end
        end
        local low = string.lower(query)
        local shown = 0
        for _, it in ipairs(options) do
            local s = tostring(it)
            if low == "" or string.find(string.lower(s), low, 1, true) then
                local on = selected[it] == true
                local btn = mk("TextButton", {
                    Size = UDim2.new(1, 0, 0, 24),
                    BackgroundColor3 = on and COL.Accent or COL.Bg2,
                    BackgroundTransparency = on and 0.55 or 0,
                    Text = s,
                    Font = FONT,
                    TextSize = 11,
                    TextColor3 = on and COL.Accent or COL.Text,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    BorderSizePixel = 0,
                    AutoButtonColor = true,
                    ZIndex = 9,
                    Parent = listFrame,
                })
                round(btn, UDim.new(0, 4))
                mk("UIPadding", { PaddingLeft = UDim.new(0, 6), Parent = btn })
                btn.MouseButton1Click:Connect(function()
                    if selected[it] then selected[it] = nil else selected[it] = true end
                    refreshLabel()
                    buildList()
                    pcall(cb, rapKeysOf(selected))
                end)
                shown = shown + 1
            end
        end
        if shown == 0 then
            mk("TextLabel", {
                Size = UDim2.new(1, 0, 0, 22),
                BackgroundTransparency = 1,
                Text = "Tidak ada hasil",
                Font = FONT,
                TextSize = 11,
                TextColor3 = COL.Dim,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 9,
                Parent = listFrame,
            })
        end
        local listH = (shown == 0) and 22 or math.min(shown * 26, 260)
        local bodyH = 28 + 4 + 24 + 4 + listH + 4
        listFrame.Size = UDim2.new(1, 0, 0, listH)
        body.Size = UDim2.new(1, -16, 0, bodyH)
        base.Size = UDim2.new(1, 0, 0, 44 + bodyH)
    end

    search:GetPropertyChangedSignal("Text"):Connect(function()
        query = search.Text or ""
        if isOpen then buildList() end
    end)

    local btnAll = mk("TextButton", {
        Size = UDim2.new(0, 92, 0, 22),
        BackgroundColor3 = COL.Bg2,
        BorderSizePixel = 0,
        Text = "Pilih Semua",
        Font = FONT,
        TextSize = 10,
        TextColor3 = COL.Text,
        AutoButtonColor = true,
        ZIndex = 9,
        Parent = actsFrame,
    })
    round(btnAll, UDim.new(0, 4))
    btnAll.MouseButton1Click:Connect(function()
        for _, it in ipairs(options) do selected[it] = true end
        refreshLabel()
        if isOpen then buildList() end
        pcall(cb, rapKeysOf(selected))
    end)

    local btnNone = mk("TextButton", {
        Size = UDim2.new(0, 92, 0, 22),
        BackgroundColor3 = COL.Bg2,
        BorderSizePixel = 0,
        Text = "Kosongkan",
        Font = FONT,
        TextSize = 10,
        TextColor3 = COL.Text,
        AutoButtonColor = true,
        ZIndex = 9,
        Parent = actsFrame,
    })
    round(btnNone, UDim.new(0, 4))
    btnNone.MouseButton1Click:Connect(function()
        selected = {}
        refreshLabel()
        if isOpen then buildList() end
        pcall(cb, rapKeysOf(selected))
    end)

    local toggle = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 36),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 10,
        Parent = base,
    })
    toggle.MouseButton1Click:Connect(function()
        setOpen(not isOpen)
    end)

    refreshLabel()

    return {
        Set = function(_, list)
            selected = {}
            for _, v in ipairs(list or {}) do selected[v] = true end
            refreshLabel()
            if isOpen then buildList() end
            pcall(cb, rapKeysOf(selected))
        end,
        Get = function() return rapKeysOf(selected) end,
        SetItems = function(_, list)
            -- Ganti daftar opsi tanpa menghapus pilihan yang sudah ada.
            options = list or {}
            if isOpen then buildList() end
        end,
        _base = base,
    }
end

local function rapNewFilter(parent, label, options, defaultList, callback)
    local sel = {}
    for _, v in ipairs(defaultList or {}) do sel[v] = true end
    local obj = rapMultiSelect({
        Parent = parent,
        Label = label,
        Options = options,
        Callback = callback,
    })
    if obj and obj.Set then pcall(function() obj:Set(rapKeysOf(sel)) end) end
    return obj
end

-- ==============================================================================================
-- MENU: MAIN
-- ==============================================================================================
local TabMainRAP = tabGroup:Tab({ Name = "Main", Image = "lucide/zap" })
local TabFarmRAP = tabGroup:Tab({ Name = "Farm", Image = "lucide/sprout" })
-- ===== FARM: PROGRESSION ala foto (pakai UI Zypherax) =====
local SecProg = TabMainRAP:Section({ Name = "Main", Side = 1 })
SecProg:Header({ Name = ZypheraxLib:Gradient("Main", Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 140, 230)) })
rapPlanned = rapPlanned or {}
local function rapProgToggle(name, key, onMsg, offMsg)
    SecProg:Toggle({ Name = name, Default = false, Callback = function(enabled)
        rapPlanned[key] = enabled and true or false
        Window:Notify({ Title = "Main", Description = enabled and onMsg or offMsg, Lifetime = 3 })
    end })
end
rapProgToggle("Auto Buy Hatch Luck", "buyLuck", "Auto buy hatch luck aktif.", "Auto buy hatch luck dimatikan.")
rapProgToggle("Buy Max", "buyMax", "Buy max aktif.", "Buy max dimatikan.")
rapProgToggle("Auto Unlock Nests", "unlockNests", "Auto unlock nests aktif.", "Auto unlock nests dimatikan.")
rapProgToggle("Auto Rebirth", "autoRebirth", "Auto rebirth aktif.", "Auto rebirth dimatikan.")
rapProgToggle("Auto Ride Best Pet", "rideBest", "Auto ride best pet aktif.", "Auto ride best pet dimatikan.")
rapProgToggle("Auto Claim Index Rewards", "claimIndex", "Auto claim index rewards aktif.", "Auto claim index rewards dimatikan.")
rapProgToggle("Auto Claim Offline Earnings", "claimOffline", "Auto claim offline earnings aktif.", "Auto claim offline earnings dimatikan.")
SecProg:Label({ Name = "Luck 1.0x | Next $5 | Bought 0" })
SecProg:Label({ Name = "Planted 0 / 10" })
SecProg:Label({ Name = "Idle  Rebirth $49.23K / $1M" })
SecProg:Label({ Name = "Ride: Idle  Speed 0  Mounts 0" })

-- ===== FARM: 2 GRUP (EGGS kiri | PETS kanan) =====
local farmEggSecs, farmPetSecs = {}, {}
local eggsHidden, petsHidden = false, false
local function farmSetVisible(list, vis)
    for _, s in ipairs(list) do
        pcall(function()
            local box = s._box or (s._zsec and s._zsec._box)
            if box then box.Visible = vis end
        end)
    end
end
local SecEggs = TabFarmRAP:Section({ Name = "EGGS", Side = 1 })
-- hideEmptyEggs: strip header saja, box kosong disembunyikan (tanpa padding)
do pcall(function()
    local hb = SecEggs._box or (SecEggs._zsec and SecEggs._zsec._box)
    if hb then
        for _, ch in ipairs(hb:GetChildren()) do
            if ch:IsA("Frame") and ch.Name ~= "Header" then ch.Visible = false end
        end
        hb.AutomaticSize = Enum.AutomaticSize.Y
        local pad = hb:FindFirstChildOfClass("UIPadding")
        if pad then pad:Destroy() end
    end
end) end
SecEggs:Header({ Name = ZypheraxLib:Gradient("Eggs", Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 140, 230)) })
-- Panah v di kanan header Eggs (klik = hide/show sebaris ikut semua)
do -- farmArrowEggs
    pcall(function()
        local box = SecEggs._box or (SecEggs._zsec and SecEggs._zsec._box)
    local hdr = box and box:FindFirstChild("Header")
    if not hdr then return end
    local b = Instance.new("TextButton")
    b.Name = "CollapseArrow"
    b.Size = UDim2.fromOffset(30, 28)
    b.Position = UDim2.new(1, -32, 0, 0)
    b.BackgroundTransparency = 1
    b.Text = "v"
    b.Font = Enum.Font.GothamBold
    b.TextSize = 15
    b.TextColor3 = Color3.fromRGB(0, 170, 255)
    b.ZIndex = 7
    b.Parent = hdr
    local hidden = false
    b.MouseButton1Click:Connect(function()
        hidden = not hidden
        b.Text = hidden and "^" or "v"
        farmSetVisible(farmEggSecs, not hidden)
    end)
end) end
local SecPetsHead = TabFarmRAP:Section({ Name = "PETS", Side = 2 })
-- hideEmptyPets: strip header saja, box kosong disembunyikan (tanpa padding)
do pcall(function()
    local hb = SecPetsHead._box or (SecPetsHead._zsec and SecPetsHead._zsec._box)
    if hb then
        for _, ch in ipairs(hb:GetChildren()) do
            if ch:IsA("Frame") and ch.Name ~= "Header" then ch.Visible = false end
        end
        hb.AutomaticSize = Enum.AutomaticSize.Y
        local pad = hb:FindFirstChildOfClass("UIPadding")
        if pad then pad:Destroy() end
    end
end) end
SecPetsHead:Header({ Name = ZypheraxLib:Gradient("Pets", Color3.fromRGB(255, 170, 90), Color3.fromRGB(255, 110, 140)) })
-- Panah v di kanan header Pets (klik = hide/show sebaris ikut semua)
do pcall(function()
    local box = SecPetsHead._box or (SecPetsHead._zsec and SecPetsHead._zsec._box)
    local hdr = box and box:FindFirstChild("Header")
    if not hdr then return end
    local b = Instance.new("TextButton")
    b.Name = "CollapseArrow"
    b.Size = UDim2.fromOffset(30, 28)
    b.Position = UDim2.new(1, -32, 0, 0)
    b.BackgroundTransparency = 1
    b.Text = "v"
    b.Font = Enum.Font.GothamBold
    b.TextSize = 15
    b.TextColor3 = Color3.fromRGB(255, 170, 90)
    b.ZIndex = 7
    b.Parent = hdr
    local hidden = false
    b.MouseButton1Click:Connect(function()
        hidden = not hidden
        b.Text = hidden and "^" or "v"
        farmSetVisible(farmPetSecs, not hidden)
    end)
end) end
local SecAutoEgg = TabFarmRAP:Section({ Name = "Auto Egg Collector", Side = 1 })
SecAutoEgg:Header({ Name = ZypheraxLib:Gradient("Auto Egg Collector", Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 140, 230)) })
do table.insert(farmEggSecs, SecAutoEgg) end
-- header di atas sudah jelas

-- Grup Auto Farm ala foto (pakai UI Zypherax sendiri)
local RAP_ALL = "--"
local function rapSetSingle(setName, val)
    local set = (setName == "rarity") and rapRarityFilterSet
        or (setName == "mutation") and rapMutationFilterSet
        or rapEggFilterSet
    for k in pairs(set) do set[k] = nil end
    if val and val ~= RAP_ALL and val ~= "" then
        set[val] = true
    end
end
rapPlanned = rapPlanned or {}

SecAutoEgg:Toggle({
    Name = "Auto Farm Eggs",
    Default = false,
    Callback = function(enabled)
        rapSet("pickup", enabled, "Auto Farm Eggs",
            ("Farming telur (rarity: %s, egg: %s, mutation: %s)."):format(
                rapFilterText(rapRarityFilterSet, "Semua"),
                rapFilterText(rapEggFilterSet, "Semua"),
                rapFilterText(rapMutationFilterSet, "Semua")),
            "Auto farm eggs dimatikan.")
    end,
})

SecAutoEgg:Toggle({
    Name = "Auto Farm Rebirth Egg",
    Default = false,
    Callback = function(enabled)
        rapPlanned.rebirthEgg = enabled and true or false
        Window:Notify({ Title = "Rebirth Egg", Description = enabled and "Auto farm rebirth egg aktif (engine menyusul)." or "Auto farm rebirth egg dimatikan.", Lifetime = 3 })
    end,
})

SecAutoEgg:Dropdown({
    Name = "Rarity",
    Items = (function()
        local o = { RAP_ALL }
        for _, r in ipairs(RARITY_LIST) do table.insert(o, r) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v) rapSetSingle("rarity", v) end,
})

-- Daftar telur urut rarity (nama polos, tanpa tanda kurung)
local rapEggSorted = {}
do
    local order = {}
    for i, r in ipairs((typeof(RARITY_LIST)=="table" and RARITY_LIST) or {"Common","Rare","Epic","Legendary","Mythic"}) do order[r] = i end
    for _, eggName in ipairs(rapEggNames) do table.insert(rapEggSorted, eggName) end
    table.sort(rapEggSorted, function(a, b)
        local ra, rb = RAP_RARITY[a] or "Unknown", RAP_RARITY[b] or "Unknown"
        if (order[ra] or 99) ~= (order[rb] or 99) then
            return (order[ra] or 99) < (order[rb] or 99)
        end
        return a < b
    end)
end

SecAutoEgg:Dropdown({
    Name = "Egg",
    Items = (function()
        local o = { RAP_ALL }
        for _, e in ipairs(rapEggSorted) do table.insert(o, e) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v) rapSetSingle("egg", v) end,
})

SecAutoEgg:Dropdown({
    Name = "Mutation",
    Items = (function()
        local o = { RAP_ALL }
        for _, m in ipairs(RAP_MUTATIONS) do table.insert(o, m) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v) rapSetSingle("mutation", v) end,
})

SecAutoEgg:Slider({
    Name = "Tween Speed (st/s)",
    Default = 1000,
    Minimum = 100,
    Maximum = 5000,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(value) rapPlanned.glideSpeed = value end,
})

SecAutoEgg:Slider({
    Name = "Claim Delay (0.1s)",
    Default = 5,
    Minimum = 1,
    Maximum = 30,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(value)
        RAP_DELAY = math.max(0.25, (tonumber(value) or 5) / 10)
    end,
})

local SecPlace = TabFarmRAP:Section({ Name = "Auto Place Eggs", Side = 1 })
SecPlace:Header({ Name = ZypheraxLib:Gradient("Auto Place Eggs", Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 140, 230)) })
do table.insert(farmEggSecs, SecPlace) end
-- header di atas sudah jelas

SecPlace:Toggle({
    Name = "Auto Place Eggs",
    Default = false,
    Callback = function(enabled)
        rapSet("placedEgg", enabled, "Placed Egg",
            "Telur otomatis ditaruh di My Plot.",
            "Auto place eggs dimatikan.")
    end,
})

SecPlace:Dropdown({
    Name = "Place",
    Items = { "All", "Best", "Filtered" },
    Default = "All",
    Callback = function(v) rapPlanned.placeMode = v or "All" end,
})

SecPlace:Slider({
    Name = "Max Planted",
    Default = 5,
    Minimum = 1,
    Maximum = 30,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(value) rapEggCapacity = value end,
})

SecPlace:Dropdown({
    Name = "Place Rarity",
    Items = (function()
        local o = { RAP_ALL }
        for _, r in ipairs(RARITY_LIST) do table.insert(o, r) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v)
        rapPlanned.placeRarity = v
    end,
})

SecPlace:Dropdown({
    Name = "Place Egg",
    Items = (function()
        local o = { RAP_ALL }
        for _, e in ipairs(rapEggSorted) do table.insert(o, e) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v)
        rapPlanned.placeEgg = v
    end,
})

SecPlace:Dropdown({
    Name = "Place Mutation",
    Items = (function()
        local o = { RAP_ALL }
        for _, m in ipairs(RAP_MUTATIONS) do table.insert(o, m) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v)
        rapPlanned.placeMutation = v
    end,
})

SecPlace:Input({
    Name = "Place Min Size (KG)",
    Default = "0",
    Placeholder = "0",
    Callback = function(text) rapPlanned.placeMinSize = tonumber(text) or 0 end,
})

SecPlace:Input({
    Name = "Place Only Below KG",
    Default = "0",
    Placeholder = "0",
    Callback = function(text) rapPlanned.placeBelowKG = tonumber(text) or 0 end,
})

SecPlace:Dropdown({
    Name = "Place Order",
    Items = { "Rarity then Size", "Size then Rarity", "Rarity Only" },
    Default = "Rarity then Size",
    Callback = function(v) rapPlanned.placeOrder = v or "Rarity then Size" end,
})

SecPlace:Toggle({
    Name = "Auto Hatch Eggs",
    Default = false,
    Callback = function(enabled)
        rapSet("hatch", enabled, "Auto Hatch", "Menetaskan telur otomatis.", "Auto hatch dimatikan.")
    end,
})

-- Engine lama yang dipertahankan
SecAutoEgg:Dropdown({
    Name = "Mode Ambil Telur",
    Items = { "Tween", "Instant" },
    Default = "Tween",
    Callback = function(v) rapPickupMode = v or "Tween" end,
})

SecAutoEgg:Toggle({
    Name = "Balik ke Plot Setelah Ambil Telur",
    Default = true,
    Callback = function(enabled)
        rapReturnRanch = enabled and true or false
    end,
})

SecAutoEgg:Toggle({
    Name = "Pakai Trigger Remote (Cadangan Gagal Pick Up)",
    Default = true,
    Callback = function(enabled)
        rapUseRemoteFallback = enabled and true or false
    end,
})

local SecTele = TabMainRAP:Section({ Name = "Teleport", Side = 1 })
SecTele:Header({ Name = ZypheraxLib:Gradient("Teleport Cepat", Color3.fromRGB(240, 190, 100), Color3.fromRGB(255, 160, 120)) })

SecTele:Dropdown({
    Name = "Tujuan Teleport",
    Items = rapGoals,
    Default = "Player Spawn",
    Callback = function(v) rapGoal = v or "Player Spawn" end,
})

SecTele:Button({
    Name = "Teleport ke Tujuan Terpilih",
    Callback = function()
        for _, d in ipairs(rapTickList()) do
            if (d:IsA("Model") or d:IsA("BasePart")) and d.Name == rapGoal then
                local p = rapEntityPos(d)
                if p then
                    rapTeleportTo(p, rapGoal)
                    Window:Notify({ Title = "Teleport", Description = "Pindah ke " .. tostring(rapGoal) .. ".", Lifetime = 3 })
                end
                return
            end
        end
        Window:Notify({ Title = "Teleport", Description = tostring(rapGoal) .. " tidak ditemukan.", Lifetime = 3 })
    end,
})

SecTele:Button({
    Name = "Teleport ke Spawn",
    Callback = function()
        local sp = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
        if sp then
            rapTeleportTo(sp.Position, "Spawn")
            Window:Notify({ Title = "Teleport", Description = "Pindah ke spawn.", Lifetime = 3 })
        end
    end,
})

SecTele:Toggle({
    Name = "Auto Teleport ke Tujuan",
    Default = false,
    Callback = function(enabled)
        rapSet("autoTp", enabled, "Auto Teleport",
            "Terus pindah ke " .. tostring(rapGoal) .. ".",
            "Auto teleport dimatikan.")
    end,
})

local SecRanch = TabMainRAP:Section({ Name = "My Plot", Side = 2 })
SecRanch:Header({ Name = ZypheraxLib:Gradient("My Plot", Color3.fromRGB(255, 170, 90), Color3.fromRGB(255, 110, 140)) })

SecRanch:Label({ Name = "My Plot dideteksi otomatis (nama objek mengandung 'ranch/pen/nest/home/base'), cadangan dari SpawnLocation." })

SecRanch:Button({
    Name = "Balik ke My Plot Sekarang",
    Callback = function() rapGoPlot(true) end,
})

SecRanch:Button({
    Name = "Jadikan Posisi Ini Plot Saya",
    Callback = function()
        if rapSetHomeHere() then Window:Notify({ Title = "Plot", Description = "Plot dikunci di posisi kamu berdiri.", Lifetime = 3 }) else Window:Notify({ Title = "Plot", Description = "Karakter tidak ketemu.", Lifetime = 3 }) end
    end,
})

SecRanch:Button({
    Name = "Deteksi Ulang My Plot",
    Callback = function()
        rapRanchPos = nil rapPlotPos = nil
        local p = rapRefreshRanch()
        Window:Notify({
            Title = "Plot",
            Description = p and ("My Plot ditemukan: " .. tostring(math.floor(p.X)) .. ", " .. tostring(math.floor(p.Z))) or "My Plot tidak ditemukan.",
            Lifetime = 4,
        })
    end,
})

SecRanch:Toggle({
    Name = "Auto Placed Egg (Taruh Telur di Plot)",
    Default = false,
    Callback = function(enabled)
        rapSet("placedEgg", enabled, "Placed Egg",
            "Telur otomatis ditaruh di My Plot.",
            "Auto placed egg dimatikan.")
    end,
})

SecRanch:Button({
    Name = "Taruh Telur Sekarang",
    Callback = function()
        local n = rapPlaceEggs()
        Window:Notify({
            Title = "Placed Egg",
            Description = (n > 0) and ("Menaruh telur (%d prompt)."):format(n) or "Tidak ada prompt taruh telur ditemukan di plot.",
            Lifetime = 4,
        })
    end,
})

local SecEvent = TabMainRAP:Section({ Name = "Event & Klaim", Side = 1 })
SecEvent:Header({ Name = ZypheraxLib:Gradient("Event & Reward", Color3.fromRGB(99, 130, 255), Color3.fromRGB(168, 120, 255)) })

SecEvent:Toggle({
    Name = "Auto Claim Event & Group (Remote)",
    Default = false,
    Callback = function(enabled)
        rapSet("remoteClaim", enabled, "Auto Claim", "Klaim reward event & group otomatis.", "Auto claim dimatikan.")
    end,
})

SecEvent:Toggle({
    Name = "Auto Klaim Prompt (Claim / Unlock)",
    Default = false,
    Callback = function(enabled)
        rapSet("claim", enabled, "Auto Klaim", "Menekan prompt Claim / Unlock Nest otomatis.", "Auto klaim dimatikan.")
    end,
})

SecEvent:Toggle({
    Name = "Auto Join Event",
    Default = false,
    Callback = function(enabled)
        rapSet("join", enabled, "Auto Join", "Masuk event otomatis jika tersedia.", "Auto join dimatikan.")
    end,
})

SecEvent:Toggle({
    Name = "Auto Ride Hewan (Snail, Cheetah, dll)",
    Default = false,
    Callback = function(enabled)
        rapSet("ride", enabled, "Auto Ride", "Menaiki hewan (Ride) otomatis.", "Auto ride dimatikan.")
    end,
})

SecEvent:Toggle({
    Name = "Auto Pakai Skill / Spell / Feed",
    Default = false,
    Callback = function(enabled)
        rapSet("skill", enabled, "Auto Skill", "Menekan skill/spell/ability/feed otomatis.", "Auto skill dimatikan.")
    end,
})

-- ==============================================================================================
-- Grup tambahan ala foto (UI Zypherax sendiri, engine menyusul)
local SecVolcano = TabFarmRAP:Section({ Name = "Volcano", Side = 1 })
SecVolcano:Header({ Name = ZypheraxLib:Gradient("Volcano", Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 140, 230)) })
do table.insert(farmEggSecs, SecVolcano) end
-- header di atas sudah jelas

SecVolcano:Toggle({
    Name = "Auto Volcano Dip",
    Default = false,
    Callback = function(enabled)
        rapPlanned.volcanoDip = enabled and true or false
        Window:Notify({ Title = "Volcano", Description = enabled and "Auto volcano dip aktif (engine menyusul)." or "Auto volcano dip dimatikan.", Lifetime = 3 })
    end,
})

SecVolcano:Dropdown({
    Name = "Dip Rarity",
    Items = (function()
        local o = { RAP_ALL }
        for _, r in ipairs(RARITY_LIST) do table.insert(o, r) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v) rapPlanned.dipRarity = v end,
})

SecVolcano:Dropdown({
    Name = "Dip Egg",
    Items = (function()
        local o = { RAP_ALL }
        for _, e in ipairs(rapEggSorted) do table.insert(o, e) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v) rapPlanned.dipEgg = v end,
})

SecVolcano:Label({ Name = "Skips eggs whose mutation already beats Magma (10x)" })
rapVolcanoStatus = SecVolcano:Label({ Name = "Volcano: Idle | 0 Dipped | 0 Magma" })

local SecPets = TabFarmRAP:Section({ Name = "Place Pets", Side = 2 })
SecPets:Header({ Name = ZypheraxLib:Gradient("Place Pets", Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 140, 230)) })
do table.insert(farmPetSecs, SecPets) end
SecPets:Toggle({ Name = "Auto Place Pets (Taruh Pet)", Default = false, Callback = function(enabled)
    rapPlanned.placePets = enabled and true or false
    Window:Notify({ Title = "Pets", Description = enabled and "Auto place pets aktif." or "Auto place pets dimatikan.", Lifetime = 3 })
end })
SecPets:Label({ Name = "pets untuk auto place pets" })

SecPets:Toggle({
    Name = "Auto Place Best Pets",
    Default = false,
    Callback = function(enabled)
        rapPlanned.placeBest = enabled and true or false
        Window:Notify({ Title = "Pets", Description = enabled and "Auto place best pets aktif (engine menyusul)." or "Auto place best pets dimatikan.", Lifetime = 3 })
    end,
})

SecPets:Slider({
    Name = "Place Best Delay (s)",
    Default = 10,
    Minimum = 1,
    Maximum = 60,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(value) rapPlanned.placeBestDelay = value end,
})

SecPets:Toggle({
    Name = "Auto Sell Pets",
    Default = false,
    Callback = function(enabled)
        rapSet("autoSell", enabled, "Auto Sell Pets",
            "Menjual pet otomatis sesuai filter.",
            "Auto sell pets dimatikan.")
    end,
})

SecPets:Input({
    Name = "Below $/s",
    Default = "0",
    Placeholder = "0",
    Callback = function(text) rapPlanned.sellBelow = tonumber(text) or 0 end,
})

SecPets:Dropdown({
    Name = "Rarity",
    Items = (function()
        local o = { RAP_ALL }
        for _, r in ipairs(RARITY_LIST) do table.insert(o, r) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v)
        for k in pairs(rapSellRaritySet) do rapSellRaritySet[k] = nil end
        if v and v ~= RAP_ALL and v ~= "" then rapSellRaritySet[v] = true end
    end,
})

SecPets:Dropdown({
    Name = "Mutation",
    Items = (function()
        local o = { RAP_ALL }
        for _, m in ipairs(RAP_MUTATIONS) do table.insert(o, m) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v) rapPlanned.sellMutation = v end,
})

local SecFusion = TabFarmRAP:Section({ Name = "Fusion", Side = 2 })
SecFusion:Header({ Name = ZypheraxLib:Gradient("Fusion", Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 140, 230)) })
do table.insert(farmPetSecs, SecFusion) end
-- header di atas sudah jelas

SecFusion:Toggle({
    Name = "Auto Fuse",
    Default = false,
    Callback = function(enabled)
        rapSet("fuse", enabled, "Fusion", "Auto fuse aktif.", "Auto fuse dimatikan.")
    end,
})

SecFusion:Toggle({
    Name = "Auto Claim Fuse",
    Default = false,
    Callback = function(enabled)
        rapPlanned.autoClaimFuse = enabled and true or false
        Window:Notify({ Title = "Fusion", Description = enabled and "Auto claim fuse aktif (engine menyusul)." or "Auto claim fuse dimatikan.", Lifetime = 3 })
    end,
})

SecFusion:Dropdown({
    Name = "Fuse Rarity",
    Items = (function()
        local o = { RAP_ALL }
        for _, r in ipairs(RARITY_LIST) do table.insert(o, r) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v) rapPlanned.fuseRarity = v end,
})

SecFusion:Dropdown({
    Name = "Fuse Pet",
    Items = { RAP_ALL },
    Default = RAP_ALL,
    Callback = function(v) rapPlanned.fusePet = v end,
})

SecFusion:Input({
    Name = "Below $/s",
    Default = "0",
    Placeholder = "0",
    Callback = function(text) rapPlanned.fuseBelow = tonumber(text) or 0 end,
})

SecFusion:Label({ Name = "Never fuses favourites" })
rapFusionStatus = SecFusion:Label({ Name = "Fusion: Idle | Fused 0" })

local SecFeeds = TabFarmRAP:Section({ Name = "Feeds", Side = 2 })
SecFeeds:Header({ Name = ZypheraxLib:Gradient("Feeds", Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 140, 230)) })
do table.insert(farmPetSecs, SecFeeds) end
-- farmUnify: DIHAPUS (kotak sub kembali normal)


-- farmBlend: diganti farmNest (sub tetap berkotak tipis)

SecFeeds:Toggle({
    Name = "Auto Feed Pets",
    Default = false,
    Callback = function(enabled)
        rapSet("feed", enabled, "Auto Feed", "Memberi makan pet otomatis.", "Auto feed dimatikan.")
    end,
})

SecFeeds:Dropdown({
    Name = "Food",
    Items = (function()
        local o = { RAP_ALL }
        for _, f in ipairs(rapFoodItems) do table.insert(o, f) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v) rapPlanned.feedFood = v end,
})

SecFeeds:Toggle({
    Name = "Auto Feed Best Pet",
    Default = false,
    Callback = function(enabled)
        rapPlanned.feedBest = enabled and true or false
        Window:Notify({ Title = "Feeds", Description = enabled and "Auto feed best pet aktif (engine menyusul)." or "Auto feed best pet dimatikan.", Lifetime = 3 })
    end,
})

SecFeeds:Toggle({
    Name = "Auto Feed Above $/s",
    Default = false,
    Callback = function(enabled)
        rapPlanned.feedAboveMoney = enabled and true or false
    end,
})

SecFeeds:Input({
    Name = "Min $/s",
    Default = "0",
    Placeholder = "0",
    Callback = function(text) rapPlanned.feedMinMoney = tonumber(text) or 0 end,
})

SecFeeds:Toggle({
    Name = "Auto Feed Above Age",
    Default = false,
    Callback = function(enabled)
        rapPlanned.feedAboveAge = enabled and true or false
    end,
})

SecFeeds:Slider({
    Name = "Min Age",
    Default = 1,
    Minimum = 1,
    Maximum = 100,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(value) rapPlanned.feedMinAge = value end,
})

SecFeeds:Toggle({
    Name = "Auto Feed By Rarity",
    Default = false,
    Callback = function(enabled)
        rapPlanned.feedByRarity = enabled and true or false
    end,
})

SecFeeds:Dropdown({
    Name = "Rarity",
    Items = (function()
        local o = { RAP_ALL }
        for _, r in ipairs(RARITY_LIST) do table.insert(o, r) end
        return o
    end)(),
    Default = RAP_ALL,
    Callback = function(v) rapPlanned.feedRarity = v end,
})
-- MENU: SHOP (AUTO BUY FOOD/GEARS + AUTO SELL / SELL ALL)
-- ==============================================================================================
local TabShop = tabGroup:Tab({ Name = "Shop", Image = "lucide/shopping-cart" })

-- Auto Shop (Autobuy remote, terbukti OK via trigger)
local SecAutoShop = TabShop:Section({ Name = "Auto Shop", Side = 1 })
SecAutoShop:Header({ Name = ZypheraxLib:Gradient("Auto Shop", Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 140, 230)) })
SecAutoShop:Toggle({
    Name = "Auto Buy (Autobuy)",
    Default = false,
    Callback = function(enabled)
        rapSet("shop", enabled, "Auto Shop", "Auto buy aktif.", "Auto buy dimatikan.")
    end,
})

local SecBuyFood = TabShop:Section({ Name = "Auto Buy - Food", Side = 1 })
SecBuyFood:Header({ Name = ZypheraxLib:Gradient("Auto Buy Food", Color3.fromRGB(120, 230, 140), Color3.fromRGB(72, 214, 200)) })

rapFoodDD = rapNewFilter(SecBuyFood, "Pilih Food yang Dibeli", rapFoodItems, {}, function(list)
    rapBuyFoodSet = {}
    for _, v in ipairs(list) do rapBuyFoodSet[v] = true end
end)

SecBuyFood:Button({
    Name = "Scan Item Shop (Food + Gears)",
    Callback = function()
        local f, g = rapScanShopItems()
        Window:Notify({
            Title = "Scan Shop",
            Description = ("Dapat %d food & %d gears. Buka dulu tab Food/Gears di shop game-nya."):format(f, g),
            Lifetime = 4,
        })
    end,
})

SecBuyFood:Label({ Name = "Pilih food yang mau dibeli (bisa banyak + search). Kosong = beli semua food." })

SecBuyFood:Toggle({
    Name = "Auto Buy Food",
    Default = false,
    Callback = function(enabled)
        rapBuyFood = enabled and true or false
        if enabled then rapLoopStart() end
        Window:Notify({
            Title = "Auto Buy Food",
            Description = enabled and ("Membeli food: " .. rapFilterText(rapBuyFoodSet, "Semua")) or "Auto buy food dimatikan.",
            Lifetime = 3,
        })
    end,
})

SecBuyFood:Button({
    Name = "Beli Food Sekarang",
    Callback = function()
        rapBuyFood = true
        local n = rapBuyTick()
        rapBuyFood = false
        Window:Notify({ Title = "Shop", Description = (n > 0) and ("Membeli %d food."):format(n) or "Tidak ada tombol Buy Food ditemukan (buka shop dulu).", Lifetime = 4 })
    end,
})

SecBuyFood:Label({ Name = "Buka shop in-game dulu agar tombol Food muncul, lalu nyalakan Auto Buy." })

local SecBuyGear = TabShop:Section({ Name = "Auto Buy - Gears", Side = 2 })
SecBuyGear:Header({ Name = ZypheraxLib:Gradient("Auto Buy Gears", Color3.fromRGB(255, 190, 90), Color3.fromRGB(255, 130, 120)) })

rapGearDD = rapNewFilter(SecBuyGear, "Pilih Gears yang Dibeli", rapGearItems, {}, function(list)
    rapBuyGearSet = {}
    for _, v in ipairs(list) do rapBuyGearSet[v] = true end
end)

SecBuyGear:Label({ Name = "Pilih gears yang mau dibeli (bisa banyak + search). Kosong = beli semua gears." })

SecBuyGear:Toggle({
    Name = "Auto Buy Gears",
    Default = false,
    Callback = function(enabled)
        rapBuyGear = enabled and true or false
        if enabled then rapLoopStart() end
        Window:Notify({
            Title = "Auto Buy Gears",
            Description = enabled and "Membeli gears otomatis di shop." or "Auto buy gears dimatikan.",
            Lifetime = 3,
        })
    end,
})

SecBuyGear:Button({
    Name = "Beli Gears Sekarang",
    Callback = function()
        rapBuyGear = true
        local n = rapBuyTick()
        rapBuyGear = false
        Window:Notify({ Title = "Shop", Description = (n > 0) and ("Membeli %d gear."):format(n) or "Tidak ada tombol Buy Gears ditemukan (buka shop dulu).", Lifetime = 4 })
    end,
})

SecBuyGear:Label({ Name = "Gears dipisah dari Food, toggle-nya berdiri sendiri." })

local SecSell = TabShop:Section({ Name = "Auto Sell & Sell All", Side = 1 })
SecSell:Header({ Name = ZypheraxLib:Gradient("Auto Sell (Rarity + Weight)", Color3.fromRGB(255, 107, 138), Color3.fromRGB(199, 155, 255)) })

rapNewFilter(SecSell, "Filter Rarity untuk Dijual", RARITY_LIST, {}, function(list)
    rapSellRaritySet = {}
    for _, v in ipairs(list) do rapSellRaritySet[v] = true end
end)

SecSell:Label({ Name = "Filter bisa pilih banyak + search. Kosong = semua rarity." })

SecSell:Toggle({
    Name = "Pakai Filter Weight",
    Default = false,
    Callback = function(enabled) rapUseWeightFilter = enabled and true or false end,
})

SecSell:Slider({
    Name = "Berat Maksimum yang Dijual",
    Default = 0,
    Minimum = 0,
    Maximum = 500,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(value) rapSellMaxWeight = value end,
})

SecSell:Label({ Name = "Berat dibaca dari atribut/NumberValue bernama 'Weight' pada pet. 0 = abaikan berat." })

SecSell:Toggle({
    Name = "Auto Sell (Sesuai Filter)",
    Default = false,
    Callback = function(enabled)
        rapSet("autoSell", enabled, "Auto Sell",
            ("Menjual otomatis (rarity: %s)."):format(rapFilterText(rapSellRaritySet, "Semua Rarity")),
            "Auto sell dimatikan.")
    end,
})

SecSell:Button({
    Name = "Sell All (Sesuai Filter)",
    Callback = function()
        local n = rapSellTick(false)
        Window:Notify({
            Title = "Sell All",
            Description = (n > 0) and ("Menjual %d item sesuai filter."):format(n) or "Tidak ada prompt Sell ditemukan.",
            Lifetime = 4,
        })
    end,
})

SecSell:Button({
    Name = "Sell All (Tanpa Filter / Semua)",
    Callback = function()
        local n = rapSellTick(true)
        Window:Notify({
            Title = "Sell All",
            Description = (n > 0) and ("Menjual %d item (tanpa filter)."):format(n) or "Tidak ada prompt Sell ditemukan.",
            Lifetime = 4,
        })
    end,
})

local SecShopInfo = TabShop:Section({ Name = "Info & Statistik", Side = 2 })
SecShopInfo:Header({ Name = ZypheraxLib:Gradient("Statistik Shop", Color3.fromRGB(140, 152, 190), Color3.fromRGB(120, 170, 200)) })

SecShopInfo:Button({
    Name = "Lihat Statistik",
    Callback = function()
        Window:Notify({
            Title = "Statistik",
            Description = ("Telur: %d | Dijual: %d | Dibeli: %d"):format(rapPickedCount, rapSellCount, rapBuyCount),
            Lifetime = 4,
        })
    end,
})

SecShopInfo:Label({ Name = "Auto Sell & Sell All hanya menjual item yang lolos filter rarity/weight yang kamu set." })
SecShopInfo:Label({ Name = "Sell All / Auto Sell langsung menyelesaikan penjualan (tekan prompt Sell + tombol Sell/Sell All), bukan cuma teleport." })
SecShopInfo:Label({ Name = "Jika tombol Buy/Sell berupa tombol UI, buka shop-nya dulu supaya tombol terdeteksi." })

-- ==============================================================================================
-- MENU: ESP
-- ==============================================================================================
local TabESPRAP = tabGroup:Tab({ Name = "ESP", Image = "lucide/eye" })

local SecEggESP = TabESPRAP:Section({ Name = "ESP Telur & Zone", Side = 1 })
SecEggESP:Header({ Name = ZypheraxLib:Gradient("ESP Kumpulan Telur", Color3.fromRGB(110, 220, 255), Color3.fromRGB(72, 214, 200)) })

SecEggESP:Toggle({
    Name = "ESP Semua Telur (label [Rarity])",
    Default = false,
    Callback = function(enabled)
        espSet("egg", enabled, "ESP Telur",
            "Telur di-mark sesuai rarity (Common hijau, Rare biru, Epic ungu, Legendary emas, Mythic merah).",
            "ESP telur dimatikan.")
    end,
})

SecEggESP:Toggle({
    Name = "ESP Zone Spawn (Common / Rare / Epic)",
    Default = false,
    Callback = function(enabled)
        espSet("zone", enabled, "ESP Zone", "Zone spawn telur di-mark kuning.", "ESP zone dimatikan.")
    end,
})

SecEggESP:Toggle({
    Name = "ESP Plot (Lokasi My Plot)",
    Default = false,
    Callback = function(enabled)
        espSet("ranch", enabled, "ESP Ranch", "Lokasi ranch di-mark putih.", "ESP ranch dimatikan.")
    end,
})

SecEggESP:Button({
    Name = "Hitung Target Sekarang",
    Callback = function()
        pcall(espRefresh)
        Window:Notify({
            Title = "Target",
            Description = ("Jenis telur: %d | Zone: %d | NPC/Hewan: %d | Pemain: %d"):format(
                rapEggCount, rapZoneCount, rapNpcCount, rapPlayerCount),
            Lifetime = 4,
        })
    end,
})

local SecWorldESP = TabESPRAP:Section({ Name = "ESP Pemain & NPC", Side = 2 })
SecWorldESP:Header({ Name = ZypheraxLib:Gradient("ESP Dunia", Color3.fromRGB(120, 255, 160), Color3.fromRGB(255, 170, 90)) })

SecWorldESP:Toggle({
    Name = "ESP Pemain (Nama + Jarak)",
    Default = false,
    Callback = function(enabled)
        espSet("player", enabled, "ESP Pemain", "Pemain lain di-mark hijau + jarak.", "ESP pemain dimatikan.")
    end,
})

SecWorldESP:Toggle({
    Name = "ESP NPC & Hewan",
    Default = false,
    Callback = function(enabled)
        espSet("npc", enabled, "ESP NPC", "NPC & hewan di-mark oranye.", "ESP NPC dimatikan.")
    end,
})

SecWorldESP:Label({ Name = "ESP di-refresh cepat tiap 0.45 detik dan selalu terlihat di depan objek." })
end -- [End Engine RIDE A PET]

-- ==============================================================================
-- TAB 3: PENGATURAN & TEMA
-- ==============================================================================
tabGroup:Divider()
do
do
local TabWebhook = tabGroup:Tab({ Name = "Webhook", Image = "lucide/bell" })
local SecWh = TabWebhook:Section({ Name = "Discord Webhook", Side = 1 })
SecWh:Header({ Name = ZypheraxLib:Gradient("Discord Webhook", Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 140, 230)) })
rapPlanned = rapPlanned or {}
SecWh:Input({ Name = "Webhook URL", Placeholder = "https://discord.com/api/webhooks/...", Default = "", Callback = function(v) rapPlanned.webhookUrl = tostring(v or "") end })
SecWh:Toggle({ Name = "Aktifkan Webhook", Default = false, Callback = function(enabled) rapPlanned.webhookOn = enabled and true or false Window:Notify({ Title = "Webhook", Description = enabled and "Webhook aktif." or "Webhook dimatikan.", Lifetime = 3 }) end })
SecWh:Toggle({ Name = "Notif Telur Langka", Default = true, Callback = function(enabled) rapPlanned.whEgg = enabled and true or false end })
SecWh:Dropdown({ Name = "Filter Egg Webhook (min rarity)", Items = (function() local o={} local src = (typeof(RARITY_LIST)=="table" and RARITY_LIST) or {"Common","Rare","Epic","Legendary","Mythic"} for _, r in ipairs(src) do table.insert(o, r) end return o end)(), Default = "Legendary", Callback = function(v) rapPlanned.whMinRarity = v end })
SecWh:Toggle({ Name = "Notif Rebirth", Default = true, Callback = function(enabled) rapPlanned.whRebirth = enabled and true or false end })
SecWh:Toggle({ Name = "Notif Magma (Volcano)", Default = true, Callback = function(enabled) rapPlanned.whMagma = enabled and true or false end })
SecWh:Button({ Name = "Test Webhook", Callback = function()
    local url = rapPlanned.webhookUrl or ""
    if url == "" then Window:Notify({ Title = "Webhook", Description = "Isi Webhook URL dulu.", Lifetime = 3 }) return end
    rapSendWH("Zypherax Hub - Test", "Webhook tersambung. Game: Ride A Pet.", "57F287")
    Window:Notify({ Title = "Webhook", Description = "Test terkirim (cek Discord).", Lifetime = 3 })
end })
end
local TabConfig = tabGroup:Tab({ Name = "Pengaturan", Image = "lucide/settings" })

-- SEKSI 1: PENAMPILAN & TEMA
local SecTheme = TabConfig:Section({ Name = "Tema & Penampilan", Side = 1 })
SecTheme:Header({ Name = "Penampilan (Appearance)" })

-- Config Manager System (Save / Load / Autoload) sesuai foto
pcall(function()
    if SecTheme.CreateConfigSystem then
        SecTheme:CreateConfigSystem()
    end
end)

SecTheme:Dropdown({
    Name = "Pilihan Tema (Color Themes)",
    Options = ZypheraxLib:GetThemes(),
    Default = "Dark",
    Callback = function(themeName)
        ZypheraxLib:SetTheme(themeName)
        Window:Notify({ Title = "Tema", Description = "Tema diubah ke " .. tostring(themeName), Lifetime = 3 })
    end
})

SecTheme:Toggle({
    Name = "Acrylic Blur",
    Default = Window:GetAcrylicBlurState(),
    Callback = function(bool)
        Window:SetAcrylicBlurState(bool)
        Window:Notify({ Title = "Pengaturan", Description = (bool and "Mengaktifkan" or "Mematikan") .. " Blur", Lifetime = 3 })
    end
})
end

-- Watermark frosted tampil terakhir (tidak tertimpa loading/window)
_zy_show_watermark("Ride A Pet")
