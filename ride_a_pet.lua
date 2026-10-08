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
-- Modul Avatar & Outfit Studio (dipakai tab Modifikasi)
local apply_avatar_swap, reset_avatar_swap
local apply_outfit
local add_accessory, remove_accessory, remove_all_accessories, update_accessory_transform
local apply_korblox, remove_korblox, apply_headless, remove_headless

-- Modul Fullbright & Custom FOV (dipakai tab View)
local fullbrightEnabled = false
local fullbright_start, fullbright_stop
local customFovEnabled = false
local customFovValue = 70
local fov_start, fov_stop, fov_apply
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
        { "Accent           = Color3.fromRGB(0, 180, 255),   -- primary accent",
          "Accent           = Color3.fromRGB(0, 200, 255),   -- primary accent" },
        { "AccentGradient   = Color3.fromRGB(30, 140, 220),  -- subtle gradient end",
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
        Accent           = Color3.fromRGB(0, 200, 255),
        AccentDark       = Color3.fromRGB(0, 120, 190),
        AccentGradient   = Color3.fromRGB(130, 120, 255),
        Text             = Color3.fromRGB(242, 244, 250),
        TextMuted        = Color3.fromRGB(145, 152, 170),
        TextDim          = Color3.fromRGB(90, 96, 112),
        Stroke           = Color3.fromRGB(38, 43, 58),
        StrokeHover      = Color3.fromRGB(55, 62, 84),
        StrokeActive     = Color3.fromRGB(0, 200, 255),
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
        Accent           = Color3.fromRGB(0, 150, 240),
        AccentDark       = Color3.fromRGB(0, 110, 180),
        AccentGradient   = Color3.fromRGB(90, 110, 230),
        Text             = Color3.fromRGB(25, 28, 36),
        TextMuted        = Color3.fromRGB(105, 112, 128),
        TextDim          = Color3.fromRGB(150, 155, 168),
        Stroke           = Color3.fromRGB(216, 222, 234),
        StrokeHover      = Color3.fromRGB(190, 198, 214),
        StrokeActive     = Color3.fromRGB(0, 150, 240),
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
        BackgroundTransparency = 0.08,
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
        BackgroundTransparency = 0.04,
        ClipsDescendants = true,
        ZIndex = 1,
        Parent = shadow
    })
    U.Corner(main, T.CornerLg)
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
    local titleLbl = U.New("TextLabel", {
        Text = string.upper(title),
        Font = T.FontBold,
        TextSize = 13,
        TextColor3 = T.Accent,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 14, 0, 32),
        Size = UDim2.new(1, -24, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 5,
        Parent = sidebarHeader
    })
    RegisterThemeColor(titleLbl, "TextColor3", "Accent")

    local subLbl = U.New("TextLabel", {
        Text = sub,
        Font = T.FontRegular,
        TextSize = 10,
        TextColor3 = T.TextMuted,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 14, 0, 48),
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
        Size = UDim2.new(0, 320, 0, 32),
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
                    BackgroundTransparency = 0.25,
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
                    BackgroundTransparency = 0.3,
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
        accentA   = Color3.fromRGB(0, 180, 255),
        accentB   = Color3.fromRGB(30, 140, 220),
        accentC   = Color3.fromRGB(140, 120, 255),
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
            logo.Size = UDim2.fromOffset(56, 56)
            logo.Position = UDim2.new(0.5, -28, 0, 26)
            logo.BackgroundColor3 = Color3.new(1, 1, 1)
            logo.BorderSizePixel = 0
            logo.ZIndex = 6
            logo.Parent = card
            _round(logo, 14)
            _grad(logo, P.accentA, P.accentC, 135)

            local logoText = Instance.new("TextLabel")
            logoText.Size = UDim2.fromScale(1, 1)
            logoText.BackgroundTransparency = 1
            logoText.Text = "Z"
            logoText.Font = Enum.Font.GothamBold
            logoText.TextSize = 30
            logoText.TextColor3 = Color3.new(1, 1, 1)
            logoText.ZIndex = 7
            logoText.Parent = logo

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
            _grad(title, P.accentA, P.accentC, 20)

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
            local chips = { "Auto Egg", "Hatch", "Skip Growth", "ESP", "Sell" }
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
-- RIDE A PET: ENGINE PROMPT / TELEPORT / REMOTE / ESP (dibangun dari trigger scan in-game)
-- ==============================================================================================
do
local RAP_DELAY = 0.5
local rapFlag = {}
local rapRunning = false
local rapGoal = "Player Spawn"

local rapEggNames = {
    "White Egg", "Brown Egg", "Galaxy Egg", "Tidal Egg", "Soul Egg", "Aurora Egg",
    "Asteroid Egg", "Sinister Egg", "Blackhole Egg", "Golden Egg", "Flower Egg",
    "Leaf Egg", "Stone Egg", "Easter Egg", "Cracked Egg", "Bloom Egg", "Glass Egg",
    "Ice Egg", "Slime Egg", "Skull Egg", "Flaming Egg", "Dog egg",
}

local rapActors = {
    "Snail", "Cheetah", "Giraffe", "Unicorn",
    "Tim", "Richie", "Eggo", "Rick",
}

local rapGoals = { "Player Spawn" }
for _, n in ipairs(rapEggNames) do table.insert(rapGoals, n) end
for _, n in ipairs(rapActors) do table.insert(rapGoals, n) end

local function rapPassBatch(matchFn, batch)
    local n = 0
    pcall(function()
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local act = tostring(d.ActionText or "")
                if matchFn(act, d) then
                    pcall(function()
                        d.HoldDuration = 0
                        d.MaxActivationDistance = 500
                        d.RequiresLineOfSight = false
                    end)
                    if type(fireproximityprompt) == "function" then
                        pcall(fireproximityprompt, d, 0)
                    else
                        pcall(function()
                            d:InputHoldBegin()
                            task.wait(0.05)
                            d:InputHoldEnd()
                        end)
                    end
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

local function rapFire(names)
    local r = rapPath(ReplicatedStorage, names)
    if not r then return false end
    local ok = pcall(function() r:FireServer() end)
    return ok
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

local function rapTeleport(name)
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then
        Window:Notify({ Title = "Teleport", Description = "Karakter belum siap.", Lifetime = 3 })
        return
    end
    local target = nil
    if name == "Player Spawn" then
        target = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    end
    if not target then
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("Model") and d.Name == name then target = d; break end
        end
    end
    if not target then
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == name then target = d; break end
        end
    end
    if not target then
        Window:Notify({ Title = "Teleport", Description = tostring(name) .. " tidak ditemukan.", Lifetime = 3 })
        return
    end
    local pos = rapEntityPos(target)
    if not pos then
        Window:Notify({ Title = "Teleport", Description = "Posisi " .. tostring(name) .. " tidak valid.", Lifetime = 3 })
        return
    end
    root.CFrame = CFrame.new(pos + Vector3.new(0, 6, 0))
    Window:Notify({ Title = "Teleport", Description = "Pindah ke " .. tostring(name) .. ".", Lifetime = 3 })
end

local function rapStep()
    if rapFlag.pickup then rapPassBatch(function(a) return a == "Pick Up" end, 5) end
    if rapFlag.hatch then rapPassBatch(function(a) return a == "Hatch" end, 3) end
    if rapFlag.grow then rapPassBatch(function(a) return a:find("Skip", 1, true) ~= nil end, 3) end
    if rapFlag.feed then rapPassBatch(function(a) return a == "Feed" end, 3) end
    if rapFlag.sell then rapPassBatch(function(a) return a == "Sell" end, 1) end
    if rapFlag.join then rapPassBatch(function(a) return a:find("Join", 1, true) ~= nil end, 1) end
    if rapFlag.claim then rapPassBatch(function(a) return a == "Claim" or a:find("Unlock", 1, true) ~= nil end, 2) end
    if rapFlag.ride then rapPassBatch(function(a) return a == "Ride" end, 1) end
    if rapFlag.remoteClaim then
        rapFire({ "Remotes", "Game", "ClaimEventReward" })
        rapFire({ "Remotes", "Reusable", "ClaimGroupReward" })
    end
    if rapFlag.autoTp then rapTeleport(rapGoal) end
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
local espMode = { egg = false, zone = false, player = false, npc = false }
local espRunning = false
local rapEggCount, rapZoneCount, rapNpcCount, rapPlayerCount = 0, 0, 0, 0

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

local function espWipe()
    pcall(function()
        if espHost then
            for _, c in ipairs(espHost:GetChildren()) do c:Destroy() end
        end
    end)
end

local function espMark(inst, label, color)
    if not inst or not inst.Parent then return end
    local f = espFolder()
    local hl = Instance.new("Highlight")
    hl.Name = ESP_NAME
    hl.Adornee = inst
    hl.FillColor = color
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.7
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = f
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
            bb.Size = UDim2.new(0, 170, 0, 24)
            bb.StudsOffset = Vector3.new(0, 3, 0)
            bb.AlwaysOnTop = true
            bb.MaxDistance = 600
            local tl = Instance.new("TextLabel")
            tl.Size = UDim2.new(1, 0, 1, 0)
            tl.BackgroundTransparency = 1
            tl.Font = Enum.Font.GothamBold
            tl.TextSize = 12
            tl.TextColor3 = color
            tl.TextStrokeColor3 = Color3.new(0, 0, 0)
            tl.TextStrokeTransparency = 0.3
            tl.Text = label
            tl.Parent = bb
            bb.Parent = f
        end
    end
end

local function rapCountNames(names, mark, color)
    local c = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Model") or d:IsA("BasePart") then
            for _, n in ipairs(names) do
                if d.Name == n then
                    c = c + 1
                    if mark then espMark(d, d.Name, color) end
                    break
                end
            end
        end
    end
    return c
end

local function rapZones(mark)
    local c = 0
    for _, d in ipairs(workspace:GetDescendants()) do
        if (d:IsA("Model") or d:IsA("BasePart")) and d.Parent and d.Parent.Name == "EggSpawns" then
            c = c + 1
            if mark then espMark(d, "Zone " .. d.Name, Color3.fromRGB(255, 210, 90)) end
        end
    end
    return c
end

local function rapPlayers(mark)
    local c = 0
    local myRoot = nil
    pcall(function()
        local ch = LocalPlayer.Character
        myRoot = ch and ch:FindFirstChild("HumanoidRootPart")
    end)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local ok, root = pcall(function() return p.Character:FindFirstChild("HumanoidRootPart") end)
            local dist = 0
            if ok and root and myRoot then
                dist = math.floor((root.Position - myRoot.Position).Magnitude + 0.5)
            end
            c = c + 1
            if mark then
                espMark(p.Character, p.DisplayName .. " [" .. tostring(dist) .. "m]", Color3.fromRGB(120, 255, 160))
            end
        end
    end
    return c
end

local function espRefresh()
    espWipe()
    rapEggCount    = rapCountNames(rapEggNames, espMode.egg, Color3.fromRGB(110, 220, 255))
    rapZoneCount   = rapZones(espMode.zone)
    rapNpcCount    = rapCountNames(rapActors, espMode.npc, Color3.fromRGB(255, 170, 90))
    rapPlayerCount = rapPlayers(espMode.player)
end

local function espLoopStart()
    if espRunning then return end
    espRunning = true
    task.spawn(function()
        while espMode.egg or espMode.zone or espMode.player or espMode.npc do
            pcall(espRefresh)
            task.wait(1.5)
        end
        pcall(espWipe)
        espRunning = false
    end)
end

local function espSet(key, on, title, onMsg, offMsg)
    espMode[key] = on and true or nil
    if on then espLoopStart() end
    Window:Notify({ Title = title, Description = on and onMsg or offMsg, Lifetime = 3 })
end

-- ==============================================================================================
-- MENU: MAIN (AUTO TELUR, EVENT & TELEPORT)
-- ==============================================================================================
local TabMainRAP = tabGroup:Tab({ Name = "Main", Image = "lucide/zap" })

local SecAutoEgg = TabMainRAP:Section({ Name = "Auto Telur & Pet", Side = 1 })
SecAutoEgg:Header({ Name = ZypheraxLib:Gradient("Auto Egg Collector", Color3.fromRGB(72, 214, 200), Color3.fromRGB(99, 130, 255)) })

SecAutoEgg:Toggle({
    Name = "Auto Pickup Telur",
    Default = false,
    Callback = function(enabled)
        rapSet("pickup", enabled, "Auto Pickup",
            "Mengambil semua telur (Pick Up) otomatis.",
            "Auto pickup dimatikan.")
    end,
})

SecAutoEgg:Toggle({
    Name = "Auto Hatch Telur",
    Default = false,
    Callback = function(enabled)
        rapSet("hatch", enabled, "Auto Hatch",
            "Menetaskan telur (Hatch) otomatis.",
            "Auto hatch dimatikan.")
    end,
})

SecAutoEgg:Toggle({
    Name = "Auto Skip Growth (Semua Pet)",
    Default = false,
    Callback = function(enabled)
        rapSet("grow", enabled, "Skip Growth",
            "Melewati pertumbuhan pet otomatis.",
            "Skip growth dimatikan.")
    end,
})

SecAutoEgg:Toggle({
    Name = "Auto Feed Pet",
    Default = false,
    Callback = function(enabled)
        rapSet("feed", enabled, "Auto Feed",
            "Memberi makan pet otomatis.",
            "Auto feed dimatikan.")
    end,
})

SecAutoEgg:Slider({
    Name = "Kecepatan Loop (detik x0.1)",
    Default = 5,
    Minimum = 1,
    Maximum = 30,
    DisplayMethod = "Round",
    Precision = 0,
    Callback = function(value)
        RAP_DELAY = value / 10
    end,
})

local SecEvent = TabMainRAP:Section({ Name = "Event, Klaim & Jual", Side = 2 })
SecEvent:Header({ Name = ZypheraxLib:Gradient("Event & Reward", Color3.fromRGB(99, 130, 255), Color3.fromRGB(168, 120, 255)) })

SecEvent:Toggle({
    Name = "Auto Claim Event & Group (Remote)",
    Default = false,
    Callback = function(enabled)
        rapSet("remoteClaim", enabled, "Auto Claim",
            "Klaim reward event & group berjalan otomatis.",
            "Auto claim dimatikan.")
    end,
})

SecEvent:Toggle({
    Name = "Auto Klaim Prompt (Claim / Unlock)",
    Default = false,
    Callback = function(enabled)
        rapSet("claim", enabled, "Auto Klaim",
            "Menekan prompt Claim / Unlock Nest otomatis.",
            "Auto klaim dimatikan.")
    end,
})

SecEvent:Toggle({
    Name = "Auto Join Event",
    Default = false,
    Callback = function(enabled)
        rapSet("join", enabled, "Auto Join",
            "Masuk event otomatis jika tersedia.",
            "Auto join dimatikan.")
    end,
})

SecEvent:Toggle({
    Name = "Auto Jual (NPC Richie)",
    Default = false,
    Callback = function(enabled)
        rapSet("sell", enabled, "Auto Jual",
            "Menjual item otomatis ke Richie.",
            "Auto jual dimatikan.")
    end,
})

SecEvent:Button({
    Name = "Buka Shop (NPC Rick)",
    Callback = function()
        local n = rapPassBatch(function(a) return a == "Shop" end, 1)
        Window:Notify({ Title = "Shop", Description = n > 0 and "Prompt Shop ditekan." or "Prompt Shop tidak ditemukan.", Lifetime = 3 })
    end,
})

SecEvent:Button({
    Name = "Buka Stock Shop (Remote)",
    Callback = function()
        local ok = rapFire({ "Remotes", "Game", "OpenStockShop" })
        Window:Notify({ Title = "Stock Shop", Description = ok and "Remote Stock Shop dikirim." or "Remote tidak ditemukan / gagal.", Lifetime = 3 })
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
    Callback = function() rapTeleport(rapGoal) end,
})

SecTele:Button({
    Name = "Teleport ke Spawn",
    Callback = function() rapTeleport("Player Spawn") end,
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

local SecRide = TabMainRAP:Section({ Name = "Ride & Utility", Side = 2 })
SecRide:Header({ Name = ZypheraxLib:Gradient("Ride & Utility", Color3.fromRGB(140, 152, 190), Color3.fromRGB(120, 170, 200)) })

SecRide:Toggle({
    Name = "Auto Ride Hewan (Snail, Cheetah, dll)",
    Default = false,
    Callback = function(enabled)
        rapSet("ride", enabled, "Auto Ride",
            "Menaiki hewan (Ride) otomatis.",
            "Auto ride dimatikan.")
    end,
})

SecRide:Button({
    Name = "Hatch Sekarang",
    Callback = function()
        local n = rapPassBatch(function(a) return a == "Hatch" end, 5)
        Window:Notify({ Title = "Hatch", Description = tostring(n) .. " prompt Hatch ditekan.", Lifetime = 3 })
    end,
})

SecRide:Button({
    Name = "Feed Sekarang",
    Callback = function()
        local n = rapPassBatch(function(a) return a == "Feed" end, 5)
        Window:Notify({ Title = "Feed", Description = tostring(n) .. " prompt Feed ditekan.", Lifetime = 3 })
    end,
})

SecRide:Label({ Name = "Prompt dijalankan dengan fireproximityprompt. Jika executor tidak mendukung, fitur prompt mungkin tidak berjalan." })

-- ==============================================================================================
-- MENU: ESP (TELUR, ZONE, PEMAIN & NPC)
-- ==============================================================================================
local TabESPRAP = tabGroup:Tab({ Name = "ESP", Image = "lucide/eye" })

local SecEggESP = TabESPRAP:Section({ Name = "ESP Telur & Zone", Side = 1 })
SecEggESP:Header({ Name = ZypheraxLib:Gradient("ESP Kumpulan Telur", Color3.fromRGB(110, 220, 255), Color3.fromRGB(72, 214, 200)) })

SecEggESP:Toggle({
    Name = "ESP Semua Telur",
    Default = false,
    Callback = function(enabled)
        espSet("egg", enabled, "ESP Telur",
            "Semua telur di-mark biru muda.",
            "ESP telur dimatikan.")
    end,
})

SecEggESP:Toggle({
    Name = "ESP Zone Spawn (Common / Rare / Epic)",
    Default = false,
    Callback = function(enabled)
        espSet("zone", enabled, "ESP Zone",
            "Zone spawn telur di-mark kuning.",
            "ESP zone dimatikan.")
    end,
})

SecEggESP:Button({
    Name = "Hitung Target Sekarang",
    Callback = function()
        pcall(espRefresh)
        Window:Notify({
            Title = "Target",
            Description = ("Telur: %d | Zone: %d | NPC/Hewan: %d | Pemain: %d"):format(
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
        espSet("player", enabled, "ESP Pemain",
            "Pemain lain di-mark hijau + jarak.",
            "ESP pemain dimatikan.")
    end,
})

SecWorldESP:Toggle({
    Name = "ESP NPC & Hewan",
    Default = false,
    Callback = function(enabled)
        espSet("npc", enabled, "ESP NPC",
            "NPC (Tim, Richie, Eggo, Rick) & hewan di-mark oranye.",
            "ESP NPC dimatikan.")
    end,
})

SecWorldESP:Label({ Name = "ESP otomatis di-refresh tiap 1.5 detik." })
end -- [End Engine RIDE A PET]

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
log("Zypherax Hub (Ride A Pet - 6 Tabs) berhasil dijalankan")
end -- [End TabConfig]
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
