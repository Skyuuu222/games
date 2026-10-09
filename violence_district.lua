-- UNIVERSAL AVATAR & OUTFIT STUDIO HUB (POWERED BY ZYPHERAXUI)
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
-- Menjamin jumlah variabel lokal di main function jauh di bawah batas 200 Lua (LUAI_MAXVARS)

-- Modul 1, 2, 3, 4 (Avatar & Outfit Studio)
local apply_avatar_swap, reset_avatar_swap
local apply_outfit
local add_accessory, remove_accessory, remove_all_accessories, update_accessory_transform
local apply_korblox, remove_korblox, apply_headless, remove_headless

-- Modul 6 (Auto Heal)
local autoHealEnabled = false
local autoheal_start, autoheal_stop, start_auto_heal, stop_auto_heal
HEAL_COOLDOWN = 1.5  -- Global, bisa diubah dari UI slider

-- Modul 7 (Killer Radar)
local killerRadarEnabled = false
local RADAR_RANGE = 350
local killerradar_start, killerradar_stop, check_is_killer, radar_is_killer, is_local_player_killer

-- Modul 8 & 9 (Fullbright & Custom FOV)
local fullbrightEnabled = false
local fullbright_start, fullbright_stop
local customFovEnabled = false
local customFovValue = 70
local fov_start, fov_stop, fov_apply

-- Modul 10 (Infinite Item Charges)
local infiniteChargesEnabled = false
local infinite_charges_start, infinite_charges_stop, infinite_charges_apply, infcharges_start, infcharges_stop

-- Modul 11 (ESP Exit Gate)
local espGateEnabled = false
local start_esp_gate, stop_esp_gate, is_exit_gate_lever, esp_gate_get_part

-- Modul 12 (Auto Escape & Bypass)
local autoEscapeEnabled = false
local start_auto_escape, stop_auto_escape, trigger_instant_escape, teleport_to_lobby

-- Modul 13 (Discord Webhook Notifier)
local webhookUrl = ""
local webhookNotifyEscape = true
local webhookNotifyMatch = true
local send_discord_webhook, start_webhook_live_monitor, stop_webhook_live_monitor, get_player_stats, send_match_summary_webhook

-- Modul Auto Perfect Generator
local autoGenEnabled = false
local agen_start, agen_stop, start_auto_generator, stop_auto_generator

-- Modul 4.5 (Auto Parry)
local autoParryEnabled = false
local autoparry_start, autoparry_stop, start_auto_parry, stop_auto_parry

-- Modul 4.6 (Twist of Fate - Anti Miss)
local tofAntiMissEnabled = false
local tof_start, tof_stop

-- Modul ESP Generator
local espGenEnabled = false
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
do
-- MODUL 1: AVATAR CLONER & SWAP (Client Mirroring)
-- ==============================================================================
shared.AvatarSwapState = shared.AvatarSwapState or { targets = {} }
local SwapState = shared.AvatarSwapState

local function reset_swap_state(st)
    for _, c in ipairs(st.conns or {}) do pcall(function() c:Disconnect() end) end
    st.conns = {}
    if st.model then pcall(function() st.model:Destroy() end) end
    st.model = nil
    for inst, val in pairs(st.original or {}) do
        if inst.Parent then pcall(function() inst.Transparency = val end) end
    end
    st.original = {}
end

local function sanitize_accessory(acc)
    if not acc then return end
    for _, s in ipairs(acc:GetDescendants()) do
        if s:IsA("BaseScript") then pcall(function() s:Destroy() end) end
    end
    for _, d in ipairs(acc:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = false
            d.CanCollide = false
            d.CanTouch = false
            d.CanQuery = false
            d.Massless = true
        end
    end
end

local function cleanup_swap(player)
    local st = SwapState.targets[player]
    if not st then return end
    reset_swap_state(st)
    if st.respawnConn then pcall(function() st.respawnConn:Disconnect() end) end
    SwapState.targets[player] = nil

    local char = player.Character
    if char then
        -- Jika headless masih aktif saat swap dibersihkan, sembunyikan kepala karakter asli kembali
        if shared.HeadlessActive and shared.HeadlessActive[player] then
            local h = char:FindFirstChild("Head")
            if h then
                h.Transparency = 1
                for _, d in ipairs(h:GetChildren()) do
                    if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
                end
            end
        end
        -- Jika korblox masih aktif saat swap dibersihkan, sembunyikan kaki kanan asli kembali
        if shared.KorbloxActive and shared.KorbloxActive[player] then
            local rleg = char:FindFirstChild("Original_Right_Leg") or char:FindFirstChild("Right Leg")
            if rleg and not rleg:GetAttribute("IsKorblox") then rleg.Transparency = 1 end
            for _, c in ipairs(char:GetChildren()) do
                if c:GetAttribute("IsKorblox") or c.Name == "Right Leg Korblox" then c.Transparency = 0 end
            end
        end
    end
end

local function get_user_description(username)
    local userId = LocalPlayer.UserId
    if username and username ~= "" then
        local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, username)
        if not ok or not id then return nil, "Username '" .. tostring(username) .. "' tidak ditemukan!" end
        userId = id
    end
    local ok2, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, userId)
    if not ok2 or not desc then return nil, "Gagal mengambil data avatar dari UserId: " .. tostring(userId) end
    return desc, nil
end

local function dress_mirror(player, char, desc, st, modelPrefix)
    reset_swap_state(st)

    local hum = char:WaitForChild("Humanoid", 10)
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if not hum or not hrp then return false, "Karakter tidak lengkap" end
    task.wait(0.3)

    local ok, model = pcall(function()
        return Players:CreateHumanoidModelFromDescription(desc, hum.RigType)
    end)
    if not ok or not model then return false, "Gagal membuat model: " .. tostring(model) end
    model.Name = (modelPrefix or "Cloned_") .. player.Name

    local mhum = model:FindFirstChildOfClass("Humanoid")
    local mhrp = model:FindFirstChild("HumanoidRootPart")
    if not mhum or not mhrp then
        model:Destroy()
        return false, "Model kloning tidak lengkap"
    end

    local heightDiff = (mhum.HipHeight + mhrp.Size.Y / 2) - (hum.HipHeight + hrp.Size.Y / 2)
    mhum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    mhum.EvaluateStateMachine = false
    pcall(function() mhum:ChangeState(Enum.HumanoidStateType.Physics) end)

    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BaseScript") then d:Destroy() end
        if d:IsA("Motor6D") then d.Enabled = false end
    end

    local mapped = {}
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and not part:GetAttribute("IsKorblox") and part.Name ~= "Right Leg Korblox" and part.Name ~= "Original_Right_Leg" then
            local cp = model:FindFirstChild(part.Name)
            if cp and cp:IsA("BasePart") then
                cp.Anchored = true
                table.insert(mapped, { part, cp })
            end
        end
    end

    local copyParts = {}
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false
            d.CanTouch = false
            d.CanQuery = false
            d.Massless = true
            table.insert(copyParts, d)
        end
    end

    model.Parent = workspace

    -- Jika target sedang pakai Headless, sembunyikan kepala swap model
    if shared.HeadlessActive and shared.HeadlessActive[player] then
        local swapHead = model:FindFirstChild("Head")
        if swapHead then
            swapHead.Transparency = 1
            for _, d in ipairs(swapHead:GetChildren()) do
                if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
            end
        end
    end

    -- Jika target sedang pakai Korblox, sembunyikan Right Leg swap model
    if shared.KorbloxActive and shared.KorbloxActive[player] then
        local swapRLeg = model:FindFirstChild("Right Leg")
        if swapRLeg then
            swapRLeg.Transparency = 1
            for _, d in ipairs(swapRLeg:GetChildren()) do
                if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
            end
        end
    end

    table.insert(st.conns, RunService.Stepped:Connect(function()
        for _, part in ipairs(copyParts) do
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
        end
    end))

    st.accFollowers = {}

    table.insert(st.conns, RunService.RenderStepped:Connect(function()
        if not hrp.Parent then return end
        local root = hrp.CFrame
        local inv = root:Inverse()
        local lift = CFrame.new(0, heightDiff, 0)
        for _, p in ipairs(mapped) do
            p[2].CFrame = root * lift * (inv * p[1].CFrame)
        end
        local swapHead = model:FindFirstChild("Head")
        if swapHead then
            for _, item in ipairs(st.accFollowers or {}) do
                if item.part and item.part.Parent then
                    item.part.CFrame = swapHead.CFrame * item.offset
                end
            end
        end
    end))

    local function hide(d)
        if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart")
            or d:IsA("Decal") or d:IsA("Texture") then
            if d:GetAttribute("IsKorblox") or (d.Parent and d.Parent:GetAttribute("IsKorblox")) then return end
            if d.Name == "Right Leg Korblox" or (d.Parent and d.Parent.Name == "Right Leg Korblox") then return end
            if d.Parent and (d.Parent:IsA("Accessory") and d.Parent:GetAttribute("IsCustomAccessory")) then return end
            if st.original[d] == nil then st.original[d] = d.Transparency end
            d.Transparency = 1
        end
    end
    for _, d in ipairs(char:GetDescendants()) do hide(d) end
    table.insert(st.conns, char.DescendantAdded:Connect(hide))

    -- Pasang Custom Accessories yang aktif sebagai visual puppet (Anchored + CFrame Follower = 100% Anti-Nyangkut)
    if shared.CustomAccessories and shared.CustomAccessories[player] then
        local swapHead = model:FindFirstChild("Head")
        for _, cId in ipairs(shared.CustomAccessories[player]) do
            task.spawn(function()
                pcall(function()
                    local okLoad, objects = pcall(function() return game:GetObjects("rbxassetid://" .. cId) end)
                    if okLoad and objects and #objects > 0 then
                        local modelAcc = objects[1]
                        local acc = modelAcc:IsA("Accessory") and modelAcc or modelAcc:FindFirstChildOfClass("Accessory")
                        local handle = acc and acc:FindFirstChild("Handle")
                        if handle and model.Parent and swapHead then
                            local dummy = handle:Clone()
                            for _, desc in ipairs(dummy:GetDescendants()) do
                                if desc:IsA("BaseScript") or desc:IsA("JointInstance") then desc:Destroy() end
                            end
                            dummy.Name = "CustomAccPart_" .. cId
                            dummy:SetAttribute("CustomAssetId", cId)
                            dummy:SetAttribute("IsCustomAccessory", true)
                            dummy.Anchored = true
                            dummy.CanCollide = false
                            dummy.CanTouch = false
                            dummy.CanQuery = false
                            dummy.Massless = true
                            dummy.Transparency = 0
                            dummy.Parent = model

                            local sAttachment = dummy:FindFirstChildOfClass("Attachment")
                            local sHeadAttachment = swapHead:FindFirstChild(sAttachment and sAttachment.Name or "") or swapHead:FindFirstChild("HatAttachment")
                            local offset = (sHeadAttachment and sHeadAttachment.CFrame or CFrame.new(0, 0.5, 0)) * (sAttachment and sAttachment.CFrame:Inverse() or CFrame.new())
                            dummy.CFrame = swapHead.CFrame * offset
                            table.insert(st.accFollowers, { part = dummy, offset = offset, id = cId })
                        end
                    end
                end)
            end)
        end
    end

    st.model = model
    return true, "Avatar berhasil dipasang pada " .. player.Name
end

function apply_avatar_swap(targetName, avatarUsername)
    local target = find_player(targetName)
    if not target then return false, "Pemain '" .. tostring(targetName) .. "' tidak ditemukan di server!" end

    local desc, err = get_user_description(avatarUsername)
    if not desc then return false, err end

    cleanup_swap(target)
    local st = { conns = {}, original = {} }
    SwapState.targets[target] = st

    if target.Character then
        task.spawn(dress_mirror, target, target.Character, desc, st, "Swap_")
    end
    st.respawnConn = target.CharacterAdded:Connect(function(newChar)
        task.wait(1)
        dress_mirror(target, newChar, desc, st, "Swap_")
    end)
    return true, "Avatar '" .. avatarUsername .. "' dipasang ke " .. target.Name
end

function reset_avatar_swap(targetName)
    if not targetName or targetName == "" then
        for p in pairs(SwapState.targets) do cleanup_swap(p) end
        return true, "Semua avatar pemain dikembalikan normal."
    else
        local target = find_player(targetName)
        if target then
            cleanup_swap(target)
            return true, "Avatar " .. target.Name .. " dikembalikan normal."
        end
        return false, "Target tidak ditemukan."
    end
end

-- ==============================================================================
-- MODUL 2: OUTFIT CLONER
-- ==============================================================================
local ACC_TYPES = {
    [8] = Enum.AccessoryType.Hat, [41] = Enum.AccessoryType.Hair,
    [42] = Enum.AccessoryType.Face, [43] = Enum.AccessoryType.Neck,
    [44] = Enum.AccessoryType.Shoulder, [45] = Enum.AccessoryType.Front,
    [46] = Enum.AccessoryType.Back, [47] = Enum.AccessoryType.Waist,
    [64] = Enum.AccessoryType.TShirt, [65] = Enum.AccessoryType.Shirt,
    [66] = Enum.AccessoryType.Pants, [67] = Enum.AccessoryType.Jacket,
    [68] = Enum.AccessoryType.Sweater, [69] = Enum.AccessoryType.Shorts,
    [70] = Enum.AccessoryType.LeftShoe, [71] = Enum.AccessoryType.RightShoe,
    [72] = Enum.AccessoryType.DressSkirt,
    [76] = Enum.AccessoryType.Eyebrow, [77] = Enum.AccessoryType.Eyelash,
}
local LAYERED = {
    [64]=true,[65]=true,[66]=true,[67]=true,[68]=true,[69]=true,
    [70]=true,[71]=true,[72]=true,
}
local BODY_IDS = {
    [17] = "Head", [79] = "Head", [27] = "Torso", [28] = "RightArm",
    [29] = "LeftArm", [30] = "LeftLeg", [31] = "RightLeg",
    [18] = "Face", [11] = "Shirt", [12] = "Pants", [2] = "GraphicTShirt",
}

local function fetch_outfits(userId)
    local all, seen = {}, {}
    for _, extra in ipairs({ "", "&isEditable=true" }) do
        for page = 1, 30 do
            local url = ("https://avatar.roblox.com/v1/users/%d/outfits?itemsPerPage=50&page=%d%s"):format(userId, page, extra)
            local data = http_json(url)
            if not data or not data.data or #data.data == 0 then break end
            for _, o in ipairs(data.data) do
                if not seen[o.id] then
                    seen[o.id] = true
                    table.insert(all, o)
                end
            end
            if #data.data < 50 then break end
        end
    end
    return all
end

