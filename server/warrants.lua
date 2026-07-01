local IsAuthorized = function(src) return exports['cipher-mdt']:IsAuthorized(src) end

lib.callback.register('cipher-mdt:server:getWarrants', function(source, data)
    if not IsAuthorized(source) then return nil end
    local filter = (type(data) == 'table' and data.filter) or (type(data) == 'string' and data) or 'active'
    local results = MySQL.query.await([[
        SELECT w.*, CONCAT(c.firstname, ' ', c.lastname) as subject_name, c.dob
        FROM mdt_warrants w
        LEFT JOIN mdt_civilians c ON w.citizenid = c.citizenid
        WHERE w.status = ?
        ORDER BY w.created_at DESC
        LIMIT 100
    ]], { filter })

    for _, w in ipairs(results) do
        w.charges = json.decode(w.charges)
    end
    return results
end)

lib.callback.register('cipher-mdt:server:issueWarrant', function(source, data)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    if not officer then return false end
    if not data.citizenid or not data.charges or #data.charges == 0 then return false end

    -- Build expires_at from optional expiryDays field
    local expiresAt = nil
    if data.expiryDays and data.expiryDays > 0 then
        expiresAt = os.date('%Y-%m-%d %H:%M:%S', os.time() + data.expiryDays * 86400)
    end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_warrants (citizenid, charges, description, issued_by, issued_by_name, expires_at)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { data.citizenid, json.encode(data.charges), data.description, officer.citizenid, officer.name, expiresAt })

    -- Notify all on-duty officers
    local civName = MySQL.scalar.await("SELECT CONCAT(firstname, ' ', lastname) FROM mdt_civilians WHERE citizenid = ?", { data.citizenid })
    TriggerClientEvent('cipher-mdt:client:warrantAlert', -1, {
        subject = civName or data.citizenid,
        charges = data.charges,
        issuedBy = officer.name,
    })

    exports['cipher-mdt']:AuditLog('Warrant Issued', officer.name, 'Subject: ' .. (civName or data.citizenid))

    if Config.BodyCam.Enabled then
        MySQL.insert.await('INSERT INTO mdt_bodycam (citizenid, officer_name, action, details) VALUES (?,?,?,?)', {
            officer.citizenid, officer.name, 'WARRANT_ISSUED',
            'Subject: ' .. (civName or data.citizenid) .. ' | Charges: ' .. #data.charges
        })
    end
    return id
end)

lib.callback.register('cipher-mdt:server:clearWarrant', function(source, warrantId)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    MySQL.update.await("UPDATE mdt_warrants SET status = 'cleared', cleared_by = ?, cleared_at = NOW() WHERE id = ?", {
        officer.citizenid, warrantId
    })
    exports['cipher-mdt']:AuditLog('Warrant Cleared', officer.name, 'Warrant ID: ' .. warrantId)
    exports['cipher-mdt']:LogBodyCam(source, 'WARRANT_CLEARED', 'Warrant ID: ' .. warrantId)
    return true
end)

lib.callback.register('cipher-mdt:server:getWarrantsForCivilian', function(source, citizenid)
    if not IsAuthorized(source) then return nil end
    local results = MySQL.query.await('SELECT * FROM mdt_warrants WHERE citizenid = ? ORDER BY created_at DESC', { citizenid })
    for _, w in ipairs(results) do w.charges = json.decode(w.charges) end
    return results
end)

-- Auto-expire warrants that have passed their expires_at date
CreateThread(function()
    while true do
        Wait(300000) -- check every 5 minutes
        local expired = MySQL.query.await([[
            SELECT id FROM mdt_warrants
            WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at <= NOW()
        ]], {})
        if expired and #expired > 0 then
            local ids = {}
            for _, r in ipairs(expired) do ids[#ids+1] = r.id end
            MySQL.update.await(
                'UPDATE mdt_warrants SET status = "expired" WHERE id IN (' .. table.concat(ids, ',') .. ')',
                {}
            )
            print('[CipherMDT] Auto-expired ' .. #expired .. ' warrant(s)')
        end
    end
end)
