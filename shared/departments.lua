-- CipherMDT — department resolution, shared by client and server.
-- Everything that asks "what can this job do?" comes through here so the
-- sidebar, the blip layer and every server callback agree on one answer.

Dept = {}

-- Department key for a job name, or nil if the job has no MDT access.
function Dept.OfJob(jobName)
    if not jobName then return nil end
    return Config.AuthorizedJobs[jobName]
end

-- Full department config table for a job, or nil.
function Dept.ConfigOfJob(jobName)
    local key = Dept.OfJob(jobName)
    return key and Config.Departments[key] or nil
end

-- Panel list a job may open. Always a table (empty when unauthorized).
function Dept.PanelsOfJob(jobName)
    local cfg = Dept.ConfigOfJob(jobName)
    return cfg and cfg.panels or {}
end

-- Does this job have access to a given panel?
function Dept.HasPanel(jobName, panel)
    for _, p in ipairs(Dept.PanelsOfJob(jobName)) do
        if p == panel then return true end
    end
    return false
end

-- Supervisor grade for a job's department, falling back to the global value.
function Dept.SupervisorGrade(jobName)
    local cfg = Dept.ConfigOfJob(jobName)
    return (cfg and cfg.supervisorGrade) or Config.SupervisorGrade or 3
end

-- ── Blips ──────────────────────────────────────────────────────────────────

-- Is this job tracked on the live unit map? Honours Config.Blips.TrackedJobs
-- when set, otherwise every job that belongs to a department.
function Dept.IsTracked(jobName)
    local B = Config.Blips or {}
    if not B.Enabled then return false end
    if B.TrackedJobs then
        for _, j in ipairs(B.TrackedJobs) do
            if j == jobName then return true end
        end
        return false
    end
    return Dept.OfJob(jobName) ~= nil
end

-- Can `viewerJob` see a unit working `unitJob`? Same department always;
-- across departments only when CrossDepartment is on.
function Dept.CanSeeUnit(viewerJob, unitJob)
    if not Dept.IsTracked(viewerJob) or not Dept.IsTracked(unitJob) then return false end
    if (Config.Blips or {}).CrossDepartment then return true end
    return Dept.OfJob(viewerJob) == Dept.OfJob(unitJob)
end

-- Blip colour for a job: explicit JobColors override → department blipColor → blue.
function Dept.BlipColor(jobName)
    local override = ((Config.Blips or {}).JobColors or {})[jobName]
    if override then return override end
    local cfg = Dept.ConfigOfJob(jobName)
    return (cfg and cfg.blipColor) or 3
end
