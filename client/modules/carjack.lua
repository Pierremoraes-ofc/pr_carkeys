-- ----------------------------------------------------------------
--   pr_carkeys — client/modules/carjack.lua
--   Confisco policial e Roubo de veículo NPC
--   Standalone: não depende de ox_lib para funcionar.
-- ----------------------------------------------------------------

-- ----------------------------------------------------------------
-- Estado da máquina
-- ----------------------------------------------------------------
local isConfiscating   = false
local isCarjacking     = false
local isNpcSurrendered = false
local currentTarget    = nil
local currentVehicle   = nil
local textUIVisible    = false
local handsUpPedd      = false
local handsUpActive    = false
local pendingGrantTemp = false
local pendingGrantOk   = false

-- NPC fugiu com a chave: permite matar e "pegar" a chave
local fleeingPed       = nil
local fleeingVehicle   = nil
local fleeingPlate     = nil
local canLootFleeKey   = false
local lootBusy         = false

-- ----------------------------------------------------------------
-- Contagem de tiros (acumulativo, zerado a cada novo alvo)
-- ----------------------------------------------------------------
local shotsFired = 0.0
local canCount   = true

-- ----------------------------------------------------------------
-- Debug local
-- ----------------------------------------------------------------
local function cjDebug(level, msg)
    Debug(level, "[Carjack] " .. msg)
end

-- ----------------------------------------------------------------
-- Verifica se a arma está na blacklist
-- ----------------------------------------------------------------
local function isBlacklistedWeapon()
    if not Config.Carjack.blacklistedWeapons then return false end
    local weapon = GetSelectedPedWeapon(cache.ped)
    for _, w in ipairs(Config.Carjack.blacklistedWeapons) do
        if joaat(w) == weapon then return true end
    end
    return false
end

-- ----------------------------------------------------------------
-- Chance base pela categoria da arma
-- ----------------------------------------------------------------
local function getWeaponChance()
    local weapon   = GetSelectedPedWeapon(cache.ped)
    local category = tostring(GetWeapontypeGroup(weapon))
    local chances  = Config.Carjack.chance
    if chances and chances[category] then
        return chances[category]
    end
    return 0.5
end

-- ----------------------------------------------------------------
-- Hint na tela — ox_lib ou DrawText nativo
-- ----------------------------------------------------------------
local function showHint(text)
    if textUIVisible then return end
    textUIVisible = true

    if GetResourceState("ox_lib"):find("start") and lib and lib.showTextUI then
        lib.showTextUI(text, { position = "right-center" })
    else
        CreateThread(function()
            while textUIVisible do
                SetTextFont(4)
                SetTextProportional(1)
                SetTextScale(0.0, 0.45)
                SetTextColour(255, 255, 255, 215)
                SetTextDropshadow(0, 0, 0, 0, 255)
                SetTextEdge(2, 0, 0, 0, 150)
                SetTextDropShadow()
                SetTextOutline()
                SetTextEntry("STRING")
                AddTextComponentString(text)
                DrawText(0.5, 0.89)
                Wait(0)
            end
        end)
    end
end

local function hideHint()
    if not textUIVisible then return end
    textUIVisible = false
    if GetResourceState("ox_lib"):find("start") and lib and lib.hideTextUI then
        lib.hideTextUI()
    end
end

local function clearFleeKeyState()
    fleeingPed     = nil
    fleeingVehicle = nil
    fleeingPlate   = nil
    canLootFleeKey = false
    lootBusy       = false
end

-- ----------------------------------------------------------------
-- Carrega animDict nativamente
-- ----------------------------------------------------------------
local function loadAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = 0
    while not HasAnimDictLoaded(dict) and timeout < 3000 do
        Wait(50)
        timeout = timeout + 50
    end
end

-- ----------------------------------------------------------------
-- Progressbar — ox_lib ou Wait simples
-- ----------------------------------------------------------------
local function doProgressBar(duration, label, cb)
    if GetResourceState("ox_lib"):find("start") and lib and lib.progressBar then
        local success = lib.progressBar({
            duration  = duration,
            label     = label,
            canCancel = false,
            disable   = { move = true, car = true, combat = true },
        })
        cb(success)
    else
        Wait(duration)
        cb(true)
    end
end

