-- ============================================================
--   pr_carkeys - shared/bridge.lua
--   Adaptador interno do recurso usando pr_bridge como fonte.
-- ============================================================

Bridge = {
    framework = {},
    inventory = {},
    notify = {},
    progress = {},
    vehicle_key = {},
    minigame = {},
}

local function hasBridge(path)
    local current = pr_lib
    for i = 1, #path do
        current = current and current[path[i]]
    end
    return current
end

local function normalizeSlots(slots)
    local result = {}
    if type(slots) ~= "table" then return result end

    for _, slotData in pairs(slots) do
        if type(slotData) == "table" then
            result[#result + 1] = slotData
        end
    end

    return result
end

function Bridge.framework.isPolice(src)
    if not Config.Police or not Config.Police.enabled then return false end
    if not hasBridge({ "framework", "GetPlayerJob" }) then return false end

    local job = pr_lib.framework.GetPlayerJob(src)
    local jobName = type(job) == "table" and job.name or job
    if not jobName then return false end

    for i = 1, #(Config.Police.jobs or {}) do
        if jobName == Config.Police.jobs[i] then return true end
    end

    return false
end

if IsDuplicityVersion() then
    function Bridge.framework.RegisterUsableItem(item, cb)
        if hasBridge({ "inventory", "RegisterUsableItem" }) then
            return pr_lib.inventory.RegisterUsableItem(item, cb, {
                cancelUse = true,
                debug = Config.Debug == true,
            })
        end

        if hasBridge({ "framework", "RegisterUsableItem" }) then
            return pr_lib.framework.RegisterUsableItem(item, cb)
        end

        Debug("ERROR", ("RegisterUsableItem: pr_bridge indisponivel para '%s'"):format(tostring(item)))
        return false
    end

    function Bridge.framework.GetPlayer(src)
        if hasBridge({ "framework", "GetPlayer" }) then
            return pr_lib.framework.GetPlayer(src)
        end
        return nil
    end

    function Bridge.framework.GetIdentifier(src)
        if hasBridge({ "framework", "GetIdentifier" }) then
            return pr_lib.framework.GetIdentifier(src)
        end

        if hasBridge({ "framework", "GetPlayerIdentifier" }) then
            return pr_lib.framework.GetPlayerIdentifier(src)
        end

        local playerData = hasBridge({ "framework", "GetPlayerData" }) and pr_lib.framework.GetPlayerData(src) or nil
        return playerData and (playerData.citizenid or playerData.identifier or playerData.charId or playerData.license) or nil
    end

    function Bridge.inventory.RegisterStash(stashId, label, slots, weight, owner)
        if not hasBridge({ "inventory", "RegisterStash" }) then return false end
        pr_lib.inventory.RegisterStash(stashId, label, slots, weight, owner or false)
        return true
    end

    function Bridge.inventory.GetInventory(stashId)
        if hasBridge({ "inventory", "GetInventory" }) then
            return pr_lib.inventory.GetInventory(stashId, false) or {}
        end

        if hasBridge({ "inventory", "GetInventoryItems" }) then
            return pr_lib.inventory.GetInventoryItems(stashId, false) or {}
        end

        return {}
    end

    function Bridge.inventory.GetSlot(src, slot)
        if not hasBridge({ "inventory", "GetSlot" }) then return nil end
        return pr_lib.inventory.GetSlot(src, slot)
    end

    function Bridge.inventory.AddItem(src, item, count, metadata)
        if not hasBridge({ "inventory", "AddItem" }) then return false end
        return pr_lib.inventory.AddItem(src, item, count or 1, metadata)
    end

    function Bridge.inventory.RemoveItemByBarcode(src, barcode)
        if not barcode or not hasBridge({ "inventory", "Search" }) or not hasBridge({ "inventory", "RemoveItem" }) then
            return false
        end

        for itemName in pairs(Config.KeyTypes or {}) do
            local slots = normalizeSlots(pr_lib.inventory.Search(src, "slots", itemName, { barcode = barcode }))
            for i = 1, #slots do
                local slot = slots[i].slot
                if slot and pr_lib.inventory.RemoveItem(src, itemName, 1, nil, slot) then
                    Debug("INFO", ("RemoveItemByBarcode: inventario | OK | item=%s | barcode=%s | slot=%s"):format(
                        itemName, barcode, tostring(slot)))
                    return true
                end
            end
        end

        local bagItems = {}
        for bagName in pairs(Config.Bags or {}) do
            bagItems[#bagItems + 1] = bagName
        end

        for i = 1, #bagItems do
            local bagSlots = normalizeSlots(pr_lib.inventory.GetSlotsWithItem and pr_lib.inventory.GetSlotsWithItem(src, bagItems[i], nil) or {})
            for j = 1, #bagSlots do
                local bagMeta = bagSlots[j].metadata or bagSlots[j].info or {}
                if bagMeta.barcode then
                    local stashId = PRCarkeys.GetStashId(bagMeta.barcode)
                    for itemName in pairs(Config.KeyTypes or {}) do
                        local keySlots = normalizeSlots(pr_lib.inventory.Search(stashId, "slots", itemName, { barcode = barcode }))
                        for k = 1, #keySlots do
                            local slot = keySlots[k].slot
                            if slot and pr_lib.inventory.RemoveItem(stashId, itemName, 1, nil, slot) then
                                Debug("INFO", ("RemoveItemByBarcode: bolsa | OK | stash=%s | item=%s | barcode=%s | slot=%s"):format(
                                    stashId, itemName, barcode, tostring(slot)))
                                return true
                            end
                        end
                    end
                end
            end
        end

        Debug("WARNING", ("RemoveItemByBarcode: nao encontrado | src=%s | barcode=%s"):format(tostring(src), tostring(barcode)))
        return false
    end

    function Bridge.inventory.SetMetadata(src, slot, metadata)
        if not hasBridge({ "inventory", "SetMetadata" }) then return false end
        return pr_lib.inventory.SetMetadata(src, slot, metadata)
    end

    function Bridge.inventory.GetItemBySlot(src, slot)
        if not hasBridge({ "inventory", "GetItemBySlot" }) then
            return Bridge.inventory.GetSlot(src, slot)
        end
        return pr_lib.inventory.GetItemBySlot(src, slot)
    end

    function Bridge.notify.Notify(src, data)
        if not src or not data or not hasBridge({ "notify", "Notify" }) then return false end
        return pr_lib.notify.Notify(src, data)
    end
else
    function Bridge.notify.Notify(data)
        if not data or not hasBridge({ "notify", "Notify" }) then return false end
        return pr_lib.notify.Notify(data)
    end

    function Bridge.progress.doProgressbar(duration, label, anim)
        if not hasBridge({ "progress", "doProgressbar" }) then return nil end
        return pr_lib.progress.doProgressbar(duration, label, anim)
    end

    function Bridge.progress.doProgressCircle(duration, label, anim)
        if not hasBridge({ "progress", "doProgressCircle" }) then return nil end
        return pr_lib.progress.doProgressCircle(duration, label, anim)
    end

    function Bridge.vehicle_key.GiveKeys(vehicle, plate)
        if not hasBridge({ "vehicle_key", "GiveKeys" }) then return false end
        return pr_lib.vehicle_key.GiveKeys(vehicle, plate)
    end

    function Bridge.inventory.GetSlotMetadata(slot)
        local items = hasBridge({ "inventory", "GetPlayerItems" }) and pr_lib.inventory.GetPlayerItems() or {}
        if type(items) ~= "table" then return {} end

        for key, item in pairs(items) do
            if type(item) == "table" and (item.slot == slot or tonumber(item.slot) == tonumber(slot) or tonumber(key) == tonumber(slot)) then
                return item.metadata or item.info or {}
            end
        end

        return {}
    end

    function Bridge.inventory.closeInventory()
        if not hasBridge({ "inventory", "closeInventory" }) then return false end
        return pr_lib.inventory.closeInventory()
    end

    function Bridge.inventory.openInventory(invType, data)
        if not hasBridge({ "inventory", "openInventory" }) then return false end
        return pr_lib.inventory.openInventory(invType, data)
    end

    function Bridge.minigame.Start(mode)
        if hasBridge({ "minigame", "Start" }) then
            return pr_lib.minigame.Start(Config.Minigame, mode)
        end

        Debug("WARNING", "Bridge.minigame.Start: pr_bridge minigame indisponivel.")
        return false
    end

    function Bridge.framework.GetIdentifier()
        if hasBridge({ "framework", "GetPlayerIdentifier" }) then
            return pr_lib.framework.GetPlayerIdentifier()
        end
        return nil
    end

    function Bridge.framework.GetPlayer()
        if hasBridge({ "framework", "GetPlayer" }) then
            return pr_lib.framework.GetPlayer()
        end
        return nil
    end
end
