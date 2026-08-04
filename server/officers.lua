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
    -- Drop the cached badge so live blip labels pick the new one up.
    exports['cipher-mdt']:InvalidateBadgeCache(officer.citizenid)
    return true
end)


-- ═══════════════════════════════════════════════════════════════════════════
--  LIVE UNIT TRACKING
--  One in-memory store of every tracked unit's position, rebroadcast to
--  everyone allowed to see them. Which jobs take part and whether departments
--  see each other is decided by Dept.IsTracked / Dept.CanSeeUnit.
-- ═══════════════════════════════════════════════════════════════════════════

local _unitPositions = {}   -- [citizenid] = unit record
local _badgeCache    = {}   -- [citizenid] = badge; avoids a query every tick

local function GetBadge(citizenid)
    local cached = _badgeCache[citizenid]
    if cached ~= nil then return cached end
    local badge = MySQL.scalar.await('SELECT badge FROM mdt_officers WHERE citizenid = ?', { citizenid })
    _badgeCache[citizenid] = badge or 'N/A'
    return _badgeCache[citizenid]
end

-- Called after a profile edit so the blip label picks up the new badge.
local function InvalidateBadge(citizenid) _badgeCache[citizenid] = nil end

-- Units seen recently enough to still be considered live.
local function LiveUnits()
    local staleAfter = (Config.Blips or {}).StaleAfter or 15
    local now, units = os.time(), {}
    for _, u in pairs(_unitPositions) do
        if now - u.ts < staleAfter then units[#units + 1] = u end
    end
    return units
end

-- Push the unit list to every connected player, filtered to what that
-- player's department is allowed to see.
function BroadcastUnits()
    if not (Config.Blips or {}).Enabled then return end
    local units = LiveUnits()
    for psrc, p in pairs(exports['qbx_core']:GetQBPlayers()) do
        local viewerJob = p.PlayerData.job and p.PlayerData.job.name
        if Dept.IsTracked(viewerJob) then
            local visible = {}
            for _, u in ipairs(units) do
                if Dept.CanSeeUnit(viewerJob, u.job) then visible[#visible + 1] = u end
            end
            TriggerClientEvent('cipher-mdt:client:updateBlips', psrc, visible)
        end
    end
end

RegisterNetEvent('cipher-mdt:server:broadcastPosition')
AddEventHandler('cipher-mdt:server:broadcastPosition', function(data)
    if not (Config.Blips or {}).Enabled then return end
    local src    = source
    local player = exports['qbx_core']:GetPlayer(src)
    if not player or type(data) ~= 'table' then return end

    local pd = player.PlayerData
    if not Dept.IsTracked(pd.job.name) then return end
    if (Config.Blips or {}).OnDutyOnly ~= false and not pd.job.onduty then
        _unitPositions[pd.citizenid] = nil
        return BroadcastUnits()
    end

    local prev = _unitPositions[pd.citizenid]
    _unitPositions[pd.citizenid] = {
        citizenid  = pd.citizenid,
        name       = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname,
        job        = pd.job.name,
        department = Dept.OfJob(pd.job.name),
        badge      = GetBadge(pd.citizenid),
        coords     = { x = data.x or 0, y = data.y or 0, z = data.z or 0 },
        sprite     = data.sprite or 1,
        heading    = data.heading or 0,
        status     = prev and prev.status or nil,
        ts         = os.time(),
    }

    BroadcastUnits()
end)

-- Callback for the NUI map to pull the current picture on demand.
lib.callback.register('cipher-mdt:server:getUnits', function(source)
    if not IsAuthorized(source) then return {} end
    local player = exports['qbx_core']:GetPlayer(source)
    local viewerJob = player and player.PlayerData.job and player.PlayerData.job.name
    local out = {}
    for _, u in ipairs(LiveUnits()) do
        if Dept.CanSeeUnit(viewerJob, u.job) then out[#out + 1] = u end
    end
    return out
end)

-- Clear a unit's position (going off duty or disconnecting)
RegisterNetEvent('cipher-mdt:server:clearPosition')
AddEventHandler('cipher-mdt:server:clearPosition', function()
    local player = exports['qbx_core']:GetPlayer(source)
    if not player then return end
    _unitPositions[player.PlayerData.citizenid] = nil
    BroadcastUnits()
end)

AddEventHandler('playerDropped', function()
    local player = exports['qbx_core']:GetPlayer(source)
    if not player then return end
    local cid = player.PlayerData.citizenid
    _unitPositions[cid] = nil
    _badgeCache[cid]    = nil
    BroadcastUnits()
end)

exports('InvalidateBadgeCache', InvalidateBadge)

-- Unit status update (10-8, 10-6, Code 4, etc.)
lib.callback.register('cipher-mdt:server:setUnitStatus', function(source, status)
    if not IsAuthorized(source) then return false end
    local officer = exports['cipher-mdt']:GetOfficerInfo(source)
    if not officer then return false end
    if _unitPositions[officer.citizenid] then
        _unitPositions[officer.citizenid].status = status
    end
    MySQL.update.await('UPDATE mdt_officers SET status = ? WHERE citizenid = ?', { status, officer.citizenid })
    BroadcastUnits()   -- rebroadcast so the roster/map update live
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
