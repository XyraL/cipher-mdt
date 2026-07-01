-- CipherMDT Blips — live on-duty officer/EMS/fire blips on the game map

local _blips = {}       -- [citizenid] = blip handle
local _blipData = {}    -- [citizenid] = last known state (for label refresh)

-- Blip sprite IDs
local SPRITE = {
    ON_FOOT     = 1,
    CAR         = 225,
    MOTORCYCLE  = 226,
    HELICOPTER  = 64,
    PLANE       = 307,
    BOAT        = 427,
    BICYCLE     = 348,
}

-- Blip colors per job
local JOB_COLOR = {
    police    = 3,   -- blue
    sheriff   = 3,   -- blue
    swat      = 3,   -- blue
    ambulance = 5,   -- yellow
    fire      = 1,   -- red
}
local DEFAULT_COLOR = 3

local function GetJobColor(jobName)
    return JOB_COLOR[jobName] or DEFAULT_COLOR
end

local function GetVehicleSprite(veh)
    if not veh or veh == 0 then return SPRITE.ON_FOOT end
    local vehClass = GetVehicleClass(veh)
    -- Vehicle class IDs: 8=motorcycle, 9=bicycle, 13=cycle, 14=boat, 15=helicopter, 16=plane
    if vehClass == 8  then return SPRITE.MOTORCYCLE end
    if vehClass == 9 or vehClass == 13 then return SPRITE.BICYCLE end
    if vehClass == 14 then return SPRITE.BOAT end
    if vehClass == 15 then return SPRITE.HELICOPTER end
    if vehClass == 16 then return SPRITE.PLANE end
    return SPRITE.CAR
end

local function MakeBlipLabel(name, badge, inVehicle, vehClass)
    local status = ''
    if inVehicle then
        if vehClass == 15 then status = ' [AIR]'
        elseif vehClass == 14 then status = ' [BOAT]'
        else status = ' [VEH]' end
    end
    return (badge ~= '' and badge ~= 'N/A') and (name .. ' [' .. badge .. ']' .. status) or (name .. status)
end

local function CreateBlip(citizenid, name, badge, jobName, coords, sprite, color)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipColour(blip, color)
    SetBlipScale(blip, 0.82)
    SetBlipAsShortRange(blip, false) -- visible at all map zoom levels
    ShowHeadingIndicatorOnBlip(blip, true)

    local label = MakeBlipLabel(name, badge, sprite ~= SPRITE.ON_FOOT, nil)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)

    _blips[citizenid] = blip
    _blipData[citizenid] = { name = name, badge = badge, job = jobName, sprite = sprite }
end

local function UpdateBlip(citizenid, coords, sprite, color, name, badge)
    local blip = _blips[citizenid]
    if not blip or not DoesBlipExist(blip) then return end

    SetBlipCoords(blip, coords.x, coords.y, coords.z)
    SetBlipColour(blip, color)

    -- Only update sprite/label if something changed (avoids flicker)
    local prev = _blipData[citizenid] or {}
    if prev.sprite ~= sprite or prev.badge ~= badge or prev.name ~= name then
        SetBlipSprite(blip, sprite)
        local inVeh = sprite ~= SPRITE.ON_FOOT
        local label = MakeBlipLabel(name, badge, inVeh, nil)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(label)
        EndTextCommandSetBlipName(blip)
        _blipData[citizenid].sprite = sprite
        _blipData[citizenid].badge  = badge
        _blipData[citizenid].name   = name
    end
end

local function RemoveUnitBlip(citizenid)
    if _blips[citizenid] and DoesBlipExist(_blips[citizenid]) then
        RemoveBlip(_blips[citizenid])
    end
    _blips[citizenid]    = nil
    _blipData[citizenid] = nil
end

-- Receive full unit list from server every broadcast cycle
RegisterNetEvent('cipher-mdt:client:updateBlips', function(units)
    local myData = exports['qbx_core']:GetPlayerData()
    local myCid  = myData and myData.citizenid

    local seen = {}
    for _, unit in ipairs(units) do
        if unit.citizenid == myCid then goto continue end -- skip self

        seen[unit.citizenid] = true
        local coords = unit.coords or { x = 0, y = 0, z = 0 }
        local color  = GetJobColor(unit.job)
        local sprite = unit.sprite or SPRITE.ON_FOOT

        if _blips[unit.citizenid] and DoesBlipExist(_blips[unit.citizenid]) then
            UpdateBlip(unit.citizenid, coords, sprite, color, unit.name, unit.badge or '')
        else
            CreateBlip(unit.citizenid, unit.name, unit.badge or '', unit.job, coords, sprite, color)
        end

        ::continue::
    end

    -- Remove blips for units no longer in the list (went off-duty / disconnected)
    for cid in pairs(_blips) do
        if not seen[cid] then RemoveUnitBlip(cid) end
    end
end)

-- ── Position broadcast loop ───────────────────────────────────────────────
-- Runs every 2 seconds. Sends coords + vehicle sprite so the server
-- can forward the correct icon to all other clients.
CreateThread(function()
    while true do
        Wait(2000)
        local pd = exports['qbx_core']:GetPlayerData()
        if not pd or not pd.job then goto continue end
        if not Config.AuthorizedJobs[pd.job.name] then goto continue end
        if Config.OnDutyOnly and not pd.job.onduty then goto continue end

        local ped    = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local inVeh  = IsPedInAnyVehicle(ped, false)
        local veh    = inVeh and GetVehiclePedIsIn(ped, false) or 0
        local sprite = GetVehicleSprite(veh)
        local heading= GetEntityHeading(ped)

        TriggerServerEvent('cipher-mdt:server:broadcastPosition', {
            x       = coords.x,
            y       = coords.y,
            z       = coords.z,
            sprite  = sprite,
            heading = heading,
        })

        ::continue::
    end
end)

-- Clean up all blips when resource stops
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for cid, blip in pairs(_blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    _blips    = {}
    _blipData = {}
end)
