local IsAuthorized = function(src) return exports['cipher-mdt']:IsAuthorized(src) end
local GetOfficerInfo = function(src) return exports['cipher-mdt']:GetOfficerInfo(src) end

-- Get all currently on-duty officers (live, from connected players)
lib.callback.register('cipher-mdt:server:getRoster', function(source)
    if not IsAuthorized(source) then return nil end
    local roster = {}
    local players = exports['qbx_core']:GetQBPlayers()
    for src, player in pairs(players) do
        local pd = player.PlayerData
        if Config.AuthorizedJobs[pd.job.name] and pd.job.onduty then
            local profile = MySQL.single.await('SELECT badge, callsign, status FROM mdt_officers WHERE citizenid = ?', { pd.citizenid })
            roster[#roster + 1] = {
                source    = src,
                citizenid = pd.citizenid,
                name      = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname,
                job       = pd.job.name,
                grade     = pd.job.grade.name,
                badge     = (profile and profile.badge) or 'N/A',
                callsign  = (profile and profile.callsign) or 'N/A',
                status    = (profile and profile.status) or '10-8',
            }
        end
    end
    return roster
end)

-- Get or create the MDT officer profile for the requesting player
lib.callback.register('cipher-mdt:server:getMyOfficerProfile', function(source)
    if not IsAuthorized(source) then return nil end
    local officer = GetOfficerInfo(source)
    local profile = MySQL.single.await('SELECT * FROM mdt_officers WHERE citizenid = ?', { officer.citizenid })
    if not profile then
        -- Auto-create a basic profile on first open
        local badge = tostring(math.random(1000, 9999))
        MySQL.insert.await('INSERT INTO mdt_officers (citizenid, badge, rank, department) VALUES (?, ?, ?, ?)', {
            officer.citizenid, badge, officer.gradeLabel, officer.job
        })
        profile = MySQL.single.await('SELECT * FROM mdt_officers WHERE citizenid = ?', { officer.citizenid })
    end
    profile.name        = officer.name
    profile.onduty      = officer.onduty
    profile.grade       = officer.gradeLabel    -- human-readable rank label
    profile.gradeLevel  = officer.grade         -- numeric grade for permission checks
    profile.isSupervisor = officer.grade >= Config.SupervisorGrade
    return profile
end)

-- Search on-duty officers by name (for incident linking)
lib.callback.register('cipher-mdt:server:searchOfficers', function(source, query)
    if not IsAuthorized(source) then return nil end
    if not query or #query < 2 then return {} end
    local search = '%' .. query:lower() .. '%'
    local results = {}
    local players = exports['qbx_core']:GetQBPlayers()
    for src, player in pairs(players) do
        local pd = player.PlayerData
        if Config.AuthorizedJobs[pd.job.name] then
            local fullname = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
            if fullname:lower():find(search, 1, true) then
                local badge = MySQL.scalar.await('SELECT badge FROM mdt_officers WHERE citizenid = ?', { pd.citizenid })
                results[#results + 1] = {
                    citizenid = pd.citizenid,
                    name = fullname,
                    grade = pd.job.grade.name,
                    badge = badge or 'N/A',
                    onduty = pd.job.onduty,
                }
            end
        end
    end
    return results
end)

-- Update officer callsign/badge
lib.callback.register('cipher-mdt:server:updateOfficerProfile', function(source, data)
    if not IsAuthorized(source) then return false end
    local officer = GetOfficerInfo(source)
    if not officer then return false end

    -- Ensure badge is unique
    if data.badge then
        local existing = MySQL.scalar.await('SELECT citizenid FROM mdt_officers WHERE badge = ? AND citizenid != ?', { data.badge, officer.citizenid })
        if existing then return false, 'Badge number already in use' end
    end

    MySQL.update.await('UPDATE mdt_officers SET badge = ?, callsign = ? WHERE citizenid = ?', {
        data.badge, data.callsign, officer.citizenid
    })
    return true
end)


-- Unit position store (in-memory, updated via broadcast)
local _unitPositions = {}

