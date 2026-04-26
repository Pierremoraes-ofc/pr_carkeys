-- ============================================================
--   pr_carkeys — shared/bridge.lua
--   Bridge próprio — suporte standalone sem ox_lib.
--   Frameworks: qb-core | qbx-core | es_extended | ox_core | ND_Core
--   Inventários: ox_inventory | qb-inventory
--   Menus:       ox_lib (se disponível) | qb-menu (fallback)
-- ============================================================

Bridge                = Bridge or {}
Bridge.framework      = Bridge.framework or {}
Bridge.inventory      = Bridge.inventory or {}
Bridge.notify         = Bridge.notify    or {}
Bridge.progress       = Bridge.progress  or {}
Bridge.vehicle_key    = Bridge.vehicle_key or {}

local fw  = PRCarkeys.ActiveResource  -- definido em shared/main.lua
local inv = ActiveInventory            -- definido em shared/main.lua

-- ============================================================
--   SERVER-SIDE
-- ============================================================
if IsDuplicityVersion() then

    -- ──────────────────────────────────────────────────────────
    --   FRAMEWORK — RegisterUsableItem / GetPlayer / GetIdentifier
    -- ──────────────────────────────────────────────────────────

    -- qb-core (standalone / sem QBX)
    if fw == "qb-core" then
        local QBCore = exports["qb-core"]:GetCoreObject()

        function Bridge.framework.RegisterUsableItem(item, cb)
            QBCore.Functions.CreateUseableItem(item, function(source, itemData)
                cb(source, itemData)
            end)
        end

        function Bridge.framework.GetPlayer(src)
            return QBCore.Functions.GetPlayer(src)
        end

        function Bridge.framework.GetIdentifier(src)
            local Player = QBCore.Functions.GetPlayer(src)
            return Player and Player.PlayerData.citizenid or nil
        end

    -- qbx-core (fork do QBCore)
    elseif fw == "qbx-core" then
        -- QBX mantém compat com exports qb-core
        local QBCore = exports["qb-core"]:GetCoreObject()

        function Bridge.framework.RegisterUsableItem(item, cb)
            QBCore.Functions.CreateUseableItem(item, function(source, itemData)
                cb(source, itemData)
            end)
        end

        function Bridge.framework.GetPlayer(src)
            return QBCore.Functions.GetPlayer(src)
        end

        function Bridge.framework.GetIdentifier(src)
            local Player = QBCore.Functions.GetPlayer(src)
            return Player and Player.PlayerData.citizenid or nil
        end

    -- es_extended (ESX Legacy usa ox_inventory; não suportamos compat antigo)
    elseif fw == "es_extended" then
        local ESX = exports["es_extended"]:getSharedObject()

        function Bridge.framework.RegisterUsableItem(item, cb)
            -- ESX Legacy com ox_inventory: registro via hook
            if inv == "ox_inventory" then
                exports.ox_inventory:registerHook("useItem", function(payload)
                    if payload.item.name == item then
                        cb(payload.source, payload.item)
                        return false
                    end
                end)
            else
                ESX.RegisterUsableItem(item, function(source)
                    cb(source, {})
                end)
            end
        end

        function Bridge.framework.GetPlayer(src)
            return ESX.GetPlayerFromId(src)
        end

        function Bridge.framework.GetIdentifier(src)
            local xPlayer = ESX.GetPlayerFromId(src)
            return xPlayer and xPlayer.getIdentifier() or nil
        end

    -- ox_core
    elseif fw == "ox_core" then
        function Bridge.framework.RegisterUsableItem(item, cb)
            exports.ox_inventory:registerHook("useItem", function(payload)
                if payload.item.name == item then
                    cb(payload.source, payload.item)
                    return false
                end
            end)
        end

        function Bridge.framework.GetPlayer(src)
            return Ox.GetPlayer(src)
        end

        function Bridge.framework.GetIdentifier(src)
            local player = Ox.GetPlayer(src)
            return player and tostring(player.charId) or nil
        end

    -- ND_Core
    elseif fw == "ND_Core" then
        function Bridge.framework.RegisterUsableItem(item, cb)
            if inv == "ox_inventory" then
                exports.ox_inventory:registerHook("useItem", function(payload)
                    if payload.item.name == item then
                        cb(payload.source, payload.item)
                        return false
                    end
                end)
            else
                Debug("WARNING", ("RegisterUsableItem: ND_Core sem ox_inventory — item '%s' nao registrado."):format(item))
            end
        end

        function Bridge.framework.GetPlayer(src)
            return exports["ND_Core"]:GetPlayer(src)
        end

        function Bridge.framework.GetIdentifier(src)
            local player = exports["ND_Core"]:GetPlayer(src)
            return player and tostring(player.citizenid) or nil
        end

    -- Fallback
    else
        function Bridge.framework.RegisterUsableItem(item, cb)
            Debug("WARNING", ("RegisterUsableItem: framework '%s' nao suportado para '%s'"):format(fw, item))
        end
        function Bridge.framework.GetPlayer(src) return nil end
        function Bridge.framework.GetIdentifier(src) return nil end
    end

    -- ──────────────────────────────────────────────────────────
    --   INVENTÁRIO (SERVER)
    -- ──────────────────────────────────────────────────────────

    if inv == "ox_inventory" then

        function Bridge.inventory.RegisterStash(stashId, label, slots, weight, owner)
            exports.ox_inventory:RegisterStash(stashId, label, slots, weight, false)
        end

        function Bridge.inventory.GetInventory(stashId)
            return exports.ox_inventory:GetInventory(stashId, false) or {}
        end

        function Bridge.inventory.GetSlot(src, slot)
            return exports.ox_inventory:GetSlot(src, slot)
        end

        function Bridge.inventory.AddItem(src, item, count, metadata)
            count = count or 1
            return exports.ox_inventory:AddItem(src, item, count, metadata)
        end

        function Bridge.inventory.RemoveItemByBarcode(src, barcode)
            -- 1. Inventário direto — Search com partial match por barcode
            for itemName, _ in pairs(Config.KeyTypes) do
                local slots = exports.ox_inventory:Search(src, "slots", itemName, { barcode = barcode })
                if slots and #slots > 0 then
                    -- Remoção por slot é mais confiável que metadata filter (evita mismatch de meta/serialização)
                    local removedAny = false
                    for _, s in ipairs(slots) do
                        local ok = exports.ox_inventory:RemoveItem(src, itemName, 1, nil, s.slot)
                        if ok then
                            removedAny = true
                            Debug("INFO", ("RemoveItemByBarcode: inventario | OK | item=%s | barcode=%s | slot=%s"):format(
                                itemName, barcode, tostring(s.slot)))
                            break
                        end
                    end
                    if not removedAny then
                        Debug("WARNING", ("RemoveItemByBarcode: inventario | FALHOU | item=%s | barcode=%s"):format(
                            itemName, barcode))
                    end
                    return
                end
            end

            -- 2. Bolsas do player
            for _, bagName in ipairs({ "carkey_bag", "carkey_bag_large" }) do
                local bagSlots = exports.ox_inventory:GetSlotsWithItem(src, bagName, nil)
                if bagSlots then
                    for _, bagSlot in pairs(bagSlots) do
                        local bagMeta = bagSlot.metadata or {}
                        if bagMeta.barcode then
                            local stashId = "pr_carkeys_bag_" .. bagMeta.barcode
                            for itemName, _ in pairs(Config.KeyTypes) do
                                local keySlots = exports.ox_inventory:Search(stashId, "slots", itemName, { barcode = barcode })
                                if keySlots and #keySlots > 0 then
                                    local targetSlot = keySlots[1].slot
                                    -- Igual ao inventário direto: sem metadata, só slot
                                    local ok = exports.ox_inventory:RemoveItem(stashId, itemName, 1, nil, targetSlot)
                                    Debug("INFO", ("RemoveItemByBarcode: bolsa | %s | stash=%s | item=%s | barcode=%s | slot=%s"):format(
                                        ok and "OK" or "FALHOU", stashId, itemName, barcode, tostring(targetSlot)))
                                    return
                                end
                            end
                        end
                    end
                end
            end

            Debug("WARNING", ("RemoveItemByBarcode: nao encontrado | src=%d | barcode=%s"):format(src, barcode))
        end

        function Bridge.inventory.SetMetadata(src, slot, metadata)
            exports.ox_inventory:SetMetadata(src, slot, metadata)
        end

        function Bridge.inventory.GetItemBySlot(src, slot)
            return exports.ox_inventory:GetSlot(src, slot)
        end

        function Bridge.inventory.closeInventory()
            exports.ox_inventory:closeInventory()
        end

    else -- qb-inventory

        function Bridge.inventory.RegisterStash(stashId, label, slots, weight, owner)
            exports["qb-inventory"]:RegisterStash(stashId, slots, weight)
        end

        function Bridge.inventory.GetInventory(stashId)
            return exports["qb-inventory"]:GetStashItems(stashId) or {}
        end

        function Bridge.inventory.GetSlot(src, slot)
            local Player = Bridge.framework.GetPlayer(src)
            if not Player then return nil end
            return Player.PlayerData.items and Player.PlayerData.items[slot] or nil
        end

        function Bridge.inventory.AddItem(src, item, count, metadata)
            count = count or 1
            if fw == "qb-core" then
                local QBCore = exports["qb-core"]:GetCoreObject()
                local Player = QBCore.Functions.GetPlayer(src)
                if Player then
                    Player.Functions.AddItem(item, count, nil, metadata)
                    TriggerClientEvent("inventory:client:ItemBox", src, QBCore.Shared.Items[item], "add")
                end
            elseif fw == "qbx-core" then
                local QBCore = exports["qb-core"]:GetCoreObject()
                local Player = QBCore.Functions.GetPlayer(src)
                if Player then
                    Player.Functions.AddItem(item, count, nil, metadata)
                    TriggerClientEvent("inventory:client:ItemBox", src, QBCore.Shared.Items[item], "add")
                end
            else
                Debug("WARNING", ("AddItem: framework '%s' nao tem suporte para qb-inventory."):format(fw))
            end
        end

        function Bridge.inventory.RemoveItemByBarcode(src, barcode)
            local Player = Bridge.framework.GetPlayer(src)
            if not Player then return end
            local items = Player.PlayerData.items
            for slot, item in pairs(items or {}) do
                local meta = item.info or item.metadata or {}
                if meta.barcode == barcode then
                    Player.Functions.RemoveItem(item.name, 1, slot)
                    break
                end
            end
        end

        function Bridge.inventory.SetMetadata(src, slot, metadata)
            local Player = Bridge.framework.GetPlayer(src)
            if not Player then return end
            local item = Player.PlayerData.items[slot]
            if not item then return end
            item.info = metadata
            Player.Functions.SetInventory(Player.PlayerData.items)
        end

        function Bridge.inventory.GetItemBySlot(src, slot)
            local Player = Bridge.framework.GetPlayer(src)
            if not Player then return nil end
            return Player.PlayerData.items and Player.PlayerData.items[slot] or nil
        end

        function Bridge.inventory.closeInventory()
            -- nao é necessario
        end
    end

    -- ──────────────────────────────────────────────────────────
    --   NOTIFY (SERVER)
    -- ──────────────────────────────────────────────────────────
    function Bridge.notify.Notify(src, data)
        if not src or not data then return end

        -- ox_lib (opcional)
        if GetResourceState("ox_lib"):find("start") then
            TriggerClientEvent("ox_lib:notify", src, {
                title       = data.title,
                description = data.description,
                type        = data.type or "inform",
            })

        -- qb-core
        elseif fw == "qb-core" then
            TriggerClientEvent("QBCore:Notify", src, data.description, data.type or "primary")

        -- qbx-core
        elseif fw == "qbx-core" then
            TriggerClientEvent("QBCore:Notify", src, data.description, data.type or "primary")

        -- ESX
        elseif fw == "es_extended" then
            TriggerClientEvent("esx:showNotification", src, data.description)

        -- Fallback chat
        else
            TriggerClientEvent("chat:addMessage", src, { args = { "[pr_carkeys]", data.description } })
        end
    end

