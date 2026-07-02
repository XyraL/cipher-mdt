local IsAuthorized = function(src) return exports['cipher-mdt']:IsAuthorized(src) end

-- Sync civilian record from QBCore players table into mdt_civilians
local function SyncCivilian(citizenid)
    local player = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { citizenid })
    if not player then return nil end
    local info = json.decode(player.charinfo)
    MySQL.insert.await([[
        INSERT INTO mdt_civilians (citizenid, firstname, lastname, dob, gender, phone)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE firstname = VALUES(firstname), lastname = VALUES(lastname),
        dob = VALUES(dob), gender = VALUES(gender), phone = VALUES(phone)
    ]], { citizenid, info.firstname, info.lastname, info.birthdate, info.gender, info.phone })
    return MySQL.single.await('SELECT * FROM mdt_civilians WHERE citizenid = ?', { citizenid })
end

-- Search civilians by name or DOB
lib.callback.register('cipher-mdt:server:searchCivilians', function(source, query)
    if not IsAuthorized(source) then return nil end
    if not query or #query < 2 then return {} end

    local search = '%' .. query .. '%'
    local results = MySQL.query.await([[
        SELECT c.*,
            (SELECT COUNT(*) FROM mdt_warrants w WHERE w.citizenid = c.citizenid AND w.status = 'active') as active_warrants,
            (SELECT COUNT(*) FROM mdt_arrests a WHERE a.citizenid = c.citizenid) as arrest_count
        FROM mdt_civilians c
        WHERE CONCAT(c.firstname, ' ', c.lastname) LIKE ?
           OR c.dob LIKE ?
           OR c.citizenid LIKE ?
        LIMIT 20
    ]], { search, search, search })

    -- If no local record, try pulling from QBCore players table
    if #results == 0 then
        local qbResults = MySQL.query.await([[
            SELECT citizenid, charinfo FROM players
            WHERE JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) LIKE ?
               OR CONCAT(JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')), ' ', JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))) LIKE ?
            LIMIT 10
        ]], { search, search })
        for _, row in ipairs(qbResults) do
            SyncCivilian(row.citizenid)
        end
        results = MySQL.query.await([[
            SELECT c.*,
                (SELECT COUNT(*) FROM mdt_warrants w WHERE w.citizenid = c.citizenid AND w.status = 'active') as active_warrants,
                (SELECT COUNT(*) FROM mdt_arrests a WHERE a.citizenid = c.citizenid) as arrest_count
            FROM mdt_civilians c
            WHERE CONCAT(c.firstname, ' ', c.lastname) LIKE ?
               OR c.dob LIKE ?
            LIMIT 20
        ]], { search, search })
    end

    return results
end)

-- Get full civilian profile with all records
lib.callback.register('cipher-mdt:server:getCivilianProfile', function(source, citizenid)
    if not IsAuthorized(source) then return nil end
    local civilian = MySQL.single.await('SELECT * FROM mdt_civilians WHERE citizenid = ?', { citizenid })
    if not civilian then
        civilian = SyncCivilian(citizenid)
    end
    if not civilian then return nil end

    civilian.warrants  = MySQL.query.await('SELECT * FROM mdt_warrants WHERE citizenid = ? ORDER BY created_at DESC', { citizenid })
    civilian.arrests   = MySQL.query.await('SELECT * FROM mdt_arrests WHERE citizenid = ? ORDER BY created_at DESC', { citizenid })
    civilian.citations = MySQL.query.await('SELECT * FROM mdt_citations WHERE citizenid = ? ORDER BY created_at DESC', { citizenid })

    -- Registered vehicles from QBCore player_vehicles table
    civilian.vehicles = MySQL.query.await([[
        SELECT plate, vehicle, garage, state, fuel, mods
        FROM player_vehicles
        WHERE citizenid = ?
        ORDER BY plate ASC
    ]], { citizenid })

    -- Parse vehicle model label from mods JSON where available
    for _, v in ipairs(civilian.vehicles) do
        local ok, mods = pcall(json.decode, v.mods or '{}')
        v.label = (ok and mods and mods.model) or v.vehicle or 'Unknown'
        v.mods  = nil -- don't send full mods blob to client
    end

    -- Decode JSON fields
    for _, w in ipairs(civilian.warrants)  do w.charges = json.decode(w.charges) end
    for _, a in ipairs(civilian.arrests)   do a.charges = json.decode(a.charges) end
    for _, c in ipairs(civilian.citations) do c.charges = json.decode(c.charges) end

    return civilian
end)

-- Update civilian mugshot image URL
lib.callback.register('cipher-mdt:server:updateCivilianImage', function(source, data)
    if not IsAuthorized(source) then return false end
    if not data or not data.citizenid then return false end
    MySQL.update.await('UPDATE mdt_civilians SET image = ? WHERE citizenid = ?', { data.image, data.citizenid })
    return true
end)

-- Update civilian notes or flags (officer-added info only)
lib.callback.register('cipher-mdt:server:updateCivilianNotes', function(source, data)
    if not IsAuthorized(source) then return false end
    MySQL.update.await('UPDATE mdt_civilians SET notes = ?, flags = ? WHERE citizenid = ?', {
        data.notes, json.encode(data.flags), data.citizenid
    })
    return true
end)

-- Mugshot gallery — all civilians with a mugshot, searchable by name
lib.callback.register('cipher-mdt:server:getMugshots', function(source, data)
    if not IsAuthorized(source) then return nil end
    data = data or {}
    local where = { 'image IS NOT NULL', "image != ''" }
    local params = {}

    if data.search and #data.search >= 2 then
        where[#where+1] = "CONCAT(firstname, ' ', lastname) LIKE ?"
        params[#params+1] = '%' .. data.search .. '%'
    end

    local sql = [[
        SELECT c.citizenid, c.firstname, c.lastname, c.dob, c.image,
               (SELECT COUNT(*) FROM mdt_arrests a WHERE a.citizenid = c.citizenid) as arrest_count,
               (SELECT COUNT(*) FROM mdt_warrants w WHERE w.citizenid = c.citizenid AND w.status = 'active') as active_warrants
        FROM mdt_civilians c
        WHERE ]] .. table.concat(where, ' AND ') .. [[
        ORDER BY c.lastname ASC, c.firstname ASC
        LIMIT 100
    ]]
    return MySQL.query.await(sql, params)
end)
