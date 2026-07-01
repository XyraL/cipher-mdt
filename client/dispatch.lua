-- CipherMDT Client Dispatch — detects game events and sends auto-dispatch calls

-- Suppression table: callType -> true means blocked
local _suppressed = {}

-- Export: other resources suppress a call type
--   exports['cipher-mdt']:SuppressDispatch('SHOTS_FIRED', true)
--   exports['cipher-mdt']:SuppressDispatch('SHOTS_FIRED', false)
exports('SuppressDispatch', function(callType, suppressed)
    _suppressed[callType] = suppressed == true
end)

-- Net event alternative (for scripts that prefer events over exports)
--   TriggerEvent('cipher-mdt:client:setSuppression', 'SHOTS_FIRED', true)
AddEventHandler('cipher-mdt:client:setSuppression', function(callType, suppressed)
    _suppressed[callType] = suppressed == true
end)

local function IsSuppr(callType)
    return _suppressed[callType] == true
end

local function GetStreetLabel(x, y, z)
    local streetHash, _ = GetStreetNameAtCoord(x, y, z)
    return GetStreetNameFromHashKey(streetHash)
end

local function SendDispatch(callType, description, coords)
    local street = GetStreetLabel(coords.x, coords.y, coords.z)
    TriggerServerEvent('cipher-mdt:server:autoDispatch', {
        callType    = callType,
        description = description,
        street      = street,
        coords      = { x = coords.x, y = coords.y, z = coords.z },
    })
end

-- Gunshot detection (native GTA event)
local _lastShotAlert = 0
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventGunShot' then return end
    if IsSuppr('SHOTS_FIRED') then return end
    local now = GetGameTimer()
    if now - _lastShotAlert < 15000 then return end
    _lastShotAlert = now
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    SendDispatch('SHOTS_FIRED', 'Shots fired reported in the area.', coords)
end)

-- Fight / assault detection via animation
local _lastFightAlert = 0
CreateThread(function()
    while true do
        Wait(3000)
        if IsSuppr('FIGHT') then goto continue end
        local now   = GetGameTimer()
        local ped   = PlayerPedId()
        if IsPedInMeleeCombat(ped) and now - _lastFightAlert > 30000 then
            _lastFightAlert = now
            local coords = GetEntityCoords(ped)
            SendDispatch('FIGHT', 'Physical altercation reported.', coords)
        end
        ::continue::
    end
end)

-- Vehicle crash detection
local _lastCrashAlert = 0
CreateThread(function()
    while true do
        Wait(1000)
        if IsSuppr('VEHICLE_CRASH') then goto continue end
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            local spd = GetEntitySpeed(veh)
            local now = GetGameTimer()
            if GetEntityHealth(veh) < 700 and spd < 2.0 and now - _lastCrashAlert > 45000 then
                _lastCrashAlert = now
                local coords = GetEntityCoords(veh)
                SendDispatch('VEHICLE_CRASH', 'Vehicle crash reported.', coords)
            end
        end
        ::continue::
    end
end)

-- Robbery / store robbery events (common QBCore events)
AddEventHandler('police:client:robbery', function(coords, desc)
    if IsSuppr('ROBBERY') then return end
    if not coords then coords = GetEntityCoords(PlayerPedId()) end
    SendDispatch('ROBBERY', desc or 'Robbery in progress.', coords)
end)

-- Bank robbery
AddEventHandler('qb-bankrobbery:client:started', function(data)
    if IsSuppr('BANK_ROBBERY') then return end
    local coords = data and data.coords or GetEntityCoords(PlayerPedId())
    SendDispatch('BANK_ROBBERY', 'Bank robbery in progress!', coords)
end)

-- Store robbery (common event from qb-robbery)
AddEventHandler('qb-robbery:client:notify', function(data)
    if IsSuppr('STORE_ROBBERY') then return end
    local coords = data and data.coords or GetEntityCoords(PlayerPedId())
    SendDispatch('STORE_ROBBERY', 'Store robbery in progress.', coords)
end)

-- Public API: other resources trigger a custom dispatch call directly
--   TriggerEvent('cipher-mdt:client:dispatch:custom', 'CUSTOM', 'Description', vector3(x,y,z))
AddEventHandler('cipher-mdt:client:dispatch:custom', function(callType, description, coords)
    if IsSuppr(callType) or IsSuppr('CUSTOM') then return end
    if not coords then coords = GetEntityCoords(PlayerPedId()) end
    SendDispatch(callType, description, coords)
end)
