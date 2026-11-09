-- Keys remain bound to the original plate, regardless of inventory holder.
function PRCarkeys.ResolveKeyPlate(plate)
    plate = PRCarkeys.SanitizePlate(plate)
    if not plate then return nil end
    if IsDuplicityVersion() and GetResourceState('forge-garage') == 'started' then
        local ok, original = pcall(function()
            return exports['forge-garage']:ResolveVehicleKeyPlate(plate)
        end)
        if ok and original then return original end
    end
    return plate
end

function PRCarkeys.GetVehicleKeyPlate(vehicle)
    local displayed = PRCarkeys.SanitizePlate(GetVehicleNumberPlateText(vehicle))
    if IsDuplicityVersion() then return PRCarkeys.ResolveKeyPlate(displayed) end
    local identity = Entity(vehicle).state.garageVehicleIdentity
    if type(identity) == 'table' then
        local original = PRCarkeys.SanitizePlate(identity.originalPlate)
        local fake = PRCarkeys.SanitizePlate(identity.fakePlate)
        if original and (displayed == original or displayed == fake) then return original end
    end
    return displayed
end

if not IsDuplicityVersion() then
    AddStateBagChangeHandler('garageVehicleIdentity', nil, function(bagName, _, identity)
        local vehicle = GetEntityFromStateBagName(bagName)
        local current = PRCarkeys.VehicleState
        if not current or vehicle == 0 or current.currentVehicle ~= vehicle then return end
        -- Use the callback value: the state bag may still expose the previous value here.
        local displayed = PRCarkeys.SanitizePlate(GetVehicleNumberPlateText(vehicle))
        local original = type(identity) == 'table' and PRCarkeys.SanitizePlate(identity.originalPlate)
        local fake = type(identity) == 'table' and PRCarkeys.SanitizePlate(identity.fakePlate)
        current.currentPlate = original and (displayed == original or displayed == fake) and original or displayed
        current.hasKey = current:HasKey(current.currentPlate)
    end)
end