end -- fim IsDuplicityVersion()

-- ============================================================
--   CLIENT-SIDE
-- ============================================================
if not IsDuplicityVersion() then

    -- ──────────────────────────────────────────────────────────
    --   NOTIFY (CLIENT)
    -- ──────────────────────────────────────────────────────────
    function Bridge.notify.Notify(data)
        if not data then return end

        -- ox_lib (opcional)
        if GetResourceState("ox_lib"):find("start") then
            lib.notify({
                title       = data.title,
                description = data.description,
                type        = data.type or "inform",
            })

        -- qb-core
        elseif fw == "qb-core" then
            exports["qb-core"]:GetCoreObject().Functions.Notify(data.description, data.type or "primary")

        -- qbx-core
        elseif fw == "qbx-core" then
            exports["qb-core"]:GetCoreObject().Functions.Notify(data.description, data.type or "primary")

        -- ESX
        elseif fw == "es_extended" then
            exports["es_extended"]:getSharedObject().ShowNotification(data.description)

        -- Fallback chat
        else
            TriggerEvent("chat:addMessage", { args = { "[pr_carkeys]", data.description } })
        end
    end

    -- ──────────────────────────────────────────────────────────
    --   PROGRESSBAR (CLIENT)
    --   Bridge.progress definido como tabela vazia caso não haja
    --   implementação — cl_main.lua usa ox_lib ou fallback simples.
    -- ──────────────────────────────────────────────────────────
    Bridge.progress = {}
    -- Sem implementação própria: cl_main.lua detecta e usa ox_lib ou fallback

    -- ──────────────────────────────────────────────────────────
    --   VEHICLE KEYS (CLIENT)
    -- ──────────────────────────────────────────────────────────
    if GetResourceState("qb-vehiclekeys"):find("start") then
        function Bridge.vehicle_key.GiveKeys(vehicle, plate)
            exports["qb-vehiclekeys"]:GiveKeys(plate)
        end
    elseif GetResourceState("ND_vehicleKeys"):find("start") then
        function Bridge.vehicle_key.GiveKeys(vehicle, plate)
            exports["ND_vehicleKeys"]:addKey(plate)
        end
    else
        function Bridge.vehicle_key.GiveKeys(vehicle, plate)
            -- Sem vehicle keys externo: nenhuma ação necessária
        end
    end

    -- ──────────────────────────────────────────────────────────
    --   INVENTÁRIO (CLIENT) — metadata slot
    -- ──────────────────────────────────────────────────────────
    function Bridge.inventory.GetSlotMetadata(slot)
        if inv == "ox_inventory" then
            local slotData = exports.ox_inventory:GetSlot(cache.playerId, slot)
            return slotData and (slotData.metadata or slotData.info) or {}
        else
            -- qb-inventory: via PlayerData
            local items = exports["qb-core"]:GetCoreObject().Functions.GetPlayerData().items
            local item  = items and items[slot]
            return item and (item.info or item.metadata) or {}
        end
    end

    -- ──────────────────────────────────────────────────────────
    --   MINIGAME (CLIENT)
    -- ──────────────────────────────────────────────────────────
    Bridge.minigame = {}  -- ← declaração obrigatória antes de usar

    function Bridge.minigame.Start(mode)
        -- mode: 'parked' | 'carjack'
        local cfg = Config.Minigame
        local data = (mode == 'parked')
            and cfg.dificultMinigame.vehiParked   -- ← caminho correto
            or  cfg.dificultMinigame.vehiCarjack

        local success = false

        -- ── glitch-minigame ───────────────────────────────────
        local glitchStarted = GetResourceState("glitch-minigame"):find("start")
            or GetResourceState("glitch-minigames"):find("start")
        if cfg.minigame == "glitch-minigame" and glitchStarted then
            local g = cfg.game
            local exportName = GetResourceState("glitch-minigames"):find("start")
                and "glitch-minigames"
                or "glitch-minigame"
            local gm = exports[exportName]

            if     g == "BarHit"            then success = gm:StartBarHitGame(data.rounds, data.speed, data.zoneSize, data.maxFailures, data.timeLimit)
            elseif g == "SkillCheck"        then success = gm:StartSkillCheckGame(data.speed, data.timeLimit, data.zoneSize, data.perfectZoneSize, data.maxFailures, data.randomizeZone)
            elseif g == "NumberUp"          then success = gm:StartNumberUpGame(data.count, data.timeLimit, data.gridCols, data.maxMistakes)
            elseif g == "ComboInput"        then success = gm:StartComboInputGame(data.rounds, data.comboLength, data.timePerCombo, data.maxFailures, data.lengthIncrease)
            elseif g == "HoldZone"          then
                -- glitch-minigames espera: (key, rounds, speed, zoneSize, perfectZoneSize, maxFailures, idleTimeoutSeconds)
                local idleTimeout = math.max(3, math.floor(((data.timeLimit or 10000) / 1000)))
                success = gm:StartHoldZoneGame('E', data.rounds, data.speed, data.zoneSize, data.perfectZoneSize, data.maxFailures, idleTimeout)
            elseif g == "WireConnect"       then success = gm:StartWireConnectGame(data.wireCount, data.timeLimit)
            elseif g == "SimonSays"         then success = gm:StartSimonSaysGame(data.rounds, data.flashSpeed, data.flashGap, data.timeLimit, data.maxMistakes)
            elseif g == "AimTest"           then success = gm:StartAimTestGame(data.targetsToHit, data.maxMisses, data.targetLifetime, data.targetSize, data.timeLimit)
            elseif g == "CircleClick"       then success = gm:StartCircleClickGame(data.rounds, data.rotationSpeed, data.targetZoneSize, data.maxFailures, data.speedIncrease, data.randomizeDirection)
            elseif g == "Lockpick"          then success = gm:StartLockpickGame(data.rounds, data.sweetSpotSize, data.maxFailures, data.shakeRange, data.lockTime)
            elseif g == "Keymash"           then success = gm:StartSurgeOverride(data.keyPressValue, data.decayRate)
            elseif g == "Untangle"          then success = gm:StartUntangleGame(data.nodeCount, data.timeLimit)
            elseif g == "Pairs"             then success = gm:StartPairsGame(data.gridSize, data.timeLimit, data.maxAttempts)
            elseif g == "MemoryColors"      then success = gm:StartMemoryColorsGame(data.gridSize, data.memorizeTime, data.answerTime, data.rounds)
            elseif g == "Fingerprint"       then success = gm:StartFingerprintGame(data.timeLimit, data.showAlignedCount, data.showCorrectIndicator)
            elseif g == "CodeCrack"         then success = gm:StartCodeCrackGame(data.timeLimit, data.digitCount, data.maxAttempts)
            elseif g == "FirewallPulse"     then success = gm:StartFirewallPulse(data.requiredHacks, data.initialSpeed, data.maxSpeed, data.timeLimit)
            elseif g == "BackdoorSequence"  then success = gm:StartBackdoorSequence(data.totalStages, data.keysPerStage, data.timeLimit)
            elseif g == "Rhythm"            then success = gm:StartCircuitRhythm(data.lanes, data.noteSpeed, data.noteSpawnRate, data.requiredNotes, data.maxWrongKeys, data.maxMissedNotes)
            elseif g == "Memory"            then success = gm:StartMemoryGame(data.gridSize, data.squareCount, data.rounds, data.showTime, data.maxWrongPresses)
            elseif g == "SequenceMemory"    then success = gm:StartSequenceMemoryGame(data.gridSize, data.rounds, data.showTime, data.delayBetween, data.maxWrongPresses)
            elseif g == "VerbalMemory"      then success = gm:StartVerbalMemoryGame(data.maxStrikes, data.wordsToShow, data.wordDuration)
            elseif g == "NumberedSequence"  then success = gm:StartNumberedSequenceGame(data.gridSize, data.sequenceLength, data.rounds, data.showTime, data.guessTime, data.maxWrongPresses)
            elseif g == "SymbolSearch"      then success = gm:StartSymbolSearchGame(data.gridSize, data.shiftInterval, data.timeLimit, data.minKeyLength, data.maxKeyLength)
            elseif g == "VarHack"           then success = gm:StartVarHack(data.blocks, data.speed)
            elseif g == "PipePressure"      then success = gm:StartPipePressureGame(data.gridSize, data.timeLimit)
            elseif g == "WordCrack"         then success = gm:StartWordCrackGame(data.timeLimit, data.wordLength, data.maxAttempts)
            elseif g == "Balance"           then success = gm:StartBalanceGame(data.timeLimit, data.driftSpeed, data.sensitivity, data.greenZoneWidth, data.yellowZoneWidth, data.driftRandomness, data.maxDangerTime)
            elseif g == "BruteForce"        then success = gm:StartBruteForce(data.numLives)
            elseif g == "DataCrack"         then success = gm:StartDataCrack(data.difficulty)
            elseif g == "CircuitBreaker"    then success = gm:StartCircuitBreaker(data.levelNumber, data.difficultyLevel, data.delayStartMs, data.minFailureDelayTimeMs, data.maxFailureDelayTimeMs, data.disconnectChance, data.disconnectCheckRateMs, data.minReconnectTimeMs, data.maxReconnectTimeMs)
            elseif g == "FleecaDrilling"    then success = gm:StartDrilling()
            elseif g == "PlasmaDrilling"    then success = gm:StartPlasmaDrilling(data.difficulty)
            end

        -- ── mhacking ──────────────────────────────────────────
        elseif cfg.minigame == "mhacking" and GetResourceState("mhacking"):find("start") then
            local g  = cfg.game
            local mh = exports["mhacking"]
            if     g == "lockpick"    then success = mh:Lockpick(data)
            elseif g == "chopping"    then success = mh:Chopping(data)
            elseif g == "pincracker"  then success = mh:PinCracker(data)
            elseif g == "roofrunning" then success = mh:RoofRunning(data)
            elseif g == "thermite"    then success = mh:Thermite(data)
            elseif g == "terminal"    then success = mh:Terminal(data)
            end

        -- ── ox_lib skillcheck ─────────────────────────────────
        elseif cfg.minigame == "ox_lib" and GetResourceState("ox_lib"):find("start") then
            -- data.keys = {'w','a','s','d'} e data.difficulty = {'easy','easy','hard'} na config
            success = lib.skillCheck(data.difficulty or {'easy', 'easy', 'hard'}, data.keys or {'w','a','s','d'})

        else
            -- Nenhum minigame disponível: aprova por padrão
            Debug("WARNING", "Bridge.minigame.Start: nenhum minigame disponivel — aprovado por padrao")
            success = true
        end

        return success
    end

    
    -- ──────────────────────────────────────────────────────────
    --   EMPREGO (SERVER)
    -- ──────────────────────────────────────────────────────────
    function Bridge.framework.isPolice()
    if not Config.Police or not Config.Police.enabled then return false end
    local fw = PRCarkeys.ActiveResource

    if fw == "qb-core" then
        local pd  = exports["qb-core"]:GetCoreObject().Functions.GetPlayerData()
        local job = pd and pd.job and pd.job.name
        if not job then return false end
        for _, j in ipairs(Config.Police.jobs) do
            if job == j then return true end
        end

    elseif fw == "qbx-core" then
        local pd  = exports["qb-core"]:GetCoreObject().Functions.GetPlayerData()
        local job = pd and pd.job and pd.job.name
        if not job then return false end
        for _, j in ipairs(Config.Police.jobs) do
            if job == j then return true end
        end

    elseif fw == "es_extended" then
        local ESX = exports["es_extended"]:getSharedObject()
        local job = ESX.GetPlayerData().job and ESX.GetPlayerData().job.name
        if not job then return false end
        for _, j in ipairs(Config.Police.jobs) do
            if job == j then return true end
        end

    elseif fw == "ox_core" then
        local player = Ox.GetPlayer()
        local job    = player and player.get("job")
        if not job then return false end
        for _, j in ipairs(Config.Police.jobs) do
            if job == j then return true end
        end
    end

    return false
end

    
    -- Stubs client-side
    function Bridge.framework.GetIdentifier() return nil end
    function Bridge.framework.GetPlayer()     return nil end

end
