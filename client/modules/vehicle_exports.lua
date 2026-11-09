-- Public client contracts are registered before the reactive vehicle modules.
-- This keeps qbx_core integrations available even if a later module fails.
local VehicleState = assert(
    PRCarkeys.VehicleState,
    "[pr_carkeys] VehicleState deve ser carregado antes dos exports"
)

exports("HaveKey", function(plate)
    return VehicleState:HasKey(plate)
end)

exports("HavePermanentKey", function(plate)
    if not plate then return false end
    local normalized = PRCarkeys.SanitizePlate(plate)
    return normalized ~= nil and VehicleState.permanentKeys[normalized] ~= nil
end)

exports("HaveTempKey", function(plate)
    if not plate then return false end
    local normalized = PRCarkeys.SanitizePlate(plate)
    return normalized ~= nil and VehicleState.temporaryKeys[normalized] == true
end)

return true
