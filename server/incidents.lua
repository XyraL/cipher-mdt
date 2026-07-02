local IsAuthorized = function(src) return exports['cipher-mdt']:IsAuthorized(src) end

lib.callback.register('cipher-mdt:server:getIncidents', function(source, data)
    if not IsAuthorized(source) then return nil end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    local filter = (type(data) == 'table' and data.filter) or (type(data) == 'string' and data) or 'all'

    local results
    if filter == 'mine' then
        results = MySQL.query.await('SELECT * FROM mdt_incidents WHERE created_by = ? ORDER BY created_at DESC LIMIT 50', { officer.citizenid })
    else
        results = MySQL.query.await('SELECT * FROM mdt_incidents ORDER BY created_at DESC LIMIT 100', {})
    end

    for _, i in ipairs(results) do
        i.involved_civilians = i.involved_civilians and json.decode(i.involved_civilians) or {}
        i.involved_officers = i.involved_officers and json.decode(i.involved_officers) or {}
        i.linked_arrests = i.linked_arrests and json.decode(i.linked_arrests) or {}
        i.linked_citations = i.linked_citations and json.decode(i.linked_citations) or {}
    end
    return results
end)

lib.callback.register('cipher-mdt:server:getIncident', function(source, id)
    if not IsAuthorized(source) then return nil end
    local incident = MySQL.single.await('SELECT * FROM mdt_incidents WHERE id = ?', { id })
    if not incident then return nil end
    incident.involved_civilians = incident.involved_civilians and json.decode(incident.involved_civilians) or {}
    incident.involved_officers = incident.involved_officers and json.decode(incident.involved_officers) or {}
    incident.linked_arrests = incident.linked_arrests and json.decode(incident.linked_arrests) or {}
    incident.linked_citations = incident.linked_citations and json.decode(incident.linked_citations) or {}
    return incident
end)

lib.callback.register('cipher-mdt:server:createIncident', function(source, data)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    if not data.title or not data.narrative then return false end

    local id = MySQL.insert.await([[
        INSERT INTO mdt_incidents (title, narrative, involved_civilians, involved_officers, linked_arrests, linked_citations, severity, created_by, created_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.title, data.narrative,
        json.encode(data.involved_civilians or {}),
        json.encode(data.involved_officers or {}),
        json.encode(data.linked_arrests or {}),
        json.encode(data.linked_citations or {}),
        data.severity or nil,
        officer.citizenid, officer.name
    })

    exports['cipher-mdt']:AuditLog('Incident Created', officer.name, 'Incident #' .. id .. ': ' .. data.title)
    return id
end)

lib.callback.register('cipher-mdt:server:updateIncident', function(source, data)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)

    -- Only the author or a supervisor (grade 3+) can edit
    local existing = MySQL.single.await('SELECT created_by FROM mdt_incidents WHERE id = ?', { data.id })
    if not existing then return false end
    local player = exports['qbx_core']:GetPlayer(source)
    if existing.created_by ~= officer.citizenid and player.PlayerData.job.grade.level < 3 then
        return false
    end

    MySQL.update.await([[
        UPDATE mdt_incidents SET title=?, narrative=?, involved_civilians=?, involved_officers=?,
        linked_arrests=?, linked_citations=?, updated_at=NOW()
        WHERE id = ?
    ]], {
        data.title, data.narrative,
        json.encode(data.involved_civilians or {}),
        json.encode(data.involved_officers or {}),
        json.encode(data.linked_arrests or {}),
        json.encode(data.linked_citations or {}),
        data.id
    })
    return true
end)

lib.callback.register('cipher-mdt:server:deleteIncident', function(source, id)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    local existing = MySQL.single.await('SELECT created_by FROM mdt_incidents WHERE id = ?', { id })
    if not existing then return false end
    local player = exports['qbx_core']:GetPlayer(source)
    if existing.created_by ~= officer.citizenid and player.PlayerData.job.grade.level < 3 then
        return false
    end
    MySQL.query.await('DELETE FROM mdt_incidents WHERE id = ?', { id })
    exports['cipher-mdt']:AuditLog('Incident Deleted', officer.name, 'Incident #' .. id)
    return true
end)

-- ── Case linking ───────────────────────────────────────────────────────────

lib.callback.register('cipher-mdt:server:setCaseNumber', function(source, data)
    if not IsAuthorized(source) then return false end
    if not data.incidentId or not data.caseNumber then return false end
    -- Trim and validate: alphanumeric + hyphens, max 50 chars
    local cn = tostring(data.caseNumber):gsub('[^%w%-]', ''):sub(1, 50)
    MySQL.update.await('UPDATE mdt_incidents SET case_number = ? WHERE id = ?', { cn ~= '' and cn or nil, data.incidentId })
    return true
end)

lib.callback.register('cipher-mdt:server:getIncidentsByCase', function(source, caseNumber)
    if not IsAuthorized(source) then return nil end
    if not caseNumber or #caseNumber < 1 then return {} end
    local results = MySQL.query.await([[
        SELECT id, title, severity, created_by_name, created_at, case_number
        FROM mdt_incidents
        WHERE case_number = ?
        ORDER BY created_at ASC
    ]], { caseNumber })
    return results
end)