local function merge_details(desc, det)
    if det.scale then
        pcall(function()
            desc.HeightScale = det.scale.height or desc.HeightScale
            desc.WidthScale = det.scale.width or desc.WidthScale
            desc.HeadScale = det.scale.head or desc.HeadScale
            desc.DepthScale = det.scale.depth or desc.DepthScale
            desc.ProportionScale = det.scale.proportion or desc.ProportionScale
            desc.BodyTypeScale = det.scale.bodyType or desc.BodyTypeScale
        end)
    end

    local bc = det.bodyColor3s
    if bc then
        pcall(function()
            desc.HeadColor = hex_to_color(bc.headColor3) or desc.HeadColor
            desc.TorsoColor = hex_to_color(bc.torsoColor3) or desc.TorsoColor
            desc.LeftArmColor = hex_to_color(bc.leftArmColor3) or desc.LeftArmColor
            desc.RightArmColor = hex_to_color(bc.rightArmColor3) or desc.RightArmColor
            desc.LeftLegColor = hex_to_color(bc.leftLegColor3) or desc.LeftLegColor
            desc.RightLegColor = hex_to_color(bc.rightLegColor3) or desc.RightLegColor
        end)
    end

    local list, have = {}, {}
    local okG, cur = pcall(function() return desc:GetAccessories(true) end)
    if okG and cur then
        for _, a in ipairs(cur) do
            have[a.AssetId] = true
            table.insert(list, a)
        end
    end

    for _, a in ipairs(det.assets or {}) do
        local tid = a.assetType and a.assetType.id
        local aid = a.id
        if BODY_IDS[tid] then
            local key = BODY_IDS[tid]
            pcall(function() if desc[key] == 0 then desc[key] = aid end end)
        elseif ACC_TYPES[tid] and not have[aid] then
            have[aid] = true
            table.insert(list, {
                AssetId = aid,
                AccessoryType = ACC_TYPES[tid],
                IsLayered = LAYERED[tid] or false,
                Order = (a.meta and a.meta.order) or (#list + 1),
                Puffiness = (a.meta and a.meta.puffiness) or 1,
            })
        end
    end
    pcall(function() desc:SetAccessories(list, true) end)
end

local function get_outfit_desc(username, outfitNameOrId)
    local outfitId = tonumber(outfitNameOrId)
    local outfitName = tostring(outfitNameOrId)

    if not outfitId then
        local userId = retry(3, 1, function() return Players:GetUserIdFromNameAsync(username) end)
        if not userId then return nil, "User '" .. username .. "' tidak ditemukan" end

        local outfits = fetch_outfits(userId)
        if #outfits == 0 then return nil, "Tidak ada outfit terbaca (profil privat)" end

        local n = normalize(outfitName)
        for _, o in ipairs(outfits) do
            if normalize(o.name) == n or normalize(o.name):find(n, 1, true) then
                outfitId = o.id
                outfitName = o.name
                break
            end
        end
        if not outfitId then return nil, "Outfit '" .. outfitName .. "' tidak ditemukan" end
    end

    local desc = retry(3, 1, function() return Players:GetHumanoidDescriptionFromOutfitId(outfitId) end)
    if not desc then desc = Instance.new("HumanoidDescription") end

    local det = http_json("https://avatar.roblox.com/v1/outfits/" .. outfitId .. "/details")
    if det then merge_details(desc, det) end
    return desc, outfitName
end

function apply_outfit(username, outfitQuery, targetName)
    local target = find_player(targetName)
    if not target then return false, "Target tidak ditemukan di server" end

    local desc, outName = get_outfit_desc(username, outfitQuery)
    if not desc then return false, outName end

    cleanup_swap(target)
    local st = { conns = {}, original = {} }
    SwapState.targets[target] = st

    if target.Character then
        task.spawn(dress_mirror, target, target.Character, desc, st, "Outfit_")
    end
    st.respawnConn = target.CharacterAdded:Connect(function(newChar)
        task.wait(1)
        dress_mirror(target, newChar, desc, st, "Outfit_")
    end)
    return true, "Outfit '" .. tostring(outName) .. "' dipasang pada " .. target.Name
end

-- ==============================================================================
-- MODUL 3: ACCESSORY LOADER
-- ==============================================================================
-- ==============================================================================
-- MODUL 3: ACCESSORY LOADER & REMOVER
-- ==============================================================================
shared.CustomAccessories = shared.CustomAccessories or {}

local function apply_acc_scale(part, scale)
    if not part or not scale or scale == 1 then return end
    local mesh = part:FindFirstChildOfClass("SpecialMesh")
    if mesh then
        if not mesh:GetAttribute("OrigScale") then
            mesh:SetAttribute("OrigScale", mesh.Scale)
        end
        mesh.Scale = mesh:GetAttribute("OrigScale") * scale
    elseif part:IsA("MeshPart") or part:IsA("BasePart") then
        if not part:GetAttribute("OrigSize") then
            part:SetAttribute("OrigSize", part.Size)
        end
        part.Size = part:GetAttribute("OrigSize") * scale
    end
end

function add_accessory(targetName, assetId, offX, offY, offZ, scaleVal)
    local target = find_player(targetName)
    if not target then return false, "Pemain tidak ditemukan" end

    local char = target.Character
    if not char then return false, "Karakter tidak ada" end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local head = char:FindFirstChild("Head")
    if not hum or not head then return false, "Humanoid/Head tidak ada" end

    local cleanId = tostring(assetId):match("%d+")
    if not cleanId then return false, "Asset ID tidak valid" end

    offX = tonumber(offX) or 0
    offY = tonumber(offY) or 0
    offZ = tonumber(offZ) or 0
    scaleVal = tonumber(scaleVal) or 1
    if scaleVal <= 0 then scaleVal = 1 end

    local userOffset = CFrame.new(offX, offY, -offZ)

    local okLoad, objects = pcall(function()
        return game:GetObjects("rbxassetid://" .. cleanId)
    end)
    if not okLoad or not objects or #objects == 0 then
        return false, "Gagal memuat aset aksesoris"
    end

    local model = objects[1]
    local accessory = model:IsA("Accessory") and model or model:FindFirstChildOfClass("Accessory")
    if not accessory then return false, "Bukan objek Accessory" end

    -- Bersihkan skrip & sifat fisik agar tidak nyangkut saat jalan
    sanitize_accessory(accessory)

    accessory:SetAttribute("CustomAssetId", cleanId)
    accessory:SetAttribute("IsCustomAccessory", true)

    local handle = accessory:FindFirstChild("Handle")
    local accAttachment = handle and handle:FindFirstChildOfClass("Attachment")
    if not handle or not accAttachment then return false, "Struktur Handle/Attachment rusak" end

    -- Terapkan scale ukuran
    apply_acc_scale(handle, scaleVal)

    -- Pasang ke karakter asli
    local headAttachment = head:FindFirstChild(accAttachment.Name) or head:FindFirstChild("HatAttachment")
    -- Cek apakah target sedang memakai copy avatar (avatar swap)
    local swapSt = SwapState.targets[target]
    if swapSt and swapSt.model then
        -- SWAP MODEL: Gunakan CFrame follower dummy (Anchored, 0 Weld, 100% Anti-Nyangkut)
        local swapHead = swapSt.model:FindFirstChild("Head")
        if swapHead then
            swapSt.accFollowers = swapSt.accFollowers or {}
            local dummy = handle:Clone()
            for _, desc in ipairs(dummy:GetDescendants()) do
                if desc:IsA("BaseScript") or desc:IsA("JointInstance") then desc:Destroy() end
            end
            dummy.Name = "CustomAccPart_" .. cleanId
            dummy:SetAttribute("CustomAssetId", cleanId)
            dummy:SetAttribute("IsCustomAccessory", true)
            dummy.Anchored = true
            dummy.CanCollide = false
            dummy.CanTouch = false
            dummy.CanQuery = false
            dummy.Massless = true
            dummy.Transparency = 0
            dummy.Parent = swapSt.model

            apply_acc_scale(dummy, scaleVal)

            local sAttachment = dummy:FindFirstChildOfClass("Attachment")
            local sHeadAttachment = swapHead:FindFirstChild(sAttachment and sAttachment.Name or "") or swapHead:FindFirstChild("HatAttachment")
            local baseOffset = (sHeadAttachment and sHeadAttachment.CFrame or CFrame.new(0, 0.5, 0)) * (sAttachment and sAttachment.CFrame:Inverse() or CFrame.new())
            local offset = baseOffset * userOffset
            dummy.CFrame = swapHead.CFrame * offset
            table.insert(swapSt.accFollowers, {
                part = dummy,
                offset = offset,
                id = cleanId,
                offX = offX,
                offY = offY,
                offZ = offZ,
                scale = scaleVal
            })
        end
    else
        -- AVATAR BIASA (tidak sedang swap): Pasang ke karakter fisik biasa
        local headAttachment = head:FindFirstChild(accAttachment.Name) or head:FindFirstChild("HatAttachment")
        accessory.Name = "CustomAcc_" .. cleanId
        accessory.Parent = char

        local weld = Instance.new("Weld")
        weld.Name = "AccessoryWeld"
        weld.Part0 = head
        weld.Part1 = handle
        local baseC0 = headAttachment and headAttachment.CFrame or CFrame.new(0, 0.5, 0)
        weld.C0 = baseC0 * userOffset
        weld.C1 = accAttachment.CFrame
        weld.Parent = handle

        sanitize_accessory(accessory)
    end

    -- Simpan riwayat aksesoris untuk target ini
    shared.CustomAccessories[target] = shared.CustomAccessories[target] or {}
    local alreadyListed = false
    for _, id in ipairs(shared.CustomAccessories[target]) do
        if id == cleanId then alreadyListed = true; break end
    end
    if not alreadyListed then
        table.insert(shared.CustomAccessories[target], cleanId)
    end

    return true, "Aksesoris ID " .. cleanId .. " dipasang ke " .. target.Name
end

function update_accessory_transform(targetName, assetId, offX, offY, offZ, scaleVal)
    local target = find_player(targetName)
    if not target then return false, "Pemain tidak ditemukan" end

    offX = tonumber(offX) or 0
    offY = tonumber(offY) or 0
    offZ = tonumber(offZ) or 0
    scaleVal = tonumber(scaleVal) or 1
    if scaleVal <= 0 then scaleVal = 1 end

    local userOffset = CFrame.new(offX, offY, -offZ)
    local cleanId = assetId and tostring(assetId):match("%d+")
    local updatedCount = 0

    -- 1. Karakter fisik asli
    local char = target.Character
    if char then
        local head = char:FindFirstChild("Head")
        for _, obj in ipairs(char:GetChildren()) do
            if obj:IsA("Accessory") and (not cleanId or obj.Name:find(cleanId) or obj:GetAttribute("CustomAssetId") == cleanId) then
                local handle = obj:FindFirstChild("Handle")
                if handle then
                    apply_acc_scale(handle, scaleVal)
                    local weld = handle:FindFirstChild("AccessoryWeld")
                    local accAttachment = handle:FindFirstChildOfClass("Attachment")
                    if weld and head then
                        local headAttachment = accAttachment and head:FindFirstChild(accAttachment.Name) or head:FindFirstChild("HatAttachment")
                        local baseC0 = headAttachment and headAttachment.CFrame or CFrame.new(0, 0.5, 0)
                        weld.C0 = baseC0 * userOffset
                        updatedCount = updatedCount + 1
                    end
                end
            end
        end
    end

    -- 2. Model Swap (Copy Avatar)
    local swapSt = SwapState.targets[target]
    if swapSt and swapSt.model then
        local swapHead = swapSt.model:FindFirstChild("Head")
        if swapHead and swapSt.accFollowers then
            for _, item in ipairs(swapSt.accFollowers) do
                if not cleanId or item.id == cleanId then
                    if item.part and item.part.Parent then
                        apply_acc_scale(item.part, scaleVal)
                        local sAttachment = item.part:FindFirstChildOfClass("Attachment")
                        local sHeadAttachment = swapHead:FindFirstChild(sAttachment and sAttachment.Name or "") or swapHead:FindFirstChild("HatAttachment")
                        local baseOffset = (sHeadAttachment and sHeadAttachment.CFrame or CFrame.new(0, 0.5, 0)) * (sAttachment and sAttachment.CFrame:Inverse() or CFrame.new())
                        item.offset = baseOffset * userOffset
                        item.part.CFrame = swapHead.CFrame * item.offset
                        updatedCount = updatedCount + 1
                    end
                end
            end
        end
    end

    if updatedCount > 0 then
        return true, "Posisi & ukuran " .. updatedCount .. " aksesoris berhasil diperbarui!"
    else
        return false, "Aksesoris belum terpasang. Klik 'Pasang Aksesoris' terlebih dahulu."
    end
end

function remove_accessory(targetName, assetId)
    local target = find_player(targetName)
    if not target then return false, "Pemain tidak ditemukan" end

    local cleanId = assetId and tostring(assetId):match("%d+")
    local searchPattern = assetId and tostring(assetId):lower():gsub("%s+", "") or ""

    local removedCount = 0

    local function checkAndRemove(acc)
        if not acc or not acc:IsA("Accessory") then return false end
        local matched = false

        -- 1. Cek Attribute CustomAssetId
        local customId = acc:GetAttribute("CustomAssetId")
        if cleanId and customId and tostring(customId) == cleanId then
            matched = true
        end

        -- 2. Cek Nama Accessory (mengandung ID atau kata kunci)
        if not matched and cleanId and acc.Name:find(cleanId) then
            matched = true
        end
        if not matched and searchPattern ~= "" and acc.Name:lower():find(searchPattern) then
            matched = true
        end

        -- 3. Cek MeshId / TextureId di Handle
        if not matched and cleanId then
            local handle = acc:FindFirstChild("Handle")
            if handle then
                for _, desc in ipairs(handle:GetDescendants()) do
                    if desc:IsA("SpecialMesh") then
                        if tostring(desc.MeshId):find(cleanId) or tostring(desc.TextureId):find(cleanId) then
                            matched = true
                            break
                        end
                    elseif desc:IsA("MeshPart") then
                        if tostring(desc.MeshId):find(cleanId) or tostring(desc.TextureID):find(cleanId) then
                            matched = true
                            break
                        end
                    end
                end
            end
        end

        if matched then
            acc:Destroy()
            removedCount = removedCount + 1
            return true
        end
        return false
    end

    -- Hapus dari karakter asli (bisa ava diri sendiri atau ava target di server)
    local char = target.Character
    if char then
        for _, obj in ipairs(char:GetChildren()) do
            checkAndRemove(obj)
        end
    end

    -- Hapus dari model swap (jika sedang pakai copy avatar)
    local swapSt = SwapState.targets[target]
    if swapSt and swapSt.model then
        for _, obj in ipairs(swapSt.model:GetChildren()) do
            if obj.Name == "CustomAccPart_" .. (cleanId or "") or obj:GetAttribute("CustomAssetId") == cleanId then
                obj:Destroy()
                removedCount = removedCount + 1
            else
                checkAndRemove(obj)
            end
        end
        if swapSt.accFollowers then
            for i = #swapSt.accFollowers, 1, -1 do
                if not cleanId or swapSt.accFollowers[i].id == cleanId or not swapSt.accFollowers[i].part.Parent then
                    table.remove(swapSt.accFollowers, i)
                end
            end
        end
    end

    -- Bersihkan dari daftar shared.CustomAccessories
    if shared.CustomAccessories and shared.CustomAccessories[target] and cleanId then
        for i = #shared.CustomAccessories[target], 1, -1 do
            if shared.CustomAccessories[target][i] == cleanId then
                table.remove(shared.CustomAccessories[target], i)
            end
        end
    end

    if removedCount > 0 then
        return true, "Berhasil menghapus " .. removedCount .. " aksesoris dari " .. target.Name
    else
        return false, "Aksesoris tidak ditemukan pada " .. target.Name
    end
end

function remove_all_accessories(targetName)
    local target = find_player(targetName)
    if not target then return false, "Pemain tidak ditemukan" end

    local removedCount = 0

    local function removeAccs(container)
        if not container then return end
        for _, obj in ipairs(container:GetChildren()) do
            if obj:IsA("Accessory") then
                if obj:GetAttribute("IsCustomAccessory") or obj.Name:find("CustomAcc_") then
                    obj:Destroy()
                    removedCount = removedCount + 1
                end
            end
        end
    end

    if target.Character then removeAccs(target.Character) end
    local swapSt = SwapState.targets[target]
    if swapSt and swapSt.model then
        removeAccs(swapSt.model)
        for _, obj in ipairs(swapSt.model:GetChildren()) do
            if obj.Name:find("CustomAccPart_") or obj:GetAttribute("IsCustomAccessory") then
                obj:Destroy()
                removedCount = removedCount + 1
            end
        end
        swapSt.accFollowers = {}
    end

    if shared.CustomAccessories then
        shared.CustomAccessories[target] = nil
    end

    if removedCount > 0 then
        return true, "Berhasil menghapus " .. removedCount .. " aksesoris custom dari " .. target.Name
    else
        return false, "Tidak ada aksesoris custom yang terpasang pada " .. target.Name
    end
end

-- ==============================================================================
-- MODUL 4: KORBLOX & HEADLESS MODIFICATIONS
-- ==============================================================================
shared.KorbloxConns = shared.KorbloxConns or {}
shared.KorbloxActive = shared.KorbloxActive or {}
shared.HeadlessActive = shared.HeadlessActive or {}
shared.HeadlessConns = shared.HeadlessConns or {}
shared.HeadlessHBConns = shared.HeadlessHBConns or {}

function remove_korblox(targetName)
    local target = find_player(targetName)
    if not target then return false, "Pemain tidak ditemukan" end

    shared.KorbloxActive[target] = nil

    if shared.KorbloxConns[target] then
        for _, c in ipairs(shared.KorbloxConns[target]) do
            pcall(function() c:Disconnect() end)
        end
        shared.KorbloxConns[target] = nil
    end

    local char = target.Character
    if char then
        local torso = char:FindFirstChild("Torso")
        local oldLimb = char:FindFirstChild("Original_Right_Leg") or char:FindFirstChild("Right Leg")

        -- 1. Hapus part Korblox (part yang ber-attribute IsKorblox atau bernama Right Leg Korblox)
        for _, child in ipairs(char:GetChildren()) do
            if child:GetAttribute("IsKorblox") or child.Name == "Right Leg Korblox" or (child ~= oldLimb and child.Name == "Right Leg" and child:IsA("BasePart")) then
                child:Destroy()
            end
        end

        if torso then
            -- Hapus Motor6D yang kita buat untuk Korblox
            for _, j in ipairs(torso:GetChildren()) do
                if j:IsA("Motor6D") and (j.Name == "Right Hip" and (j.Part1 == nil or j.Part1:GetAttribute("IsKorblox") or (oldLimb and j.Part1 ~= oldLimb))) then
                    j:Destroy()
                end
            end
            -- Kembalikan joint asli
            local origJoint = torso:FindFirstChild("Right Hip Original") or torso:FindFirstChild("Right Hip")
            if origJoint and oldLimb then
                origJoint.Name = "Right Hip"
                origJoint.Part1 = oldLimb
            end
        end

        -- 2. Kembalikan nama kaki lama menjadi "Right Leg"
        if oldLimb then
            oldLimb.Name = "Right Leg"
        end

        -- 3. Atur kembali transparansi kaki
        local isSwapped = SwapState.targets[target] and SwapState.targets[target].model
        if isSwapped then
            -- Karakter asli tetap invisible karena sedang pakai avatar swap
            if oldLimb then oldLimb.Transparency = 1 end
            -- Munculkan kembali kaki kanan di model swap
            local swapRLeg = SwapState.targets[target].model:FindFirstChild("Right Leg")
            if swapRLeg then
                swapRLeg.Transparency = 0
                for _, d in ipairs(swapRLeg:GetChildren()) do
                    if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 0 end
                end
            end
        else
            -- Tidak sedang swap: kembalikan kaki asli ke terlihat normal
            if oldLimb then
                oldLimb.Transparency = 0
            end
        end
    end

    return true, "Korblox dinonaktifkan untuk " .. target.Name
end

function apply_korblox(targetName, assetId, yOffset)
    local target = find_player(targetName)
    if not target then return false, "Pemain tidak ditemukan" end
    local char = target.Character
    if not char then return false, "Karakter belum spawn" end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.RigType ~= Enum.HumanoidRigType.R6 then
        return false, "Target bukan tipe avatar R6!"
    end

    local torso = char:FindFirstChild("Torso")
    local oldLimb = char:FindFirstChild("Right Leg")
    if not torso or not oldLimb then return false, "Torso / Right Leg tidak ditemukan" end

    -- Jika Korblox sudah terpasang, hapus dulu agar bersih
    if shared.KorbloxActive[target] or char:FindFirstChild("Original_Right_Leg") or torso:FindFirstChild("Right Hip Original") then
        remove_korblox(targetName)
        task.wait(0.05)
        oldLimb = char:FindFirstChild("Right Leg")
        torso = char:FindFirstChild("Torso")
        if not torso or not oldLimb then return false, "Gagal mereset kaki sebelum pasang" end
    end

    local originalJoint = torso:FindFirstChild("Right Hip")
    if not originalJoint then return false, "Joint 'Right Hip' tidak ditemukan" end

    local cleanId = tostring(assetId or "139607718"):match("%d+")
    local offsetVal = tonumber(yOffset) or 0.7
    local okLoad, objects = pcall(function()
        return game:GetObjects("rbxassetid://" .. cleanId)
    end)
    if not okLoad or not objects or #objects == 0 then
        return false, "Gagal memuat objek Korblox"
    end

    local newLimb = objects[1]
    if not newLimb:IsA("BasePart") then
        newLimb = newLimb:FindFirstChildWhichIsA("MeshPart") or newLimb:FindFirstChildWhichIsA("BasePart")
    end
    if not newLimb then return false, "Part kaki tidak ditemukan" end

    -- Bersihkan script di newLimb
    for _, s in ipairs(newLimb:GetDescendants()) do
        if s:IsA("BaseScript") then s:Destroy() end
    end

    local originalC0 = originalJoint.C0
    local originalC1 = originalJoint.C1

    -- Sembunyikan kaki lama & rename agar tidak bentrok nama
    oldLimb.Name = "Original_Right_Leg"
    oldLimb.Transparency = 1
    oldLimb.CanCollide = false

    -- Beri nama "Right Leg" pada newLimb agar Animator R6 Roblox menganimasikannya!
    -- Hitung posisi kaki tegak lurus (rest pose) dari Torso agar kaki Korblox tidak miring/maju ke depan saat berjalan
    local restLimbCF = torso.CFrame * originalC0 * originalC1:Inverse()
    newLimb.CFrame = restLimbCF * CFrame.new(0, offsetVal, 0)
    newLimb.Anchored = false
    newLimb.CanCollide = false
    newLimb.Massless = true
    newLimb.Transparency = 0
    newLimb:SetAttribute("IsKorblox", true)
    newLimb.Name = "Right Leg"
    newLimb.Parent = char

    -- Putuskan Part1 joint asli dan rename agar bisa di-undo
    originalJoint.Name = "Right Hip Original"
    originalJoint.Part1 = nil

    -- Buat Motor6D baru dengan C0 asli dan C1 dihitung dari posisi newLimb rest pose
    local weld = Instance.new("Motor6D")
    weld.Name = "Right Hip"
    weld.Part0 = torso
    weld.Part1 = newLimb
    weld.C0 = originalC0
    weld.C1 = newLimb.CFrame:ToObjectSpace(torso.CFrame * originalC0)
    weld.Parent = torso

    -- Sembunyikan kaki kanan di model swap jika sedang aktif
    local swapSt = SwapState.targets[target]
    if swapSt and swapSt.model then
        local swapRLeg = swapSt.model:FindFirstChild("Right Leg")
        if swapRLeg then
            swapRLeg.Transparency = 1
            for _, d in ipairs(swapRLeg:GetChildren()) do
                if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
            end
        end
    end

    -- Simpan state Korblox
    shared.KorbloxActive[target] = {
        assetId = cleanId,
        yOffset = offsetVal,
    }

    if shared.KorbloxConns[target] then
        for _, c in ipairs(shared.KorbloxConns[target]) do
            pcall(function() c:Disconnect() end)
        end
    end
    shared.KorbloxConns[target] = {}

    -- Heartbeat loop: menjaga newLimb selalu terlihat & swap model Right Leg selalu tersembunyi
    local hbConn = RunService.Heartbeat:Connect(function()
        if not newLimb or not newLimb.Parent then return end
        if newLimb.Transparency ~= 0 then
            newLimb.Transparency = 0
        end
        local currentSwap = SwapState.targets[target]
        if currentSwap and currentSwap.model then
            local sRLeg = currentSwap.model:FindFirstChild("Right Leg")
            if sRLeg and sRLeg.Transparency ~= 1 then
                sRLeg.Transparency = 1
            end
        end
    end)
    table.insert(shared.KorbloxConns[target], hbConn)

    -- Pasang ulang otomatis jika target respawn
    local respawnConn = target.CharacterAdded:Connect(function()
        task.wait(1)
        if shared.KorbloxActive[target] then
            apply_korblox(target.Name, cleanId, offsetVal)
        end
    end)
    table.insert(shared.KorbloxConns[target], respawnConn)

    return true, "Korblox Right Leg dipasang pada " .. target.Name
end

local function make_headless_char(char)
    local head = char:FindFirstChild("Head")
    if head then
        head.Transparency = 1
        for _, d in ipairs(head:GetChildren()) do
            if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
        end
    end
end

-- Sembunyikan HANYA kepala di swap model (aksesori kepala tetap utuh)
local function make_headless_swap(target)
    local swapSt = SwapState.targets[target]
    if not swapSt or not swapSt.model then return end
    local swapHead = swapSt.model:FindFirstChild("Head")
    if swapHead then
        swapHead.Transparency = 1
        for _, d in ipairs(swapHead:GetChildren()) do
            if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
        end
    end
end

function apply_headless(targetName)
    local target = find_player(targetName)
    if not target then return false, "Target tidak ditemukan" end

    shared.HeadlessActive[target] = true

    -- Disconnect semua koneksi headless lama
    if shared.HeadlessConns[target] then
        shared.HeadlessConns[target]:Disconnect()
        shared.HeadlessConns[target] = nil
    end
    if shared.HeadlessHBConns[target] then
        shared.HeadlessHBConns[target]:Disconnect()
        shared.HeadlessHBConns[target] = nil
    end

    local function setup(char)
        make_headless_char(char)
        make_headless_swap(target)

        if shared.HeadlessHBConns[target] then
            shared.HeadlessHBConns[target]:Disconnect()
        end

        local hbConn
        hbConn = RunService.Heartbeat:Connect(function()
            if not char or not char.Parent then
                hbConn:Disconnect()
                shared.HeadlessHBConns[target] = nil
                return
            end
            -- Jaga kepala karakter tetap invisible
            local h = char:FindFirstChild("Head")
            if h and h.Transparency ~= 1 then make_headless_char(char) end
            -- Jaga kepala model swap tetap invisible
            make_headless_swap(target)
        end)
        shared.HeadlessHBConns[target] = hbConn
    end

    if target.Character then setup(target.Character) end
    shared.HeadlessConns[target] = target.CharacterAdded:Connect(function(newChar)
        task.wait(0.5)
        if shared.HeadlessActive[target] then
            setup(newChar)
        end
    end)

    return true, "Headless diterapkan pada " .. target.Name
end

function remove_headless(targetName)
    local target = find_player(targetName)
    if not target then return false, "Target tidak ditemukan" end

    shared.HeadlessActive[target] = nil

    -- Disconnect CharacterAdded listener
    if shared.HeadlessConns[target] then
        shared.HeadlessConns[target]:Disconnect()
        shared.HeadlessConns[target] = nil
    end
    -- Disconnect Heartbeat listener
    if shared.HeadlessHBConns[target] then
        shared.HeadlessHBConns[target]:Disconnect()
        shared.HeadlessHBConns[target] = nil
    end

    local char = target.Character
    local swapSt = SwapState.targets[target]
    local isSwapped = swapSt and swapSt.model

    if isSwapped then
        -- KETIKA SEDANG PAKAI AVATAR SWAP:
        -- Kepala karakter asli HARUS TETAP invisible (1) agar tidak menabrak / z-fight dengan avatar swap!
        if char and char:FindFirstChild("Head") then
            char.Head.Transparency = 1
            for _, d in ipairs(char.Head:GetChildren()) do
                if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
            end
        end

        -- HANYA kembalikan kepala di swap model avatar yang sedang dicopy:
        local swapHead = swapSt.model:FindFirstChild("Head")
        if swapHead then
            swapHead.Transparency = 0
            for _, d in ipairs(swapHead:GetChildren()) do
                if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 0 end
            end
        end
    else
        -- KETIKA TIDAK SEDANG SWAP (pakai avatar sendiri):
        if char and char:FindFirstChild("Head") then
            local head = char.Head
            head.Transparency = 0
            for _, d in ipairs(head:GetChildren()) do
                if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 0 end
            end
        end
    end

    return true, "Headless dinonaktifkan untuk " .. target.Name
end







end

-- ==============================================================================
do
-- MODUL 6: AUTO HEAL
-- ==============================================================================
autoHealEnabled = false
local autoHealConn = nil
local autoHealCooldown = 0
HEAL_COOLDOWN = 1.5  -- detik antara heal (global agar bisa diubah dari UI)

function autoheal_start()
    if autoHealConn then return end
    autoHealConn = RunService.Heartbeat:Connect(function(dt)
        if not autoHealEnabled then return end
        if is_local_player_killer and is_local_player_killer() then return end
        autoHealCooldown = autoHealCooldown - dt
        if autoHealCooldown > 0 then return end
        pcall(function()
            local char = LocalPlayer.Character
            if not char then return end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum then return end
            -- Hanya heal jika HP berkurang
            if hum.Health >= hum.MaxHealth then return end
            autoHealCooldown = HEAL_COOLDOWN
            -- Metode 1: Tembak remote heal jika ada
            local remotes = ReplicatedStorage:FindFirstChild("Remotes")
            if remotes then
                local healRemote = remotes:FindFirstChild("Heal")
                    or remotes:FindFirstChild("heal")
                    or remotes:FindFirstChild("HealPlayer")
                if healRemote and healRemote:IsA("RemoteEvent") then
                    pcall(function() healRemote:FireServer() end)
                end
            end
            -- Metode 2: Langsung set HP (client-side display)
            pcall(function() hum.Health = hum.MaxHealth end)
            -- Metode 3: Cari tool obat di karakter
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") then
                    local toolName = tool.Name:lower()
                    if toolName:find("medkit") or toolName:find("heal") or toolName:find("bandage") 
                        or toolName:find("kit") or toolName:find("aid") then
                        -- Aktifkan tool secara otomatis
                        pcall(function()
                            local ts = tool:FindFirstChild("Tool Script") or tool:FindFirstChild("LocalScript")
                            if ts then return end
                            tool:Activate()
                        end)
                        break
                    end
                end
            end
        end)
    end)
end

function autoheal_stop()
    if autoHealConn then
        autoHealConn:Disconnect()
        autoHealConn = nil
    end
    autoHealCooldown = 0
end


end

-- ==============================================================================
do
-- MODUL 7: KILLER RADAR (HUD Mini-Map)
-- ==============================================================================
killerRadarEnabled = false
local killerRadarGui = nil
local killerRadarConn = nil
local RADAR_SIZE = 168

local function radar_create_gui()
    if killerRadarGui then pcall(function() killerRadarGui:Destroy() end) end
    local sg = Instance.new("ScreenGui")
    sg.Name = "ZypheraxHubKillerRadar"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 999
    sg.Enabled = true
    local parented = false
    pcall(function()
        if gethui then
            sg.Parent = gethui()
            parented = sg.Parent ~= nil
        end
    end)
    if not parented then
        pcall(function()
            sg.Parent = game:GetService("CoreGui")
            parented = sg.Parent ~= nil
        end)
    end
    if not parented then
        pcall(function()
            sg.Parent = LocalPlayer and LocalPlayer:WaitForChild("PlayerGui", 3)
        end)
    end

    local COL_BG      = Color3.fromRGB(12, 15, 24)
    local COL_CARD    = Color3.fromRGB(20, 24, 38)
    local COL_BORDER  = Color3.fromRGB(54, 62, 88)
    local COL_ACCENT  = Color3.fromRGB(0, 170, 255)
    local COL_ACCENT2 = Color3.fromRGB(130, 120, 255)
    local COL_GRID    = Color3.fromRGB(42, 50, 74)
    local COL_SELF    = Color3.fromRGB(70, 240, 140)

    local radarBg = Instance.new("Frame")
    radarBg.Name = "RadarBg"
    radarBg.AnchorPoint = Vector2.new(1, 1)
    radarBg.Position = UDim2.new(1, -18, 1, -18)
    radarBg.Size = UDim2.fromOffset(RADAR_SIZE + 28, RADAR_SIZE + 64)
    radarBg.BackgroundColor3 = COL_CARD
    radarBg.BackgroundTransparency = 0.10
    radarBg.BorderSizePixel = 0
    radarBg.Parent = sg

    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(0, 18)
    bgCorner.Parent = radarBg

    local bgStroke = Instance.new("UIStroke")
    bgStroke.Color = COL_BORDER
    bgStroke.Thickness = 1
    bgStroke.Transparency = 0.25
    bgStroke.Parent = radarBg

    local bgGrad = Instance.new("UIGradient")
    bgGrad.Color = ColorSequence.new(COL_CARD, COL_BG)
    bgGrad.Rotation = 90
    bgGrad.Parent = radarBg

    local topBar = Instance.new("Frame")
    topBar.Size = UDim2.new(1, -28, 0, 3)
    topBar.Position = UDim2.new(0, 14, 0, 12)
    topBar.BackgroundColor3 = COL_ACCENT
    topBar.BorderSizePixel = 0
    topBar.ZIndex = 3
    topBar.Parent = radarBg
    local tbCorner = Instance.new("UICorner")
    tbCorner.CornerRadius = UDim.new(1, 0)
    tbCorner.Parent = topBar
    local tbGrad = Instance.new("UIGradient")
    tbGrad.Color = ColorSequence.new(COL_ACCENT, COL_ACCENT2)
    tbGrad.Parent = topBar

    local hdr = Instance.new("TextLabel")
    hdr.Size = UDim2.new(1, -28, 0, 18)
    hdr.Position = UDim2.new(0, 14, 0, 22)
    hdr.BackgroundTransparency = 1
    hdr.Text = "PLAYER RADAR"
    hdr.TextColor3 = Color3.fromRGB(238, 242, 250)
    hdr.TextXAlignment = Enum.TextXAlignment.Left
    hdr.TextSize = 13
    hdr.Font = Enum.Font.GothamBold
    hdr.ZIndex = 4
    hdr.Parent = radarBg

    local radarCircle = Instance.new("Frame")
    radarCircle.Name = "RadarCircle"
    radarCircle.AnchorPoint = Vector2.new(0.5, 0)
    radarCircle.Position = UDim2.new(0.5, 0, 0, 48)
    radarCircle.Size = UDim2.fromOffset(RADAR_SIZE, RADAR_SIZE)
    radarCircle.BackgroundColor3 = Color3.fromRGB(8, 11, 20)
    radarCircle.BackgroundTransparency = 0.05
    radarCircle.BorderSizePixel = 0
    radarCircle.ClipsDescendants = true
    radarCircle.ZIndex = 2
    radarCircle.Parent = radarBg
    local circleCorner = Instance.new("UICorner")
    circleCorner.CornerRadius = UDim.new(0.5, 0)
    circleCorner.Parent = radarCircle

    local circleStroke = Instance.new("UIStroke")
    circleStroke.Color = COL_GRID
    circleStroke.Thickness = 1.5
    circleStroke.Transparency = 0.15
    circleStroke.Parent = radarCircle

    for _, r in ipairs({0.32, 0.62, 0.88}) do
        local ring = Instance.new("Frame")
        ring.AnchorPoint = Vector2.new(0.5, 0.5)
        ring.Position = UDim2.fromScale(0.5, 0.5)
        ring.Size = UDim2.fromScale(r, r)
        ring.BackgroundTransparency = 1
        ring.BorderColor3 = COL_GRID
        ring.BorderSizePixel = 1
        ring.ZIndex = 3
        ring.Parent = radarCircle
        local ringCorner = Instance.new("UICorner")
        ringCorner.CornerRadius = UDim.new(0.5, 0)
        ringCorner.Parent = ring
    end

    for _, axis in ipairs({"H", "V"}) do
        local line = Instance.new("Frame")
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.Position = UDim2.fromScale(0.5, 0.5)
        line.BackgroundColor3 = COL_GRID
        line.BackgroundTransparency = 0.35
        line.BorderSizePixel = 0
        line.ZIndex = 3
        if axis == "H" then
            line.Size = UDim2.new(0.94, 0, 0, 1)
        else
            line.Size = UDim2.new(0, 1, 0.94, 0)
        end
        line.Parent = radarCircle
    end

    local selfDot = Instance.new("Frame")
    selfDot.Name = "SelfDot"
    selfDot.AnchorPoint = Vector2.new(0.5, 0.5)
    selfDot.Position = UDim2.fromScale(0.5, 0.5)
    selfDot.Size = UDim2.fromOffset(12, 12)
    selfDot.BackgroundColor3 = COL_SELF
    selfDot.BorderSizePixel = 0
    selfDot.ZIndex = 10
    selfDot.Parent = radarCircle
    local selfCorner = Instance.new("UICorner")
    selfCorner.CornerRadius = UDim.new(1, 0)
    selfCorner.Parent = selfDot
    local selfRing = Instance.new("UIStroke")
    selfRing.Color = Color3.new(1, 1, 1)
    selfRing.Thickness = 1.5
    selfRing.Transparency = 0.25
    selfRing.Parent = selfDot

    killerRadarGui = sg
    return sg, radarCircle
end

-- ==============================================================================
-- UNIVERSAL KILLER & SURVIVOR DETECTION HELPER
-- ==============================================================================
function check_is_killer(char, player)
    if not char then return false end
    if not player then
        pcall(function() player = Players:GetPlayerFromCharacter(char) end)
    end

    -- 1. Cek objek "Weapon" di karakter (Killer selalu memegang model Weapon)
    if char:FindFirstChild("Weapon") then return true end

    -- 2. Cek CollectionService Tag "Killer" / "Hunter" / dll
    local cs = game:GetService("CollectionService")
    if pcall(function() return cs:HasTag(char, "Killer") end) and cs:HasTag(char, "Killer") then return true end
    if pcall(function() return cs:HasTag(char, "Hunter") end) and cs:HasTag(char, "Hunter") then return true end
    local okTags, tags = pcall(function() return cs:GetTags(char) end)
    if okTags and tags then
        for _, t in ipairs(tags) do
            local ts = t:lower()
            if ts:find("killer") or ts:find("hunter") or ts:find("slasher") or ts:find("monster") or ts:find("abyssal") then
                return true
            end
        end
    end

    -- 3. Cek Attribute khas Killer pada model karakter
    if char:GetAttribute("TerrorRadius") or char:GetAttribute("SuspenseRadius")
        or char:GetAttribute("Chasemusic") or char:GetAttribute("BloodLust")
        or char:GetAttribute("IsKiller") or char:GetAttribute("KillerSpeed")
        or char:GetAttribute("TerrorLevel") or char:GetAttribute("IsHunter") then
        return true
    end

    -- 4. Cek Team & Attribute khas Killer pada Player
    if player then
        pcall(function()
            if player.Team then
                local tn = tostring(player.Team.Name):lower()
                if tn:find("kill") or tn:find("hunt") or tn:find("slash") or tn:find("monster") or tn:find("evil") then
                    return true
                end
            end
        end)
        local role = player:GetAttribute("CurrentRole") or player:GetAttribute("Role")
            or player:GetAttribute("Team") or player:GetAttribute("Side")
            or player:GetAttribute("CharacterType")
        if role then
            local rs = tostring(role):lower()
            if rs:find("killer") or rs:find("hunter") or rs:find("slasher") or rs:find("monster") or rs == "1" then
                return true
            end
        end
    end

    -- 5. Cek Tool senjata yang dipegang
    local tool = char:FindFirstChildWhichIsA("Tool")
    if tool then
        local tn = tool.Name:lower()
        if tn:find("knife") or tn:find("axe") or tn:find("sword") or tn:find("hammer")
            or tn:find("chainsaw") or tn:find("weapon") or tn:find("scythe") or tn:find("dagger")
            or tn:find("blade") or tn:find("cleave") or tn:find("katana") then
            return true
        end
    end

    -- 6. Cek nama model/character yang mengindikasikan killer
    local charName = char.Name:lower()
    if charName:find("killer") or charName:find("abyssal") or charName:find("scourge")
        or charName:find("slasher") or charName:find("reaper") or charName:find("hunter")
        or charName:find("monster") or charName:find("king") then
        return true
    end

    -- 7. Cek HP: Killer biasanya punya MaxHealth jauh lebih besar dari 100
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.MaxHealth > 200 and not player then
        -- Model tanpa player dengan HP besar = kemungkinan NPC Killer
        return true
    end

    return false
end

-- Backward compatibility alias
function radar_is_killer(player, char)
    return check_is_killer(char, player)
end

-- ==============================================================================
-- UNIVERSAL LOCALPLAYER ROLE CHECK (KILLER vs SURVIVOR)
-- ==============================================================================
function is_local_player_killer()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then return false end

    -- 1. Cek objek "Weapon" di karakter (Killer selalu memegang model Weapon)
    if char:FindFirstChild("Weapon") then return true end

    -- 2. Cek CollectionService Tag "Killer" / "Hunter"
    local cs = game:GetService("CollectionService")
    if pcall(function() return cs:HasTag(char, "Killer") end) and cs:HasTag(char, "Killer") then return true end
    if pcall(function() return cs:HasTag(char, "Hunter") end) and cs:HasTag(char, "Hunter") then return true end

    -- 3. Cek Attribute khas Killer pada model karakter
    if char:GetAttribute("TerrorRadius") or char:GetAttribute("SuspenseRadius")
        or char:GetAttribute("Chasemusic") or char:GetAttribute("BloodLust")
        or char:GetAttribute("IsKiller") or char:GetAttribute("KillerSpeed")
        or char:GetAttribute("TerrorLevel") or char:GetAttribute("IsHunter") then
        return true
    end

    -- 4. Cek Attribute khas Killer pada Player
    local role = LocalPlayer:GetAttribute("CurrentRole") or LocalPlayer:GetAttribute("Role")
        or LocalPlayer:GetAttribute("Team") or LocalPlayer:GetAttribute("Side")
        or LocalPlayer:GetAttribute("CharacterType")
    if role then
        local rs = tostring(role):lower()
        if rs:find("killer") or rs:find("hunter") or rs:find("slasher") or rs:find("monster") or rs == "1" then
            return true
        end
    end

    -- 5. Cek Team Player
    if LocalPlayer.Team then
        local tn = tostring(LocalPlayer.Team.Name):lower()
        if tn:find("kill") or tn:find("hunt") or tn:find("slash") or tn:find("monster") or tn:find("evil") then
            return true
        end
    end

    -- 6. Cek MaxHealth: Killer di game ini HP jauh lebih besar (> 200) dibanding survivor (100)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.MaxHealth and hum.MaxHealth > 200 then
        return true
    end

    return false
end

-- DOT POOLING untuk performa tinggi & anti-flicker
local _radarDotPool = {}

-- RADAR UPDATE: Deteksi 100% Akurat (Scan Players + Workspace Models)
local function radar_update(radarCircle)
    if not radarCircle or not radarCircle.Parent then return end

    local myChar = LocalPlayer and LocalPlayer.Character
    local myHrp = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Torso"))
    if not myHrp then return end

    local cam = workspace.CurrentCamera
    if not cam then return end
    local camCF = cam.CFrame
    local myPos = myHrp.Position

    -- Kumpulkan SEMUA entitas target (Players + Workspace Models / NPCs)
    local targets = {}
    local seen = {}

    -- 1. Scan Players
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart") or p.Character:FindFirstChild("Torso")
            if hrp then
                seen[p.Character] = true
                table.insert(targets, { key = p.Character, player = p, char = p.Character, hrp = hrp, name = p.DisplayName or p.Name })
            end
        end
    end

    -- 2. Scan Workspace Children (untuk Killer NPC / Model karakter khusus)
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= myChar and not seen[obj] then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso") or (hum and obj.PrimaryPart)
            if hrp and hum then
                seen[obj] = true
                local pl = Players:GetPlayerFromCharacter(obj)
                table.insert(targets, { key = obj, player = pl, char = obj, hrp = hrp, name = (pl and (pl.DisplayName or pl.Name)) or obj.Name })
            end
        end
    end

    -- 3. Scan folder khusus jika ada (Characters / Entities / Killers / Monsters)
    local extraFolders = {
        workspace:FindFirstChild("Characters"),
        workspace:FindFirstChild("Entities"),
        workspace:FindFirstChild("Players"),
        workspace:FindFirstChild("Killers"),
        workspace:FindFirstChild("Monsters"),
        workspace:FindFirstChild("NPCs")
    }
    for _, folder in ipairs(extraFolders) do
        if folder then
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and obj ~= myChar and not seen[obj] then
                    local hum = obj:FindFirstChildOfClass("Humanoid")
                    local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso") or (hum and obj.PrimaryPart)
                    if hrp and hum then
                        seen[obj] = true
                        local pl = Players:GetPlayerFromCharacter(obj)
                        table.insert(targets, { key = obj, player = pl, char = obj, hrp = hrp, name = (pl and (pl.DisplayName or pl.Name)) or obj.Name })
                    end
                end
            end
        end
    end

    local activeKeys = {}

    -- Render & Update semua target ke radar via Object Pooling
    for _, item in ipairs(targets) do
        local p = item.player
        local pChar = item.char
        local pHrp = item.hrp
        local nameStr = item.name
        local key = item.key

        local diff = pHrp.Position - myPos
        local dist3D = math.sqrt(diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z)

        if dist3D <= RADAR_RANGE then
            activeKeys[key] = true
            -- Posisi relatif ke kamera (world space -> camera object space)
            local rel = camCF:PointToObjectSpace(pHrp.Position)

            local scale = RADAR_RANGE
            local normX = math.clamp(rel.X / scale, -1, 1)
            local normY = math.clamp(-rel.Z / scale, -1, 1)

            -- Batasi agar titik tidak keluar dari lingkaran radar
            local rLen = math.sqrt(normX * normX + normY * normY)
            if rLen > 0.94 then
                normX = normX / rLen * 0.94
                normY = normY / rLen * 0.94
            end

            local screenX = math.clamp(0.5 + normX * 0.44, 0.04, 0.96)
            local screenY = math.clamp(0.5 - normY * 0.44, 0.04, 0.96)

            local isKiller = check_is_killer(pChar, p)

            local dotData = _radarDotPool[key]
            if not dotData or not dotData.dot.Parent then
                local dot = Instance.new("Frame")
                dot.AnchorPoint = Vector2.new(0.5, 0.5)
                dot.BorderSizePixel = 0
                dot.Parent = radarCircle

                local dc = Instance.new("UICorner")
                dc.CornerRadius = UDim.new(1, 0)
                dc.Parent = dot

                local lbl = Instance.new("TextLabel")
                lbl.AnchorPoint = Vector2.new(0.5, 1)
                lbl.Position = UDim2.new(0.5, 0, 0, -2)
                lbl.Size = UDim2.fromOffset(80, 13)
                lbl.BackgroundTransparency = 1
                lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
                lbl.TextStrokeTransparency = 0
                lbl.TextScaled = true
                lbl.Font = Enum.Font.GothamBold
                lbl.Parent = dot

                dotData = { dot = dot, lbl = lbl }
                _radarDotPool[key] = dotData
            end

            local dot = dotData.dot
            local lbl = dotData.lbl
            local distReal = math.floor(dist3D)

            dot.Visible = true
            dot.Position = UDim2.fromScale(screenX, screenY)
            dot.Size = UDim2.fromOffset(isKiller and 14 or 8, isKiller and 14 or 8)
            dot.BackgroundColor3 = isKiller and Color3.fromRGB(255, 35, 35) or Color3.fromRGB(50, 190, 255)
            dot.ZIndex = isKiller and 14 or 9

            if isKiller then
                lbl.Text = "KILLER " .. distReal .. "m"
                lbl.TextColor3 = Color3.fromRGB(255, 60, 60)
                lbl.ZIndex = 15
            else
                lbl.Text = nameStr:sub(1, 8) .. " " .. distReal .. "m"
                lbl.TextColor3 = Color3.fromRGB(100, 220, 255)
                lbl.ZIndex = 10
            end
        end
    end

    -- Sembunyikan dot yang berada di luar jangkauan / sudah mati / despawn
    for k, d in pairs(_radarDotPool) do
        if not activeKeys[k] then
            if d.dot and d.dot.Parent then
                d.dot.Visible = false
            else
                _radarDotPool[k] = nil
            end
        end
    end
end

local killerRadarCircle = nil

function killerradar_start()
    if killerRadarGui then pcall(function() killerRadarGui:Destroy() end) end
    local sg, rc = radar_create_gui()
    killerRadarCircle = rc
    if killerRadarConn then killerRadarConn:Disconnect() end
    local _lastRadarTick = 0
    killerRadarConn = RunService.RenderStepped:Connect(function(dt)
        if not killerRadarEnabled then return end
        _lastRadarTick = _lastRadarTick + dt
        if _lastRadarTick < 0.05 then return end -- Throttled to 20 FPS untuk menghemat CPU
        _lastRadarTick = 0
        local now = tick()
        if now - _lastRadarTick < 0.033 then return end -- ~30 FPS stabil
        _lastRadarTick = now
        pcall(radar_update, killerRadarCircle)
    end)
end

function killerradar_stop()
    if killerRadarConn then killerRadarConn:Disconnect(); killerRadarConn = nil end
    for _, d in pairs(_radarDotPool) do
        if d.dot then pcall(function() d.dot:Destroy() end) end
    end
    _radarDotPool = {}
    if killerRadarGui then
        pcall(function() killerRadarGui.Enabled = false end)
        pcall(function() killerRadarGui:Destroy() end)
        killerRadarGui = nil
    end
    pcall(function()
        local containers = {
            (gethui and gethui()),
            (cloneref and cloneref(game:GetService("CoreGui")) or game:GetService("CoreGui")),
            (LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui"))
        }
        for _, c in ipairs(containers) do
            if c then
                for _, child in ipairs(c:GetChildren()) do
                    if child.Name == "ZypheraxHubKillerRadar" then
                        pcall(function() child.Enabled = false end)
                        pcall(function() child:Destroy() end)
                    end
                end
            end
        end
    end)
    killerRadarCircle = nil
end


end

-- ==============================================================================
do
-- MODUL 8: FULLBRIGHT + NO FOG
-- ==============================================================================
fullbrightEnabled = false
local fullbrightConn = nil
local origAmbient = nil
local origOutdoor = nil
local origBrightness = nil
local origFogEnd = nil
local origFogStart = nil

local function fullbright_apply()
    pcall(function()
        local lighting = game:GetService("Lighting")
        lighting.Ambient = Color3.fromRGB(178, 178, 178)
        lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
        lighting.Brightness = 2
        lighting.FogEnd = 100000
        lighting.FogStart = 100000
        -- Hapus/disable efek dark
        for _, child in ipairs(lighting:GetChildren()) do
            if child:IsA("BloomEffect") or child:IsA("SunRaysEffect") 
               or child:IsA("ColorCorrectionEffect") then
                pcall(function() child.Enabled = false end)
            end
        end
    end)
end

local function fullbright_restore()
    pcall(function()
        local lighting = game:GetService("Lighting")
        if origAmbient then lighting.Ambient = origAmbient end
        if origOutdoor then lighting.OutdoorAmbient = origOutdoor end
        if origBrightness then lighting.Brightness = origBrightness end
        if origFogEnd then lighting.FogEnd = origFogEnd end
        if origFogStart then lighting.FogStart = origFogStart end
        -- Kembalikan efek
        for _, child in ipairs(lighting:GetChildren()) do
            if child:IsA("BloomEffect") or child:IsA("SunRaysEffect")
               or child:IsA("ColorCorrectionEffect") then
                pcall(function() child.Enabled = true end)
            end
        end
    end)
end

function fullbright_start()
    pcall(function()
        local lighting = game:GetService("Lighting")
        origAmbient = lighting.Ambient
        origOutdoor = lighting.OutdoorAmbient
        origBrightness = lighting.Brightness
        origFogEnd = lighting.FogEnd
        origFogStart = lighting.FogStart
    end)
    fullbright_apply()
    if fullbrightConn then fullbrightConn:Disconnect() end
    fullbrightConn = RunService.Heartbeat:Connect(function()
        if not fullbrightEnabled then return end
        fullbright_apply()
    end)
end

function fullbright_stop()
    if fullbrightConn then fullbrightConn:Disconnect(); fullbrightConn = nil end
    fullbright_restore()
end

-- ==============================================================================
-- MODUL 9: CUSTOM FOV (Field of View)
-- ==============================================================================
customFovEnabled = false
customFovValue = 70
local origFov = nil
local fovConn = nil

function fov_apply(val)
    pcall(function()
        workspace.CurrentCamera.FieldOfView = val
    end)
end

function fov_start(val)
    customFovValue = val or customFovValue
    pcall(function() origFov = workspace.CurrentCamera.FieldOfView end)
    fov_apply(customFovValue)
    if fovConn then fovConn:Disconnect() end
    fovConn = RunService.RenderStepped:Connect(function()
        if not customFovEnabled then return end
        pcall(function()
            if workspace.CurrentCamera.FieldOfView ~= customFovValue then
                workspace.CurrentCamera.FieldOfView = customFovValue
            end
        end)
    end)
end

function fov_stop()
    if fovConn then fovConn:Disconnect(); fovConn = nil end
    pcall(function()
        if origFov then workspace.CurrentCamera.FieldOfView = origFov end
    end)
end


end

-- ==============================================================================
do
-- MODUL 10: INFINITE ITEM CHARGES
-- ==============================================================================
infiniteChargesEnabled = false
local infiniteChargesConn = nil

function infinite_charges_apply()
    pcall(function()
        if is_local_player_killer and is_local_player_killer() then return end
        local char = LocalPlayer and LocalPlayer.Character
        -- PERBAIKAN: Jangan skip jika char punya child bernama Weapon;
        -- hanya skip jika memang IS killer berdasarkan is_local_player_killer()
        if not char then return end

        local containers = { char }
        local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
        if bp then table.insert(containers, bp) end

        for _, container in ipairs(containers) do
            for _, obj in ipairs(container:GetChildren()) do
                if obj:IsA("Tool") then
                    -- 1. Kunci Uses / CurrentUses ke 0 (mencegah item dikonsumsi/dihapus server)
                    local usedKeys = { "Uses", "uses", "CurrentUses", "currentUses", "UsedCount", "UseCount" }
                    for _, k in ipairs(usedKeys) do
                        if obj:GetAttribute(k) ~= nil then
                            obj:SetAttribute(k, 0)
                        end
                    end

                    -- 2. Pulihkan Charges & Ammo ke nilai maksimum aman
                    local maxChargeKeys = { "Charges", "charges", "Ammo", "ammo", "RemainingCharges", "Durability" }
                    local maxVal = obj:GetAttribute("MaxCharges") or obj:GetAttribute("maxCharges")
                        or obj:GetAttribute("MaxAmmo") or obj:GetAttribute("maxAmmo") or 10
                    for _, k in ipairs(maxChargeKeys) do
                        local v = obj:GetAttribute(k)
                        if type(v) == "number" and v < maxVal then
                            obj:SetAttribute(k, maxVal)
                        end
                    end
                end
            end
        end
    end)
end

local _chargesBackpackConn = nil
local _chargesRespawnConn  = nil

function infinite_charges_start()
    infinite_charges_apply()
    if infiniteChargesConn then infiniteChargesConn:Disconnect() end
    local t = 0
    infiniteChargesConn = RunService.Heartbeat:Connect(function(dt)
        if not infiniteChargesEnabled then return end
        t = t + dt
        if t >= 0.5 then
            t = 0
            infinite_charges_apply()
        end
    end)

    -- Hook Backpack ChildAdded agar item baru langsung dapat charges
    local function hookBackpack(bp)
        if not bp then return end
        if _chargesBackpackConn then _chargesBackpackConn:Disconnect() end
        _chargesBackpackConn = bp.ChildAdded:Connect(function(child)
            if infiniteChargesEnabled and child:IsA("Tool") then
                task.wait(0.15)
                infinite_charges_apply()
            end
        end)
    end

    -- Hook CharacterAdded agar tetap aktif setelah respawn
    if _chargesRespawnConn then _chargesRespawnConn:Disconnect() end
    _chargesRespawnConn = LocalPlayer.CharacterAdded:Connect(function()
        if not infiniteChargesEnabled then return end
        task.wait(0.5)  -- tunggu karakter sepenuhnya loaded
        infinite_charges_apply()
        hookBackpack(LocalPlayer:FindFirstChildOfClass("Backpack"))
    end)

    hookBackpack(LocalPlayer:FindFirstChildOfClass("Backpack"))
end

function infinite_charges_stop()
    if infiniteChargesConn then infiniteChargesConn:Disconnect(); infiniteChargesConn = nil end
    if _chargesBackpackConn then _chargesBackpackConn:Disconnect(); _chargesBackpackConn = nil end
    if _chargesRespawnConn then _chargesRespawnConn:Disconnect(); _chargesRespawnConn = nil end
end


end

-- ==============================================================================
do
-- MODUL 11: ESP EXIT GATE (LEVER SAJA)
-- ==============================================================================
espGateEnabled = false
local espGateConns = {}
local espGateObjects = {}

function is_exit_gate_lever(obj)
    if not obj then return false end
    local name = obj.Name:lower()
    
    -- Hanya cocokkan nama model/part ExitLever yang benar-benar milik Exit Gate
    if name == "exitlever" or name == "exit_lever" or name:find("gatelever") or name:find("gate_lever") then
        return true
    end
    
    local pName = obj.Parent and obj.Parent.Name:lower() or ""
    if (name == "lever" or name == "main") and (pName == "exitlever" or pName:find("gate") or pName:find("exit")) then
        return true
    end
    
    -- Cek jika model Gate memiliki ExitLever di dalamnya
    if obj:IsA("Model") and (name == "gate" or name:find("exitgate")) and obj:FindFirstChild("ExitLever") then
        return true
    end
    
    return false
end

function esp_gate_get_part(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        local el = obj.Name:lower() == "exitlever" and obj or obj:FindFirstChild("ExitLever")
        if el then
            return el:FindFirstChild("Lever") or el:FindFirstChild("LeverStart") or el:FindFirstChildWhichIsA("BasePart")
        end
        return obj:FindFirstChild("Lever") or obj:FindFirstChild("LeverStart") or obj:FindFirstChild("Switch") 
            or obj:FindFirstChild("Handle") or obj.PrimaryPart 
            or obj:FindFirstChildWhichIsA("BasePart")
    end
    return nil
end

local function esp_gate_add_tag(obj)
    if espGateObjects[obj] then return end
    local part = esp_gate_get_part(obj)
    if not part then return end

    local hl = Instance.new("Highlight")
    hl.Name = "ESP_GateLeverHL"
    hl.Adornee = obj
    hl.FillColor = Color3.fromRGB(255, 215, 0)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.55
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    pcall(function()
        if gethui then hl.Parent = gethui() else hl.Parent = CoreGui end
    end)
    if not hl.Parent then hl.Parent = CoreGui end

    local bbg = Instance.new("BillboardGui")
    bbg.Name = "ESP_GateLeverTag"
    bbg.Adornee = part
    bbg.AlwaysOnTop = true
    bbg.Size = UDim2.fromOffset(190, 26)
    bbg.StudsOffset = Vector3.new(0, 3.5, 0)
    bbg.ResetOnSpawn = false

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.TextColor3 = Color3.fromRGB(255, 220, 50)
    lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
    lbl.TextStrokeTransparency = 0
    lbl.Text = "[🚪 LEVER EXIT GATE]"
    lbl.Parent = bbg

    pcall(function()
        if gethui then bbg.Parent = gethui() else bbg.Parent = CoreGui end
    end)
    if not bbg.Parent then bbg.Parent = CoreGui end

    espGateObjects[obj] = { hl = hl, bbg = bbg, lbl = lbl, part = part }
end

local function esp_gate_update()
    local cam = workspace.CurrentCamera
    local camPos = cam and cam.CFrame and cam.CFrame.Position or Vector3.new(0, 0, 0)

    for obj, data in pairs(espGateObjects) do
        if not obj.Parent or not data.part.Parent then
            if data.hl then pcall(function() data.hl:Destroy() end) end
            if data.bbg then pcall(function() data.bbg:Destroy() end) end
            espGateObjects[obj] = nil
        else
            local dist = math.floor((camPos - data.part.Position).Magnitude)
            data.lbl.Text = string.format("[LEVER GATE] (%dm)", dist)
        end
    end
end

local function esp_gate_scan()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if is_exit_gate_lever(obj) then
            pcall(esp_gate_add_tag, obj)
        end
    end
end

function start_esp_gate()
    for _, c in ipairs(espGateConns) do pcall(function() c:Disconnect() end) end
    espGateConns = {}
    for obj, data in pairs(espGateObjects) do
        if data.hl then pcall(function() data.hl:Destroy() end) end
        if data.bbg then pcall(function() data.bbg:Destroy() end) end
    end
    espGateObjects = {}

    esp_gate_scan()

    -- Listener saat map baru load
    local scanConn = workspace.DescendantAdded:Connect(function(desc)
        if not espGateEnabled then return end
        if is_exit_gate_lever(desc) then
            task.wait(0.1)
            pcall(esp_gate_add_tag, desc)
        end
    end)
    table.insert(espGateConns, scanConn)

    -- Loop update jarak real-time
    local updateConn = RunService.RenderStepped:Connect(function()
        if not espGateEnabled then return end
        pcall(esp_gate_update)
    end)
    table.insert(espGateConns, updateConn)
end

function stop_esp_gate()
    for _, c in ipairs(espGateConns) do
        if typeof(c) == "RBXScriptConnection" then
            pcall(function() c:Disconnect() end)
        end
    end
    espGateConns = {}
    for obj, data in pairs(espGateObjects) do
        if data.hl then pcall(function() data.hl:Destroy() end) end
        if data.bbg then pcall(function() data.bbg:Destroy() end) end
    end
    espGateObjects = {}
end

-- ==============================================================================
-- MODUL 12: AUTO ESCAPE & BYPASS (SURVIVOR WIN)
-- ==============================================================================
autoEscapeEnabled = false
local autoEscapeConn = nil
local _isEscaping = false
local _escapeCheckTimer = 0
local _autoEscapeStarted = false

-- ==============================================================================
-- STRUKTUR GERBANG EXIT
-- ==============================================================================
-- BUKTI dari rekaman trigger (04:28:27):
--   [T] Workspace.Map.Gate.Box  <-  HIT HumanoidRootPart
--   [E] CharacterRemoving  (2 detik kemudian = karakter escaped, round selesai)
--
-- => TRIGGER KELUAR YANG ASLI ADALAH `Workspace.Map.Gate.Box`
--    (Pos 1583, 165, -790 | CanCollide: false | CanTouch: true | Size 46x37x28)
--
-- CATATAN PENTING:
--   Workspace.Map.Rooftop.Gate.Box  (Pos 3115, 487, -4931) TIDAK PERNAH dipicu.
--   Itu dekorasi/map lain yang kebetulan punya nama sama.
--  lever pun TIDAK wajib untuk escape - Box saja sudah cukup.
--
-- ==============================================================================
-- DETEKSI ZONA KELUAR - YANG BENAR
-- ==============================================================================
--
-- BUKTI dari screenshot dan scan:
--   Workspace.Map.Gate.Box  | CanCollide: false | 46x37x28
--       ^ INI VOLUME DI SEKITAR STRUKTUR GERBANG, BUKAN ZONA ESCAPE.
--         Karakter dipin di sini = nyangkut di gerbang, tidak ke mana-mana.
--
--   Workspace.Map.Gate.Part | CanCollide: true  | lantai
--   ExitLever.Tp            | CanTouch: false  | teleport point
--
-- ZONA ESCAPE YANG BENAR ada DI LUAR gerbang, di ujung lorong menuju fog.
-- Cara mencarinya: RAYCAST dari gerbang ke arah luar, lalu cari part
-- non-collide di ujung lorong.
--
-- CATATAN SCOPE: get_exit_gate() didefinisikan DI BAWAH blok ini, jadi kita
-- harus forward-declare dulu, kalau tidak collect_exit_zones() akan mencari
-- global get_exit_gate (yang nil) dan selalu gagal.
-- ==============================================================================

local get_exit_gate            -- forward declaration
local gate_outward             -- forward declaration
local corridor_open_distance   -- forward declaration

-- Kata kunci yang menandakan sebuah part adalah trigger zona keluar.
-- PENTING: nama di game bisa salah ketik (terbukti "Fininshline" yang
-- dimaksudnya "Finish line"), jadi polanya harus toleran typo.
local ZONE_KEYWORDS = {
    "escape", "exit", "zone", "trigger", "goal", "win",
    "area", "box", "teleport", "safe", "outside",
    "fininsh", "finis", "finisline", "endline", "finis hline",
}

-- Nama yang secara khusus berarti "garis finish" / batas keluar.
-- DIBUKTI dari rekaman: Workspace.Map.Fininshline muncul 1.2 detik
-- sebelum ESCAPE, jadi inilah trigger yang sebenarnya.
local FINISH_NAMES = {
    "fininshline", "finishline", "finisline", "finisline",
    "finis hline", "finish line", "endline", "end line",
}

-- Skor khusus garis finish. Jauh lebih besar dari kandidat lain
-- supaya tidak pernah kalah oleh Box atau part di sekitar gerbang.
local FINISH_SCORE = 500

-- Buang spasi, garis, dan underscore supaya perbandingan nama tidak rapuh.
local function normalize_name(s)
    return (string.lower(s):gsub("[%s_%-%.]", ""))
end

-- Daftar nama finish yang sudah dinormalisasi (dihitung sekali saja).
local FINISH_KEYS = {}
for _, fn in ipairs(FINISH_NAMES) do
    FINISH_KEYS[#FINISH_KEYS + 1] = normalize_name(fn)
end

-- Apakah nama part ini salah satu nama garis finish?
local function is_finish_name(nm)
    local n = normalize_name(nm)
    for _, k in ipairs(FINISH_KEYS) do
        if n == k or n:find(k, 1, true) then
            return true
        end
    end
    return false
end

-- Cari SEMUA part garis finish yang ada di map.
-- Kalau ada beberapa, yang paling Datar (tebal Y paling kecil) dipilih,
-- karena garis finish yang sebenarnya adalah part pipih di lantai.
local function find_finish_parts()
    local found = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and is_finish_name(obj.Name) then
            found[#found + 1] = obj
        end
    end
    return found
end

-- Nilai keyword untuk satu part: nama part + nama folder induk (sampai 3 level).
local function zone_keyword_score(part)
    local score = 0
    local nm = part.Name:lower()

    for _, kw in ipairs(ZONE_KEYWORDS) do
        if nm:find(kw, 1, true) then score = score + 40 end
    end

    local parent, depth = part.Parent, 0
    while parent and depth < 3 do
        local pn = parent.Name:lower()
        for _, kw in ipairs(ZONE_KEYWORDS) do
            if pn:find(kw, 1, true) then score = score + 25 end
        end
        parent = parent.Parent
        depth = depth + 1
    end

    -- Volume trigger yang wajar: 300 - 500000 stud^3
    local s = part.Size
    local vol = s.X * s.Y * s.Z
    if vol >= 300 and vol <= 500000 then score = score + 20 end

    -- Sinyal terkuat: nama part memuat kata escape / win / goal
    if nm:find("escape", 1, true) or nm:find("win", 1, true)
        or nm:find("goal", 1, true) then
        score = score + 90
    end

    return score
end

-- Arah KELUAR dari sebuah gerbang.
-- Mengembalikan (vektor_horizontal_normalize, titik_awal, panjang_lorong).
--
-- PENTING: LookVector daun pintu bisa mengarah ke DALAM map, bukan ke luar.
-- Jadi kedua arah diuji dengan raycast, dan yang dipilih adalah arah dengan
-- lorong terpanjang (itu dia jalan keluar sebenarnya menuju zona escape).
gate_outward = function(gate)
    if not gate then return nil end

    local origin
    if gate.box and gate.box:IsA("BasePart") then
        origin = gate.box.Position
    elseif gate.leftEnd and gate.leftEnd:IsA("BasePart")
        and gate.rightEnd and gate.rightEnd:IsA("BasePart") then
        origin = (gate.leftEnd.Position + gate.rightEnd.Position) / 2
    elseif gate.main and gate.main:IsA("BasePart") then
        origin = gate.main.Position
    else
        return nil
    end

    local src = gate.leftGate or gate.leftEnd or gate.rightGate or gate.main
    if not (src and src:IsA("BasePart")) then return nil end

    local look = src.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then return nil end
    flat = flat.Unit

    -- Uji kedua arah, ambil yang lorongnya lebih panjang.
    -- Gerbang sendiri dikecualikan dari raycast supaya ray tidak
    -- langsung mengenai kusen / daun pintu yang masih tertutup.
    local dFwd = corridor_open_distance(origin, flat, 400, gate.model)
    local dBwd = corridor_open_distance(origin, -flat, 400, gate.model)

    local bestDir, bestDist = flat, dFwd
    if dBwd > dFwd then
        bestDir, bestDist = -flat, dBwd
    end

    return bestDir, origin, bestDist
end

-- Seberapa jauh lorong ke depan masih terbuka.
-- Ray di-offset 30 stud supaya tidak kena daun pintu / kusen gerbang itu sendiri.
corridor_open_distance = function(origin, dir, maxDist, excludeModel)
    maxDist = maxDist or 400
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    local char = LocalPlayer and LocalPlayer.Character
    if char then ignore[#ignore + 1] = char end
    if excludeModel then ignore[#ignore + 1] = excludeModel end
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = true

    local ok, hit = pcall(function()
        return workspace:Raycast(origin + dir * 30, dir * maxDist, params)
    end)
    if ok and hit and hit.Distance then return hit.Distance end
    return maxDist
end

-- Semua part yang cocok sebagai trigger volume (CanTouch, tidak collide).
local function collect_trigger_parts()
    local list = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and obj.CanTouch and not obj.CanCollide then
            local s = obj.Size
            local vol = s.X * s.Y * s.Z
            if vol >= 300 and vol <= 500000 then
                list[#list + 1] = obj
            end
        end
    end
    return list
end

local function collect_exit_zones()
    local zones = {}
    local gate = get_exit_gate()
    local dir, origin, corridorLen = nil, nil, nil
    if gate then dir, origin, corridorLen = gate_outward(gate) end

    local char = LocalPlayer and LocalPlayer.Character
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    local myPos = (hrp and hrp.Position) or origin

    -- Diagnostik arah keluar. Hanya muncul kalau ZYPHERAX_DEBUG = true.
    if dir then
        log("[AutoEscape] arah keluar: %.2f, 0, %.2f | lorong: %d stud",
            dir.X, dir.Z, math.floor(corridorLen or 0))
    else
        log("[AutoEscape] arah keluar tidak bisa ditentukan dari gerbang")
    end

    -- Kandidat TERAKHIR (paling kuat): bagian garis finish.
    -- Bukti rekaman 05:06: pada detik 67.66 karakter menyentuh Gate.Box,
    -- lalu pada detik 68.70 masuk area Fininshline,
    -- dan pada detik 69.91 karakter dihapus (= ESCAPE).
    -- Jadi Fininshline itu trigger aslinya, bukan Gate.Box.
    for _, fp in ipairs(find_finish_parts()) do
        local fpSize = fp.Size
        table.insert(zones, {
            part = fp,
            score = FINISH_SCORE,
            why = string.format("GARIS FINISH (bukti rekaman) %s | %.0fx%.0fx%.0f | Touch=%s Collide=%s",
                fp:GetFullName(), fpSize.X, fpSize.Y, fpSize.Z,
                tostring(fp.CanTouch), tostring(fp.CanCollide)),
        })
    end

    -- Zona yang terbukti dari rekaman trigger: volume DI SEKITAR gerbang.
    -- Skor sengaja RENDAH karena ini hanya area nikah di gerbang,
    -- bukan zona escape di ujung lorong.
    if gate and gate.box and gate.box:IsA("BasePart") then
        table.insert(zones, {
            part = gate.box,
            score = 40,
            why = "Gate.Box (volume di sekitar gerbang, dari rekaman trigger)",
        })
    end

    for _, part in ipairs(collect_trigger_parts()) do
        if not (gate and part == gate.box) then
            local score = zone_keyword_score(part)
            if score > 0 then
                local pos = part.Position
                local why = "trigger volume"

                if origin and dir then
                    local delta = pos - origin
                    local fwd = delta:Dot(dir)
                    local side = (delta - dir * fwd).Magnitude

                    if fwd > 10 then
                        -- DI DEPAN gerbang = searah keluar = kandidat terkuat
                        score = score + 120
                        score = score - math.min(fwd / 6, 70)
                        if side < 70 then
                            score = score + 60
                        elseif side < 150 then
                            score = score + 20
                        end
                        why = why .. string.format(" | di depan gerbang %.0f stud, sisi %.0f", fwd, side)
                    elseif fwd > -40 then
                        -- Tepat di area gerbang
                        score = score - 80
                        why = why .. " | di area gerbang"
                    else
                        -- Di belakang gerbang = bukan zona keluar
                        score = score - 250
                        why = why .. " | di belakang gerbang"
                    end
                end

                if myPos then
                    local d = (pos - myPos).Magnitude
                    if d < 900 then score = score + 30 end
                end

                table.insert(zones, { part = part, score = score, why = why })
            end
        end
    end

    -- Fallback terakhir: kalau tidak ada trigger di depan gerbang,
    -- pakai titik di ujung lorong yang masih terbuka (hasil raycast).
    if origin and dir then
        local open = corridor_open_distance(origin, dir, 400)
        if open > 40 then
            local p = origin + dir * (30 + (open - 20) * 0.6)
            table.insert(zones, {
                part = nil,
                point = p,
                score = 90,
                why = string.format("titik di ujung lorong, %.0f stud dari gerbang", open),
            })
        end
    end

    return zones
end

-- Pilih zona keluar TERBAIK: skor tertinggi, dan jika seri pilih yang TERDEKAT
-- dengan karakter (karena map punya beberapa zona, hanya yang aktif itu yg benar).
local function find_escape_zone()
    local zones = collect_exit_zones()
    if #zones == 0 then return nil end

    -- Posisi tiap zona (bisa berupa part atau titik lorong)
    local function zone_pos_of(z)
        if z.part then return z.part.Position end
        return z.point
    end

    local char = LocalPlayer and LocalPlayer.Character
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not hrp then
        -- Tanpa karakter, ambil yang skor tertinggi
        local best = zones[1]
        for _, z in ipairs(zones) do
            if z.score > best.score then best = z end
        end
        return best
    end

    local pos = hrp.Position
    local best, bestScore = zones[1], -math.huge
    for _, z in ipairs(zones) do
        local zp = zone_pos_of(z)
        if zp then
            -- Skor gabungan: skor utama didominasi nilai zone, tapi jarak
            -- tetap berpengaruh supaya zona yang lebih dekat ke pemain diutamakan
            -- kalau nilai skornya hampir sama.
            local dist = (zp - pos).Magnitude
            local combined = z.score - math.min(dist, 600) / 60
            if combined > bestScore then
                best, bestScore = z, combined
            end
        end
    end
    return best
end

-- Titik jangkar karakter DI DALAM zona keluar.
-- Kalau zona punya `part` (trigger volume) -> turun ke bagian bawahnya
-- lalu cari lantai sungguhan di bawah dengan raycast ke bawah.
-- Kalau zona cuma punya `point` (ujung lorong hasil raycast) -> pakai titik itu.
local function zone_anchor_cframe(zone)
    if not zone then return nil end

    if not zone.part then
        if not zone.point then return nil end
        return CFrame.new(zone.point)
    end

    local p = zone.part
    local size = p.Size
    local target

    -- Raycast ke bawah dari titik tengah zona.
    -- Kalau ketemu lantai, berdiri di lantai itu.
    -- Kalau tidak, pakai pinggir atas zona + sedikit ke atas.
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local char = LocalPlayer and LocalPlayer.Character
    params.FilterDescendantsInstances = char and { char } or {}
    params.IgnoreWater = true

    local startPos
    if size.Y <= 6 then
        -- Garis finish / trigger datar: mulai dari ATAS permukaannya
        startPos = p.Position + Vector3.new(0, size.Y / 2 + 4, 0)
    else
        -- Volume besar: mulai dari tengah, nanti turun ke lantai
        startPos = p.Position
    end

    local ok, hit = pcall(function()
        return workspace:Raycast(startPos, Vector3.new(0, -400, 0), params)
    end)
    if ok and hit and hit.Position then
        target = hit.Position + Vector3.new(0, 3, 0)
    else
        -- Tidak ada lantai: pakai tepi atas trigger
        target = p.Position + Vector3.new(0, math.max(size.Y / 2, 1) + 2, 0)
    end

    return CFrame.new(target)
end

-- Wrapper kompatibilitas: cari gerbang ber-lever (dipakai hanya untuk fallback).
-- PENTING: struktur gerbang bisa berupa Model ATAU Folder, jadi jangan hanya
-- cek Model. `Workspace.Map.Gate` kemungkinan besar Folder, bukan Model.
-- CATATAN SCOPE: ditulis sebagai ASSIGNMENT (bukan `local function`) karena
-- forward declaration `local get_exit_gate` sudah ada di baris atas blok ini.
-- Kalau ditulis `local function`, itu akan membuat local BARU yang
-- menutupi forward declaration, dan collect_exit_zones() akan selalu
-- melihat nil.
get_exit_gate = function()
    local best = nil

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("Folder") then
            local leverModel = obj:FindFirstChild("ExitLever")
            if leverModel then
                local main = leverModel:FindFirstChild("Main")
                    or (leverModel:IsA("Model") and leverModel:FindFirstChildWhichIsA("BasePart"))
                if main then
                    local cand = {
                        model      = obj,
                        leverModel = leverModel,
                        main       = main,
                        lever      = leverModel:FindFirstChild("Lever") or main,
                        leverStart = leverModel:FindFirstChild("LeverStart"),
                        leverGoal  = leverModel:FindFirstChild("LeverGoal"),
                        box        = obj:FindFirstChild("Box"),
                        leftGate   = obj:FindFirstChild("LeftGate"),
                        rightGate  = obj:FindFirstChild("RightGate"),
                        leftEnd    = obj:FindFirstChild("LeftGate-end"),
                        rightEnd   = obj:FindFirstChild("RightGate-end"),
                    }
                    -- Prioritaskan gerbang yang punya Box (itu zona keluar aslinya)
                    if cand.box and not best then
                        best = cand
                    elseif not best then
                        best = cand
                    end
                end
            end
        end
    end
    return best
end

-- Wrapper kompatibilitas: tetap mengembalikan MeshPart 'Main' dari gerbang aktif
local function find_lever_main_part()
    local g = get_exit_gate()
    return g and g.main or nil
end

-- Helper: Notifikasi aman via Window ZypheraxLib.
-- PENTING: pada baris ini `local Window` BELUM dideklarasi (dideklarasi jauh di bawah),
-- jadi kalau dipanggil langsung akan error "attempt to index nil with 'Notify'".
-- Karena itu kita lewat global `ZypheraxWindow` yang diisi setelah Window dibuat.
local function safe_notify(opts)
    opts = opts or {}
    pcall(function()
        local w = ZypheraxWindow
        if w and type(w.Notify) == "function" then
            w:Notify({
                Title = opts.Title or "Info",
                Description = tostring(opts.Description or ""),
                Lifetime = opts.Lifetime or 3
            })
        end
    end)
end



local function find_escape_target()
    -- 1. Zona keluar terbukti (Gate.Box) - ini yang benar
    local zone = find_escape_zone()
    if zone then return zone.part, "zone" end

    -- 2. Fallback: ExitLever via ESP helper
    for _, obj in ipairs(workspace:GetDescendants()) do
        if is_exit_gate_lever and is_exit_gate_lever(obj) then
            local part = esp_gate_get_part and esp_gate_get_part(obj)
            if part then return part, "lever" end
        end
    end

    -- 3. Fallback terakhir: LeverEvent remote
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local exitF = remotes:FindFirstChild("Exit")
        if exitF and exitF:FindFirstChild("LeverEvent") then
            return exitF:FindFirstChild("LeverEvent"), "remote"
        end
    end
    return nil, nil
end

-- Helper: Teleport ke Lobby / Waiting Room setelah Escape
function teleport_to_lobby(hrp)
    if not hrp then return false end
    local lobbyTarget = nil

    -- 1. Cari SpawnLocation dengan nama Lobby / Wait
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("SpawnLocation") then
            local n = obj.Name:lower()
            local pName = obj.Parent and obj.Parent.Name:lower() or ""
            if n:find("lobby") or pName:find("lobby") or n:find("wait") or pName:find("wait") then
                lobbyTarget = obj
                break
            end
        end
    end

    -- 2. Cari Model / Folder Lobby di workspace
    if not lobbyTarget then
        for _, obj in ipairs(workspace:GetChildren()) do
            local n = obj.Name:lower()
            if n == "lobby" or n:find("lobby") or n == "waitingroom" or n == "intermission" then
                lobbyTarget = obj:FindFirstChildWhichIsA("SpawnLocation") 
                    or obj:FindFirstChildWhichIsA("BasePart")
                    or (obj:IsA("Model") and (obj.PrimaryPart or obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart")))
                if lobbyTarget then break end
            end
        end
    end

    -- 3. Cari sembarang SpawnLocation yang aktif
    if not lobbyTarget then
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("SpawnLocation") and obj.Enabled then
                lobbyTarget = obj
                break
            end
        end
    end

    if lobbyTarget then
        local cf = (lobbyTarget:IsA("Model") and lobbyTarget:GetPivot()) or lobbyTarget.CFrame
        hrp.CFrame = cf * CFrame.new(0, 4, 0)
        return true
    end
    return false
end

-- BYPASS AUTO ESCAPE ENGINE (TAILOR-MADE UNTUK VIOLENCE DISTRICT)
-- Helper: Fire semua remote reward (EXP, Screw, Sin, Gears) seperti escape normal
-- Helper: Fire remote reward escape secara aman (Mencegah kick / freeze / foreclose)
local function fire_escape_reward_remotes()
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if not remotes then return end

        -- Hanya panggil RemoteEvent spesifik yang sudah terbukti aman dan valid
        local genF = remotes:FindFirstChild("Generator")
        if genF then
            local et = genF:FindFirstChild("Escapetime")
            if et and et:IsA("RemoteEvent") then
                pcall(function() et:FireServer() end)
            end
        end

        local exitF = remotes:FindFirstChild("Exit")
        if exitF then
            local leverAnim = exitF:FindFirstChild("LeverAnim")
            if leverAnim and leverAnim:IsA("RemoteEvent") then
                pcall(function() leverAnim:FireServer(true) end)
            end
        end

        -- Remote reward aman
        local itemsF = remotes:FindFirstChild("Items")
        if itemsF then
            local gateF = itemsF:FindFirstChild("Gate")
            if gateF then
                local gateRemote = gateF:FindFirstChild("gate")
                if gateRemote and gateRemote:IsA("RemoteEvent") then
                    pcall(function() gateRemote:FireServer() end)
                end
            end
        end
    end)
end

function trigger_instant_escape()
    if _isEscaping then return false, "Proses escape sedang berjalan..." end
    local char = LocalPlayer and LocalPlayer.Character
    local hrp = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    if not hrp then return false, "Karakter tidak ditemukan!" end

    -- Penanda versi ini hanya muncul kalau ZYPHERAX_DEBUG = true,
    -- supaya tidak mengganggu console.
    log("[AutoEscape] VERSI 3: deteksi garis finish (Fininshline)")

    _isEscaping = true
    task.spawn(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")

        -- [LANGKAH 1] Escapetime remote (buka gate)
        pcall(function()
            if remotes then
                local genF = remotes:FindFirstChild("Generator")
                if genF then
                    local et = genF:FindFirstChild("Escapetime")
                    if et and et:IsA("RemoteEvent") then
                        et:FireServer()
                        et:FireServer(true)
                    end
                end
            end
        end)
        task.wait(0.1)

        -- ======================================================================
        -- [TAHAP A] Temukan ZONA KELUAR.
        --
        -- Bukti rekaman manual (05:06):
        --   1. 67.66s  karakter menyentuh Gate.Box     (lewat gerbang)
        --   2. 68.70s  karakter masuk area Fininshline (garis finish)
        --   3. 69.91s  karakter dihapus                 (= ESCAPE)
        --
        -- Jadi Gate.Box itu area nikah di gerbang, sedangkan
        -- Fininshline (garis finish) yang benar-benar memicu escape.
        -- ======================================================================
        local zone = find_escape_zone()
        local anchorCF = zone_anchor_cframe(zone)

        -- Semua zona keluar. Dipanggil SATU KALI saja supaya baris
        -- diagnostik "Arah keluar" tidak tercetak dua kali.
        local allZones = collect_exit_zones()

        -- Part yang perlu disentuh: zona itu sendiri + semua kandidat lain
        -- (beberapa zona mungkin aktif bersamaan, jadi sentuh semuanya).
        local zoneParts = {}
        for _, z in ipairs(allZones) do
            if z.part then table.insert(zoneParts, z.part) end
        end

        -- Titik SEBELUM garis finish. Karakter harus datang dari sisi gerbang,
        -- lalu menyeberang ke seberang garis finish (bukan teleport statis),
        -- karena server memverifikasi perpindahan karakter.
        local approachCF = nil
        if zone and zone.part then
            local gate = get_exit_gate()
            local dir, origin = nil, nil
            if gate then dir, origin = gate_outward(gate) end
            if dir and origin then
                local fwd = (zone.part.Position - origin):Dot(dir)
                if fwd > 5 then
                    -- Berdiri 14 stud SEBELUM garis finish, menghadap ke garis
                    local before = origin + dir * math.max(fwd - 14, 6)
                    if (zone.part.Position - before).Magnitude > 0.5 then
                        approachCF = CFrame.lookAt(before, zone.part.Position)
                    else
                        approachCF = CFrame.new(before)
                    end
                end
            end
        end

        local currentChar = LocalPlayer and LocalPlayer.Character
        local currentHrp  = currentChar and (currentChar:FindFirstChild("HumanoidRootPart") or currentChar:FindFirstChild("Torso"))

        if zone then
            local zp = zone.part and zone.part.Position or zone.point
            log("[AutoEscape] zona keluar : %s",
                zone.part and zone.part:GetFullName() or "(titik lorong)")
            log("[AutoEscape] alasan      : %s", tostring(zone.why))
            if zp then
                log("[AutoEscape] pos zona    : %d, %d, %d",
                    math.floor(zp.X), math.floor(zp.Y), math.floor(zp.Z))
            end
        else
            log("[AutoEscape] zona keluar tidak ditemukan")
        end
        if anchorCF then
            local ap = anchorCF.Position
            log("[AutoEscape] anchor      : %d, %d, %d",
                math.floor(ap.X), math.floor(ap.Y), math.floor(ap.Z))
        end

        -- ======================================================================
        -- [TAHAP B] BUKA GERBANG, lalu masuk zona.
        --
        -- Bukti rekaman manual (04:28):
        --   1. Pemain MENARIK TUAS di gerbang  -> gerbang terbuka
        --   2. Pemain JALAN ke dalam Box         -> Touched terpicu
        --   3. 2 detik kemudian                 -> CharacterRemoving (escaped)
        --
        -- Jadi urutan WAJIB: tuas dulu (gerbang harus terbuka), baru masuk zona.
        -- Lever harus diambil dari GERBANG YANG SAMA dengan zona terpilih,
        -- bukan dari gerbang lain di map (terbukti lever Rooftop tidak bekerja).
        -- ======================================================================
        local function touchAll()
            -- Sentuh secara aman tanpa spam firetouchinterest yang bisa meng-crash executor
            if currentHrp and currentHrp.Parent then
                for _, zp in ipairs(zoneParts) do
                    if zp and zp.Parent and zp:IsA("BasePart") then
                        pcall(function()
                            if firetouchinterest and zp.CanTouch and currentHrp.CanTouch then
                                firetouchinterest(currentHrp, zp, 0)
                                task.wait()
                                firetouchinterest(currentHrp, zp, 1)
                            end
                        end)
                    end
                end
            end
        end

        -- Pantau apakah karakter sudah di-escape (CharacterRemoving = sinyal sukses)
        local escaped = false
        local monitorConns = {}
        pcall(function()
            monitorConns[#monitorConns + 1] = LocalPlayer.CharacterRemoving:Connect(function()
                escaped = true
            end)
        end)

        -- [B1] BUKA GERBANG: cari LeverEvent + Main dari gerbang yang SAMA
        --      dengan zona keluar, lalu tekan tuas sampai daun pintu bergeser.
        local leverEvent = nil
        local leverMain  = nil
        pcall(function()
            if remotes then
                local exitF = remotes:FindFirstChild("Exit")
                if exitF then leverEvent = exitF:FindFirstChild("LeverEvent") end
            end
        end)

        -- Cocokkan lever dengan zona: cari ExitLever yang jaraknya paling dekat
        -- ke zona keluar terpilih.
        if leverEvent then
            local bestLever, bestDist = nil, math.huge
            local zonePos = zone and (zone.part and zone.part.Position or zone.point)
                or (currentHrp and currentHrp.Position)
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("Model") or obj:IsA("Folder") then
                    local lm = obj:FindFirstChild("ExitLever")
                    if lm then
                        local m = lm:FindFirstChild("Main")
                            or (lm:IsA("Model") and lm:FindFirstChildWhichIsA("BasePart"))
                        if m and m:IsA("BasePart") then
                            local d = (m.Position - zonePos).Magnitude
                            if d < bestDist then bestLever, bestDist = m, d end
                        end
                    end
                end
            end
            leverMain = bestLever
            if leverMain then
                log("[AutoEscape] lever       : %s | jarak %d stud",
                    leverMain:GetFullName(), math.floor(bestDist))
            else
                log("[AutoEscape] ExitLever tidak ditemukan")
            end
        end

        if leverEvent and leverMain then
            -- Gerbang harus terbuka: tekan tuas berulang selama ~2 detik.
            -- Signature server: LeverEvent:FireServer(MeshPart, true|false)
            for _ = 1, 12 do
                pcall(function() leverEvent:FireServer(leverMain, true) end)
                task.wait(0.08)
                pcall(function() leverEvent:FireServer(leverMain, false) end)
                task.wait(0.08)
                if escaped then break end
            end
            log("[AutoEscape] tuas ditekan, gerbang seharusnya terbuka")
        end

        -- ======================================================================
        -- [B2] TELEPORT LANGSUNG KE ZONA (TANPA FLY / TANPA MELAYANG)
        --
        -- Semua part karakter di-set CanCollide = false sebentar supaya
        -- tidak tertahan daun pintu/walls saat di-teleport. Setelah sampai,
        -- CanCollide dikembalikan ke semula.
        --
        -- Posisi tujuan: titik di dasar volume zona (bukan melayang di udara),
        -- sehingga karakter langsung berdiri 'di dalam' zona.
        -- ======================================================================
        local savedCollide = {}
        local function noclipOn()
            if not currentChar then return end
            for _, d in ipairs(currentChar:GetDescendants()) do
                if d:IsA("BasePart") then
                    savedCollide[d] = d.CanCollide
                    pcall(function() d.CanCollide = false end)
                end
            end
        end

        local function noclipOff()
            if not currentChar then return end
            for d, v in pairs(savedCollide) do
                if d and d.Parent then
                    pcall(function() d.CanCollide = v end)
                end
            end
            savedCollide = {}
        end

        noclipOn()

        -- ======================================================================
        -- [B2] MENYEBERANGI GARIS FINISH
        --
        -- Rekaman manual menunjukkan karakter BERJALAN menembus garis finish,
        -- bukan berdiri diam di atasnya:
        --   67.66s menyentuh Gate.Box -> 68.70s masuk Fininshline -> 69.91s escape
        --
        -- Jadi server memeriksa PERPINDAHAN karakter. Teleport statis ke satu
        -- titik sering ditolak karena tidak ada perpindahan yang tercatat.
        --
        -- Strategi: teleport ke titik SEBELUM garis finish, lalu JALAN
        -- pelan-pelan menembusnya di banyak frame supaya perpindahan
        -- benar-benar tercatat di server.
        -- ======================================================================
        local startCF = approachCF or anchorCF
        local crossed = false

        if currentHrp and startCF then
            -- Tahap 1: teleport ke titik sebelum garis finish
            pcall(function()
                currentHrp.CFrame = startCF
                currentHrp.AssemblyLinearVelocity = Vector3.zero
                currentHrp.AssemblyAngularVelocity = Vector3.zero
            end)
            task.wait(0.2)
            touchAll()
            task.wait(0.1)

            -- Tahap 2: jalan menembus garis finish (30 langkah)
            if anchorCF then
                local from = startCF.Position
                local to = anchorCF.Position
                local steps = 30
                for i = 1, steps do
                    if escaped then break end
                    if not (currentHrp and currentHrp.Parent) then break end

                    local t = i / steps
                    -- Smoothstep supaya mulai dan berakhir pelan
                    local e = t * t * (3 - 2 * t)
                    local want = from:Lerp(to, e)

                    pcall(function()
                        currentHrp.CFrame = CFrame.new(want)
                        currentHrp.AssemblyLinearVelocity = Vector3.zero
                    end)

                    -- Picu touch setiap beberapa langkah
                    if i % 3 == 0 then touchAll() end
                    task.wait(0.03)
                end
                crossed = true
            end
        end

        -- Kembalikan collide supaya karakter normal lagi
        noclipOff()
        task.wait(0.1)

        -- [B3] TETAP di seberang garis finish sampai server memproses
        -- (maks 15 detik). Karakter ditahan di anchor supaya tetap di zona.
        local waited = 0
        while waited < 150 and not escaped do
            if currentHrp and currentHrp.Parent and anchorCF then
                pcall(function()
                    -- hanya reposisi kalau karakter menyimpang jauh
                    if (currentHrp.Position - anchorCF.Position).Magnitude > 8 then
                        noclipOn()
                        currentHrp.CFrame = anchorCF
                        task.defer(noclipOff)
                    end
                    currentHrp.AssemblyLinearVelocity = Vector3.zero
                end)
            end
            touchAll()
            task.wait(0.1)
            waited = waited + 1
        end

        for _, conn in ipairs(monitorConns) do
            pcall(function() conn:Disconnect() end)
        end
        noclipOff()

        log("[AutoEscape] selesai. escaped = %s | menyeberang = %s | tunggu %.1f detik",
            tostring(escaped), tostring(crossed), waited * 0.1)
        task.wait(0.2)

        -- [LANGKAH 4] Fire semua remote reward EXP/Screw/etc
        fire_escape_reward_remotes()
        task.wait(0.2)

        -- [LANGKAH 5] Set attribute status escaped
        pcall(function()
            local c = LocalPlayer and LocalPlayer.Character
            if c and c.Parent then
                c:SetAttribute("Escaped", true)
                c:SetAttribute("WinState", true)
                c:SetAttribute("Survived", true)
            end
            LocalPlayer:SetAttribute("Escaped", true)
            LocalPlayer:SetAttribute("WinState", true)
            LocalPlayer:SetAttribute("Survived", true)
        end)

        -- [LANGKAH 6] Pantau perubahan EXP/Screws
        local escapeProcessed = false
        local connList = {}
        local expBefore   = tonumber(tostring(LocalPlayer:GetAttribute("ExpinRound") or LocalPlayer:GetAttribute("EXP") or LocalPlayer:GetAttribute("Exp") or 0)) or 0
        local screwBefore = tonumber(tostring(LocalPlayer:GetAttribute("Screws") or LocalPlayer:GetAttribute("screw") or LocalPlayer:GetAttribute("Screw") or 0)) or 0

        local attrNames = { "ExpinRound","EXP","Exp","XP","experience","Screws","screw","Screw","Sin","Gears","Reward" }
        for _, attrName in ipairs(attrNames) do
            pcall(function()
                local conn = LocalPlayer:GetAttributeChangedSignal(attrName):Connect(function()
                    escapeProcessed = true
                end)
                table.insert(connList, conn)
            end)
        end

        for step = 1, 40 do
            if escapeProcessed then break end
            if step % 5 == 0 then
                pcall(function()
                    local expNow   = tonumber(tostring(LocalPlayer:GetAttribute("ExpinRound") or LocalPlayer:GetAttribute("EXP") or LocalPlayer:GetAttribute("Exp") or 0)) or 0
                    local screwNow = tonumber(tostring(LocalPlayer:GetAttribute("Screws") or LocalPlayer:GetAttribute("screw") or LocalPlayer:GetAttribute("Screw") or 0)) or 0
                    if expNow ~= expBefore or screwNow ~= screwBefore then
                        escapeProcessed = true
                    end
                end)
            end
            task.wait(0.1)
        end

        for _, conn in ipairs(connList) do
            pcall(function() conn:Disconnect() end)
        end

        -- [LANGKAH 7] Konfirmasi reward sekali lagi
        fire_escape_reward_remotes()
        task.wait(0.5)

        -- [LANGKAH 8] Webhook summary (dikirim langsung saat berhasil escape)
        pcall(function()
            if webhookUrl and webhookUrl ~= "" and webhookNotifyMatch then
                task.spawn(function()
                    task.wait(0.2)
                    pcall(function() send_match_summary_webhook("ESCAPED", true) end)
                end)
            end
        end)

        -- Reset state
        _isEscaping = false
        autoEscapeEnabled = false
        _autoEscapeStarted = false
        stop_auto_escape()

        local statusMsg
        if escaped then
            statusMsg = "ESCAPED! Karakter langsung dipindahkan ke lobby oleh game."
        elseif escapeProcessed then
            statusMsg = "Escape diproses! EXP & Screws bertambah."
        else
            statusMsg = "Zona disentuh tapi server belum memproses. Coba ulangi."
        end
        -- Hasil akhir tetap dicetak karena ini yang paling penting.
        -- Detail diagnostik lain sudah disembunyikan lewat ZYPHERAX_DEBUG.
        print("[Escape] " .. statusMsg)
        safe_notify({
            Title = escaped and "Escape Berhasil" or "Auto Escape",
            Description = statusMsg,
            Lifetime = 6
        })
    end)

    return true, "Memulai Escape..."
end

function start_auto_escape()
    if autoEscapeConn then autoEscapeConn:Disconnect() end
    _escapeCheckTimer = 0
    _autoEscapeStarted = true
    autoEscapeConn = RunService.Heartbeat:Connect(function(dt)
        if not autoEscapeEnabled or _isEscaping then return end
        if is_local_player_killer and is_local_player_killer() then return end
        _escapeCheckTimer = _escapeCheckTimer + dt
        if _escapeCheckTimer < 0.5 then return end
        _escapeCheckTimer = 0

        -- Auto escape setelah match dimulai (deteksi LeverEvent sudah ada di Remotes)
        local targetObj, targetType = find_escape_target()
        if targetObj then
            autoEscapeEnabled = false
            stop_auto_escape()
            trigger_instant_escape()
        end
    end)
end

function stop_auto_escape()
    _autoEscapeStarted = false
    if autoEscapeConn then autoEscapeConn:Disconnect(); autoEscapeConn = nil end
end


end

-- ==============================================================================
do
-- MODUL 13: DISCORD WEBHOOK NOTIFIER (MATCH SUMMARY SAAT MATCH SELESAI / ESCAPED)
-- ==============================================================================
webhookUrl = ""
local webhookNotifyMatch = true
local _matchStartStats = nil
local _matchStartTime = tick()
local _matchEndFired = false
local _lastWebhookSentTime = 0

local WEBHOOK_SETTINGS_FILE = "zypherax_webhook.json"

local function save_webhook_settings()
    pcall(function()
        if writefile then
            local data = {
                url = tostring(webhookUrl or ""),
                enabled = webhookNotifyMatch == true
            }
            writefile(WEBHOOK_SETTINGS_FILE, HttpService:JSONEncode(data))
        end
    end)
end

local function load_webhook_settings()
    pcall(function()
        if isfile and isfile(WEBHOOK_SETTINGS_FILE) and readfile then
            local raw = readfile(WEBHOOK_SETTINGS_FILE)
            local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
            if ok and type(data) == "table" then
                if data.url and data.url ~= "" then
                    webhookUrl = tostring(data.url)
                end
                if data.enabled ~= nil then
                    webhookNotifyMatch = (data.enabled == true)
                end
            end
        end
    end)
end

load_webhook_settings()

function get_player_stats()
    local stats = {
        level = 0,
        sin   = 0,
        exp   = 0,
        screw = 0,
        gold  = 0,
        map   = "Violence District"
    }

    local function _set(field, num)
        if type(num) ~= "number" then return end
        if num < 0 then num = 0 end
        if num ~= 0 or stats[field] == 0 then
            stats[field] = num
        end
    end

    local function _classify(nm, val)
        local num = tonumber(val)
        if num == nil then
            -- fallback: ekstrak angka dari string (misal "1500 XP" -> 1500)
            local s = tostring(val):gsub(",", "")
            local digits = s:match("(%-?%d+%.?%d*)")
            if digits then num = tonumber(digits) end
        end
        if num == nil then return end
        nm = tostring(nm):lower()
        if nm:find("screw") then
            _set("screw", num)
        elseif nm:find("sin") then
            _set("sin", num)
        elseif nm:find("gold") or nm:find("gear") or nm:find("coin") or nm:find("money") then
            _set("gold", num)
        elseif nm:find("exp") or nm:find("xp") or nm:find("experience") then
            _set("exp", num)
        elseif nm:find("level") or nm:find("lvl") then
            _set("level", num)
        end
    end

    local visited = {}
    local queue = {}
    local function push(obj, depth)
        if obj and type(obj) ~= "number" and type(obj) ~= "string" and type(obj) ~= "boolean" and not visited[obj] then
            local okGC = pcall(function() return obj:GetChildren() end)
            if okGC and depth <= 6 then
                visited[obj] = true
                table.insert(queue, { obj = obj, depth = depth })
            end
        end
    end

    pcall(function()
        if LocalPlayer then
            push(LocalPlayer, 0)
            push(LocalPlayer.Character, 0)
            push(LocalPlayer:FindFirstChild("leaderstats"), 1)
            push(LocalPlayer:FindFirstChild("stats"), 1)
            push(LocalPlayer:FindFirstChild("Data"), 1)
        end
    end)
    pcall(function()
        if ReplicatedStorage then
            push(ReplicatedStorage, 0)
            for _, key in ipairs({"PlayerData","Data","PlayerStats","Leaderstats","leaderstats","Stats","Profile","PlayerProfile","Inventory"}) do
                push(ReplicatedStorage:FindFirstChild(key), 1)
            end
        end
    end)
    pcall(function()
        if workspace then
            push(workspace:FindFirstChild("PlayerStats"), 1)
            push(workspace:FindFirstChild("Stats"), 1)
        end
    end)

    local qi = 1
    while qi <= #queue do
        local node = queue[qi].obj
        local depth = queue[qi].depth
        qi = qi + 1
        pcall(function()
            local attrs = node:GetAttributes()
            for k, v in pairs(attrs) do _classify(k, v) end
        end)
        pcall(function()
            for _, ch in ipairs(node:GetChildren()) do
                local okv, v = pcall(function() return ch.Value end)
                if okv and v ~= nil then _classify(ch.Name, v) end
                push(ch, depth + 1)
            end
        end)
    end
    visited = nil
    queue = nil

    pcall(function()
        local mapFolder = workspace:FindFirstChild("Map") or workspace:FindFirstChild("CurrentMap")
            or workspace:FindFirstChild("Level") or workspace:FindFirstChild("MapFolder")
            or workspace:FindFirstChild("GameMap")
        if mapFolder then
            stats.map = mapFolder.Name
        else
            local mapAttr = workspace:GetAttribute("MapName") or workspace:GetAttribute("CurrentMap")
                or workspace:GetAttribute("Map") or workspace:GetAttribute("Level")
                or ReplicatedStorage:GetAttribute("MapName") or ReplicatedStorage:GetAttribute("CurrentMap")
            if mapAttr then stats.map = tostring(mapAttr) end
        end
    end)

    return stats
end

local function mask_username(name)
    local n = tostring(name or "?")
    if #n <= 2 then return n .. "***" end
    return n:sub(1, 2) .. "***"
end

local function start_match_tracking()
    _matchStartStats = get_player_stats()
    _matchStartTime = tick()
    _matchEndFired = false
end

local function do_http_request(options)
    local req = (syn and syn.request) 
        or (http and http.request) 
        or http_request 
        or request 
        or (fluxus and fluxus.request)
        or (krnl and krnl.request)
        or (identifyexecutor and request)
    if req then
        local ok, res = pcall(req, options)
        if ok then return res end
        return nil, tostring(res)
    end
    return nil, "Executor tidak mendukung HTTP request!"
end

function send_match_summary_webhook(resultStatus, force)
    if not webhookUrl or webhookUrl == "" or not webhookUrl:find("discord.com/api/webhooks") then
        return false, "Webhook URL belum diisi atau tidak valid!"
    end
    
    local now = tick()
    if not force and (_matchEndFired or (now - _lastWebhookSentTime < 5)) then
        return false, "Summary match ini sudah dikirim."
    end
    _lastWebhookSentTime = now
    _matchEndFired = true

    -- refresh stats
    pcall(get_player_stats)
    local currStats = get_player_stats()
    local baseStats = _matchStartStats or currStats

    local matchDuration = math.max(0, now - (_matchStartTime or now))
    local mins = math.floor(matchDuration / 60)
    local secs = math.floor(matchDuration % 60)
    local matchTimeStr = mins > 0 and string.format("%dm %ds", mins, secs) or string.format("%ds", secs)

    local pName = tostring(LocalPlayer and LocalPlayer.Name or "?")
    local pDisplay = tostring(LocalPlayer and LocalPlayer.DisplayName or pName)
    local maskedName = mask_username(pDisplay)

    local rawJobId = tostring(game.JobId or "502b4d8a-server-id-xxxx")
    local serverIdMasked = (rawJobId:sub(1, 4)) .. string.rep("*", 32)

    local expDelta   = (tonumber(tostring(currStats.exp))   or 0) - (tonumber(tostring(baseStats.exp))   or 0)
    local screwDelta = (tonumber(tostring(currStats.screw)) or 0) - (tonumber(tostring(baseStats.screw)) or 0)
    local sinDelta   = (tonumber(tostring(currStats.sin))   or 0) - (tonumber(tostring(baseStats.sin))   or 0)
    local gearDelta  = (tonumber(tostring(currStats.gold))  or 0) - (tonumber(tostring(baseStats.gold))  or 0)
    local lvlDelta   = (tonumber(tostring(currStats.level)) or 0) - (tonumber(tostring(baseStats.level)) or 0)

    local function fmtStat(val, delta)
        local s = tostring(val)
        if delta > 0 then return s .. " (+**" .. delta .. "**)"
        elseif delta < 0 then return s .. " (**" .. delta .. "**)"
        else return s .. " (+**0**)" end
    end

    local levelField = fmtStat(tonumber(tostring(currStats.level)) or 0, lvlDelta)
    local sinField   = fmtStat(tonumber(tostring(currStats.sin))   or 0, sinDelta)
    local expField   = fmtStat(tonumber(tostring(currStats.exp))   or 0, expDelta)
    local screwField = fmtStat(tonumber(tostring(currStats.screw)) or 0, screwDelta)
    local gearField  = fmtStat(tonumber(tostring(currStats.gold))  or 0, gearDelta)

    local totalCurrency = math.max(0, screwDelta + gearDelta)
    local totalSin = math.max(0, sinDelta)
    local matchTotalStr = tostring(totalCurrency) .. " currency + " .. tostring(totalSin) .. " Sin"

    _matchStartStats = currStats
    _matchStartTime  = tick()

    -- Embed persis sesuai format foto (Green bar, 11 fields, emoji unicode hex)
    local payload = {
        username   = "Zypherax Hub",
        avatar_url = "https://i.imgur.com/6FVu1WJ.png?v=3",
        embeds = {
            {
                color = 5763719, -- #57F287 Hijau
                fields = {
                    { name = "\xF0\x9F\x9F\xA2 Status",       value = "End Match",                           inline = false },
                    { name = "\xF0\x9F\x91\xA4 Username",     value = maskedName,                            inline = false },
                    { name = "\xF0\x9F\x86\x99 Level",        value = levelField,                            inline = false },
                    { name = "\xE2\x98\xA0\xEF\xB8\x8F Sin",          value = sinField,                              inline = false },
                    { name = "\xE2\xAD\x90 EXP",          value = expField,                              inline = false },
                    { name = "\xF0\x9F\x94\xA9 Screws",       value = screwField,                            inline = false },
                    { name = "\xE2\x9A\x99\xEF\xB8\x8F Gears",        value = gearField,                             inline = false },
                    { name = "\xE2\x8F\xB1\xEF\xB8\x8F Match Time",   value = matchTimeStr,                          inline = false },
                    { name = "\xF0\x9F\x97\xBA\xEF\xB8\x8F Maps",         value = currStats.map or "Violence District",    inline = false },
                    { name = "\xF0\x9F\x8F\x86 Match Total",  value = matchTotalStr,                         inline = false },
                    { name = "\xF0\x9F\x86\x94 Server ID",    value = "```" .. serverIdMasked .. "```",   inline = false },
                }
            }
        }
    }

    local ok, res = pcall(function()
        return do_http_request({
            Url     = webhookUrl,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode(payload)
        })
    end)
    return ok, res
end

function send_discord_webhook(embedTitle, embedDesc, colorHex)
    if not webhookUrl or webhookUrl == "" or not webhookUrl:find("discord.com/api/webhooks") then
        return false, "Webhook URL belum diisi atau tidak valid!"
    end

    local payload = {
        username   = "Zypherax Hub",
        avatar_url = "https://i.imgur.com/6FVu1WJ.png?v=3",
        embeds = {
            {
                title       = embedTitle or "Test Webhook",
                description = embedDesc or "Zypherax Hub Webhook Notifier aktif!",
                color       = tonumber(colorHex or "57F287", 16) or 5763719,
                fields = {
                    { name = "Status", value = "\xF0\x9F\x9F\xA2 Webhook Berfungsi!", inline = true },
                    { name = "Game", value = "Violence District", inline = true }
                },
                timestamp   = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }
        }
    }
    local ok, res = pcall(function()
        return do_http_request({
            Url     = webhookUrl,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode(payload)
        })
    end)
    return ok, res
end

local _webhookLiveConn = nil
local _matchActive = false
local _endCheckTimer = 0

local function _read_game_state()
    local gs = workspace:GetAttribute("GameState") or workspace:GetAttribute("State")
        or workspace:GetAttribute("RoundState")
        or ReplicatedStorage:GetAttribute("GameState") or ReplicatedStorage:GetAttribute("State")
    return gs and tostring(gs):lower() or nil
end

local function _is_lobby_state(gs)
    if not gs then return false end
    return gs == "lobby" or gs == "waiting" or gs == "intermission"
        or gs == "end" or gs == "ended" or gs == "results" or gs == "post"
        or gs == "gameover" or gs == "finished"
end

function start_webhook_live_monitor()
    if _webhookLiveConn then _webhookLiveConn:Disconnect(); _webhookLiveConn = nil end
    start_match_tracking()
    _matchActive = true
    _matchEndFired = false

    _webhookLiveConn = RunService.Heartbeat:Connect(function(dt)
        if not webhookUrl or webhookUrl == "" or not webhookNotifyMatch then return end
        _endCheckTimer = _endCheckTimer + dt
        if _endCheckTimer < 1 then return end
        _endCheckTimer = 0

        local gs = _read_game_state()
        local char = LocalPlayer and LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local alive = hum and hum.Health > 0

        if alive and not _is_lobby_state(gs) then
            if not _matchActive then
                _matchActive = true
                _matchEndFired = false
                start_match_tracking()
            end
            return
        end

        local ended = _is_lobby_state(gs)
        if ended and _matchActive then
            _matchActive = false
            if not _matchEndFired then
                task.spawn(function() pcall(function() send_match_summary_webhook("End Match", true) end) end)
                task.delay(3, function() start_match_tracking() end)
            end
        end
    end)
end

function stop_webhook_live_monitor()
    if _webhookLiveConn then _webhookLiveConn:Disconnect(); _webhookLiveConn = nil end
    _matchActive = false
end

-- Deteksi escape via attribute change
pcall(function()
    if LocalPlayer then
        LocalPlayer:GetAttributeChangedSignal("Escaped"):Connect(function()
            if LocalPlayer:GetAttribute("Escaped") == true and webhookNotifyMatch and webhookUrl and webhookUrl ~= "" then
                task.spawn(function()
                    pcall(function() send_match_summary_webhook("End Match", true) end)
                end)
            end
        end)
    end
end)

task.defer(function()
    start_match_tracking()
    if webhookNotifyMatch and webhookUrl and webhookUrl ~= "" then
        start_webhook_live_monitor()
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
        { "AccentGradient   = Color3.fromRGB(0, 140, 230),  -- subtle gradient end",
          "AccentGradient   = Color3.fromRGB(130, 120, 255), -- subtle gradient end" },
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
        AccentDark       = Color3.fromRGB(0, 120, 190),
        AccentGradient   = Color3.fromRGB(130, 120, 255),
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
        AccentDark       = Color3.fromRGB(0, 110, 180),
        AccentGradient   = Color3.fromRGB(90, 110, 230),
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
        BackgroundTransparency = 0.02,
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
        BackgroundTransparency = 0.5,
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

    card.Position = UDim2.new(0, 34, 0, 0)
    card.BackgroundTransparency = 1
    stroke.Transparency = 1
    U.Tween(card, 0.34, { Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0.08 }, Enum.EasingStyle.Quart)
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
        BackgroundTransparency = 0.15,
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
    local sub     = config.Description or config.SubName or "Violence District"
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
        BackgroundTransparency = 0.12,
        ClipsDescendants = true,
        ZIndex = 1,
        Parent = shadow
    })
    U.Corner(main, T.CornerLg)
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
    local mainStroke = U.Stroke(main, T.Stroke, 1.2, 0)
    RegisterThemeColor(main, "BackgroundColor3", "Background")
    RegisterThemeColor(mainStroke, "Color", "Stroke")

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
    local sideDiv = U.New("Frame", {
        Size = UDim2.new(0, 1, 1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = T.Stroke,
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = sidebar
    })
    RegisterThemeColor(sideDiv, "BackgroundColor3", "Stroke")

    -- // SIDEBAR HEADER (MacOS Traffic Lights + Titles) \ --
    local sidebarHeader = U.New("Frame", {
        Name = "SidebarHeader",
        Size = UDim2.new(1, 0, 0, 78),
        BackgroundTransparency = 1,
        ZIndex = 4,
        Parent = sidebar
    })

    -- MacOS Traffic Light Buttons (🔴 Red, 🟡 Yellow, 🟢 Green - Compact)
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

    -- 🔴 Close: smoothly closes window
    makeTrafficDot(Color3.fromRGB(255, 95, 86), Color3.fromRGB(255, 120, 110), function()
        Win:ToggleVisibility(false)
    end)

    -- 🟡 Minimize: minimizes window
    makeTrafficDot(Color3.fromRGB(255, 189, 46), Color3.fromRGB(255, 210, 80), function()
        Win:ToggleVisibility(false)
    end)

    -- 🟢 Maximize: toggles size
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
        Size = UDim2.fromOffset(20, 20),
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
        Size = UDim2.new(1, -24, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 5,
        Parent = sidebarHeader
    })
    titleLbl.TextColor3 = Color3.fromRGB(0, 170, 255) -- LOGOBLUE_TITLE

    local subLbl = U.New("TextLabel", {
        Text = sub,
        Font = T.FontRegular,
        TextSize = 10,
        TextColor3 = T.TextMuted,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 40, 0, 46),
        Size = UDim2.new(1, -24, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 5,
        Parent = sidebarHeader
    })
    RegisterThemeColor(subLbl, "TextColor3", "TextMuted")

    -- Horizontal divider under sidebar header
    local hDiv = U.New("Frame", {
        Size = UDim2.new(1, -24, 0, 1),
        Position = UDim2.new(0, 12, 1, -1),
        BackgroundColor3 = T.Stroke,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = sidebarHeader
    })
    RegisterThemeColor(hDiv, "BackgroundColor3", "Stroke")

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
        BackgroundTransparency = 0.5,
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
        BackgroundTransparency = 0.2,
        ZIndex = 5,
        Parent = contentArea
    })
    U.Corner(searchBarFrame, T.CornerMd)
    local sbStroke = U.Stroke(searchBarFrame, T.Stroke, 1, 0.2)
    RegisterThemeColor(searchBarFrame, "BackgroundColor3", "Surface2")
    RegisterThemeColor(sbStroke, "Color", "Stroke")

    local searchIcon = U.New("TextLabel", {
        Text = "\xF0\x9F\x94\x8D",
        Font = T.FontRegular,
        TextSize = 13,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(0, 20, 1, 0),
        TextColor3 = T.TextMuted,
        ZIndex = 6,
        Parent = searchBarFrame
    })
    pcall(function() searchIcon.Visible = false end) -- ikon search dihapus

    local searchInput = U.New("TextBox", {
        Name = "SearchInput",
        Text = "",
        PlaceholderText = "Cari fitur...",
        Font = T.FontRegular,
        TextSize = 11,
        TextColor3 = T.Text,
        PlaceholderColor3 = T.TextDim,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 34, 0, 0),
        Size = UDim2.new(1, -64, 1, 0),
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
                AutomaticSize = Enum.AutomaticSize.Y,
                ZIndex = 4,
                Parent = targetCol
            })
            U.Corner(sectionBox, T.CornerMd)
            local sStroke = U.Stroke(sectionBox, T.Stroke, 1, 0.4)
            RegisterThemeColor(sectionBox, "BackgroundColor3", "SectionBg")
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

            local SectionObj = { _box = sectionBox, _name = displayName, _items = {} }
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
                    BackgroundTransparency = 0.5,
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
                    Text = "▼",
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
                            chevron.Text = "▼"
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
                        chevron.Text = "▲"
                    else
                        U.Tween(base, 0.2, { Size = UDim2.new(1, 0, 0, 36) })
                        U.Tween(listFrame, 0.2, { Size = UDim2.new(1, -16, 0, 0) }).Completed:Connect(function()
                            listFrame.Visible = false
                        end)
                        chevron.Text = "▼"
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
                local txt = type(textOrCfg) == "table" and (textOrCfg.Name or textOrCfg.Text or textOrCfg[1]) or tostring(textOrCfg)
                local lbl = U.New("TextLabel", {
                    Text = txt,
                    Font = T.FontRegular,
                    TextSize = 11,
                    TextColor3 = T.TextMuted,
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
                    BackgroundTransparency = 0.35,
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
                    Text = "⚙  Config Manager",
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
    local BridgeWatermark = {
        Set = function() end,
        SetVisible = function() end,
    }

    -- --------------------------------------------------------------------------
    -- Window tiruan: semua method lama tetap aman dipanggil.
    -- --------------------------------------------------------------------------
    local _zwin = ZypheraxUI:CreateWindow({
        Title       = "Zypherax Hub",
        Description = "Violence District",
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
            -- UI lama hanya 1 kolom; UI baru punya 2 kolom.
            -- Sebar section bergantian (kiri/kanan) supaya tidak ada kolom kosong.
            Tab._secIdx = Tab._secIdx + 1
            if side == 1 then side = (Tab._secIdx % 2 == 1) and 1 or 2 end
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
    function BridgeLib:Watermark(_)
        return BridgeWatermark
    end
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
        local shadow = Instance.new("ImageLabel")
        shadow.BackgroundTransparency = 1
        shadow.Image = "rbxassetid://1316045217"
        shadow.ImageColor3 = Color3.new(0, 0, 0)
        shadow.ImageTransparency = 0.55
        shadow.ScaleType = Enum.ScaleType.Slice
        shadow.SliceCenter = Rect.new(10, 10, 118, 118)
        shadow.Position = UDim2.new(0, 8, 0, 10)
        shadow.Size = UDim2.fromOffset(300, 42)
        shadow.Parent = sg
        local pill = Instance.new("Frame")
        pill.Position = UDim2.new(0, 12, 0, 12)
        pill.Size = UDim2.fromOffset(292, 32)
        pill.BackgroundColor3 = Color3.fromRGB(10, 13, 20)
        pill.BackgroundTransparency = 0.22
        pill.BorderSizePixel = 0
        pill.Active = true
        pill.Draggable = true
        pill.Parent = sg
        local cn = Instance.new("UICorner") cn.CornerRadius = UDim.new(0, 10) cn.Parent = pill
        local sk = Instance.new("UIStroke") sk.Color = Color3.fromRGB(0, 170, 255) sk.Thickness = 1 sk.Transparency = 0.55 sk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border sk.Parent = pill
        local hi = Instance.new("Frame")
        hi.BackgroundColor3 = Color3.fromRGB(255, 255, 255) hi.BackgroundTransparency = 0.88 hi.BorderSizePixel = 0
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
_zy_show_watermark("Violence District")



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
            logo.BackgroundTransparency = 1
            logo.BackgroundColor3 = Color3.new(1, 1, 1) -- transparan (BackgroundTransparency=1)
            logo.BorderSizePixel = 0
            logo.ZIndex = 6
            logo.Parent = card
            _round(logo, 14)
            -- logoPure: tanpa kotak gradien

            local logoImg = Instance.new("ImageLabel")
            logoImg.AnchorPoint = Vector2.new(0.5, 0.5)
            logoImg.Position = UDim2.fromScale(0.5, 0.5)
            logoImg.Size = UDim2.fromScale(1, 1)
            logoImg.BackgroundTransparency = 1
            logoImg.Image = "rbxassetid://106764279090045"
            logoImg.ScaleType = Enum.ScaleType.Fit
            logoImg.ZIndex = 7
            logoImg.Parent = logo

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
            sub.Text = "Violence District"
            sub.Font = Enum.Font.GothamMedium
            sub.TextSize = 13
            sub.TextColor3 = P.textMuted
            sub.ZIndex = 6
            sub.Parent = card

            -- Chip fitur.
            local chips = { "Auto Gen", "Auto Parry", "Auto Heal", "ESP", "Escape" }
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


-- State Variabel Form
local swap_target = ""
local swap_avatar = "usnavatar"

local outfit_owner = "zhbrxty"
local outfit_name = "cp 1"
local outfit_target = ""

local acc_target = ""
local acc_id = "10159600649"

local mod_target = ""

-- ==============================================================================
do-- MODUL AUTO PERFECT GENERATOR (SKILL CHECK AUTOMATION)
-- ==============================================================================
local PlayerGui       = LocalPlayer:WaitForChild("PlayerGui")

autoGenEnabled = false
local autoGenConn     = nil
local autoGenHitCount = 0
local autoGenOffset   = 0

-- State tracking untuk siklus minigame aktif & King's Scourge
local isMinigameActive       = false
local hasHitCurrentMinigame  = false
local lastLineRotation       = nil
local lastGoalRotation       = nil
local lastHitTick            = 0
local lineMoveCount          = 0

-- Helper untuk memastikan GUI benar-benar aktif & terlihat di layar
local function is_gui_visible(v)
    if not v or not v:IsA("GuiObject") then return false end
    if not v.Visible then return false end
    if v.AbsoluteSize.X < 5 or v.AbsoluteSize.Y < 5 then return false end
    local p = v.Parent
    while p and not p:IsA("PlayerGui") do
        if p:IsA("ScreenGui") and not p.Enabled then return false end
        if p:IsA("GuiObject") and not p.Visible then return false end
        p = p.Parent
    end
    return true
end

-- Deteksi circular skill check (Violence District):
-- Jalur presisi: SkillCheckPromptGui -> Check -> (Line, Goal, Space)
local function agen_get_skillcheck_ui()
    -- 1. Jalur langsung berkecepatan tinggi O(1)
    local scpGui = PlayerGui:FindFirstChild("SkillCheckPromptGui")
    if scpGui and scpGui.Enabled then
        local check = scpGui:FindFirstChild("Check")
        if check and check.Visible then
            local line = check:FindFirstChild("Line")
            local goal = check:FindFirstChild("Goal")
            local space = check:FindFirstChild("Space")
            if line and goal and line.Visible and goal.Visible then
                return line, goal, space, check
            end
        end
    end

    -- 2. Fallback scan jika struktur GUI di-update oleh game
    for _, v in ipairs(PlayerGui:GetDescendants()) do
        if v:IsA("GuiObject") and v.Name == "Line" and is_gui_visible(v) then
            local p = v.Parent
            if p then
                local goal = p:FindFirstChild("Goal")
                if goal and goal:IsA("GuiObject") and is_gui_visible(goal) then
                    local space = p:FindFirstChild("Space")
                    return v, goal, space, p
                end
            end
        end
    end
    return nil, nil, nil, nil
end

-- Input simulator multi-metode INSTAN (0ms delay, tanpa task.wait yang menghambat)
local function agen_press(spaceObj)
    -- 1. VirtualInputManager (Core Roblox)
    pcall(function()
        game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode.Space, false, game)
    end)

    -- 2. VirtualUser (Universal Roblox Input)
    pcall(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:SetKeyDown("0x20")
    end)

    -- 3. Executor keypress VK_SPACE
    pcall(function()
        if keypress then keypress(32) end
        if keypress then keypress(Enum.KeyCode.Space.Value) end
    end)

    -- 4. GUI Button activation (jika tombol Space adalah GuiButton atau punya child button)
    if spaceObj then
        pcall(function()
            if spaceObj:IsA("GuiButton") and firesignal then
                firesignal(spaceObj.Activated)
                firesignal(spaceObj.MouseButton1Down)
                firesignal(spaceObj.MouseButton1Click)
            end
            for _, btn in ipairs(spaceObj:GetDescendants()) do
                if btn:IsA("GuiButton") and firesignal then
                    firesignal(btn.Activated)
                    firesignal(btn.MouseButton1Down)
                    firesignal(btn.MouseButton1Click)
                end
            end
        end)
    end

    -- Release tombol secara asinkron setelah 15ms (sangat cepat untuk King's Scourge)
    task.spawn(function()
        task.wait(0.015)
        pcall(function()
            game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end)
        pcall(function()
            game:GetService("VirtualUser"):SetKeyUp("0x20")
        end)
        pcall(function()
            if keyrelease then keyrelease(32) end
            if keyrelease then keyrelease(Enum.KeyCode.Space.Value) end
        end)
    end)
end

local function agen_tick()
    if not autoGenEnabled then return end

    local lineObj, goalObj, spaceObj = agen_get_skillcheck_ui()

    -- Jika minigame tidak ada atau sudah tertutup
    if not lineObj or not goalObj then
        if isMinigameActive then
            isMinigameActive       = false
            hasHitCurrentMinigame  = false
            lastLineRotation       = nil
            lastGoalRotation       = nil
            lastHitTick            = 0
            lineMoveCount          = 0
        end
        return
    end

    local currentRot = lineObj.Rotation
    local goalRot    = goalObj.Rotation % 360
    if goalRot < 0 then goalRot = goalRot + 360 end

    -- DUKUNGAN KHUSUS KING'S SCOURGE (RAPID-FIRE CHECKS):
    -- Deteksi perpindahan Goal sudut (> 2.0°) = ronde/skill check baru langsung reset
    if lastGoalRotation ~= nil then
        local goalDiff = math.abs((goalRot - lastGoalRotation + 180) % 360 - 180)
        if goalDiff > 2.0 then
            hasHitCurrentMinigame = false
            lastHitTick            = 0
            lineMoveCount          = 1
            lastGoalRotation       = goalRot
        end
    else
        lastGoalRotation = goalRot
    end

    -- Minigame baru muncul
    if not isMinigameActive then
        isMinigameActive      = true
        hasHitCurrentMinigame = false
        lastLineRotation      = lineObj.Rotation
        lastGoalRotation      = goalRot
        lineMoveCount         = 0
        return
    end

    -- Hitung kecepatan jarum (derajat per frame, searah jarum jam)
    local rawSpeed = 0
    if lastLineRotation ~= nil then
        rawSpeed = (currentRot - lastLineRotation) % 360
        if rawSpeed > 180 then rawSpeed = rawSpeed - 360 end
    end
    lastLineRotation = currentRot

    -- Jika minigame sedang standby/idle (jarum diam di 0°):
    if math.abs(rawSpeed) < 0.05 and (currentRot % 360 == 0) then
        isMinigameActive      = false
        hasHitCurrentMinigame = false
        lineMoveCount         = 0
        return
    end

    -- Deteksi pergerakan jarum aktif
    if math.abs(rawSpeed) > 0.05 then
        lineMoveCount = lineMoveCount + 1
    end

    -- Tunggu minimal 1 frame pergerakan agar kecepatan terukur (maksimal responsif)
    if lineMoveCount < 1 then return end

    -- Jangan tekan lagi jika sudah pernah hit untuk minigame ini
    if hasHitCurrentMinigame then return end

    -- Normalisasi rotasi needle (0-360)
    local lineRot = currentRot % 360
    if lineRot < 0 then lineRot = lineRot + 360 end

    -- TARGET ZONA PUTIH PRESISI (Violence District white zone: offset 104.5° s/d 112.5°, center 108.3°)
    local offset = (lineRot - goalRot) % 360
    local speed  = math.abs(rawSpeed)

    -- Keputusan hit PRESISI: tekan saat jarum PAS di TENGAH zona putih.
    -- Zona putih Violence District: offset 104.5 s/d 112.5, center 108.5
    -- (baseline lama: zona 103-114). Versi lama menekan begitu masuk 103
    -- (pinggir zona) => sering miss. Sekarang tekan hanya di jendela
    -- tengah 105.0-112.0 supaya selalu dekat center. Tune CENTER_HALF
    -- kalau masih kurang pas (makin kecil = makin tengah, risiko kelewat).
    local shouldHit = false
    local ZONE_CENTER = 108.5
    local CENTER_HALF = 2.5
    local JENDELA_MIN = ZONE_CENTER - CENTER_HALF -- 106.0
    local JENDELA_MAX = ZONE_CENTER + CENTER_HALF -- 111.0
    if rawSpeed >= 0 then
        -- Searah jarum jam (Normal & Fast King's Scourge CW):
        -- 1. Jarum sudah berada di jendela tengah -> tekan sekarang
        if offset >= JENDELA_MIN and offset <= JENDELA_MAX then
            shouldHit = true
        -- 2. Kecepatan ekstrem: frame berikutnya melompat MELEWATI jendela
        --    (tidak akan ada frame yang mendarat di tengah) -> tekan di
        --    pinggir supaya tidak miss total saat speed sangat tinggi.
        elseif offset < JENDELA_MIN and (offset + speed * 1.2) > JENDELA_MAX then
            shouldHit = true
        end
    else
        -- Berlawanan jarum jam (Hex / CCW):
        if offset >= JENDELA_MIN and offset <= JENDELA_MAX then
            shouldHit = true
        elseif offset > JENDELA_MAX and (offset - speed * 1.2) < JENDELA_MIN then
            shouldHit = true
        end
    end

    if shouldHit then
        hasHitCurrentMinigame = true
        lastHitTick           = tick()
        autoGenHitCount       = autoGenHitCount + 1
        agen_press(spaceObj)

    end
end

function agen_start()
    if autoGenConn then return end
    autoGenHitCount       = 0
    isMinigameActive      = false
    hasHitCurrentMinigame = false
    lastLineRotation      = nil
    lastGoalRotation      = nil
    lastHitTick           = 0
    lineMoveCount         = 0
    autoGenConn = RunService.RenderStepped:Connect(agen_tick)
end

function agen_stop()
    if autoGenConn then
        autoGenConn:Disconnect()
        autoGenConn = nil
    end
    isMinigameActive = false
    hasHitCurrentMinigame = false
    lastLineRotation = nil
    lineMoveCount = 0
end


end

-- ==============================================================================
do
-- MODUL 4.5: AUTO PARRY (PARRYING DAGGER)
-- ==============================================================================
autoParryEnabled = false
local autoParryConn    = nil
local PARRY_DISTANCE   = 16.0
local PARRY_COOLDOWN   = 3.5  -- Mengikuti cooldown resmi game (minimal 3.5 detik)
local lastParryTick    = 0
local isParrying       = false
local gameParryCooldownEnd = 0
local trackedAnimators = {}

local function cleanup_animator_tracks()
    for anim, conn in pairs(trackedAnimators) do
        if typeof(conn) == "RBXScriptConnection" then
            pcall(function() conn:Disconnect() end)
        end
    end
    trackedAnimators = {}
end

local KNOWN_ATTACK_ANIM_IDS = {
    -- Abysswalker
    ["98833771436786"]  = true,
    ["118907603246885"] = true,
    ["78432063483146"]  = true,
    ["126626340093785"] = true,
    -- Masked
    ["129784271201071"] = true,
    ["132817836308238"] = true,
    ["76503974441748"]  = true,
    ["82666958311998"]  = true,
    ["133002120549396"] = true,
    -- Hidden Killer
    ["73681849513551"]  = true,
}

local IGNORED_LOOP_NAMES = {
    ["idle"] = true, ["walk"] = true, ["run"] = true, ["jump"] = true,
    ["fall"] = true, ["strafe"] = true, ["climb"] = true,
}

local cachedParryClient = nil
local cachedParryRemote = nil

-- Lapis 1: cari instance ParryClient yang SUDAH dipegang game lewat GC.
-- (Dulu langsung dipakai; sekarang jadi lapis pertama saja.)
local parry_gc_scan
parry_gc_scan = function()
    if not getgc then return nil end
    local found = nil
    pcall(function()
        for _, v in pairs(getgc(true)) do
            if type(v) == "table" and rawget(v, "Parry") and rawget(v, "isParryOnCooldown") ~= nil then
                found = v
                return
            end
        end
    end)
    return found
end

-- Lapis 2 (FIX): kalau GC-scan gagal, buat sendiri instance ParryClient dari module.
-- Ini yang membuat ANIMASI parry muncul & cooldown (isParryOnCooldown) terisi.
-- Tanpa ini, blob hanya kirim remote dan tidak memicu animasi/cooldown.
local parry_module_scan
parry_module_scan = function()
    local ok, res = pcall(function()
        local modules = ReplicatedStorage:WaitForChild("Modules", 3)
        local items = modules and modules:WaitForChild("Items", 3)
        local mod = items and items:WaitForChild("ParryClient", 3)
        if not mod then return nil end

        local ParryClient = require(mod)
        if type(ParryClient) ~= "table" or type(ParryClient.new) ~= "function" then return nil end

        -- Ambil tool dagger yang sedang dipegang (jika ada) agar skin tidak rusak.
        local char = LocalPlayer and LocalPlayer.Character
        local tool = char
        pcall(function()
            if char then
                local daggerModel = char:FindFirstChild("Parrying Dagger")
                if daggerModel then
                    local leftArm = daggerModel:FindFirstChild("Left Arm")
                    local part = leftArm and leftArm:FindFirstChild("Parry Dagger")
                    tool = part or (daggerModel:FindFirstChildOfClass("Model")) or daggerModel
                end
            end
        end)

        return ParryClient.new({
            animationId  = 109133187196613,
            lockDuration = 0.8,
            tool         = tool or nil
        })
    end)
    if ok and type(res) == "table" then return res end
    return nil
end

local function get_parry_instance()
    if cachedParryClient and cachedParryClient.Parry then
        return cachedParryClient
    end

    -- Lapis 1: instance GC milik game
    cachedParryClient = parry_gc_scan()

    -- Lapis 2: bikin sendiri dari module
    if not cachedParryClient then
        cachedParryClient = parry_module_scan()
    end

    return cachedParryClient
end

-- Dengarkan event parryResult resmi game untuk mengetahui kapan cooldown selesai
pcall(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 2)
    local items = remotes and remotes:WaitForChild("Items", 2)
    local dagger = items and items:WaitForChild("Parrying Dagger", 2)
    local parryResult = dagger and dagger:WaitForChild("parryResult", 2)
    if parryResult then
        parryResult.OnClientEvent:Connect(function(arg1, cd)
            local cooldownDuration = tonumber(cd) or 3.5
            gameParryCooldownEnd = tick() + cooldownDuration
            isParrying = false
        end)
    end
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    cachedParryClient = nil
    cachedParryRemote = nil
    isParrying = false
    lastParryTick = 0
    gameParryCooldownEnd = 0
    cleanup_animator_tracks()

    task.delay(1, function()
        if is_local_player_killer and is_local_player_killer() then
            cleanup_animator_tracks()
            isParrying = false
            pcall(function()
                Window:Notify({
                    Title = "⚔️ Mode Killer Terdeteksi",
                    Description = "Auto Parry dinonaktifkan otomatis. Serangan (M1) & skill kamu 100% lancar!",
                    Lifetime = 4
                })
            end)
        else
            if autoParryEnabled then
                scanAllEntities()
            end
        end
    end)
end)

local function execute_perfect_parry(killerModel, killerName, reason, dist)
    -- [CRITICAL FIX KILLER] Jangan pernah parry jika kita sendiri adalah Killer!
    if is_local_player_killer and is_local_player_killer() then return end
    local myChar = LocalPlayer.Character
    if not myChar or killerModel == myChar then return end

    local now = tick()
    -- Cek cooldown internal & cooldown dari game
    if isParrying or (now - lastParryTick < PARRY_COOLDOWN) or (now < gameParryCooldownEnd) then
        return
    end

    local myHrp = myChar:FindFirstChild("HumanoidRootPart") or myChar:FindFirstChild("Torso")
    local killerHrp = killerModel and (killerModel:FindFirstChild("HumanoidRootPart") or killerModel:FindFirstChild("Torso"))
    if not myHrp or not killerHrp then return end

    -- Cek apakah karakter sedang melakukan aksi lain / dibawa / di-hook
    local cs = game:GetService("CollectionService")
    if cs:HasTag(myHrp, "doing action") or myChar:GetAttribute("IsCarried") or myChar:GetAttribute("IsHooked") then
        return
    end

    -- Cek instance ParryClient game: apakah sedang cooldown / resolving
    local parryObj = get_parry_instance()
    if parryObj then
        if parryObj.isParryOnCooldown or parryObj.isParryResolving then
            return -- Sedang cooldown di dalam game!
        end
        if parryObj.CanUse and not parryObj:CanUse() then
            return -- Tidak bisa digunakan (cooldown / busy)
        end
    end

    lastParryTick = now
    isParrying = true
    -- Pasang cooldown awal minimal 3.5s sampai di-update oleh event parryResult
    gameParryCooldownEnd = now + PARRY_COOLDOWN

    -- 1. Auto-Face: Hadapkan badan tepat ke arah killer (0ms snap)
    local toKiller = Vector3.new(killerHrp.Position.X - myHrp.Position.X, 0, killerHrp.Position.Z - myHrp.Position.Z)
    if toKiller.Magnitude > 0.5 then
        myHrp.CFrame = CFrame.new(myHrp.Position, myHrp.Position + toKiller.Unit)
    end

    -- 2. Panggil Method Resmi ParryClient
    local called = false
    if parryObj and parryObj.Parry then
        local ok = pcall(function()
            parryObj:Parry()
        end)
        called = ok
    end

    -- 3. HANYA panggil Remote jika parryObj TIDAK ADA atau GAGAL
    -- (PENTING: Jangan pernah panggil keduanya sekaligus agar tidak terjadi parry 2x)
    if not called then
        pcall(function()
            if not cachedParryRemote then
                local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
                local itemsFolder = remotesFolder and remotesFolder:FindFirstChild("Items")
                local daggerFolder = itemsFolder and itemsFolder:FindFirstChild("Parrying Dagger")
                cachedParryRemote = daggerFolder and daggerFolder:FindFirstChild("parry")
            end
            if cachedParryRemote then
                cachedParryRemote:FireServer()
            end
        end)
    end

    -- Hanya tampil kalau ZYPHERAX_DEBUG = true, karena ini bisa sangat sering.
    log("[AutoParry] PERFECT PARRY! Killer: %s | Jarak: %.1f studs | %s",
        tostring(killerName), dist or 0, reason)

    -- Fallback: reset isParrying setelah PARRY_COOLDOWN detik
    -- (event parryResult akan reset lebih cepat jika server merespons)
    task.delay(PARRY_COOLDOWN, function()
        isParrying = false
    end)
end

local function is_killer_entity(model)
    if not model or not model:IsA("Model") then return false end
    -- [CRITICAL FIX KILLER] Diri sendiri BUKAN target parry!
    local myChar = LocalPlayer and LocalPlayer.Character
    if model == myChar then return false end
    local p = Players:GetPlayerFromCharacter(model)
    if p == LocalPlayer then return false end

    -- 1. Cek Model "Weapon" di karakter (Killer selalu memegang child Model "Weapon")
    if model:FindFirstChild("Weapon") then return true end
    -- 2. Cek CollectionService Tag "Killer"
    local cs = game:GetService("CollectionService")
    if cs:HasTag(model, "Killer") then return true end
    local ok, tags = pcall(function() return cs:GetTags(model) end)
    if ok and tags then
        for _, t in ipairs(tags) do
            if t:lower():find("killer") then return true end
        end
    end
    -- 3. Cek Attribute khas Killer
    if model:GetAttribute("TerrorRadius") or model:GetAttribute("SuspenseRadius")
        or model:GetAttribute("Chasemusic") or model:GetAttribute("BloodLust") then
        return true
    end
    -- 4. Cek Player jika entity adalah karakter Player
    if p then
        local role = p:GetAttribute("CurrentRole") or p:GetAttribute("Role")
        if role and tostring(role):lower() == "killer" then return true end
        if p.Character and p.Character:FindFirstChild("Weapon") then return true end
    end
    return false
end

local function monitorAnimator(animator, ownerModel, ownerName)
    if trackedAnimators[animator] then return end

    -- [CRITICAL FIX KILLER] JANGAN PERNAH monitor animator karakter sendiri!
    local myChar = LocalPlayer and LocalPlayer.Character
    if not ownerModel or ownerModel == myChar then return end
    if ownerName == (LocalPlayer.DisplayName or LocalPlayer.Name) or ownerName == LocalPlayer.Name then return end

    local conn = animator.AnimationPlayed:Connect(function(track)
        if not autoParryEnabled then return end
        -- [CRITICAL FIX KILLER] Jika kita adalah Killer, jangan pernah tangkis!
        if is_local_player_killer and is_local_player_killer() then return end

        local curChar = LocalPlayer and LocalPlayer.Character
        if not curChar or ownerModel == curChar then return end

        -- Cek SEMUA kondisi cooldown sebelum parry
        local now2 = tick()
        if isParrying or (now2 - lastParryTick < PARRY_COOLDOWN) or (now2 < gameParryCooldownEnd) then return end

        -- HANYA AUTO PARRY JIKA ENTITY ADALAH KILLER! JANGAN PARRY JIKA SURVIVOR NEMBAK!
        if not is_killer_entity(ownerModel) then
            return
        end

        local myHrp = curChar:FindFirstChild("HumanoidRootPart") or curChar:FindFirstChild("Torso")
        local killerHrp = ownerModel and (ownerModel:FindFirstChild("HumanoidRootPart") or ownerModel:FindFirstChild("Torso"))

        if not myHrp or not killerHrp then return end

        -- Skip jika killer sedang MEMBAWA survivor (bukan menyerang kita)
        local killerIsCarrying = ownerModel:GetAttribute("IsCarrying") or ownerModel:GetAttribute("Carrying")
        if killerIsCarrying and killerIsCarrying ~= false and killerIsCarrying ~= 0 then
            return -- Killer sedang bawa survi, bukan menyerang
        end
        -- Juga cek apakah kita sedang di-carry
        if curChar:GetAttribute("IsCarried") then
            return
        end

        local dist = (myHrp.Position - killerHrp.Position).Magnitude
        -- Wajib dist > 0.5 agar tidak pernah mendeteksi karakter sendiri
        if dist <= PARRY_DISTANCE and dist > 0.5 then
            -- DIRECTIONAL CHECK: Hanya tangkis jika killer menghadap kita
            local killerLook = killerHrp.CFrame.LookVector
            local killerLookFlat = Vector3.new(killerLook.X, 0, killerLook.Z)
            if killerLookFlat.Magnitude > 0 then killerLookFlat = killerLookFlat.Unit else killerLookFlat = killerLook end

            local toPlayer = (myHrp.Position - killerHrp.Position)
            local toPlayerFlat = Vector3.new(toPlayer.X, 0, toPlayer.Z)
            if toPlayerFlat.Magnitude > 0 then toPlayerFlat = toPlayerFlat.Unit else toPlayerFlat = toPlayer end

            local facingAngle = killerLookFlat:Dot(toPlayerFlat)
            if facingAngle < 0.45 then
                return -- Killer mengayun ke arah lain / membelakangi
            end

            local anim = track.Animation
            local animId = anim and anim.AnimationId or ""
            local cleanId = tostring(animId):match("%d+")
            local animName = (track.Name or ""):lower()

            -- Skip animasi carry / pickup
            local isCarryAnim = animName:find("carry") or animName:find("pickup")
                or animName:find("pick_up") or animName:find("grab") or animName:find("lift")
                or animName:find("drop") or animName:find("throw") or animName:find("release")
            if isCarryAnim then return end

            -- Skip animasi tembakan senjata api / flare
            if animName:find("shoot") or animName:find("gun") or animName:find("fire")
                or animName:find("flare") or animName:find("aim") then
                return
            end

            local isAttack = false
            local reason = ""

            if cleanId and KNOWN_ATTACK_ANIM_IDS[cleanId] then
                isAttack = true
                reason = "ID: " .. cleanId
            elseif animName:find("attack") or animName:find("swing") or animName:find("slash")
                or animName:find("m1") or animName:find("hit") or animName:find("strike") then
                isAttack = true
                reason = "Keyword: " .. animName
            elseif not track.Looped and not IGNORED_LOOP_NAMES[animName] then
                if track.Speed >= 0.4 then
                    isAttack = true
                    reason = string.format("Action Swing (Facing: %.2f)", facingAngle)
                end
            end

            if isAttack then
                execute_perfect_parry(ownerModel, ownerName, reason, dist)
            end
        end
    end)
    trackedAnimators[animator] = conn
end

local function scanAllEntities()
    if not autoParryEnabled then return end
    -- [CRITICAL FIX KILLER] Jika kita adalah Killer, jangan scan & jangan pasang parry!
    if is_local_player_killer and is_local_player_killer() then return end
    local myChar = LocalPlayer and LocalPlayer.Character
    if not myChar then return end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character ~= myChar and is_killer_entity(p.Character) then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            local anim = hum and hum:FindFirstChildOfClass("Animator")
            if anim then monitorAnimator(anim, p.Character, p.DisplayName or p.Name) end
        end
    end

    for _, obj in ipairs(workspace:GetChildren()) do
        if obj:IsA("Model") and obj ~= myChar and is_killer_entity(obj) then
            local p = Players:GetPlayerFromCharacter(obj)
            if p ~= LocalPlayer then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                local anim = hum and hum:FindFirstChildOfClass("Animator")
                if anim then monitorAnimator(anim, obj, obj.Name) end
            end
        end
    end
end

local autoParryDescConn = nil

function autoparry_start()
    if autoParryConn then return end
    -- [CRITICAL FIX KILLER] Jika kita Killer, jangan mulai
    if is_local_player_killer and is_local_player_killer() then
        return
    end
    isParrying = false
    lastParryTick = 0
    gameParryCooldownEnd = 0
    -- Scan awal sekali
    scanAllEntities()
    -- Event-driven: pasang listener saat ada child/descendant baru di workspace
    autoParryDescConn = workspace.DescendantAdded:Connect(function(desc)
        if not autoParryEnabled then return end
        if is_local_player_killer and is_local_player_killer() then return end
        if desc:IsA("Animator") then
            local ownerModel = desc.Parent and desc.Parent.Parent
            local myChar = LocalPlayer and LocalPlayer.Character
            if ownerModel and ownerModel ~= myChar and is_killer_entity(ownerModel) then
                local p = Players:GetPlayerFromCharacter(ownerModel)
                if p ~= LocalPlayer then
                    monitorAnimator(desc, ownerModel, ownerModel.Name)
                end
            end
        end
    end)
    -- Heartbeat hanya untuk re-scan entitas baru secara berkala (jarang)
    local scanTimer2 = 0
    autoParryConn = RunService.Heartbeat:Connect(function(dt)
        if not autoParryEnabled then return end
        if is_local_player_killer and is_local_player_killer() then
            -- Jika kita berubah jadi Killer di tengah match, bersihkan semua listener parry
            cleanup_animator_tracks()
            return
        end
        scanTimer2 = scanTimer2 + dt
        if scanTimer2 >= 3 then
            scanTimer2 = 0
            scanAllEntities()
        end
    end)
end

function autoparry_stop()
    if autoParryConn then
        autoParryConn:Disconnect()
        autoParryConn = nil
    end
    if autoParryDescConn then
        autoParryDescConn:Disconnect()
        autoParryDescConn = nil
    end
    isParrying = false
    cleanup_animator_tracks()
end

-- Watcher: jika peran berubah menjadi Killer di tengah permainan, bersihkan tracking segera
pcall(function()
    local function onRoleChanged()
        pcall(function()
            if is_local_player_killer and is_local_player_killer() then
                cleanup_animator_tracks()
                isParrying = false
            end
        end)
    end
    -- Wrap setiap GetAttributeChangedSignal di pcall tersendiri agar tidak crash jika atribut tidak ada
    pcall(function() LocalPlayer:GetAttributeChangedSignal("CurrentRole"):Connect(onRoleChanged) end)
    pcall(function() LocalPlayer:GetAttributeChangedSignal("Role"):Connect(onRoleChanged) end)
    pcall(function() LocalPlayer:GetAttributeChangedSignal("Team"):Connect(onRoleChanged) end)
    pcall(function() LocalPlayer:GetAttributeChangedSignal("Side"):Connect(onRoleChanged) end)
    pcall(function() LocalPlayer:GetAttributeChangedSignal("CharacterType"):Connect(onRoleChanged) end)
end)


end

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

-- ==============================================================================
-- TAB 2: MAIN (AUTO GENERATOR, AUTO PARRY, AUTO HEAL)
-- ==============================================================================
local TabMain = tabGroup:Tab({ Name = "Main", Image = "lucide/zap" })

local SecAutoGen = TabMain:Section({ Name = "Auto Generator", Side = 1 })
SecAutoGen:Header({ Name = ZypheraxLib:Gradient("Auto Perfect Generator", Color3.fromRGB(72,214,200), Color3.fromRGB(99,130,255)) })

SecAutoGen:Toggle({
    Name = "Aktifkan Auto Perfect Gen",
    Default = false,
    Callback = function(enabled)
        autoGenEnabled = enabled
        if enabled then
            agen_start()
            Window:Notify({ Title = "Auto Perfect Gen", Description = "Aktif! Otomatis Perfect di tengah zona putih.", Lifetime = 3 })
        else
            agen_stop()
            Window:Notify({ Title = "Auto Perfect Gen", Description = "Dimatikan.", Lifetime = 2 })
        end
    end
})


local SecAutoParry = TabMain:Section({ Name = "Auto Parry", Side = 2 })
SecAutoParry:Header({ Name = ZypheraxLib:Gradient("Auto Parry", Color3.fromRGB(232,120,140), Color3.fromRGB(168,120,255)) })

SecAutoParry:Toggle({
    Name = "Aktifkan Auto Parry",
    Default = false,
    Callback = function(enabled)
        autoParryEnabled = enabled
        if enabled then
            if is_local_player_killer and is_local_player_killer() then
                Window:Notify({
                    Title = "Auto Parry",
                    Description = "Kamu sedang bermain sebagai Killer! Auto Parry ditangguhkan agar serangan & skill kamu lancar.",
                    Lifetime = 4
                })
                return
            end
            autoparry_start()
            Window:Notify({ Title = "Auto Parry", Description = "Aktif! Menangkis serangan killer otomatis.", Lifetime = 3 })
        else
            autoparry_stop()
            Window:Notify({ Title = "Auto Parry", Description = "Auto Parry dimatikan.", Lifetime = 2 })
        end
    end
})

-- SEKSI 3: AUTO HEAL
local SecAutoHealMain = TabMain:Section({ Name = "Auto Heal", Side = 1 })
SecAutoHealMain:Header({ Name = ZypheraxLib:Gradient("Auto Heal (Pemulihan Otomatis)", Color3.fromRGB(86,204,158), Color3.fromRGB(72,214,200)) })

SecAutoHealMain:Toggle({
    Name = "Aktifkan Auto Heal",
    Default = false,
    Callback = function(enabled)
        autoHealEnabled = enabled
        if enabled then
            autoheal_start()
            Window:Notify({ Title = "Auto Heal", Description = "Otomatis memulihkan HP!", Lifetime = 3 })
        else
            Window:Notify({ Title = "Auto Heal", Description = "Auto Heal dimatikan.", Lifetime = 2 })
        end
    end
})

SecAutoHealMain:Slider({
    Name = "Interval Heal (x10 = detik)",
    Default = 15,
    Minimum = 5,
    Maximum = 60,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(val)
        HEAL_COOLDOWN = val / 10
    end
})

-- SEKSI: AUTO ESCAPE (BYPASS SURVIVOR WIN)
local SecAutoEscape = TabMain:Section({ Name = "Auto Escape", Side = 2 })
SecAutoEscape:Header({ Name = ZypheraxLib:Gradient("Auto Escape (Bypass Win)", Color3.fromRGB(72,214,200), Color3.fromRGB(140,200,255)) })

-- Pastikan auto-loop dari sesi sebelumnya tidak masih berjalan
autoEscapeEnabled = false
stop_auto_escape()

SecAutoEscape:Button({
    Name = "ESCAPE SEKARANG",
    Callback = function()
        local ok, msg = trigger_instant_escape()
        Window:Notify({
            Title = ok and "Escape diproses" or "Gagal",
            Description = msg or "Error saat escape.",
            Lifetime = 3
        })
    end
})

SecAutoEscape:Label({ Name = "Teleport langsung ke zona keluar. Gerbang otomatis dibuka." })

-- ==============================================================================
-- MODUL CROSSHAIR
-- ==============================================================================
do
local crosshairGui = nil
local crosshairEnabled = false
local crosshairOffsetX = 0
local crosshairOffsetY = 0
local crosshairSize = 20
local crosshairThickness = 2
local crosshairGap = 5
local crosshairColor = Color3.fromRGB(255, 255, 255)
local crosshairOpacity = 1.0
-- Tipe crosshair: "Titik", "Plus", "Keduanya"
local crosshairType = "Plus"

local CROSSHAIR_COLORS = {
    ["Putih"]   = Color3.fromRGB(255, 255, 255),
    ["Merah"]   = Color3.fromRGB(255, 60,  60),
    ["Hijau"]   = Color3.fromRGB(60,  255, 100),
    ["Biru"]    = Color3.fromRGB(60,  160, 255),
    ["Kuning"]  = Color3.fromRGB(255, 230, 50),
    ["Orange"]  = Color3.fromRGB(255, 140, 30),
    ["Pink"]    = Color3.fromRGB(255, 100, 200),
    ["Cyan"]    = Color3.fromRGB(50,  240, 230),
    ["Ungu"]    = Color3.fromRGB(180, 80,  255),
    ["Hitam"]   = Color3.fromRGB(0,   0,   0),
}

local function destroy_crosshair()
    if crosshairGui then
        pcall(function() crosshairGui:Destroy() end)
        crosshairGui = nil
    end
end

local function build_crosshair()
    destroy_crosshair()

    local parent = (gethui and gethui()) or (cloneref and cloneref(CoreGui)) or CoreGui
    local sg = Instance.new("ScreenGui")
    sg.Name = "ZypheraxCrosshair"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 999999
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() sg.IgnoreGuiInset = true end)
    sg.Parent = parent
    crosshairGui = sg

    local function makeBar(w, h, ox, oy)
        local f = Instance.new("Frame")
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.Size = UDim2.fromOffset(w, h)
        f.Position = UDim2.new(0.5, crosshairOffsetX + ox, 0.5, crosshairOffsetY + oy)
        f.BackgroundColor3 = crosshairColor
        f.BackgroundTransparency = 1 - crosshairOpacity
        f.BorderSizePixel = 0
        f.Name = "Bar"
        f.Parent = sg
        Instance.new("UICorner", f).CornerRadius = UDim.new(0, 1)
        return f
    end

    local function makeDot(sizePx)
        local dot = Instance.new("Frame")
        dot.AnchorPoint = Vector2.new(0.5, 0.5)
        dot.Size = UDim2.fromOffset(sizePx, sizePx)
        dot.Position = UDim2.new(0.5, crosshairOffsetX, 0.5, crosshairOffsetY)
        dot.BackgroundColor3 = crosshairColor
        dot.BackgroundTransparency = 1 - crosshairOpacity
        dot.BorderSizePixel = 0
        dot.Name = "Dot"
        dot.Parent = sg
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    end

    if crosshairType == "Titik" then
        -- Hanya tampilkan titik bulat di tengah
        local dotSize = math.max(4, crosshairThickness * 3)
        makeDot(dotSize)
    elseif crosshairType == "Plus" then
        -- Hanya tampilkan garis Plus (+)
        local half = crosshairGap + crosshairSize / 2
        makeBar(crosshairThickness, crosshairSize, 0, -(half + crosshairSize / 2))
        makeBar(crosshairThickness, crosshairSize, 0,  (half + crosshairSize / 2))
        makeBar(crosshairSize, crosshairThickness, -(half + crosshairSize / 2), 0)
        makeBar(crosshairSize, crosshairThickness,  (half + crosshairSize / 2), 0)
    else -- "Keduanya": Plus + Titik tengah
        local half = crosshairGap + crosshairSize / 2
        makeBar(crosshairThickness, crosshairSize, 0, -(half + crosshairSize / 2))
        makeBar(crosshairThickness, crosshairSize, 0,  (half + crosshairSize / 2))
        makeBar(crosshairSize, crosshairThickness, -(half + crosshairSize / 2), 0)
        makeBar(crosshairSize, crosshairThickness,  (half + crosshairSize / 2), 0)
        local dotSize = math.max(4, crosshairThickness * 2 + 1)
        makeDot(dotSize)
    end
end

local function toggle_crosshair(enable)
    crosshairEnabled = enable
    if enable then
        build_crosshair()
    else
        destroy_crosshair()
    end
end

local function update_crosshair()
    if crosshairEnabled then build_crosshair() end
end

-- ==============================================================================
do
-- MODUL 4.6: TWIST OF FATE - ANTI MISS (100% HIT CHANCE) [OPTIMIZED]
-- ==============================================================================
-- DIOPTIMALKAN (Anti Drop FPS):
--   * TIDAK memakai hook __namecall global (penyebab utama drop FPS).
--   * Hanya hook 2 method spesifik: BindableEvent Result.Fire & RemoteEvent Fire.FireServer.
--   * Filter rawequal lebih dulu, jadi closure hanya jalan saat remote TOF ditembak.
--   * Scan module (require) SEKALI saja, bukan di loop.
--   * Patch attribute tiap 3 detik (bukan tiap 1.5 detik).
-- API global (tofAntiMissEnabled, tof_start, tof_stop) tetap sama -> toggle menu aman.
-- ==============================================================================
tofAntiMissEnabled = false
tofRepatchInterval = 3.0
tofMetaHooked      = false

local AM_RESULT, AM_FIRE  = nil, nil
local AM_GUN_TABLE        = nil
local AM_TOOL             = nil
local AM_UPDATE_CONN      = nil
local AM_CHAR_CONN        = nil
local AM_HOOKED           = false
local AM_ORIG_RESULT      = nil
local AM_ORIG_FIRE        = nil

local AM_MISS = {"MissChance","missChance","miss_chance","FailChance","failChance",
                 "GunPenalty","WeaponPenalty","TwistPenalty"}
local AM_HIT  = {"HitChance","hitChance","Accuracy","accuracy","GunAccuracy"}

local function am_is_miss(val)
    if type(val) == "boolean" and val == false then return true end
    if type(val) == "string" then
        local fs = val:lower()
        if fs:find("miss") or fs:find("fail") or fs:find("self") or fs == "false" then
            return true
        end
    end
    if type(val) == "number" and val == 0 then return true end
    if type(val) == "table" then
        for k, v in pairs(val) do
            local ks = tostring(k):lower()
            if ks:find("miss") or ks:find("fail") then
                if v == true or v == 1 then return true end
            elseif ks:find("hit") or ks:find("success") then
                if v == false or v == 0 then return true end
            end
        end
    end
    return false
end

local function am_fix_args(...)
    local n = select("#", ...)
    if n == 0 then return true end
    local out = table.pack(...)
    for i = 1, out.n do
        local v  = out[i]
        local tv = type(v)
        if tv ~= "table" and am_is_miss(v) then
            if tv == "boolean" then
                out[i] = true
            elseif tv == "string" then
                out[i] = "hit"
            elseif tv == "number" then
                out[i] = 1
            end
        elseif tv == "table" and am_is_miss(v) then
            for tk in pairs(v) do
                local tks = tostring(tk):lower()
                if tks:find("miss") or tks:find("fail") then
                    v[tk] = false
                elseif tks:find("hit") or tks:find("success") then
                    v[tk] = true
                end
            end
        end
    end
    return table.unpack(out, 1, out.n)
end

local function am_find_remotes()
    if AM_RESULT and AM_FIRE then return true end
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local items   = remotes and remotes:FindFirstChild("Items")
        local tof     = items and items:FindFirstChild("Twist of Fate")
        if tof then
            AM_RESULT = tof:FindFirstChild("Result")
            AM_FIRE   = tof:FindFirstChild("Fire")
        end
    end)
    return AM_RESULT ~= nil
end

local function am_patch_fields(tbl)
    pcall(function()
        for k, v in pairs(tbl) do
            local ks = tostring(k):lower()
            if type(v) == "number" then
                if ks:find("miss") or ks:find("fail") or ks:find("penalty") then
                    tbl[k] = 0
                elseif ks:find("chance") or ks:find("accuracy") or ks:find("hit") or ks:find("success") then
                    tbl[k] = 100
                end
            elseif type(v) == "boolean" then
                if ks:find("miss") or ks:find("fail") then
                    tbl[k] = false
                elseif ks:find("hit") or ks:find("success") then
                    tbl[k] = true
                end
            end
        end
    end)
end

local function am_scan_modules()
    if AM_GUN_TABLE then
        am_patch_fields(AM_GUN_TABLE)
        return
    end
    pcall(function()
        local modules = ReplicatedStorage:FindFirstChild("Modules")
        local items   = modules and modules:FindFirstChild("Items")
        if items then
            for _, child in ipairs(items:GetChildren()) do
                local cn = child.Name:lower()
                if cn:find("twist") or cn:find("fate") or cn:find("gun") or cn:find("pistol") then
                    local ok, mod = pcall(require, child)
                    if ok and type(mod) == "table" then
                        AM_GUN_TABLE = mod
                        am_patch_fields(mod)
                    end
                end
            end
        end
    end)
end

local function am_patch_attrs()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then return end
    pcall(function()
        for _, k in ipairs(AM_MISS) do
            if char:GetAttribute(k) ~= nil then char:SetAttribute(k, 0) end
        end
        for _, k in ipairs(AM_HIT) do
            if char:GetAttribute(k) ~= nil then char:SetAttribute(k, 100) end
        end
        local tool = AM_TOOL
        if tool and tool.Parent ~= char then AM_TOOL = nil; tool = nil end
        if tool then
            for _, k in ipairs(AM_MISS) do
                if tool:GetAttribute(k) ~= nil then tool:SetAttribute(k, 0) end
            end
            for _, k in ipairs(AM_HIT) do
                if tool:GetAttribute(k) ~= nil then tool:SetAttribute(k, 100) end
            end
        else
            for _, child in ipairs(char:GetChildren()) do
                if child:IsA("Tool") and child.Name:lower():find("twist") then
                    AM_TOOL = child
                    for _, k in ipairs(AM_MISS) do
                        if child:GetAttribute(k) ~= nil then child:SetAttribute(k, 0) end
                    end
                    for _, k in ipairs(AM_HIT) do
                        if child:GetAttribute(k) ~= nil then child:SetAttribute(k, 100) end
                    end
                    break
                end
            end
        end
    end)
end

local function am_install_hooks()
    if AM_HOOKED then return end
    am_find_remotes()

    if hookfunction then
        if AM_RESULT then
            pcall(function()
                AM_ORIG_RESULT = hookfunction(AM_RESULT.Fire, function(self, ...)
                    if not tofAntiMissEnabled or not rawequal(self, AM_RESULT) then
                        return AM_ORIG_RESULT(self, ...)
                    end
                    return AM_ORIG_RESULT(self, am_fix_args(...))
                end)
            end)
        end
        if AM_FIRE then
            pcall(function()
                AM_ORIG_FIRE = hookfunction(AM_FIRE.FireServer, function(self, ...)
                    if not tofAntiMissEnabled or not rawequal(self, AM_FIRE) then
                        return AM_ORIG_FIRE(self, ...)
                    end
                    local n = select("#", ...)
                    if n == 0 then return AM_ORIG_FIRE(self, ...) end
                    local out = table.pack(...)
                    for i = 1, out.n do
                        local v = out[i]
                        if type(v) == "boolean" and v == false then
                            out[i] = true
                        elseif type(v) == "string" then
                            local s = v:lower()
                            if s:find("miss") or s:find("fail") or s:find("self") then
                                out[i] = "hit"
                            end
                        end
                    end
                    return AM_ORIG_FIRE(self, table.unpack(out, 1, out.n))
                end)
            end)
        end
    end

    AM_HOOKED = true
end

function tof_start()
    tofAntiMissEnabled = true
    am_find_remotes()
    am_install_hooks()
    am_scan_modules()       -- sekali saja
    am_patch_attrs()        -- sekali awal

    local lp = game:GetService("Players").LocalPlayer
    if AM_CHAR_CONN then AM_CHAR_CONN:Disconnect() end
    if lp then
        AM_CHAR_CONN = lp.CharacterAdded:Connect(function() AM_TOOL = nil end)
    end

    if AM_UPDATE_CONN then AM_UPDATE_CONN:Disconnect() end
    local t = 0
    AM_UPDATE_CONN = RunService.Heartbeat:Connect(function(dt)
        if not tofAntiMissEnabled then return end
        t = t + dt
        if t >= tofRepatchInterval then
            t = 0
            am_patch_attrs()
        end
    end)
end

function tof_stop()
    tofAntiMissEnabled = false
    if AM_UPDATE_CONN then AM_UPDATE_CONN:Disconnect(); AM_UPDATE_CONN = nil end
    if AM_CHAR_CONN then AM_CHAR_CONN:Disconnect(); AM_CHAR_CONN = nil end
    AM_TOOL = nil
end


end

-- ==============================================================================
-- TAB 2: COMBAT (CROSSHAIR)
-- ==============================================================================
local TabCombat = tabGroup:Tab({ Name = "Combat", Image = "lucide/crosshair" })

local SecCross = TabCombat:Section({ Name = "Crosshair", Side = 1 })
SecCross:Header({ Name = ZypheraxLib:Gradient("Crosshair", Color3.fromRGB(232,120,140), Color3.fromRGB(255,170,120)) })

SecCross:Toggle({
    Name = "Aktifkan Crosshair",
    Default = false,
    Callback = function(enabled)
        toggle_crosshair(enabled)
        Window:Notify({
            Title = "Crosshair",
            Description = enabled and "Crosshair diaktifkan!" or "Crosshair dimatikan.",
            Lifetime = 3
        })
    end
})

-- TIPE CROSSHAIR
SecCross:Dropdown({
    Name = "Tipe Crosshair",
    Default = "Plus",
    Options = { "Titik", "Plus", "Keduanya" },
    Callback = function(selected)
        crosshairType = selected
        update_crosshair()
        Window:Notify({ Title = "Crosshair", Description = "Tipe diubah ke: " .. selected, Lifetime = 2 })
    end
})

-- WARNA CROSSHAIR
SecCross:Dropdown({
    Name = "Warna Crosshair",
    Default = "Putih",
    Options = { "Putih", "Merah", "Kuning", "Hitam", "Biru", "Hijau", "Orange", "Pink", "Cyan", "Ungu" },
    Callback = function(selected)
        local col = CROSSHAIR_COLORS[selected]
        if col then
            crosshairColor = col
            update_crosshair()
            Window:Notify({ Title = "Crosshair", Description = "Warna diubah ke: " .. selected, Lifetime = 2 })
        end
    end
})

-- Ukuran, ketebalan, celah, dan opacity dibuat default (size = 20) dan tidak diubah.
-- Hanya posisi X & Y yang bisa diatur.

-- Posisi X (kiri/kanan dari tengah layar)
SecCross:Slider({
    Name = "Posisi X (Kiri - Kanan)",
    Default = 0,
    Minimum = -500,
    Maximum = 500,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(val)
        crosshairOffsetX = val
        update_crosshair()
    end
})

-- Posisi Y (atas/bawah dari tengah layar)
SecCross:Slider({
    Name = "Posisi Y (Atas - Bawah)",
    Default = 0,
    Minimum = -300,
    Maximum = 300,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(val)
        crosshairOffsetY = val
        update_crosshair()
    end
})

SecCross:Button({
    Name = "Reset Posisi ke Tengah",
    Callback = function()
        crosshairOffsetX = 0
        crosshairOffsetY = 0
        update_crosshair()
        Window:Notify({ Title = "Crosshair", Description = "Posisi crosshair dikembalikan ke tengah layar.", Lifetime = 3 })
    end
})

-- ==============================================================================
-- SECTION: TWIST OF FATE - ANTI MISS
-- ==============================================================================
local SecTOF = TabCombat:Section({ Name = "Twist of Fate (Anti Miss)", Side = 2 })
SecTOF:Header({ Name = ZypheraxLib:Gradient("Twist of Fate - Anti Miss [ULTRA]", Color3.fromRGB(168,120,255), Color3.fromRGB(99,130,255)) })

SecTOF:Toggle({
    Name = "Anti Miss (100% Hit Chance) [ULTRA]",
    Default = false,
    Callback = function(enabled)
        tofAntiMissEnabled = enabled
        if enabled then
            tof_start()
            Window:Notify({
                Title = "⚡ Twist of Fate ULTRA",
                Description = "Anti Miss aktif! Proteksi otomatis 5 layer berjalan.",
                Lifetime = 3
            })
        else
            tof_stop()
            Window:Notify({
                Title = "Twist of Fate",
                Description = "Anti Miss dimatikan.",
                Lifetime = 2
            })
        end
    end
})

-- ==============================================================================
-- SEKSI: INFINITE ITEM CHARGES (UNLIMITED USES)
-- ==============================================================================
local SecInfCharge = TabCombat:Section({ Name = "Infinite Charges", Side = 1 })
SecInfCharge:Header({ Name = ZypheraxLib:Gradient("Infinite Item Charges", Color3.fromRGB(99,130,255), Color3.fromRGB(168,120,255)) })

SecInfCharge:Toggle({
    Name = "Aktifkan Infinite Charges",
    Default = false,
    Callback = function(enabled)
        infiniteChargesEnabled = enabled
        if enabled then
            infinite_charges_start()
            Window:Notify({
                Title = "Infinite Charges",
                Description = "Semua item / tool charges tidak akan pernah habis (999+ uses)!",
                Lifetime = 3
            })
        else
            infinite_charges_stop()
            Window:Notify({
                Title = "Infinite Charges",
                Description = "Infinite Charges dinonaktifkan.",
                Lifetime = 2
            })
        end
    end
})

SecInfCharge:Button({
    Name = "⚡ Refill / Lock Charges Sekarang",
    Callback = function()
        infinite_charges_apply()
        Window:Notify({
            Title = "Refill Selesai",
            Description = "Semua item di inventory telah di-refill ke charges maksimal!",
            Lifetime = 2
        })
    end
})

end -- [End TabCombat]

-- ==============================================================================
-- MODUL ESP Player - Survivor dan Killer
-- ==============================================================================
do
local espPlayerEnabled = false

local ESP_WHITE  = Color3.fromRGB(255, 255, 255)
local ESP_RED    = Color3.fromRGB(255,  50,  50)
local ESP_YELLOW = Color3.fromRGB(255, 200,  50)
local ESP_ORANGE = Color3.fromRGB(255, 120,  30)
local ESP_PURPLE = Color3.fromRGB(200, 100, 255)
local ESP_GREY   = Color3.fromRGB(150, 150, 150)

local CollectionService_ESP = game:GetService("CollectionService")

local function esp_is_killer(char)
    if not char or not char:IsA("Model") then return false end
    if char:FindFirstChild("Weapon") then return true end
    local cs = CollectionService_ESP
    if cs:HasTag(char, "Killer") then return true end
    local ok, tags = pcall(function() return cs:GetTags(char) end)
    if ok and tags then
        for _, t in ipairs(tags) do
            if t:lower():find("killer") then return true end
        end
    end
    if char:GetAttribute("TerrorRadius") or char:GetAttribute("SuspenseRadius")
        or char:GetAttribute("Chasemusic") or char:GetAttribute("BloodLust") then
        return true
    end
    local p = Players:GetPlayerFromCharacter(char)
    if p then
        local role = p:GetAttribute("CurrentRole") or p:GetAttribute("Role")
        if role and tostring(role):lower() == "killer" then return true end
    end
    return false
end

local function esp_get_status(char)
    local ok, hum = pcall(function() return char:FindFirstChildOfClass("Humanoid") end)
    if not ok or not hum then return "?", ESP_GREY end

    -- Cek Hooked via Collection Tag
    local tagOk, tags = pcall(function() return CollectionService_ESP:GetTags(char) end)
    if tagOk and tags then
        for _, tag in ipairs(tags) do
            if tag:lower():find("hook") then
                return "[HK] Hooked", ESP_PURPLE
            end
        end
    end

    -- Cek Hooked via Attribute
    local hookedAttr = char:GetAttribute("IsHooked") or char:GetAttribute("Hooked") or char:GetAttribute("OnHook")
    if hookedAttr == true or hookedAttr == 1 then
        return "[HK] Hooked", ESP_PURPLE
    end

    -- Cek Knocked via Attribute
    local knockedAttr = char:GetAttribute("Knocked")
    if knockedAttr == true or knockedAttr == 1 then
        return "[KO] Knocked", ESP_RED
    end

    -- Fallback via HP
    local hp  = hum.Health
    local maxHp = hum.MaxHealth
    if maxHp <= 0 then return "?", ESP_GREY end
    local ratio = hp / maxHp
    if ratio <= 0   then return "[KO] Knocked", ESP_RED    end
    if ratio < 0.99 then return "[~] Injured",  ESP_ORANGE end
    return "[OK] Aman", ESP_YELLOW
end

local function esp_get_item(char)
    -- Prioritas 1: Attributes pada Player
    local player = Players:GetPlayerFromCharacter(char)
    if player then
        local pAttr = player:GetAttribute("EquippedItem") or player:GetAttribute("Item") 
            or player:GetAttribute("HoldingItem") or player:GetAttribute("CurrentItem") 
            or player:GetAttribute("SelectedTool") or player:GetAttribute("Tool")
        if pAttr and tostring(pAttr) ~= "" and tostring(pAttr) ~= "None" and tostring(pAttr) ~= "nil" then
            return tostring(pAttr)
        end
        -- Fallback: Cek Backpack
        local bp = player:FindFirstChildOfClass("Backpack")
        if bp then
            for _, v in ipairs(bp:GetChildren()) do
                if v:IsA("Tool") and v.Name ~= "" then return v.Name end
            end
        end
    end
    -- Prioritas 2: Tool yang sedang dipegang di Character
    for _, v in ipairs(char:GetChildren()) do
        if v:IsA("Tool") and v.Name ~= "" then return v.Name end
    end
    -- Prioritas 3: Attribute pada Character itu sendiri
    local cAttr = char:GetAttribute("Item") or char:GetAttribute("EquippedItem") 
        or char:GetAttribute("Weapon") or char:GetAttribute("HoldingItem")
    if cAttr and tostring(cAttr) ~= "" and tostring(cAttr) ~= "None" and tostring(cAttr) ~= "nil" then
        return tostring(cAttr)
    end
    return nil
end

local espPlayerTags = {}
local espHighlights = {}

local function esp_set_highlight_player(player, char, color)
    local h = espHighlights[player]
    if not h then
        h = Instance.new("Highlight")
        h.DepthMode        = Enum.HighlightDepthMode.AlwaysOnTop
        h.FillTransparency = 0.65
        h.OutlineTransparency = 0
        espHighlights[player] = h
    end
    h.FillColor    = color
    h.OutlineColor = color
    if h.Parent ~= char then h.Parent = char end
end

local function esp_remove_highlight_player(player)
    if espHighlights[player] then
        pcall(function() espHighlights[player]:Destroy() end)
        espHighlights[player] = nil
    end
end

local function esp_remove_player(player)
    if espPlayerTags[player] then
        if espPlayerTags[player].bbg then
            pcall(function() espPlayerTags[player].bbg:Destroy() end)
        end
        espPlayerTags[player] = nil
    end
    esp_remove_highlight_player(player)
end

local function esp_hide_player(player)
    if espPlayerTags[player] and espPlayerTags[player].bbg then
        espPlayerTags[player].bbg.Enabled = false
    end
    esp_remove_highlight_player(player)
end

local function esp_get_or_create_tag(player, char)
    local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    if not head then return nil end

    local tagData = espPlayerTags[player]
    if tagData and tagData.bbg and tagData.bbg.Parent and tagData.head == head then
        return tagData
    end

    if tagData and tagData.bbg then
        pcall(function() tagData.bbg:Destroy() end)
    end

    local bbg = Instance.new("BillboardGui")
    bbg.Name = "ESP_PlayerTag"
    bbg.Adornee = head
    bbg.AlwaysOnTop = true
    bbg.Size = UDim2.new(0, 240, 0, 38)
    bbg.StudsOffset = Vector3.new(0, 2.5, 0)
    bbg.ResetOnSpawn = false

    -- Baris 1 (Atas): Nama Pemain + Jarak (Selalu Putih)
    local nameLbl = Instance.new("TextLabel")
    nameLbl.Name = "NameLabel"
    nameLbl.Size = UDim2.new(1, 0, 0, 18)
    nameLbl.Position = UDim2.new(0, 0, 0, 0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextSize = 11
    nameLbl.TextColor3 = ESP_WHITE
    nameLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLbl.TextStrokeTransparency = 0
    nameLbl.Text = player.DisplayName
    nameLbl.Parent = bbg

    -- Baris 2 (Bawah): Status di samping Item (Status berwarna, Item putih)
    local infoLbl = Instance.new("TextLabel")
    infoLbl.Name = "InfoLabel"
    infoLbl.Size = UDim2.new(1, 0, 0, 16)
    infoLbl.Position = UDim2.new(0, 0, 0, 18)
    infoLbl.BackgroundTransparency = 1
    infoLbl.Font = Enum.Font.GothamBold
    infoLbl.TextSize = 10
    infoLbl.RichText = true
    infoLbl.TextColor3 = ESP_WHITE
    infoLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
    infoLbl.TextStrokeTransparency = 0
    infoLbl.Text = "[OK] Aman"
    infoLbl.Parent = bbg

    -- Parent ke CoreGui agar label tidak ikut destroy saat karakter mati/respawn
    -- dan AlwaysOnTop benar-benar berfungsi menembus dinding
    pcall(function()
        if gethui then
            bbg.Parent = gethui()
        else
            bbg.Parent = game:GetService("CoreGui")
        end
    end)
    if not bbg.Parent then bbg.Parent = game:GetService("CoreGui") end

    tagData = {
        bbg = bbg,
        nameLbl = nameLbl,
        infoLbl = infoLbl,
        head = head,
    }
    espPlayerTags[player] = tagData
    return tagData
end

local function to_hex_color(col)
    return string.format("#%02X%02X%02X",
        math.clamp(math.floor(col.R * 255), 0, 255),
        math.clamp(math.floor(col.G * 255), 0, 255),
        math.clamp(math.floor(col.B * 255), 0, 255)
    )
end

local function esp_update_player(player)
    if not espPlayerEnabled then esp_hide_player(player); return end

    local char = player.Character
    if not char then esp_hide_player(player); return end

    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    if not root then esp_hide_player(player); return end

    local cam = workspace.CurrentCamera
    local camPos = cam and cam.CFrame and cam.CFrame.Position or Vector3.new(0, 0, 0)
    local dist = (camPos - root.Position).Magnitude

    local tagData = esp_get_or_create_tag(player, char)
    if not tagData then esp_hide_player(player); return end

    tagData.bbg.Enabled = true
    -- Keep adornee synced
    pcall(function()
        local currentHead = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
        if currentHead and tagData.bbg.Adornee ~= currentHead then
            tagData.bbg.Adornee = currentHead
        end
    end)

    if esp_is_killer(char) then
        esp_set_highlight_player(player, char, ESP_RED)
        -- Baris 1 (Atas): Nama Killer (Merah)
        tagData.nameLbl.Text = "[KILLER] " .. player.DisplayName .. " (" .. math.floor(dist) .. "m)"
        tagData.nameLbl.TextColor3 = ESP_RED
        -- Baris 2 (Bawah): Status Killer (Merah)
        tagData.infoLbl.Text = '<font color="#FF3232">[KILLER]</font>'
    else
        local status, statusColor = esp_get_status(char)
        local item = esp_get_item(char)
        esp_set_highlight_player(player, char, ESP_WHITE)

        -- Baris 1 (Atas): Nama Pemain + Jarak (Selalu PUTIH)
        tagData.nameLbl.Text = player.DisplayName .. " (" .. math.floor(dist) .. "m)"
        tagData.nameLbl.TextColor3 = ESP_WHITE

        -- Baris 2 (Bawah): Status di samping Item (Status warna dinamis, Item selalu PUTIH)
        local hex = to_hex_color(statusColor)
        if item and item ~= "" then
            tagData.infoLbl.Text = string.format('<font color="%s">%s</font> <font color="#FFFFFF">| %s</font>', hex, status, item)
        else
            tagData.infoLbl.Text = string.format('<font color="%s">%s</font>', hex, status)
        end
    end
end

local espPlayerConn = nil
local espPlayerRemovingConn = nil

local function start_esp_player()
    if espPlayerConn then return end
    for p in pairs(espPlayerTags) do esp_remove_player(p) end

    if espPlayerRemovingConn then espPlayerRemovingConn:Disconnect() end
    espPlayerRemovingConn = Players.PlayerRemoving:Connect(esp_remove_player)

    local _espPlayerTick = 0
    espPlayerConn = RunService.RenderStepped:Connect(function(dt)
        _espPlayerTick = _espPlayerTick + dt
        if _espPlayerTick < 0.033 then return end -- Throttled to ~30 FPS untuk mencegah drop FPS
        _espPlayerTick = 0
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                pcall(esp_update_player, p)
            end
        end
    end)
end

local function stop_esp_player()
    if espPlayerConn then
        espPlayerConn:Disconnect()
        espPlayerConn = nil
    end
    if espPlayerRemovingConn then espPlayerRemovingConn:Disconnect(); espPlayerRemovingConn = nil end
    for p in pairs(espPlayerTags) do esp_remove_player(p) end
end

-- ==============================================================================
do
-- MODUL ESP GENERATOR
-- ==============================================================================
espGenEnabled = false
local espHighlight    = true   -- selalu aktif
local espMaxDist      = math.huge -- tampilkan semua generator di map tanpa batas jarak

local GEN_KEYWORDS = { "generator", "gen" }
local genData_esp   = {}
local espConn       = nil

local function is_gen_esp(obj)
    -- Hanya terima Model (bukan BasePart individual) agar tidak muncul banyak label
    if not obj:IsA("Model") then return false end
    local n = obj.Name:lower()
    for _, kw in ipairs(GEN_KEYWORDS) do
        if n:find(kw, 1, true) then return true end
    end
    return false
end

local function get_gen_pos(gen)
    if gen:IsA("BasePart") then return gen.Position end
    local pp = gen.PrimaryPart or gen:FindFirstChildOfClass("BasePart")
    if pp then return pp.Position end
    local ok, cf = pcall(function() return gen:GetBoundingBox() end)
    if ok then return cf.Position end
    return nil
end

local function get_gen_progress(gen)
    local curVal = nil
    local maxVal = nil

    -- 1. Cari Nilai Maximum jika ada (misal MaxProgress = 100)
    for _, v in ipairs(gen:GetDescendants()) do
        if v:IsA("NumberValue") or v:IsA("IntValue") then
            local n = v.Name:lower()
            if (n:find("max") or n:find("req") or n:find("goal") or n:find("total")) 
                and (n:find("progress") or n:find("charge") or n:find("repair")) then
                if v.Value > 0 then maxVal = v.Value end
            end
        end
    end

    -- 2. Cari Nilai Progress Saat Ini (Abaikan semua yang mengandung 'max', 'req', 'goal', 'total')
    local BEST_NAMES = { "progress", "currentprogress", "repairprogress", "charge", "repair", "percent" }
    for _, kw in ipairs(BEST_NAMES) do
        for _, v in ipairs(gen:GetDescendants()) do
            if v:IsA("NumberValue") or v:IsA("IntValue") then
                local n = v.Name:lower()
                if not (n:find("max") or n:find("req") or n:find("goal") or n:find("total")) then
                    if n == kw or n:find(kw, 1, true) then
                        curVal = v.Value
                        break
                    end
                end
            end
        end
        if curVal ~= nil then break end
    end

    -- 3. Cari dari Attributes jika belum ketemu
    if curVal == nil then
        local ok, attrs = pcall(function() return gen:GetAttributes() end)
        if ok and attrs then
            for attrName, av in pairs(attrs) do
                if type(av) == "number" then
                    local n = attrName:lower()
                    if not (n:find("max") or n:find("req") or n:find("goal") or n:find("total")) then
                        if n:find("progress") or n:find("charge") or n:find("repair") or n:find("percent") then
                            curVal = av
                            break
                        end
                    end
                end
            end
        end
    end

    -- Kalkulasi persentase yang benar
    if curVal ~= nil then
        if maxVal and maxVal > 0 then
            return math.clamp((curVal / maxVal) * 100, 0, 100)
        elseif curVal > 0 and curVal <= 1 then
            return math.clamp(curVal * 100, 0, 100)
        elseif curVal >= 0 and curVal <= 100 then
            return math.clamp(curVal, 0, 100)
        end
    end

    return nil
end

local ESP_GEN_COLOR = Color3.fromRGB(100, 200, 255) -- Biru tetap, tidak berubah

local function esp_has_registered_ancestor(obj)
    local p = obj.Parent
    while p and p ~= workspace do
        if genData_esp[p] then return true end
        p = p.Parent
    end
    return false
end

local function esp_setup_gen(gen)
    if genData_esp[gen] then return end
    if esp_has_registered_ancestor(gen) then return end

    local part = gen:FindFirstChildWhichIsA("BasePart") or gen.PrimaryPart
    local h = nil
    if espHighlight and gen:IsA("Model") then
        h = Instance.new("Highlight")
        h.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
        h.FillColor           = ESP_GEN_COLOR
        h.OutlineColor        = ESP_GEN_COLOR
        h.FillTransparency    = 0.65
        h.OutlineTransparency = 0
        h.Parent              = gen
    end

    local bbg = nil
    local pctLbl = nil
    if part then
        bbg = Instance.new("BillboardGui")
        bbg.Name = "ESP_GenTag"
        bbg.Adornee = part
        bbg.AlwaysOnTop = true
        bbg.Size = UDim2.new(0, 100, 0, 26)
        bbg.StudsOffset = Vector3.new(0, 6.0, 0)
        bbg.ResetOnSpawn = false

        pctLbl = Instance.new("TextLabel")
        pctLbl.Name = "PctLabel"
        pctLbl.Size = UDim2.new(1, 0, 1, 0)
        pctLbl.BackgroundTransparency = 1
        pctLbl.Font = Enum.Font.GothamBold
        pctLbl.TextSize = 14
        pctLbl.TextColor3 = ESP_GEN_COLOR
        pctLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
        pctLbl.Text = gen.Name .. "\n" .. "0%"
        pctLbl.Parent = bbg

        bbg.Parent = part
    end

    genData_esp[gen] = {
        bbg = bbg,
        pctLbl = pctLbl,
        highlight = h,
        part = part,
    }
end

local function esp_remove_gen(gen)
    local e = genData_esp[gen]
    if not e then return end
    if e.bbg then pcall(function() e.bbg:Destroy() end) end
    if e.highlight then pcall(function() e.highlight:Destroy() end) end
    genData_esp[gen] = nil
end

local function esp_hide_all()
    for _, e in pairs(genData_esp) do
        if e.bbg then pcall(function() e.bbg.Enabled = false end) end
        if e.highlight then pcall(function() e.highlight.FillTransparency = 1; e.highlight.OutlineTransparency = 1 end) end
    end
end

local function esp_scan()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if is_gen_esp(obj) then esp_setup_gen(obj) end
    end
    for g in pairs(genData_esp) do
        if not g.Parent then esp_remove_gen(g) end
    end
end

function start_esp_gen()
    if espConn then return end
    esp_scan()
    local scanTimer = 0
    espConn = RunService.RenderStepped:Connect(function(dt)
        scanTimer = scanTimer + dt
        if scanTimer >= 5 then
            scanTimer = 0
            esp_scan()
        end

        local cam = workspace.CurrentCamera
        local camPos = cam and cam.CFrame and cam.CFrame.Position or Vector3.new(0, 0, 0)

        for gen, e in pairs(genData_esp) do
            if not gen.Parent or not espGenEnabled then
                if e.bbg then e.bbg.Enabled = false end
                if e.highlight then e.highlight.FillTransparency = 1; e.highlight.OutlineTransparency = 1 end
            else
                local pos = get_gen_pos(gen)
                if not pos then
                    if e.bbg then e.bbg.Enabled = false end
                else
                    local dist = (camPos - pos).Magnitude
                    if espMaxDist > 0 and dist > espMaxDist then
                        if e.bbg then e.bbg.Enabled = false end
                    else
                        local progress = get_gen_progress(gen)
                        local label    = progress and string.format("%.0f%%", progress) or "0%"

                        if e.highlight then
                            e.highlight.FillTransparency    = espHighlight and 0.65 or 1
                            e.highlight.OutlineTransparency = espHighlight and 0   or 1
                        end

                        if e.bbg and e.pctLbl then
                            e.pctLbl.Text = label
                            e.bbg.Enabled = true
                        end
                    end
                end
            end
        end
    end)
end

function stop_esp_gen()
    if espConn then
        espConn:Disconnect()
        espConn = nil
    end
    esp_hide_all()
end


end

-- ==============================================================================
-- TAB 3: ESP
-- ==============================================================================
local TabESP = tabGroup:Tab({ Name = "ESP", Image = "lucide/eye" })

local SecESPPlayer = TabESP:Section({ Name = "ESP Player", Side = 1 })
SecESPPlayer:Header({ Name = ZypheraxLib:Gradient("ESP Player - Survivor dan Killer", Color3.fromRGB(232,120,140), Color3.fromRGB(255,160,120)) })

SecESPPlayer:Toggle({
    Name = "Aktifkan ESP Player",
    Default = false,
    Callback = function(enabled)
        espPlayerEnabled = enabled
        if enabled then
            start_esp_player()
            Window:Notify({ Title = "ESP Player", Description = "ESP Player aktif! Putih=Survivor, Merah=Killer.", Lifetime = 3 })
        else
            stop_esp_player()
            Window:Notify({ Title = "ESP Player", Description = "ESP Player dimatikan.", Lifetime = 3 })
        end
    end
})

local SecESPGen = TabESP:Section({ Name = "ESP Generator", Side = 2 })
SecESPGen:Header({ Name = ZypheraxLib:Gradient("ESP Generator", Color3.fromRGB(86,204,158), Color3.fromRGB(99,130,255)) })

SecESPGen:Toggle({
    Name = "Aktifkan ESP Generator",
    Default = false,
    Callback = function(enabled)
        espGenEnabled = enabled
        if enabled then
            start_esp_gen()
            Window:Notify({ Title = "ESP Generator", Description = "ESP aktif! Semua generator di map terlihat.", Lifetime = 3 })
        else
            stop_esp_gen()
            Window:Notify({ Title = "ESP Generator", Description = "ESP Generator dimatikan.", Lifetime = 3 })
        end
    end
})


-- SEKSI ESP EXIT GATE (tambah ke TabESP)
local SecESPGate = TabESP:Section({ Name = "ESP Gate & Exit", Side = 1 })
SecESPGate:Header({ Name = ZypheraxLib:Gradient("ESP Pintu Keluar (Exit Gate)", Color3.fromRGB(240,190,100), Color3.fromRGB(232,150,110)) })

SecESPGate:Toggle({
    Name = "Aktifkan ESP Exit Gate",
    Default = false,
    Callback = function(enabled)
        espGateEnabled = enabled
        if enabled then
            start_esp_gate()
            Window:Notify({ Title = "ESP Gate", Description = "Pintu keluar terlihat dari mana saja!", Lifetime = 3 })
        else
            stop_esp_gate()
            Window:Notify({ Title = "ESP Gate", Description = "ESP Exit Gate dimatikan.", Lifetime = 2 })
        end
    end
})


-- SEKSI KILLER RADAR (digabung dari tab Radar)
local SecRadar = TabESP:Section({ Name = "Radar Killer", Side = 1 })
SecRadar:Header({ Name = ZypheraxLib:Gradient("Killer Radar (Mini-Map)", Color3.fromRGB(232,100,120), Color3.fromRGB(200,120,180)) })

SecRadar:Toggle({
    Name = "Aktifkan Killer Radar",
    Default = false,
    Callback = function(enabled)
        killerRadarEnabled = enabled
        if enabled then
            killerradar_start()
            Window:Notify({ Title = "Killer Radar", Description = "Merah=Killer | Biru=Survivor. Radar aktif!", Lifetime = 3 })
        else
            killerradar_stop()
            Window:Notify({ Title = "Killer Radar", Description = "Radar dimatikan.", Lifetime = 2 })
        end
    end
})

SecRadar:Slider({
    Name = "Jangkauan Radar (Studs)",
    Default = 350,
    Minimum = 50,
    Maximum = 1000,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(val)
        RADAR_RANGE = val
    end
})

SecRadar:Label({ Name = "Tampil otomatis: Hijau = Kamu, Merah = Killer, Biru = Survivor." })

local SecRadarInfo = TabESP:Section({ Name = "Info Radar", Side = 2 })
SecRadarInfo:Header({ Name = ZypheraxLib:Gradient("Cara Baca Radar", Color3.fromRGB(140,152,190), Color3.fromRGB(120,170,200)) })
SecRadarInfo:Label({ Name = "Titik Hijau = Kamu sendiri" })
SecRadarInfo:Label({ Name = "Titik Merah = Killer (ukuran besar)" })
SecRadarInfo:Label({ Name = "Titik Biru = Survivor (ukuran kecil)" })
SecRadarInfo:Label({ Name = "Radar mengikuti arah kamera kamu." })

end -- [End TabESP]



-- ==============================================================================
-- TAB: VIEW (FULLBRIGHT + CUSTOM FOV)
-- ==============================================================================
do
local TabView = tabGroup:Tab({ Name = "View", Image = "lucide/sun" })

-- SEKSI 1: FULLBRIGHT + NO FOG
local SecFB = TabView:Section({ Name = "Fullbright", Side = 1 })
SecFB:Header({ Name = ZypheraxLib:Gradient("Fullbright & No Fog", Color3.fromRGB(240,190,100), Color3.fromRGB(255,200,130)) })

SecFB:Toggle({
    Name = "Aktifkan Fullbright + No Fog",
    Default = false,
    Callback = function(enabled)
        fullbrightEnabled = enabled
        if enabled then
            fullbright_start()
            Window:Notify({ Title = "Fullbright", Description = "Map terang sempurna! Semua fog dihapus.", Lifetime = 3 })
        else
            fullbright_stop()
            Window:Notify({ Title = "Fullbright", Description = "Fullbright dimatikan. Lighting normal.", Lifetime = 2 })
        end
    end
})

-- SEKSI 2: CUSTOM FOV
local SecFov = TabView:Section({ Name = "Custom FOV", Side = 2 })
SecFov:Header({ Name = ZypheraxLib:Gradient("Custom FOV (Field of View)", Color3.fromRGB(99,130,255), Color3.fromRGB(140,200,255)) })

SecFov:Toggle({
    Name = "Aktifkan Custom FOV",
    Default = false,
    Callback = function(enabled)
        customFovEnabled = enabled
        if enabled then
            fov_start(customFovValue)
            Window:Notify({ Title = "Custom FOV", Description = "FOV diubah ke " .. tostring(customFovValue) .. "!", Lifetime = 3 })
        else
            fov_stop()
            Window:Notify({ Title = "Custom FOV", Description = "FOV dikembalikan normal (70).", Lifetime = 2 })
        end
    end
})

SecFov:Slider({
    Name = "FOV Value (derajat)",
    Default = 70,
    Minimum = 40,
    Maximum = 120,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(val)
        customFovValue = val
        if customFovEnabled then
            fov_apply(val)
        end
    end
})

SecFov:Button({
    Name = "Reset FOV ke Default (70)",
    Callback = function()
        customFovValue = 70
        if customFovEnabled then fov_apply(70) end
        Window:Notify({ Title = "FOV", Description = "FOV direset ke 70.", Lifetime = 2 })
    end
})
end -- [End TabView]


-- ==============================================================================
-- TAB: DISCORD WEBHOOK NOTIFIER
-- ==============================================================================
do
local TabWebhook = tabGroup:Tab({ Name = "Webhook", Image = "lucide/bell" })

local SecWHUrl = TabWebhook:Section({ Name = "Webhook Discord", Side = 1 })
SecWHUrl:Header({ Name = ZypheraxLib:Gradient("Discord Webhook Notifier", Color3.fromRGB(99,130,255), Color3.fromRGB(72,214,200)) })

SecWHUrl:Input({
    Name = "URL Webhook Discord",
    Placeholder = "https://discord.com/api/webhooks/...",
    Default = webhookUrl or "",
    Callback = function(val)
        webhookUrl = val or ""
        save_webhook_settings()
    end
})

SecWHUrl:Toggle({
    Name = "Auto Webhook (Kirim Saat Escaped / Selesai)",
    Default = true,
    Callback = function(enabled)
        webhookNotifyMatch = enabled
        save_webhook_settings()
        if enabled then
            start_webhook_live_monitor()
            Window:Notify({ Title = "Webhook", Description = "Aktif! Summary otomatis dikirim setelah berhasil escaped.", Lifetime = 3 })
        else
            stop_webhook_live_monitor()
            Window:Notify({ Title = "Webhook", Description = "Notifikasi match dimatikan.", Lifetime = 2 })
        end
    end
})

SecWHUrl:Button({
    Name = "Kirim Test Webhook",
    Callback = function()
        local ok, res = send_discord_webhook(
            "Test Webhook",
            "**Zypherax Hub** terhubung ke Discord kamu! Webhook berfungsi dengan baik.",
            "57F287"
        )
        Window:Notify({
            Title = ok and "Webhook Terkirim!" or "Gagal",
            Description = ok and "Pesan test berhasil dikirim ke Discord." or tostring(res),
            Lifetime = 4
        })
    end
})

local SecWHInfo = TabWebhook:Section({ Name = "Petunjuk Webhook", Side = 2 })
SecWHInfo:Header({ Name = ZypheraxLib:Gradient("Petunjuk Webhook", Color3.fromRGB(140,152,190), Color3.fromRGB(120,170,200)) })
SecWHInfo:Label({ Name = "Webhook otomatis mengirim summary setelah kamu berhasil Escaped." })
SecWHInfo:Label({ Name = "Format persis seperti contoh: Status, Username (sensor Sk***), Level, Sin, EXP, Screws, Gears, Match Time, Maps, Total, Server ID." })
SecWHInfo:Label({ Name = "URL Webhook tersimpan otomatis di executor sehingga tidak hilang saat ganti server." })

end -- [End TabWebhook]

-- ==============================================================================
-- TAB 4: MODIFIKASI (VERTIKAL SCROLL KE BAWAH)
-- ==============================================================================
do
local TabMod = tabGroup:Tab({ Name = "Modifikasi", Image = "lucide/sparkles" })


-- SEKSI 1: SALIN AVATAR PEMAIN
local SecAvatar = TabMod:Section({ Name = "Avatar Swap", Side = 1 })
SecAvatar:Header({ Name = ZypheraxLib:Gradient("Salin Avatar Pemain", Color3.fromRGB(99,130,255), Color3.fromRGB(168,120,255)) })

SecAvatar:Input({
    Name = "Target di Server",
    Default = "",
    Placeholder = "Kosongkan untuk diri sendiri...",
    Callback = function(text) swap_target = text end,
    onChanged = function(text) swap_target = text end,
})

SecAvatar:Input({
    Name = "Username Avatar Roblox",
    Default = "usnavatar",
    Placeholder = "Ketik username avatar Roblox...",
    Callback = function(text) swap_avatar = text end,
    onChanged = function(text) swap_avatar = text end,
})

SecAvatar:Button({
    Name = "Terapkan Avatar",
    Bold = true,
    Callback = function()
        Window:Notify({ Title = "Avatar Swap", Description = "Memproses penyalinan avatar...", Lifetime = 3 })
        task.spawn(function()
            local success, msg = apply_avatar_swap(swap_target, swap_avatar)
            Window:Notify({
                Title = success and "Berhasil!" or "Gagal!",
                Description = msg or "",
                Lifetime = 4
            })
        end)
    end,
})

SecAvatar:Button({
    Name = "Reset Avatar Normal",
    Callback = function()
        local success, msg = reset_avatar_swap(swap_target)
        Window:Notify({
            Title = "Reset Avatar",
            Description = msg or "",
            Lifetime = 4
        })
    end,
})

-- SEKSI 2: KLONING OUTFIT TERSIMPAN
local SecOutfit = TabMod:Section({ Name = "Outfit Clone", Side = 2 })
SecOutfit:Header({ Name = ZypheraxLib:Gradient("Kloning Outfit Tersimpan", Color3.fromRGB(232,110,170), Color3.fromRGB(168,120,255)) })

SecOutfit:Input({
    Name = "Username Pemilik Outfit",
    Default = "zhbrxty",
    Placeholder = "Contoh: zhbrxty",
    Callback = function(text) outfit_owner = text end,
    onChanged = function(text) outfit_owner = text end,
})

SecOutfit:Input({
    Name = "Nama / ID Outfit",
    Default = "cp 1",
    Placeholder = "Contoh: cp 1 atau ID outfit...",
    Callback = function(text) outfit_name = text end,
    onChanged = function(text) outfit_name = text end,
})

SecOutfit:Input({
    Name = "Target di Server",
    Default = "",
    Placeholder = "Kosongkan untuk diri sendiri...",
    Callback = function(text) outfit_target = text end,
    onChanged = function(text) outfit_target = text end,
})

SecOutfit:Button({
    Name = "Pasang Outfit ke Target",
    Bold = true,
    Callback = function()
        Window:Notify({ Title = "Outfit Cloner", Description = "Mengambil data outfit...", Lifetime = 3 })
        task.spawn(function()
            local success, msg = apply_outfit(outfit_owner, outfit_name, outfit_target)
            Window:Notify({
                Title = success and "Berhasil!" or "Gagal!",
                Description = msg or "",
                Lifetime = 4
            })
        end)
    end,
})

-- SEKSI 3: PEMUAT AKSESORIS CATALOG
local SecAcc = TabMod:Section({ Name = "Catalog Accessories", Side = 1 })
SecAcc:Header({ Name = ZypheraxLib:Gradient("Pemuat Aksesoris Catalog", Color3.fromRGB(86,204,158), Color3.fromRGB(120,160,255)) })

local acc_offset_y = 0
local acc_offset_z = 0
local acc_offset_x = 0
local acc_scale = 1.0

SecAcc:Input({
    Name = "Target di Server",
    Default = "",
    Placeholder = "Kosongkan untuk diri sendiri...",
    Callback = function(text) acc_target = text end,
    onChanged = function(text) acc_target = text end,
})

SecAcc:Input({
    Name = "Roblox Catalog Asset ID",
    Default = "10159600649",
    Placeholder = "Contoh: 10159600649",
    Callback = function(text) acc_id = text end,
    onChanged = function(text) acc_id = text end,
})

SecAcc:Slider({
    Name = "Atas / Bawah (Y Offset)",
    Default = 0,
    Minimum = -30,
    Maximum = 30,
    DisplayMethod = "Round",
    Precision = 1,
    Callback = function(val)
        acc_offset_y = val / 10
    end
})

SecAcc:Slider({
    Name = "Depan / Belakang (Z Offset)",
    Default = 0,
    Minimum = -30,
    Maximum = 30,
    DisplayMethod = "Round",
    Precision = 1,
    Callback = function(val)
        acc_offset_z = val / 10
    end
})

SecAcc:Slider({
    Name = "Kiri / Kanan (X Offset)",
    Default = 0,
    Minimum = -30,
    Maximum = 30,
    DisplayMethod = "Round",
    Precision = 1,
    Callback = function(val)
        acc_offset_x = val / 10
    end
})

SecAcc:Slider({
    Name = "Ukuran / Scale (Besar - Kecil)",
    Default = 10,
    Minimum = 2,
    Maximum = 30,
    DisplayMethod = "Round",
    Precision = 1,
    Callback = function(val)
        acc_scale = val / 10
    end
})

SecAcc:Button({
    Name = "Pasang Aksesoris",
    Bold = true,
    Callback = function()
        Window:Notify({ Title = "Aksesoris", Description = "Memuat aksesoris...", Lifetime = 3 })
        task.spawn(function()
            local success, msg = add_accessory(acc_target, acc_id, acc_offset_x, acc_offset_y, acc_offset_z, acc_scale)
            Window:Notify({
                Title = success and "Berhasil!" or "Gagal!",
                Description = msg or "",
                Lifetime = 4
            })
        end)
    end,
})

SecAcc:Button({
    Name = "Terapkan Posisi & Ukuran (Live Update)",
    Callback = function()
        local success, msg = update_accessory_transform(acc_target, acc_id, acc_offset_x, acc_offset_y, acc_offset_z, acc_scale)
        Window:Notify({
            Title = "Posisi Aksesoris",
            Description = msg or "",
            Lifetime = 3
        })
    end,
})

SecAcc:Button({
    Name = "Hapus Aksesoris (ID / Nama)",
    Callback = function()
        local success, msg = remove_accessory(acc_target, acc_id)
        Window:Notify({
            Title = "Aksesoris",
            Description = msg or "",
            Lifetime = 4
        })
    end,
})

SecAcc:Button({
    Name = "Hapus Semua Aksesoris Custom",
    Callback = function()
        local success, msg = remove_all_accessories(acc_target)
        Window:Notify({
            Title = "Aksesoris",
            Description = msg or "",
            Lifetime = 4
        })
    end,
})

-- SEKSI 4: KORBLOX & HEADLESS
local SecBody = TabMod:Section({ Name = "Korblox & Headless", Side = 2 })
SecBody:Header({ Name = ZypheraxLib:Gradient("Korblox & Headless", Color3.fromRGB(232,130,110), Color3.fromRGB(200,110,150)) })

local korblox_offset = 0.7

SecBody:Input({
    Name = "Target di Server",
    Default = "",
    Placeholder = "Kosongkan untuk diri sendiri...",
    Callback = function(text) mod_target = text end,
    onChanged = function(text) mod_target = text end,
})

SecBody:Input({
    Name = "Korblox Y Offset",
    Default = "0.7",
    Placeholder = "Default: 0.7 (sesuai contoh pas)",
    Callback = function(text) korblox_offset = tonumber(text) or 0.7 end,
    onChanged = function(text) korblox_offset = tonumber(text) or 0.7 end,
})

SecBody:Button({
    Name = "Pasang Korblox Leg (Khusus R6)",
    Bold = true,
    Callback = function()
        Window:Notify({ Title = "Korblox", Description = "Memasang Korblox leg...", Lifetime = 3 })
        task.spawn(function()
            local success, msg = apply_korblox(mod_target, 139607718, korblox_offset)
            Window:Notify({
                Title = success and "Berhasil!" or "Gagal!",
                Description = msg or "",
                Lifetime = 4
            })
        end)
    end,
})

SecBody:Button({
    Name = "Hapus Korblox Leg",
    Callback = function()
        local success, msg = remove_korblox(mod_target)
        Window:Notify({
            Title = "Korblox",
            Description = msg or "",
            Lifetime = 4
        })
    end,
})

SecBody:Button({
    Name = "Pasang Headless",
    Bold = true,
    Callback = function()
        local success, msg = apply_headless(mod_target)
        Window:Notify({
            Title = success and "Berhasil!" or "Gagal!",
            Description = msg or "",
            Lifetime = 4
        })
    end,
})

SecBody:Button({
    Name = "Hapus Headless",
    Callback = function()
        local success, msg = remove_headless(mod_target)
        Window:Notify({
            Title = "Headless",
            Description = msg or "",
            Lifetime = 4
        })
    end,
})
end -- [End TabMod]

-- ==============================================================================
-- TAB 3: PENGATURAN & TEMA
-- ==============================================================================
tabGroup:Divider()
do
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

SecTheme:Toggle({
    Name = "Tampilkan Info User",
    Default = Window:GetUserInfoState(),
    Callback = function(bool)
        Window:SetUserInfoState(bool)
    end
})

-- Toggle warna header: gradient warna-warni vs putih/hitam polos
local headerColorMode = "gradient"

local function findWmacGuis()
    local found = {}
    local containers = {}
    pcall(function() if gethui then table.insert(containers, gethui()) end end)
    pcall(function() table.insert(containers, CoreGui) end)
    pcall(function()
        if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then
            table.insert(containers, LocalPlayer.PlayerGui)
        end
    end)

    for _, container in ipairs(containers) do
        for _, sg in ipairs(container:GetChildren()) do
            if sg:IsA("ScreenGui") then
                if sg:FindFirstChild("Notifications") or sg.Name:lower():find("zypherax") or sg.Name:lower():find("mac") then
                    table.insert(found, sg)
                else
                    for _, desc in ipairs(sg:GetDescendants()) do
                        if desc:IsA("TextLabel") and (desc.Text:find("Zypherax") or desc.Text:find("Modifikasi") or desc.Text:find("Korblox")) then
                            table.insert(found, sg)
                            break
                        end
                    end
                end
            end
        end
    end
    return found
end

local function applyHeaderColor(mode)
    pcall(function()
        local guis = findWmacGuis()
        for _, target in ipairs(guis) do
            -- Listener otomatis bila ada header / TextLabel baru yang dimuat
            if not target:GetAttribute("HeaderColorHooked") then
                target:SetAttribute("HeaderColorHooked", true)
                target.DescendantAdded:Connect(function(d)
                    if d:IsA("TextLabel") and headerColorMode ~= "gradient" then
                        task.wait(0.05)
                        local txt = d.Text
                        if txt:find("<font color=") or d:GetAttribute("OrigHeaderRichText") then
                            if not d:GetAttribute("OrigHeaderRichText") then
                                d:SetAttribute("OrigHeaderRichText", txt)
                            end
                            local clean = d:GetAttribute("OrigHeaderRichText"):gsub("<[^>]->", "")
                            if headerColorMode == "white" then
                                d.Text = string.format('<font color="rgb(255,255,255)">%s</font>', clean)
                            elseif headerColorMode == "black" then
                                d.Text = string.format('<font color="rgb(20,20,20)">%s</font>', clean)
                            end
                        end
                    end
                end)
            end

            for _, obj in ipairs(target:GetDescendants()) do
                if obj:IsA("TextLabel") then
                    -- ZypheraxLib:Gradient menghasilkan rich text dengan tag <font color="rgb(...)"> per huruf
                    local txt = obj.Text
                    if txt:find("<font color=") or obj:GetAttribute("OrigHeaderRichText") then
                        if not obj:GetAttribute("OrigHeaderRichText") then
                            obj:SetAttribute("OrigHeaderRichText", txt)
                        end
                        local orig = obj:GetAttribute("OrigHeaderRichText")
                        local clean = orig:gsub("<[^>]->", "")

                        if mode == "white" then
                            obj.Text = string.format('<font color="rgb(255,255,255)">%s</font>', clean)
                        elseif mode == "black" then
                            obj.Text = string.format('<font color="rgb(20,20,20)">%s</font>', clean)
                        else
                            obj.Text = orig
                        end
                    end
                end
            end
        end
    end)
end

SecTheme:Dropdown({
    Name = "Warna Teks Header",
    Options = { "Gradient (Warna-warni)", "Putih Polos", "Hitam Polos" },
    Default = "Gradient (Warna-warni)",
    Callback = function(choice)
        if choice == "Putih Polos" then
            headerColorMode = "white"
        elseif choice == "Hitam Polos" then
            headerColorMode = "black"
        else
            headerColorMode = "gradient"
        end
        applyHeaderColor(headerColorMode)
        Window:Notify({ Title = "Teks Header", Description = "Warna teks diubah: " .. choice, Lifetime = 3 })
    end
})

-- ==============================================================================
-- SEKSI 2: WATERMARK & WINDOW
-- ==============================================================================
local SecWin = TabConfig:Section({ Name = "Window & Watermark", Side = 2 })
SecWin:Header({ Name = ZypheraxLib:Gradient("Jendela & Kontrol", Color3.fromRGB(99,130,255), Color3.fromRGB(168,120,255)) })

-- Toggle log diagnostik.
-- Matikan = console bersih. Nyalakan = semua detail fitur tampil lagi,
-- berguna kalau ada fitur yang tidak bekerja dan perlu diperiksa.
SecWin:Toggle({
    Name = "Log Detail (Debug)",
    Default = false,
    Callback = function(enabled)
        ZYPHERAX_DEBUG = enabled
        Window:Notify({
            Title = "Log Detail",
            Description = enabled
                and "Log detail ON. Semua output diagnostik akan muncul di console (F9)."
                or "Log detail OFF. Console hanya menampilkan hasil akhir.",
            Lifetime = 3
        })
    end
})

-- Salin log ke clipboard.
-- Kalau ada fitur yang bermasalah, user bisa nyalakan Log Detail,
-- pakai fitur, lalu tekan tombol ini dan paste hasilnya ke chat.
SecWin:Button({
    Name = "Salin Log Terakhir",
    Callback = function()
        if not ZYPHERAX_DEBUG then
            Window:Notify({
                Title = "Log Kosong",
                Description = "Nyalakan Log Detail (Debug) dulu supaya ada yang bisa disalin.",
                Lifetime = 3
            })
            return
        end
        pcall(function()
            setclipboard(ZYPHERAX_LOG_BUFFER)
        end)
        Window:Notify({
            Title = "Log Disalin",
            Description = "Log sudah masuk clipboard, siap di-paste.",
            Lifetime = 3
        })
    end
})

-- Widget Watermark lama dihapus; floating toggle ORB tetap ada untuk membuka UI kembali
pcall(function()
    local core = (gethui and gethui()) or (cloneref and cloneref(game:GetService("CoreGui"))) or game:GetService("CoreGui")
    local oldWm = core:FindFirstChild("ZypheraxWatermarkGui")
    if oldWm then oldWm:Destroy() end
end)

SecWin:Slider({
    Name = "Ukuran Jendela (Window Size)",
    Default = 50,
    Minimum = 0,
    Maximum = 100,
    DisplayMethod = "Percent",
    Precision = 0,
    Callback = function(value)
        local t = value / 100
        Window:SetSize(UDim2.fromOffset(450 + (900 - 450) * t, 350 + (650 - 350) * t))
    end
})

SecWin:Keybind({
    Name = "Shortcut Buka / Tutup Menu",
    Default = Enum.KeyCode.RightControl,
    onBinded = function(bind)
        Window:SetKeybind(bind)
        Window:Notify({ Title = "Keybind", Description = "Tombol toggle: " .. tostring(bind.Name), Lifetime = 3 })
    end
})

-- Welcome. Notifikasi dibuat singkat supaya tidak intrusive,
-- karena user tinggal melihat UI-nya untuk tahu fitur apa saja.
Window:Notify({
    Title = "Zypherax Hub siap",
    Description = "Tekan RightControl untuk buka / tutup menu.",
    Lifetime = 4
})

-- Hanya muncul kalau ZYPHERAX_DEBUG = true
log("Zypherax Hub (Violence District - 8 Tabs) berhasil dijalankan")
end -- [End TabConfig]


-- Aliases
start_auto_heal = autoheal_start
stop_auto_heal = autoheal_stop
start_auto_generator = agen_start
stop_auto_generator = agen_stop
start_auto_parry = autoparry_start
stop_auto_parry = autoparry_stop
start_esp_generator = start_esp_gen
stop_esp_generator = stop_esp_gen
infcharges_start = infinite_charges_start
infcharges_stop = infinite_charges_stop

-- Ekspor ke environment executor supaya bisa diakses dari konsol.
-- Contoh: ZYPHERAX_DEBUG = true   -> nyalakan log detail
--         ZYPHERAX_DEBUG = false  -> matikan lagi
--         cetakLog()         -> tampilkan log yang tersimpan di clipboard
pcall(function()
    local env = (getgenv and getgenv()) or _G
    env.ZYPHERAX_DEBUG = ZYPHERAX_DEBUG
    env.ZYPHERAX_LOG_BUFFER = ZYPHERAX_LOG_BUFFER
    env.ZYPHERAX = {
        setDebug = function(v) ZYPHERAX_DEBUG = v end,
        getLog   = function() return ZYPHERAX_LOG_BUFFER end,
        clearLog = function() ZYPHERAX_LOG_BUFFER = "" end,
    }
end)