RegisterNetEvent('cipher-mdt:server:broadcastPosition')
AddEventHandler('cipher-mdt:server:broadcastPosition', function(data)
    local src    = source
    local player = exports['qbx_core']:GetPlayer(src)
    if not player then return end
    local pd = player.PlayerData
    if not Config.AuthorizedJobs[pd.job.name] then return end
    if Config.OnDutyOnly and not pd.job.onduty then
        _unitPositions[pd.citizenid] = nil
        return
    end

    -- data may be just coords table or full table with sprite/heading
    local coords  = (type(data) == 'table' and data.x) and data or {}
    local sprite  = data.sprite  or 1
    local heading = data.heading or 0

    local badge = MySQL.scalar.await('SELECT badge FROM mdt_officers WHERE citizenid = ?', { pd.citizenid })
    _unitPositions[pd.citizenid] = {
        citizenid = pd.citizenid,
        name      = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname,
        job       = pd.job.name,
        badge     = badge or 'N/A',
        coords    = { x = data.x or 0, y = data.y or 0, z = data.z or 0 },
        sprite    = sprite,
        heading   = heading,
        ts        = os.time(),
    }

    -- Push fresh list to all authorized units every broadcast cycle
    local units = {}
    for _, u in pairs(_unitPositions) do
        if os.time() - u.ts < 15 then units[#units+1] = u end
    end
    local players = exports['qbx_core']:GetQBPlayers()
    for psrc, p in pairs(players) do
        if Config.AuthorizedJobs[p.PlayerData.job.name] then
            TriggerClientEvent('cipher-mdt:client:updateBlips', psrc, units)
        end
    end
end)

-- Callback for NUI map to pull current units
lib.callback.register('cipher-mdt:server:getUnits', function(source)
    if not IsAuthorized(source) then return {} end
    local units = {}
    for _, u in pairs(_unitPositions) do
        if os.time() - u.ts < 30 then units[#units+1] = u end
    end
    return units
end)

-- Clear a unit's position (called when going off-duty or disconnecting)
RegisterNetEvent('cipher-mdt:server:clearPosition')
AddEventHandler('cipher-mdt:server:clearPosition', function()
    local src    = source
    local player = exports['qbx_core']:GetPlayer(src)
    if not player then return end
    local cid = player.PlayerData.citizenid
    _unitPositions[cid] = nil
    -- Rebroadcast so their blip disappears for everyone
    local units = {}
    for _, u in pairs(_unitPositions) do
        if os.time() - u.ts < 15 then units[#units+1] = u end
    end
    local players = exports['qbx_core']:GetQBPlayers()
    for psrc, p in pairs(players) do
        if Config.AuthorizedJobs[p.PlayerData.job.name] then
            TriggerClientEvent('cipher-mdt:client:updateBlips', psrc, units)
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src    = source
    local player = exports['qbx_core']:GetPlayer(src)
    if not player then return end
    _unitPositions[player.PlayerData.citizenid] = nil
end)

-- Unit status update (10-8, 10-6, Code 4, etc.)
lib.callback.register('cipher-mdt:server:setUnitStatus', function(source, status)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    if not officer then return false end
    if _unitPositions[officer.citizenid] then
        _unitPositions[officer.citizenid].status = status
    end
    MySQL.update.await('UPDATE mdt_officers SET status = ? WHERE citizenid = ?', { status, officer.citizenid })
    -- Rebroadcast so roster updates live
    local units = {}
    for _, u in pairs(_unitPositions) do
        if os.time() - u.ts < 15 then units[#units+1] = u end
    end
    local players = exports['qbx_core']:GetQBPlayers()
    for psrc, p in pairs(players) do
        if Config.AuthorizedJobs[p.PlayerData.job.name] then
            TriggerClientEvent('cipher-mdt:client:updateBlips', psrc, units)
        end
    end
    return true
end)

-- ─── Department Statistics (supervisor only) ────────────────────────────────

lib.callback.register('cipher-mdt:server:getDepartmentStats', function(source)
    if not IsAuthorized(source) then return nil end
    local officer = GetOfficerInfo(source)
    if not officer or officer.grade < Config.SupervisorGrade then return nil end

    local arrests_week   = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_arrests   WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)") or 0
    local citations_week = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_citations WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)") or 0
    local arrests_today  = MySQL.scalar.await("SELECT COUNT(*) FROM mdt_arrests   WHERE DATE(created_at) = CURDATE()") or 0
    local citations_today= MySQL.scalar.await("SELECT COUNT(*) FROM mdt_citations WHERE DATE(created_at) = CURDATE()") or 0

    local fine_arrests   = MySQL.scalar.await("SELECT COALESCE(SUM(fine),0) FROM mdt_arrests   WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)") or 0
    local fine_citations = MySQL.scalar.await("SELECT COALESCE(SUM(fine),0) FROM mdt_citations WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)") or 0

    local top_officers = MySQL.query.await([[
        SELECT officer_name, COUNT(*) as arrest_count
        FROM mdt_arrests
        WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
        GROUP BY officer_citizenid, officer_name
        ORDER BY arrest_count DESC
        LIMIT 5
    ]], {})

    return {
        arrests_week   = arrests_week,
        citations_week = citations_week,
        arrests_today  = arrests_today,
        citations_today= citations_today,
        fines_week     = fine_arrests + fine_citations,
        top_officers   = top_officers,
    }
end)
