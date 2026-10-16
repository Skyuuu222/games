-- ==============================================================================
-- ZYPHERAX HUB - VIOLENCE DISTRICT (AUTO FARM & SERVER HOP)
-- Map: Violence District (VD)
-- Features:
--   1. Auto Hop Server (Filter 2 Players, Unmatched Server)
--   2. Farm (Auto Escape saat match dimulai, Instant Finishline & Lever)
--   3. Auto Execute (Queue on Teleport persistence)
--   4. Discord Webhook (Full match end summary, Screws, EXP, Sin, Gears)
--   5. Full Config Manager (Save, Overwrite, Delete, Set/Reset Autoload)
--   6. Smart Game State Machine (Instant hop if Killer/In-match, 3m lobby timeout, 20s match cutoff, 10s post-escape hop)
-- ==============================================================================

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

-- Compatibility helpers
local function log(fmt, ...)
    local msg = string.format(fmt, ...)
    print("[Zypherax Farm] " .. msg)
end

local function safe_notify(opts)
    opts = opts or {}
    pcall(function()
        local w = ZypheraxWindow or Window
        if w and type(w.Notify) == "function" then
            w:Notify({
                Title = opts.Title or "Info",
                Description = tostring(opts.Description or ""),
                Lifetime = opts.Lifetime or 3
            })
        end
    end)
end

-- ==============================================================================
-- 1. KILLER DETECTION MODULE
-- ==============================================================================
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

-- ==============================================================================
-- 2. AUTO ESCAPE & FINISHLINE MODULE (FROM VIOLENCE DISTRICT)
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

-- ==============================================================================
-- 3. DISCORD WEBHOOK MODULE (FROM VIOLENCE DISTRICT)
-- ==============================================================================
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


-- ==============================================================================
-- 4. MATCH & GAME STATE CHECKER
-- ==============================================================================
local function is_in_match()
    local gs = _read_game_state()
    if gs and not _is_lobby_state(gs) then return true end
    if get_exit_gate and get_exit_gate() ~= nil then return true end
    if find_escape_target and find_escape_target() ~= nil then return true end
    local map = workspace:FindFirstChild("Map")
    if map and (map:FindFirstChild("Gate") or map:FindFirstChild("Generators") or map:FindFirstChild("Fininshline") or map:FindFirstChild("Finishline")) then
        return true
    end
    return false
end

-- ==============================================================================
-- 5. AUTO HOP & AUTO EXECUTE ENGINE
-- ==============================================================================
local autoHopEnabled     = true
local autoExecuteEnabled = true
local targetPlayerCount  = 2
local _isHopping         = false
local visitedServers     = {}
visitedServers[game.JobId] = true

local function prepare_auto_execute()
    local qot = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
    if qot then
        pcall(function()
            local code = [[
                task.wait(2)
                pcall(function()
                    if isfile and isfile("ZYPHERAXHUB/violence district/farm.lua") and readfile then
                        loadstring(readfile("ZYPHERAXHUB/violence district/farm.lua"))()
                    elseif isfile and isfile("farm.lua") and readfile then
                        loadstring(readfile("farm.lua"))()
                    end
                end)
            ]]
            qot(code)
        end)
    end
end

local function hop_to_target_server()
    if not autoHopEnabled then
        log("Auto Hop dimatikan oleh user.")
        return
    end
    if _isHopping then return end
    _isHopping = true

    safe_notify({
        Title = "Server Hop",
        Description = "Mencari server dengan 2 pemain (belum match)...",
        Lifetime = 4
    })

    if autoExecuteEnabled then
        prepare_auto_execute()
    end

    task.spawn(function()
        local placeId = game.PlaceId
        local currentJobId = game.JobId
        local cursor = ""
        local targetServer = nil
        local fallbackServer = nil

        for page = 1, 4 do
            local url = string.format(
                "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100%s",
                tostring(placeId),
                cursor ~= "" and ("&cursor=" .. cursor) or ""
            )

            local ok, res = pcall(function() return game:HttpGet(url) end)
            if not ok or not res or res == "" then
                local r = do_http_request({ Url = url, Method = "GET" })
                if r and r.Body then res = r.Body end
            end

            if res and res ~= "" then
                local dataOk, data = pcall(function() return HttpService:JSONDecode(res) end)
                if dataOk and data and data.data then
                    for _, s in ipairs(data.data) do
                        if s.id ~= currentJobId and not visitedServers[s.id] then
                            local playing = tonumber(s.playing) or 0
                            local maxPlayers = tonumber(s.maxPlayers) or 8
                            if playing == targetPlayerCount and playing < maxPlayers then
                                targetServer = s.id
                                break
                            elseif (playing == 1 or playing == 2) and playing < maxPlayers and not fallbackServer then
                                fallbackServer = s.id
                            end
                        end
                    end

                    if targetServer then break end

                    if data.nextPageCursor and data.nextPageCursor ~= "" then
                        cursor = data.nextPageCursor
                    else
                        break
                    end
                else
                    break
                end
            else
                break
            end
            task.wait(0.2)
        end

        local chosen = targetServer or fallbackServer
        if chosen then
            visitedServers[chosen] = true
            safe_notify({
                Title = "Teleporting",
                Description = "Menghubungkan ke server baru (2 player)...",
                Lifetime = 3
            })
            task.wait(0.5)
            TeleportService:TeleportToPlaceInstance(placeId, chosen, LocalPlayer)

            task.delay(10, function()
                _isHopping = false
            end)
        else
            safe_notify({
                Title = "Server Hop",
                Description = "Server 2 player tidak ditemukan. Mencoba lagi...",
                Lifetime = 3
            })
            _isHopping = false
            task.wait(3)
            hop_to_target_server()
        end
    end)
