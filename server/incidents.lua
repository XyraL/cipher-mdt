local IsAuthorized = function(src) return exports['cipher-mdt']:IsAuthorized(src) end
local HasPanel = function(src, panel) return exports['cipher-mdt']:HasPanel(src, panel) end

-- draft   — being written, visible only to its author
-- open    — filed and active
-- review  — waiting on a supervisor
-- closed  — done
local VALID_STATUS = { draft = true, open = true, review = true, closed = true }

-- Tags come from the panel as free text and are stored as JSON, so they are
-- trimmed, lowercased for consistency, de-duplicated and capped here rather
-- than being cleaned at every place that reads them.
local function CleanTags(list)
    if type(list) ~= 'table' then return {} end
    local out, seen = {}, {}
    for _, raw in ipairs(list) do
        local tag = tostring(raw):lower():gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 24)
        if tag ~= '' and not seen[tag] then
            seen[tag] = true
            out[#out + 1] = tag
            if #out >= 10 then break end
        end
    end
    return out
end

lib.callback.register('cipher-mdt:server:getIncidents', function(source, data)
    if not HasPanel(source, 'incidents') then return nil end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    local filter = (type(data) == 'table' and data.filter) or (type(data) == 'string' and data) or 'all'

    -- A draft is a half-written report. It belongs to whoever is writing it
    -- and to nobody else, so the scoping happens here rather than trusting the
    -- panel to leave other people's drafts out of what it shows.
    local where, params = { "(status != 'draft' OR created_by = ?)" }, { officer.citizenid }

    if filter == 'mine' then
        where[#where + 1] = 'created_by = ?'
        params[#params + 1] = officer.citizenid
    end

    local status = type(data) == 'table' and data.status or nil
    if status and status ~= 'all' then
        where[#where + 1] = 'status = ?'
        params[#params + 1] = status
    end

    local results = MySQL.query.await(
        'SELECT * FROM mdt_incidents WHERE ' .. table.concat(where, ' AND ')
        .. ' ORDER BY created_at DESC LIMIT 100', params)

    for _, i in ipairs(results) do
        i.involved_civilians = i.involved_civilians and json.decode(i.involved_civilians) or {}
        i.involved_officers = i.involved_officers and json.decode(i.involved_officers) or {}
        i.linked_arrests = i.linked_arrests and json.decode(i.linked_arrests) or {}
        i.linked_citations = i.linked_citations and json.decode(i.linked_citations) or {}
        i.tags = i.tags and json.decode(i.tags) or {}
    end
    return results
end)

lib.callback.register('cipher-mdt:server:getIncident', function(source, id)
    if not HasPanel(source, 'incidents') then return nil end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    local incident = MySQL.single.await('SELECT * FROM mdt_incidents WHERE id = ?', { id })
    if not incident then return nil end
    -- Someone else's unfinished draft is not readable by id either.
    if incident.status == 'draft' and incident.created_by ~= officer.citizenid then return nil end
    incident.involved_civilians = incident.involved_civilians and json.decode(incident.involved_civilians) or {}
    incident.involved_officers = incident.involved_officers and json.decode(incident.involved_officers) or {}
    incident.linked_arrests = incident.linked_arrests and json.decode(incident.linked_arrests) or {}
    incident.linked_citations = incident.linked_citations and json.decode(incident.linked_citations) or {}
    incident.tags = incident.tags and json.decode(incident.tags) or {}
    return incident
end)

lib.callback.register('cipher-mdt:server:createIncident', function(source, data)
    if not HasPanel(source, 'incidents') then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    if not data.title or not data.narrative then return false end

    local status = VALID_STATUS[data.status] and data.status or 'open'

    local id = MySQL.insert.await([[
        INSERT INTO mdt_incidents (title, narrative, involved_civilians, involved_officers, linked_arrests, linked_citations, severity, status, location, occurred_at, tags, created_by, created_by_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.title, data.narrative,
        json.encode(data.involved_civilians or {}),
        json.encode(data.involved_officers or {}),
        json.encode(data.linked_arrests or {}),
        json.encode(data.linked_citations or {}),
        data.severity or nil,
        status,
        data.location and tostring(data.location):sub(1, 255) or nil,
        data.occurred_at or nil,
        json.encode(CleanTags(data.tags)),
        officer.citizenid, officer.name
    })

    -- Case numbers used to be typed by hand, so most reports had none and the
    -- ones that did could collide. Deriving it from the row id makes it unique
    -- without a counter to maintain anywhere.
    local caseNumber = data.caseNumber and tostring(data.caseNumber):gsub('[^%w%-]', ''):sub(1, 50) or nil
    if not caseNumber or caseNumber == '' then
        caseNumber = ('INC-%s-%05d'):format(os.date('%Y'), id)
    end
    MySQL.update.await('UPDATE mdt_incidents SET case_number = ? WHERE id = ?', { caseNumber, id })

    -- Starting to type is not an event worth auditing; filing one is.
    if status ~= 'draft' then
        exports['cipher-mdt']:AuditLog('Incident Created', officer.name, caseNumber .. ': ' .. data.title)
    end
    -- A table, not two values: the NUI bridge keeps only the first return,
    -- so the case number would never reach the panel otherwise.
    return { id = id, caseNumber = caseNumber }
end)

-- Moving a report along its lifecycle. Separate from updateIncident so that
-- closing a report does not mean sending the whole narrative back to the
-- server just to change one word.
lib.callback.register('cipher-mdt:server:setIncidentStatus', function(source, data)
    if not HasPanel(source, 'incidents') then return { ok = false, error = 'Not authorised' } end
    if type(data) ~= 'table' or not data.id then return { ok = false, error = 'Missing incident' } end
    if not VALID_STATUS[data.status] then return { ok = false, error = 'Unknown status' } end

    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    local incident = MySQL.single.await('SELECT created_by, case_number, status FROM mdt_incidents WHERE id = ?', { data.id })
    if not incident then return { ok = false, error = 'No such incident' } end

    -- Authors move their own reports; supervisors move anyone's.
    local isOwner = incident.created_by == officer.citizenid
    if not isOwner and not exports['cipher-mdt']:IsSupervisor(source) then
        return { ok = false, error = 'Only the author or a supervisor can change this' }
    end

    MySQL.update.await('UPDATE mdt_incidents SET status = ? WHERE id = ?', { data.status, data.id })
    exports['cipher-mdt']:AuditLog('Incident ' .. data.status, officer.name,
        (incident.case_number or ('#' .. data.id)) .. ' was ' .. (incident.status or '?'))
    return { ok = true }
end)

lib.callback.register('cipher-mdt:server:updateIncident', function(source, data)
    if not HasPanel(source, 'incidents') then return false end
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
    if not HasPanel(source, 'incidents') then return false end
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
    if not HasPanel(source, 'incidents') then return false end
    if not data.incidentId or not data.caseNumber then return false end
    -- Trim and validate: alphanumeric + hyphens, max 50 chars
    local cn = tostring(data.caseNumber):gsub('[^%w%-]', ''):sub(1, 50)
    MySQL.update.await('UPDATE mdt_incidents SET case_number = ? WHERE id = ?', { cn ~= '' and cn or nil, data.incidentId })
    return true
end)

lib.callback.register('cipher-mdt:server:getIncidentsByCase', function(source, caseNumber)
    if not HasPanel(source, 'incidents') then return nil end
    if not caseNumber or #caseNumber < 1 then return {} end
    local results = MySQL.query.await([[
        SELECT id, title, severity, created_by_name, created_at, case_number
        FROM mdt_incidents
        WHERE case_number = ?
        ORDER BY created_at ASC
    ]], { caseNumber })
    return results
end)
