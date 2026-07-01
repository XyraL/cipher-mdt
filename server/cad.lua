local IsAuthorized = function(src) return exports['cipher-mdt']:IsAuthorized(src) end
local activeCalls = {} -- in-memory cache for live calls

-- Generate a unique call number: e.g. CAD-20240615-001
local function GenerateCallNumber()
    local date  = os.date('%Y%m%d')
    local count = MySQL.scalar.await(
        "SELECT COALESCE(MAX(CAST(SUBSTRING_INDEX(call_number,'-',-1) AS UNSIGNED)),0)+1 FROM mdt_cad_calls WHERE DATE(created_at)=CURDATE()") or 1
    return string.format('CAD-%s-%03d', date, count)
end

lib.callback.register('cipher-mdt:server:getActiveCalls', function(source)
    if not IsAuthorized(source) then return nil end
    local calls = MySQL.query.await([[
        SELECT * FROM mdt_cad_calls
        WHERE status NOT IN ('completed', 'cancelled')
        ORDER BY created_at DESC
    ]], {})
    for _, c in ipairs(calls) do
        c.units = c.units and json.decode(c.units) or {}
        c.notes = c.notes and json.decode(c.notes) or {}
        c.coords = c.coords and json.decode(c.coords) or nil
    end
    return calls
end)

lib.callback.register('cipher-mdt:server:createCall', function(source, data)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    if not data.type or not data.description or not data.location then return false end

    local callNumber = GenerateCallNumber()
    local priority = math.max(1, math.min(3, tonumber(data.priority) or 2))
    local id = MySQL.insert.await([[
        INSERT INTO mdt_cad_calls (call_number, call_type, description, location, coords, units, caller_id, caller_name, status, priority)
        VALUES (?, ?, ?, ?, ?, '[]', ?, ?, 'pending', ?)
    ]], {
        callNumber, data.type, data.description, data.location,
        data.coords and json.encode(data.coords) or nil,
        officer.citizenid, officer.name, priority
    })

    local call = {
        id = id,
        call_number = callNumber,
        call_type = data.type,
        type = data.type,
        description = data.description,
        location = data.location,
        coords = data.coords,
        priority = priority,
        units = {},
        notes = {},
        status = 'pending',
        caller_id = officer.citizenid,
        caller_name = officer.name,
        created_at = os.date('%Y-%m-%d %H:%M:%S'),
    }
    activeCalls[id] = call

    -- Push new call to all on-duty officers
    TriggerClientEvent('cipher-mdt:client:newCall', -1, call)
    exports['cipher-mdt']:AuditLog('CAD Call Created', officer.name, callNumber .. ': ' .. data.type .. ' @ ' .. data.location)
    return call
end)

lib.callback.register('cipher-mdt:server:respondToCall', function(source, callId)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)

    local call = MySQL.single.await('SELECT units FROM mdt_cad_calls WHERE id = ?', { callId })
    if not call then return false end

    local units = json.decode(call.units) or {}
    -- Check if officer already on this call
    for _, u in ipairs(units) do
        if u.citizenid == officer.citizenid then return true end
    end

    units[#units + 1] = {
        citizenid = officer.citizenid,
        name = officer.name,
        respondedAt = os.date('%H:%M'),
    }

    MySQL.update.await("UPDATE mdt_cad_calls SET units = ?, status = 'enroute' WHERE id = ? AND status = 'pending'", {
        json.encode(units), callId
    })
    MySQL.update.await('UPDATE mdt_cad_calls SET units = ? WHERE id = ?', { json.encode(units), callId })

    -- Notify all clients of unit update
    TriggerClientEvent('cipher-mdt:client:callUpdated', -1, {
        id = callId,
        units = units,
        status = 'enroute',
    })
    exports['cipher-mdt']:LogBodyCam(source, 'CALL_RESPONDED', 'Call ID: ' .. callId)
    return true
end)

lib.callback.register('cipher-mdt:server:updateCallStatus', function(source, data)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)

    MySQL.update.await('UPDATE mdt_cad_calls SET status = ?, updated_at = NOW() WHERE id = ?', {
        data.status, data.callId
    })

    TriggerClientEvent('cipher-mdt:client:callUpdated', -1, {
        id = data.callId,
        status = data.status,
    })

    if data.status == 'completed' or data.status == 'cancelled' then
        TriggerClientEvent('cipher-mdt:client:callClosed', -1, data.callId)
        activeCalls[data.callId] = nil
    end

    exports['cipher-mdt']:AuditLog('Call Status Updated', officer.name, 'Call #' .. data.callId .. ' → ' .. data.status)
    return true
end)

lib.callback.register('cipher-mdt:server:addCallNote', function(source, data)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)

    local call = MySQL.single.await('SELECT notes FROM mdt_cad_calls WHERE id = ?', { data.callId })
    if not call then return false end

    local notes = call.notes and json.decode(call.notes) or {}
    notes[#notes + 1] = {
        author = officer.name,
        text = data.text,
        time = os.date('%H:%M'),
    }

    MySQL.update.await('UPDATE mdt_cad_calls SET notes = ? WHERE id = ?', { json.encode(notes), data.callId })
    TriggerClientEvent('cipher-mdt:client:callNoteAdded', -1, { callId = data.callId, notes = notes })
    return true
end)

-- Quick Dispatch: mark officer as responding to a call
RegisterNetEvent('cipher-mdt:server:respondToCall')
AddEventHandler('cipher-mdt:server:respondToCall', function(data)
    local src = source
    if not IsAuthorized(src) then return end
    local officer = exports['cipher-mdt']:GetOfficerInfo(src)
    if not officer or not data.callId then return end

    local call = MySQL.single.await('SELECT units FROM mdt_cad_calls WHERE id = ?', { data.callId })
    if not call then return end

    local units = call.units and json.decode(call.units) or {}

    -- Add officer if not already on this call
    local already = false
    for _, u in ipairs(units) do
        if u.citizenid == officer.citizenid then already = true break end
    end
    if not already then
        units[#units+1] = {
            citizenid  = officer.citizenid,
            name       = officer.name,
            status     = 'enroute',
        }
        MySQL.update.await('UPDATE mdt_cad_calls SET units = ?, status = IF(status = "pending","active",status) WHERE id = ?', {
            json.encode(units), data.callId
        })
    end

    -- Broadcast updated units list to all officers with MDT open
    local players = exports['qbx_core']:GetQBPlayers()
    for psrc, p in pairs(players) do
        if Config.AuthorizedJobs[p.PlayerData.job.name] then
            TriggerClientEvent('cipher-mdt:client:callUpdated', psrc, { id = data.callId, units = units })
        end
    end

    exports['cipher-mdt']:AuditLog('RESPOND_TO_CALL', officer.name, 'Call ID: ' .. data.callId)
end)

-- Pull historical calls (last 50 completed)
lib.callback.register('cipher-mdt:server:getCallHistory', function(source)
    if not IsAuthorized(source) then return nil end
    local calls = MySQL.query.await([[
        SELECT * FROM mdt_cad_calls
        WHERE status IN ('completed', 'cancelled')
        ORDER BY updated_at DESC LIMIT 50
    ]], {})
    for _, c in ipairs(calls) do
        c.units = c.units and json.decode(c.units) or {}
        c.notes = c.notes and json.decode(c.notes) or {}
    end
    return calls
end)