end

-- Teleport retry listener
pcall(function()
    TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
        if player == LocalPlayer then
            _isHopping = false
            log("Teleport gagal: %s. Mengulang pencarian...", tostring(errorMessage))
            safe_notify({
                Title = "Teleport Gagal",
                Description = "Mencoba server lain...",
                Lifetime = 3
            })
            task.wait(2)
            hop_to_target_server()
        end
    end)
end)

-- ==============================================================================
-- 6. ZYPHERAX UI & BRIDGELIB LIBRARY
-- ==============================================================================
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
        BackgroundTransparency = 0.05,
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


-- ==============================================================================
-- 7. FROSTED WATERMARK
-- ==============================================================================
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
-- 8. UI INITIALIZATION (MAIN & SETTING TABS ONLY)
-- ==============================================================================
local TabMain = tabGroup:Tab({ Name = "Main", Image = "lucide/zap" })
local TabConfig = tabGroup:Tab({ Name = "Setting", Image = "lucide/settings" })

-- ------------------------------------------------------------------------------
-- TAB 1: MAIN (AUTO HOP SERVER, FARM AUTO ESCAPE, AUTO EXECUTE, WEBHOOK)
-- ------------------------------------------------------------------------------
local SecHop = TabMain:Section({ Name = "Auto Hop Server", Side = 1 })
SecHop:Header({ Name = ZypheraxLib:Gradient("Auto Hop Server (2 Players)", Color3.fromRGB(0, 170, 255), Color3.fromRGB(0, 140, 230)) })

local lblHopStatus, lblServerInfo

SecHop:Toggle({
    Name = "Auto Hop Server",
    Flag = "auto_hop",
    Default = true,
    Callback = function(enabled)
        autoHopEnabled = enabled and true or false
        safe_notify({
            Title = "Auto Hop Server",
            Description = autoHopEnabled and "Auto Hop AKTIF (Target 2 Player)." or "Auto Hop DIMATIKAN.",
            Lifetime = 3
        })
    end
})

