local IsAuthorized = function(src) return exports['cipher-mdt']:IsAuthorized(src) end

-- Search vehicle by plate, returns owner info and vehicle details
lib.callback.register('cipher-mdt:server:lookupPlate', function(source, plate)
    if not IsAuthorized(source) then return nil end
    if not plate or #plate < 1 then return nil end

    plate = plate:upper():gsub('%s+', '')

    -- Pull from QBCore player_vehicles table
    local vehicle = MySQL.single.await([[
        SELECT pv.*, p.charinfo, p.citizenid
        FROM player_vehicles pv
        LEFT JOIN players p ON pv.citizenid = p.citizenid
        WHERE UPPER(REPLACE(pv.plate, ' ', '')) = ?
    ]], { plate })

    if not vehicle then
        return { found = false, plate = plate }
    end

    local charinfo = json.decode(vehicle.charinfo)
    local props = vehicle.vehicle and json.decode(vehicle.vehicle) or {}

    -- Check for active BOLO on this plate
    local bolo = MySQL.single.await("SELECT * FROM mdt_bolos WHERE plate = ? AND active = 1", { plate })

    -- Check if owner has active warrants
    local warrants = MySQL.query.await("SELECT COUNT(*) as count FROM mdt_warrants WHERE citizenid = ? AND status = 'active'", { vehicle.citizenid })

    -- Get civilian record for owner
    local civilian = MySQL.single.await('SELECT * FROM mdt_civilians WHERE citizenid = ?', { vehicle.citizenid })

    return {
        found = true,
        plate = plate,
        owner = {
            citizenid = vehicle.citizenid,
            name = charinfo.firstname .. ' ' .. charinfo.lastname,
            dob = charinfo.birthdate,
            phone = charinfo.phone,
        },
        vehicle = {
            model = props.model or vehicle.hash,
            label = props.modelName or 'Unknown',
            color1 = props.color1,
            color2 = props.color2,
            fuel = props.fuelLevel,
            mods = props.mods,
            garage = vehicle.garage,
            state = vehicle.state, -- 0=out, 1=garaged, 2=impounded
        },
        bolo = bolo,
        active_warrants = warrants[1] and warrants[1].count or 0,
        flags = civilian and civilian.flags and json.decode(civilian.flags) or {},
    }
end)

-- Mark vehicle as stolen
lib.callback.register('cipher-mdt:server:flagVehicleStolen', function(source, data)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)

    -- Create a BOLO for the vehicle
    MySQL.insert.await([[
        INSERT INTO mdt_bolos (type, description, reason, plate, issued_by, issued_by_name)
        VALUES ('vehicle', ?, 'Reported Stolen', ?, ?, ?)
    ]], {
        'Stolen Vehicle — Plate: ' .. data.plate .. (data.description and (' — ' .. data.description) or ''),
        data.plate,
        officer.citizenid,
        officer.name
    })

    -- Notify all on-duty officers
    TriggerClientEvent('cipher-mdt:client:boloAlert', -1, {
        type = 'vehicle',
        plate = data.plate,
        description = data.description or 'No additional description',
        issuedBy = officer.name,
    })

    exports['cipher-mdt']:AuditLog('Vehicle Flagged Stolen', officer.name, 'Plate: ' .. data.plate)
    return true
end)