-- ----------------------------------------------------------------
-- Animação de procura (loot chave)
-- ----------------------------------------------------------------
local function playSearchAnim(targetPed)
    local dict = "anim@gangops@facility@servers@bodysearch@"
    local clip = "player_search"
    loadAnimDict(dict)

    if targetPed and DoesEntityExist(targetPed) then
        local tCoords = GetEntityCoords(targetPed)
        local tHeading = GetEntityHeading(targetPed)

        -- Posição ao lado do corpo (offset lateral)
        local sideOffset = 0.55
        local backOffset = -0.15
        local off = GetOffsetFromEntityInWorldCoords(targetPed, sideOffset, backOffset, 0.0)

        -- Garante Z no chão pra não “levitar”
        local okGround, groundZ = GetGroundZFor_3dCoord(off.x, off.y, off.z + 1.0, false)
        local z = okGround and groundZ or off.z

        -- Ajusta player no lugar e direção
        SetEntityCoordsNoOffset(cache.ped, off.x, off.y, z, false, false, false)
        SetEntityHeading(cache.ped, (tHeading + 90.0) % 360.0)
        PlaceObjectOnGroundProperly(cache.ped)

        -- Animação “travada” no ponto (evita drift/levitação)
        TaskPlayAnimAdvanced(
            cache.ped,
            dict, clip,
            off.x, off.y, z,
            0.0, 0.0, GetEntityHeading(cache.ped),
            2.0, 2.0,
            -1,
            1,
            0.0,
            0, 0
        )
    else
        TaskPlayAnim(cache.ped, dict, clip, 2.0, 2.0, -1, 1, 0, false, false, false)
    end
end

local function stopSearchAnim()
    local dict = "anim@gangops@facility@servers@bodysearch@"
    local clip = "player_search"
    StopAnimTask(cache.ped, dict, clip, 1.0)
    ClearPedTasks(cache.ped)
end

RegisterNetEvent("pr_carkeys:client:carjackLootKeyResult", function(success, data)
    if success then
        PRCarkeys.Notify(Config.Carjack.notifySuccess or Config.Notify.keyUsed)
    else
        PRCarkeys.Notify(Config.Carjack.notifyFail or Config.Notify.noPermission)
        cjDebug("WARNING", ("loot key falhou | reason=%s"):format(tostring(data)))
    end
end)

RegisterNetEvent("pr_carkeys:client:grantTempAccessResult", function(success, data)
    if success then
        pendingGrantOk = true
    else
        cjDebug("WARNING", ("grant temp access falhou | reason=%s"):format(tostring(data)))
    end
end)

-- ----------------------------------------------------------------
-- Mantém motor ligado em loop por 'duration' ms
-- ----------------------------------------------------------------
local function keepEngineOn(vehicle, duration)
    local t = 0
    while DoesEntityExist(vehicle) and t < duration do
        SetVehicleEngineOn(vehicle, true, true, true)
        Wait(100)
        t = t + 100
    end
end