lblHopStatus = SecHop:Label({ Name = "Status: Menunggu Match..." })
lblServerInfo = SecHop:Label({ Name = "Server: " .. tostring(game.JobId:sub(1, 8)) .. " | Player: " .. tostring(#Players:GetPlayers()) })

SecHop:Button({
    Name = "Hop Server Sekarang",
    Callback = function()
        hop_to_target_server()
    end
})

local SecFarm = TabMain:Section({ Name = "Farm (Auto Escape)", Side = 1 })
SecFarm:Header({ Name = ZypheraxLib:Gradient("Farm & Auto Escape", Color3.fromRGB(0, 230, 170), Color3.fromRGB(0, 170, 255)) })

local lblEscapeStatus

SecFarm:Toggle({
    Name = "Auto Escape Saat Match Mulai",
    Flag = "auto_escape",
    Default = true,
    Callback = function(enabled)
        autoEscapeEnabled = enabled and true or false
        safe_notify({
            Title = "Auto Escape",
            Description = autoEscapeEnabled and "Auto Escape AKTIF saat match dimulai." or "Auto Escape DIMATIKAN.",
            Lifetime = 3
        })
    end
})

lblEscapeStatus = SecFarm:Label({ Name = "Escape: Standby (Siap saat match mulai)" })

SecFarm:Button({
    Name = "Instant Escape Sekarang",
    Callback = function()
        trigger_instant_escape()
    end
})

local SecExec = TabMain:Section({ Name = "Auto Execute", Side = 2 })
SecExec:Header({ Name = ZypheraxLib:Gradient("Auto Execute", Color3.fromRGB(180, 120, 255), Color3.fromRGB(120, 170, 255)) })

SecExec:Toggle({
    Name = "Auto Execute On Teleport",
    Flag = "auto_exec",
    Default = true,
    Callback = function(enabled)
        autoExecuteEnabled = enabled and true or false
        if autoExecuteEnabled then prepare_auto_execute() end
        safe_notify({
            Title = "Auto Execute",
            Description = autoExecuteEnabled and "Auto Execute AKTIF via queue_on_teleport." or "Auto Execute DIMATIKAN.",
            Lifetime = 3
        })
    end
})
SecExec:Label({ Name = "Menjaga script otomatis berjalan kembali saat teleport/hop server." })

local SecWebhook = TabMain:Section({ Name = "Discord Webhook", Side = 2 })
SecWebhook:Header({ Name = ZypheraxLib:Gradient("Discord Webhook Notifier", Color3.fromRGB(87, 242, 135), Color3.fromRGB(0, 170, 255)) })

SecWebhook:Input({
    Name = "Webhook URL",
    Placeholder = "https://discord.com/api/webhooks/...",
    Default = webhookUrl,
    Callback = function(val)
        webhookUrl = tostring(val or "")
        save_webhook_settings()
    end
})

SecWebhook:Toggle({
    Name = "Aktifkan Webhook Match Summary",
    Flag = "webhook_enabled",
    Default = true,
    Callback = function(enabled)
        webhookNotifyMatch = enabled and true or false
        save_webhook_settings()
        safe_notify({
            Title = "Webhook",
            Description = webhookNotifyMatch and "Webhook match summary aktif." or "Webhook dimatikan.",
            Lifetime = 3
        })
    end
})

SecWebhook:Button({
    Name = "Test Webhook",
    Callback = function()
        local ok, err = send_discord_webhook("Test Webhook", "Zypherax Hub Farm VD tersambung dengan sukses!", "57F287")
        if ok then
            safe_notify({ Title = "Webhook", Description = "Test webhook berhasil dikirim!", Lifetime = 3 })
        else
            safe_notify({ Title = "Webhook Gagal", Description = tostring(err), Lifetime = 3 })
        end
    end
})

SecWebhook:Label({ Name = "Mengirimkan embed lengkap EXP, Screws, Sin, Gears, dan Server ID saat berhasil escape." })

-- ------------------------------------------------------------------------------
-- TAB 2: SETTING (CONFIG MANAGER, AUTOLOAD, TEMA, REJOIN)
-- ------------------------------------------------------------------------------
local SecConfig = TabConfig:Section({ Name = "Config Manager", Side = 1 })
SecConfig:Header({ Name = "Config System (Save / Load / Autoload)" })

pcall(function()
    if SecConfig.CreateConfigSystem then
        SecConfig:CreateConfigSystem()
    end
end)

-- Dedicated Farm Config Backup Helper (Auto Load file)
local FARM_CFG_FILE = "ZypheraxHub/vd_farm_config.json"
local function save_farm_config()
    pcall(function()
        if writefile then
            local data = {
                autoHop = autoHopEnabled,
                autoEscape = autoEscapeEnabled,
                autoExecute = autoExecuteEnabled,
                webhook = webhookUrl,
                webhookOn = webhookNotifyMatch
            }
            writefile(FARM_CFG_FILE, HttpService:JSONEncode(data))
        end
    end)
end

local function load_farm_config()
    pcall(function()
        if isfile and isfile(FARM_CFG_FILE) and readfile then
            local raw = readfile(FARM_CFG_FILE)
            local ok, d = pcall(function() return HttpService:JSONDecode(raw) end)
            if ok and type(d) == "table" then
                if d.autoHop ~= nil then autoHopEnabled = (d.autoHop == true) end
                if d.autoEscape ~= nil then autoEscapeEnabled = (d.autoEscape == true) end
                if d.autoExecute ~= nil then autoExecuteEnabled = (d.autoExecute == true) end
                if d.webhook and d.webhook ~= "" then webhookUrl = tostring(d.webhook) end
                if d.webhookOn ~= nil then webhookNotifyMatch = (d.webhookOn == true) end
            end
        end
    end)
end
load_farm_config()

SecConfig:Button({
    Name = "Save Config Sekarang",
    Callback = function()
        save_farm_config()
        save_webhook_settings()
        safe_notify({ Title = "Config", Description = "Config berhasil disimpan!", Lifetime = 3 })
    end
})

SecConfig:Button({
    Name = "Set Sebagai Autoload",
    Callback = function()
        save_farm_config()
        pcall(function()
            if writefile then
                writefile("ZypheraxHub/farm_autoload.txt", "true")
            end
        end)
        safe_notify({ Title = "Autoload", Description = "Autoload aktif untuk server berikutnya.", Lifetime = 3 })
    end
})

SecConfig:Button({
    Name = "Reset Autoload",
    Callback = function()
        pcall(function()
            if isfile and isfile("ZypheraxHub/farm_autoload.txt") and delfile then
                delfile("ZypheraxHub/farm_autoload.txt")
            end
        end)
        safe_notify({ Title = "Autoload", Description = "Autoload direset.", Lifetime = 3 })
    end
})

local SecTheme = TabConfig:Section({ Name = "Tema & Penampilan", Side = 2 })
SecTheme:Header({ Name = "Penampilan (Appearance)" })

SecTheme:Dropdown({
    Name = "Pilihan Tema (Color Themes)",
    Options = ZypheraxLib:GetThemes(),
    Default = "Dark",
    Callback = function(themeName)
        ZypheraxLib:SetTheme(themeName)
        safe_notify({ Title = "Tema", Description = "Tema diubah ke " .. tostring(themeName), Lifetime = 3 })
    end
})

SecTheme:Toggle({
    Name = "Acrylic Blur",
    Default = Window:GetAcrylicBlurState(),
    Callback = function(bool)
        Window:SetAcrylicBlurState(bool)
        safe_notify({ Title = "Pengaturan", Description = (bool and "Mengaktifkan" or "Mematikan") .. " Blur", Lifetime = 3 })
    end
})

SecTheme:Button({
    Name = "Rejoin Server",
    Callback = function()
        safe_notify({ Title = "Server", Description = "Rejoining server...", Lifetime = 2 })
        task.wait(0.5)
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end)
    end
})

-- ==============================================================================
-- 9. REVEAL UI & FROSTED WATERMARK
-- ==============================================================================
if ZypheraxLib and ZypheraxLib._Reveal then
    pcall(function() ZypheraxLib:_Reveal() end)
end

_zy_show_watermark("Violence District - Farm")

-- ==============================================================================
-- 10. MAIN FARM CONTROLLER & STATE MACHINE
-- ==============================================================================
task.spawn(function()
    task.wait(2.5)

    -- Update info server
    pcall(function()
        if lblServerInfo then
            lblServerInfo:Set("Server: " .. tostring(game.JobId:sub(1, 8)) .. " | Player: " .. tostring(#Players:GetPlayers()) .. "/8")
        end
    end)

    -- [TAHAP 1] Cek apakah pemain terpilih menjadi Killer saat join
    if is_local_player_killer() then
        log("Pemain terdeteksi sebagai KILLER! Hop server langsung...")
        if lblHopStatus then lblHopStatus:Set("Status: Terdeteksi Killer! Hop server...") end
        safe_notify({
            Title = "Killer Terdeteksi",
            Description = "Kamu terpilih sebagai Killer! Mencari server lain...",
            Lifetime = 4
        })
        task.wait(1)
        hop_to_target_server()
        return
    end

    -- [TAHAP 2] Cek apakah server saat ini SUDAH SEDANG MATCH
    -- Sesuai permintaan: "jika server sedang match langsung cari server lain"
    if is_in_match() then
        log("Server sudah sedang match saat join! Mencari server lain...")
        if lblHopStatus then lblHopStatus:Set("Status: Server Sedang Match! Hop server...") end
        safe_notify({
            Title = "Server Sedang Match",
            Description = "Server sedang berlangsung. Mencari server 2 player lain...",
            Lifetime = 4
        })
        task.wait(1)
        hop_to_target_server()
        return
    end

    log("Berada di Lobby. Menunggu match dimulai (maksimal 3 menit)...")
    if lblHopStatus then lblHopStatus:Set("Status: Menunggu Match (Max 3 Menit)...") end
    safe_notify({
        Title = "Lobby Siap",
        Description = "Menunggu match dimulai (maksimal 3 menit)...",
        Lifetime = 4
    })

    -- [TAHAP 3] Loop tunggu match di Lobby (Maksimal 3 menit / 180 detik)
    local lobbyStart = tick()
    local matchStarted = false

    while autoHopEnabled and not _isHopping do
        task.wait(0.5)

        -- Update label timer
        local elapsed = tick() - lobbyStart
        local remaining = math.max(0, math.floor(180 - elapsed))
        if lblHopStatus then
            lblHopStatus:Set(string.format("Status: Menunggu Match (%ds tersisa)", remaining))
        end

        -- Cek Killer secara berkala
        if is_local_player_killer() then
            log("Tiba-tiba terpilih menjadi Killer! Hop server...")
            if lblHopStatus then lblHopStatus:Set("Status: Terdeteksi Killer! Hop server...") end
            safe_notify({
                Title = "Killer Terdeteksi",
                Description = "Terpilih sebagai Killer! Langsung hop server...",
                Lifetime = 3
            })
            hop_to_target_server()
            return
        end

        -- Timeout 3 menit di lobby
        if elapsed >= 180 then
            log("Batas waktu 3 menit di lobby habis tanpa match. Hop server...")
            if lblHopStatus then lblHopStatus:Set("Status: Batas 3 Menit Habis! Hop server...") end
            safe_notify({
                Title = "Batas 3 Menit",
                Description = "Tidak ada match mulai dalam 3 menit. Hop server...",
                Lifetime = 4
            })
            task.wait(0.5)
            hop_to_target_server()
            return
        end

        -- Deteksi match mulai
        if is_in_match() then
            matchStarted = true
            break
        end
    end

    if not matchStarted or _isHopping then return end

    -- [TAHAP 4] Match Terdeteksi Mulai!
    -- Sesuai permintaan:
    --   "jika terdeteksi match mulai langsung kasih 20 detik saja buat hope itu untuk tunggu reward dan langsung hope lagi"
    --   "dan system nya itu nanti hope server jika sudah berhasil escaped dan tunggu sekitar 10 detik lalu langsung hope server"
    local matchStart = tick()
    log("Match Terdeteksi Mulai! Memulai countdown 20s & auto escape...")
    if lblHopStatus then lblHopStatus:Set("Status: Match Dimulai! Menjalankan Escape...") end
    if lblEscapeStatus then lblEscapeStatus:Set("Escape: Menjalankan Instant Escape...") end

    safe_notify({
        Title = "Match Dimulai!",
        Description = "Menjalankan Auto Escape. Batas 20 detik reward...",
        Lifetime = 4
    })

    if is_local_player_killer() then
        hop_to_target_server()
        return
    end

    -- Jalankan Auto Escape jika ON
    local escapeSuccess = false
    if autoEscapeEnabled then
        task.spawn(function()
            local ok, err = trigger_instant_escape()
        end)
    end

    local monitorEsc = nil
    monitorEsc = LocalPlayer.CharacterRemoving:Connect(function()
        escapeSuccess = true
    end)
    local attrEsc = nil
    attrEsc = LocalPlayer:GetAttributeChangedSignal("Escaped"):Connect(function()
        if LocalPlayer:GetAttribute("Escaped") == true then
            escapeSuccess = true
        end
    end)

    -- Pantau selama maksimal 20 detik
    while (tick() - matchStart) < 20 and not _isHopping do
        task.wait(0.3)

        -- Cek jika berhasil escape
        if escapeSuccess or (LocalPlayer:GetAttribute("Escaped") == true) then
            if monitorEsc then monitorEsc:Disconnect() end
            if attrEsc then attrEsc:Disconnect() end

            log("Escape BERHASIL! Menunggu 10 detik untuk reward & webhook...")
            if lblEscapeStatus then lblEscapeStatus:Set("Escape: Berhasil! Menunggu reward...") end
            if lblHopStatus then lblHopStatus:Set("Status: Escape Berhasil! Hop dalam 10 detik...") end
            safe_notify({
                Title = "Escape Berhasil!",
                Description = "Menunggu 10 detik untuk klaim reward & webhook...",
                Lifetime = 4
            })

            -- Tunggu 10 detik sesuai instruksi user
            for sec = 10, 1, -1 do
                if lblHopStatus then lblHopStatus:Set(string.format("Status: Hop server dalam %ds...", sec)) end
                task.wait(1)
            end

            hop_to_target_server()
            return
        end
    end

    if monitorEsc then monitorEsc:Disconnect() end
    if attrEsc then attrEsc:Disconnect() end

    -- Batas 20 detik match tercapai
    if not _isHopping then
        log("Batas waktu match 20 detik tercapai. Mengambil reward & hop server...")
        if lblHopStatus then lblHopStatus:Set("Status: Batas 20s Tercapai! Hop server...") end
        safe_notify({
            Title = "Waktu Match 20s",
            Description = "Mengambil reward & langsung hop server...",
            Lifetime = 3
        })
        pcall(fire_escape_reward_remotes)
        task.wait(1)
        hop_to_target_server()
    end
end)

log("Zypherax Farm Violence District siap!")
