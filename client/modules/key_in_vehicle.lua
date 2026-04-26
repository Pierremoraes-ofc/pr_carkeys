-- ============================================================
--   pr_carkeys — client/modules/key_in_vehicle.lua
--   Mantido por compatibilidade — lógica movida para vehicle_init.lua
--   PRCarkeys.OnEngineStarted / PRCarkeys.OnEngineStopped
-- ============================================================

local KeyInVehicle = {}

-- Stubs mantidos para não quebrar imports existentes
function KeyInVehicle:OnEngineStart(vehicle, plate)
    if PRCarkeys.OnEngineStarted then
        PRCarkeys.OnEngineStarted(vehicle, plate)
    end
end

function KeyInVehicle:OnEngineStop(vehicle, plate)
    if PRCarkeys.OnEngineStopped then
        PRCarkeys.OnEngineStopped(vehicle, plate)
    end
end

return KeyInVehicle