-- ----------------------------------------------------------------
-- NPC foge desgovernado no veículo (pode atropelar)
-- ----------------------------------------------------------------
local function reactionPedinDrive(ped, vehicle)
    local values = { 3, 9, 13, 14, 22, 23, 28, 30, 32 }
    TaskVehicleTempAction(ped, vehicle, values[math.random(1, #values)], -1)
end

-- ----------------------------------------------------------------
-- NPC sai do veículo de forma brusca/assustada
-- ----------------------------------------------------------------
local function reactionPedinWalk(ped, vehicle)
    local values = { 64, 256, 4160, 262144 }
    TaskLeaveVehicle(ped, vehicle, values[math.random(1, #values)])
end

-- ----------------------------------------------------------------
-- Freia veículo do NPC gradualmente
-- ----------------------------------------------------------------
local function brakeNpcVehicle(ped, vehicle)
    CreateThread(function()
        for _ = 1, 80 do
            if not DoesEntityExist(vehicle) then return end
            local speed = GetEntitySpeed(vehicle)
            if speed < 0.5 then
                TaskVehicleTempAction(ped, vehicle, 6, -1)
                SetVehicleForwardSpeed(vehicle, 0.0)
                SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
                FreezeEntityPosition(vehicle, true)
                return
            end
            SetVehicleForwardSpeed(vehicle, math.max(0.0, speed - 0.5))
            Wait(50)
        end
    end)
end

-- ----------------------------------------------------------------
-- Libera veículo para o player
-- ----------------------------------------------------------------
local function driveableVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return end
    SetVehicleUndriveable(vehicle, false)
    FreezeEntityPosition(vehicle, false)
    SetVehicleDoorsLocked(vehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(vehicle, false)
    SetVehicleEngineOn(vehicle, true, true, true)
    CreateThread(function() keepEngineOn(vehicle, 6000) end)
    hideHint()
end

-- ----------------------------------------------------------------
-- Deixa veículo apagado e travado (NPC fugiu com a chave)
-- ----------------------------------------------------------------
local function lockedVehicle(vehicle)
    if not DoesEntityExist(vehicle) then return end
    FreezeEntityPosition(vehicle, false)
    SetVehicleUndriveable(vehicle, true)
    SetVehicleEngineOn(vehicle, false, true, false)
    SetVehicleDoorsLocked(vehicle, 2)
    SetVehicleDoorsLockedForAllPlayers(vehicle, true)
end

-- ----------------------------------------------------------------
-- Faz o NPC sair do veículo (bloqueante, aguarda até 8s)
-- ----------------------------------------------------------------
local function exitVehicle(ped, vehicle, code)
    if not DoesEntityExist(ped) then return end

    cjDebug("INFO", ("exitVehicle | flag=%d"):format(code or 0))

    StopAnimTask(ped, "missminuteman_1ig_2", "handsup_base", 1.0)
    Wait(150)
    SetVehicleDoorsLocked(vehicle, 1)
    SetVehicleDoorsLockedForAllPlayers(vehicle, false)
    SetBlockingOfNonTemporaryEvents(ped, false)

    TaskLeaveVehicle(ped, vehicle, code or 256)

    local t = 0
    while DoesEntityExist(ped) and IsPedInAnyVehicle(ped, false) and t < 8000 do
        Wait(100)
        t = t + 100
    end

    cjDebug("INFO", ("exitVehicle: NPC saiu em %d ms"):format(t))
end

-- ----------------------------------------------------------------
-- Desativa reações da IA do NPC
-- ----------------------------------------------------------------
local function disableActionsPed(ped)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 17, false)
    SetPedAlertness(ped, 0)
    SetPedConfigFlag(ped, 17, true)
    SetPedConfigFlag(ped, 229, false)
    SetPedConfigFlag(ped, 26, true)
    SetPedConfigFlag(ped, 398, true)
    SetPedConfigFlag(ped, 134, true)
    SetPedConfigFlag(ped, 259, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
end

-- ----------------------------------------------------------------
-- Reativa reações da IA do NPC (pânico/fuga)
-- ----------------------------------------------------------------
local function enableActionsPed(ped)
    SetPedFleeAttributes(ped, 0, true)
    SetPedCombatAttributes(ped, 17, true)
    SetPedAlertness(ped, 3)
    SetPedConfigFlag(ped, 17, false)
    SetPedConfigFlag(ped, 229, true)
    SetPedConfigFlag(ped, 26, false)
    SetPedConfigFlag(ped, 398, false)
    SetPedConfigFlag(ped, 134, false)
    SetPedConfigFlag(ped, 259, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
end

-- ----------------------------------------------------------------
-- NPC corre com medo após sair do veículo
-- ----------------------------------------------------------------
local function runAwayInFear(ped)
    if not DoesEntityExist(ped) then return end
    enableActionsPed(ped)
    TaskCower(ped, 1500)
    Wait(1500)
    if DoesEntityExist(ped) then
        SetPedFleeAttributes(ped, 0, true)
        TaskSmartFleePed(ped, cache.ped, 200.0, 30000, false, false)
    end
end

-- ----------------------------------------------------------------
-- Coloca mãos ao alto no NPC (versão policial — mantém no carro)
-- ----------------------------------------------------------------
local function handsUpPed(target, vehicle)
    cjDebug("INFO", "handsUpPed: iniciado")
    handsUpActive = true

    disableActionsPed(target)
    CreateThread(function()
        if not DoesEntityExist(target) then handsUpActive = false; return end

        if DoesEntityExist(vehicle) then
            SetVehicleUndriveable(vehicle, true)

            CreateThread(function()
                while DoesEntityExist(target) and handsUpActive do
                    brakeNpcVehicle(target, vehicle)
                    Wait(500)
                    SetVehicleDoorsLockedForAllPlayers(vehicle, true)
                    SetVehicleDoorsLocked(vehicle, 2)

                    if not IsPedInVehicle(target, vehicle, false) then
                        driveableVehicle(vehicle)
                    end
                end
            end)
        end

        loadAnimDict("missminuteman_1ig_2")
        Wait(350)
        if not DoesEntityExist(target) then handsUpActive = false; return end

        TaskTurnPedToFaceEntity(target, cache.ped, -1)
        Wait(400)

        if not DoesEntityExist(target) then handsUpActive = false; return end
        TaskPlayAnim(target, "missminuteman_1ig_2", "handsup_base",
            8.0, -8.0, -1, 49, 0, false, false, false)

        cjDebug("INFO", "handsUpPed: NPC com maos ao alto")
    end)
end

-- ----------------------------------------------------------------
-- Cancela estado de render — NPC retoma comportamento normal
-- ----------------------------------------------------------------
local function cancelSurrender(ped, vehicle)
    isNpcSurrendered = false
    handsUpPedd      = false
    handsUpActive    = false
    shotsFired       = 0.0   -- ← zera tiros ao cancelar
    currentTarget    = nil
    currentVehicle   = nil
    hideHint()

    if DoesEntityExist(ped) then
        StopAnimTask(ped, "missminuteman_1ig_2", "handsup_base", 1.0)
        SetBlockingOfNonTemporaryEvents(ped, false)
        if DoesEntityExist(vehicle) then
            SetVehicleUndriveable(vehicle, false)
            FreezeEntityPosition(vehicle, false)
            TaskVehicleDriveWander(ped, vehicle, 15.0, 786603)
        end
    end

    cjDebug("INFO", "cancelSurrender — estado limpo")
end

-- ----------------------------------------------------------------
--   CONFISCO POLICIAL
-- ----------------------------------------------------------------
local function confiscateVehicle(ped, vehicle)
    if isConfiscating then return end
    isConfiscating = true
    handsUpActive  = false  -- para o loop de warp antes de sair

    hideHint()
    cjDebug("INFO", "Confisco iniciado pelo policial")

    if not DoesEntityExist(ped) then
        isConfiscating = false
        return
    end

    CreateThread(function() keepEngineOn(vehicle, 10000) end)

    exitVehicle(ped, vehicle, 256)

    if DoesEntityExist(ped) then
        TaskStandStill(ped, 10000)
    end

    driveableVehicle(vehicle)

    handsUpActive    = false
    handsUpPedd      = false
    isConfiscating   = false
    isNpcSurrendered = false
    currentTarget    = nil
    currentVehicle   = nil

    cjDebug("SUCCESS", "Confisco concluido — NPC saiu, motor ligado")
end

-- ----------------------------------------------------------------
--   ROUBO CIVIL (doCarjack)
--
--   Fluxo automático (sem [E]):
--   1. Player mira NPC → roda probabilidade imediatamente
--   2. chanceKey = (weaponChance + shotsFired * 0.5) clamped [0,1]
--   3. math.random() + shotsFired >= npcReactChance → NPC coopera
--      NÃO coopera → reactionPedinDrive (foge desgovernado)
--   4. NPC coopera → freia + mãos ao alto + sai em pânico
--   5. chanceKey >= 0.5 → chave no carro (driveableVehicle)
--      chanceKey < 0.5  → NPC foge com chave (lockedVehicle)
--   6. Carro apagado → player faz minigame (ligação direta)
-- ----------------------------------------------------------------
local function doCarjack(ped, vehicle)
    if isCarjacking then return end
    isCarjacking     = true
    isNpcSurrendered = false
    currentTarget    = nil
    currentVehicle   = nil

    local weaponChance = getWeaponChance()
    local cooldown     = Config.Carjack.cooldown or { 5000, 10000 }

    -- Arma sem chance alguma: aborta silenciosamente
    if weaponChance <= 0.0 then
        local cd = math.random(cooldown[1], cooldown[2])
        Wait(cd)
        shotsFired   = 0.0
        isCarjacking = false
        cjDebug("INFO", "Arma sem chance — bloqueado")
        return
    end

    -- ── Calcula chanceKey considerando arma + tiros disparados ──
    -- weaponChance: 0.0~1.0 pela categoria da arma
    -- shotsFired:   acumulado por tiros próximos ao NPC
    -- chanceKey:    resultado clampado em [0.0, 1.0]
    local chanceKey = math.min(1.0, (weaponChance + (shotsFired * 0.5)) / 0.5)

    cjDebug("INFO", ("doCarjack | weaponChance=%.2f | shotsFired=%.2f | chanceKey=%.2f")
        :format(weaponChance, shotsFired, chanceKey))

    -- ── NPC coopera ou reage? ────────────────────────────────────
    -- Quanto maior chanceKey (arma forte + tiros), mais fácil cooperar
    if not (math.random() + shotsFired >= (Config.Carjack.npcReactChance or 0.3)) then
        -- NPC NÃO coopera → acelera desgovernado
        cjDebug("INFO", "NPC reagiu — fugindo de carro desgovernado")

        enableActionsPed(ped)
        reactionPedinDrive(ped, vehicle)

        PRCarkeys.Notify(Config.Carjack.notifyFail or Config.Notify.noPermission)

        local cd = math.random(cooldown[1], cooldown[2])
        Wait(cd)
        shotsFired   = 0.0
        isCarjacking = false
        cjDebug("INFO", ("NPC reagiu | cooldown=%d ms"):format(cd))
        return
    end

    -- ── NPC coopera ──────────────────────────────────────────────
    cjDebug("INFO", "NPC cooperando — freando e levantando maos")

    disableActionsPed(ped)
    brakeNpcVehicle(ped, vehicle)
    SetVehicleUndriveable(vehicle, true)
    Wait(800)  -- tempo para frear

    -- Animação mãos ao alto
    if DoesEntityExist(ped) then
        loadAnimDict("missminuteman_1ig_2")
        TaskTurnPedToFaceEntity(ped, cache.ped, -1)
        Wait(400)
        if DoesEntityExist(ped) then
            TaskPlayAnim(ped, "missminuteman_1ig_2", "handsup_base",
                8.0, -8.0, -1, 49, 0, false, false, false)
            cjDebug("INFO", "NPC com maos ao alto")
        end
    end

    Wait(1500)  -- player vê o NPC rendido por 1.5s antes de sair

    -- NPC sai do veículo em pânico
    if DoesEntityExist(ped) then
        SetVehicleUndriveable(vehicle, false)
        FreezeEntityPosition(vehicle, false)
        exitVehicle(ped, vehicle, 256)
    end

    -- NPC foge a pé com medo
    CreateThread(function()
        runAwayInFear(ped)
    end)

    -- ── Chave: ficou no carro ou NPC levou? ──────────────────────
    if chanceKey >= 0.9 then
        -- Chave no carro: veículo pronto para usar
        cjDebug("SUCCESS", ("Chave no carro | chanceKey=%.2f"):format(chanceKey))
        driveableVehicle(vehicle)
        -- Só entrega quando o player realmente entrar no banco do motorista (validação do servidor exige isso).
        local vNet = NetworkGetNetworkIdFromEntity(vehicle)
        local vPlate = PRCarkeys.SanitizePlate(GetVehicleNumberPlateText(vehicle))
        CreateThread(function()
            local waited = 0
            pendingGrantTemp = true
            pendingGrantOk = false
            while waited < 60000 and pendingGrantTemp do
                Wait(500)
                waited = waited + 500
                if not DoesEntityExist(vehicle) then
                    pendingGrantTemp = false
                    return
                end
                if cache.vehicle == vehicle and cache.seat == -1 then
                    TriggerServerEvent("pr_carkeys:server:grantTemporaryVehicleAccess", vNet, vPlate)
                    TriggerEvent("pr_carkeys:client:clearDriverHintUI")
                    -- aguarda confirmação server-side; reenvia se houver falha de timing/rede
                    Wait(400)
                    if pendingGrantOk then
                        pendingGrantTemp = false
                        PRCarkeys.Notify(Config.Carjack.notifySuccess or Config.Notify.keyUsed)
                        return
                    end
                end
            end
            pendingGrantTemp = false
        end)
    else
        -- NPC fugiu com a chave: carro apagado e travado
        cjDebug("INFO", ("NPC fugiu com a chave | chanceKey=%.2f"):format(chanceKey))
        --lockedVehicle(vehicle)
        SetVehicleEngineOn(vehicle, false, true, false)
        -- 1) Player pode matar o NPC e pegar a chave (E).
        -- 2) Ou fazer ligação direta (já existe via sistema de hotwire).
        fleeingPed     = ped
        fleeingVehicle = vehicle
        fleeingPlate   = PRCarkeys.SanitizePlate(GetVehicleNumberPlateText(vehicle))
        canLootFleeKey = true
    end

    local cd = math.random(cooldown[1], cooldown[2])
    Wait(cd)
    shotsFired   = 0.0
    isCarjacking = false
    cjDebug("SUCCESS", ("doCarjack concluido | cooldown=%d ms"):format(cd))
end

-- ----------------------------------------------------------------
--   THREAD — Conta tiros próximos ao alvo atual
-- ----------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(0)

        -- Só conta se houver alvo ativo e player não estiver em veículo
        if not isNpcSurrendered or not currentTarget then goto nextShot end
        if cache.vehicle and cache.vehicle ~= 0 then goto nextShot end

        if IsPedShooting(cache.ped) and canCount then
            -- Verifica se está atirando na direção do alvo (distância)
            local dist = #(GetEntityCoords(cache.ped) - GetEntityCoords(currentTarget))
            if dist <= (Config.Carjack.aimDistance or 30.0) then
                shotsFired = math.min(shotsFired + 0.03, 1.0)  -- clamp máx 1.0
                canCount   = false
                cjDebug("INFO", ("Tiro contado | shotsFired=%.2f"):format(shotsFired))

                SetTimeout(50, function()
                    canCount = true
                end)
            end
        end

        ::nextShot::
    end
end)

-- ----------------------------------------------------------------
--   LOOP PRINCIPAL — 200ms
-- ----------------------------------------------------------------
CreateThread(function()
    cjDebug("INFO", "Loop de carjack iniciado")

    while true do
        Wait(200)

        if not Config.Carjack or not Config.Carjack.enabled then goto continue end
        if isConfiscating or isCarjacking then goto continue end

        -- ---------------------------------------------------------
        -- Loot da chave quando NPC fugiu com ela (matar e pegar)
        -- Roda ANTES de qualquer condicional de mira/arma.
        -- ---------------------------------------------------------
        if canLootFleeKey and fleeingPed and fleeingVehicle and DoesEntityExist(fleeingVehicle) then
            if not DoesEntityExist(fleeingPed) then
                clearFleeKeyState()
            else
                local dead = IsPedDeadOrDying(fleeingPed, true)
                if dead then
                    local dist = #(GetEntityCoords(cache.ped) - GetEntityCoords(fleeingPed))
                    if dist <= 2.0 and not lootBusy then
                        showHint(Config.Carjack.hintText or "[E] Procurar chave")
                        if IsControlJustPressed(0, 38) then -- E
                            lootBusy = true
                            local duration = Config.Carjack.minTime and Config.Carjack.minTime[1] or 2500
                            playSearchAnim(fleeingPed)
                            doProgressBar(duration, Config.Carjack.label or "Procurando chave...", function(ok)
                                stopSearchAnim()
                                if ok and DoesEntityExist(fleeingVehicle) then
                                    TriggerServerEvent(
                                        "pr_carkeys:server:grantTemporaryKeyItemNearbyVehicle",
                                        NetworkGetNetworkIdFromEntity(fleeingVehicle),
                                        fleeingPlate
                                    )
                                else
                                    PRCarkeys.Notify(Config.Carjack.notifyFail or Config.Notify.noPermission)
                                end
                                hideHint()
                                clearFleeKeyState()
                            end)
                        end
                    elseif dist > 2.0 and textUIVisible then
                        hideHint()
                    end
                end
            end
        end

        -- Player dentro de um veículo: cancela qualquer render ativo
        if cache.vehicle and cache.vehicle ~= 0 then
            if isNpcSurrendered and currentTarget then
                cancelSurrender(currentTarget, currentVehicle)
            end
            goto continue
        end

        -- Sem arma ou arma na blacklist
        local weapon = GetSelectedPedWeapon(cache.ped)
        if weapon == GetHashKey("WEAPON_UNARMED") then
            if isNpcSurrendered and currentTarget then
                cancelSurrender(currentTarget, currentVehicle)
            end
            goto continue
        end
        if isBlacklistedWeapon() then goto continue end

        -- Não está mirando
        if not IsPlayerFreeAiming(cache.playerId) then
            if isNpcSurrendered and currentTarget then
                cancelSurrender(currentTarget, currentVehicle)
            end
            goto continue
        end

        local aiming, target = GetEntityPlayerIsFreeAimingAt(cache.playerId)

        if not aiming or not target or target == 0 or not DoesEntityExist(target) then
            if isNpcSurrendered and currentTarget then
                cancelSurrender(currentTarget, currentVehicle)
            end
            goto continue
        end

        if IsPedAPlayer(target)                 then goto continue end
        if IsPedDeadOrDying(target, false)      then goto continue end
        if not IsPedInAnyVehicle(target, false) then goto continue end

        local veh = GetVehiclePedIsIn(target, false)
        if GetPedInVehicleSeat(veh, -1) ~= target then goto continue end

        local dist = #(GetEntityCoords(cache.ped) - GetEntityCoords(target))
        if dist > (Config.Carjack.aimDistance or 30.0) then
            if isNpcSurrendered and currentTarget then
                cancelSurrender(currentTarget, currentVehicle)
            end
            goto continue
        end

        -- Mudou de alvo: cancela o anterior
        if isNpcSurrendered and currentTarget ~= target then
            cancelSurrender(currentTarget, currentVehicle)
        end

        -- ── POLICIAL ──────────────────────────────────────────────
        if Bridge.framework.isPolice() then
            if not isNpcSurrendered then
                isNpcSurrendered = true
                currentTarget    = target
                currentVehicle   = veh

                brakeNpcVehicle(target, veh)

                CreateThread(function()
                    Wait(600)
                    if isNpcSurrendered and DoesEntityExist(target) and not handsUpPedd then
                        handsUpPedd = true
                        handsUpPed(target, veh)
                    end
                end)

                showHint(Config.Carjack.policeHint or "[E] Confiscar veiculo")
                cjDebug("INFO", ("Policial mirando NPC | dist=%.1f"):format(dist))

                local pedRef = target
                local vehRef = veh
                CreateThread(function()
                    while isNpcSurrendered and not isConfiscating do
                        local stillAiming, stillTarget = GetEntityPlayerIsFreeAimingAt(cache.playerId)
                        local stillInRange = DoesEntityExist(pedRef)
                            and #(GetEntityCoords(cache.ped) - GetEntityCoords(pedRef)) <= (Config.Carjack.aimDistance or 30.0)

                        if not IsPlayerFreeAiming(cache.playerId)
                        or not stillAiming
                        or stillTarget ~= pedRef
                        or not stillInRange then
                            cancelSurrender(pedRef, vehRef)
                            return
                        end

                        if IsControlJustPressed(0, 38) then
                            CreateThread(function()
                                confiscateVehicle(pedRef, vehRef)
                            end)
                            return
                        end

                        Wait(0)
                    end
                end)
            end

            goto continue
        end

        -- ── CIVIL ─────────────────────────────────────────────────
        -- Ao mirar no NPC: dispara o carjack imediatamente (sem [E])
        if not isNpcSurrendered then
            isNpcSurrendered = true
            currentTarget    = target
            currentVehicle   = veh

            cjDebug("INFO", ("Civil mirando NPC | dist=%.1f | weapon=%.2f | shots=%.2f")
                :format(dist, getWeaponChance(), shotsFired))

            local pedRef = target
            local vehRef = veh
            -- Pequeno delay para dar tempo de contar mais tiros se o player já estiver atirando
            CreateThread(function()
                Wait(300)
                if isNpcSurrendered then
                    isNpcSurrendered = false  -- libera antes de chamar
                    doCarjack(pedRef, vehRef)
                end
            end)
        end

        ::continue::
    end
end)