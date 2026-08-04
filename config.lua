Config = {}

-- ═══════════════════════════════════════════════════════════════════════════
--  DEPARTMENTS
--  Each department maps a set of jobs to the panels those jobs can open.
--  `panels` is the single source of truth for access: the sidebar is built
--  from it, and every server callback re-checks it. Remove a panel here and
--  it disappears from the UI *and* stops answering.
--
--  Panel keys — shared:  dashboard · roster · map · civilians · cad
--                        callhistory · bulletins · shiftlog
--               police:  vehicles · warrants · bolos · arrests · citations
--                        incidents · penal · mugshots
--               ems:     pcr · medhistory · narclog
--               fire:    fireincidents · hazmat · apparatus
-- ═══════════════════════════════════════════════════════════════════════════
Config.Departments = {
    police = {
        label     = 'Police Department',
        short     = 'PD',
        color     = '#6366f1',   -- NUI accent
        blipColor = 3,           -- GTA blip colour (3 = blue)
        icon      = '⬡',
        jobs      = { 'police', 'sheriff', 'swat', 'statepolice' },
        supervisorGrade = 3,
        panels = {
            'dashboard', 'roster', 'map',
            'civilians', 'vehicles',
            'warrants', 'bolos', 'arrests', 'citations', 'incidents', 'penal',
            'cad', 'callhistory', 'bulletins',
            'mugshots', 'shiftlog',
        },
    },

    ems = {
        label     = 'Emergency Medical Services',
        short     = 'EMS',
        color     = '#22c55e',
        blipColor = 5,           -- yellow
        icon      = '✚',
        jobs      = { 'ambulance', 'ems' },
        supervisorGrade = 3,
        panels = {
            'dashboard', 'roster', 'map',
            'civilians',
            'pcr', 'medhistory', 'narclog',
            'cad', 'callhistory', 'bulletins',
            'shiftlog',
        },
    },

    fire = {
        label     = 'Fire Department',
        short     = 'FD',
        color     = '#ef4444',
        blipColor = 1,           -- red
        icon      = '🔥',
        jobs      = { 'fire', 'firefighter' },
        supervisorGrade = 3,
        panels = {
            'dashboard', 'roster', 'map',
            'civilians',
            'fireincidents', 'hazmat', 'apparatus',
            'cad', 'callhistory', 'bulletins',
            'shiftlog',
        },
    },
}

-- Built from Config.Departments below — do not edit by hand.
-- Maps job name → department key, e.g. Config.AuthorizedJobs['ambulance'] == 'ems'.
Config.AuthorizedJobs = {}
for dept, cfg in pairs(Config.Departments) do
    for _, job in ipairs(cfg.jobs or {}) do
        Config.AuthorizedJobs[job] = dept
    end
end

-- Minimum job grade to access MDT (0 = all grades)
Config.MinGrade = 0

-- Keybind to open MDT (default: F9 — players can rebind in Settings > Key Bindings)
Config.OpenKey = 'F9'

-- How long (ms) to hold key to open MDT (0 = instant)
Config.HoldTime = 0

-- Show MDT only while on duty
Config.OnDutyOnly = true

-- CAD Settings
Config.CAD = {
    -- Auto-assign officer to call when they respond
    AutoAssign = true,
    -- Dispatch notification method: 'chat', 'notification', 'both'
    NotifyMethod = 'notification',
    -- Max units per call before it shows as over-staffed
    MaxUnitsPerCall = 6,
}

-- Civilian records: pull from QBCore players table
Config.UseQBCoreCharacters = true

-- Default penal code categories seeded on first run
Config.SeedPenalCodes = true

-- Discord webhook for audit logs (leave empty to disable)
Config.AuditWebhook = ''

-- Map blip for active CAD calls
Config.CADBlip = {
    Sprite = 161,
    Color = 1,
    Scale = 0.8,
}

-- ═══════════════════════════════════════════════════════════════════════════
--  LIVE UNIT BLIPS
--  Police, EMS and Fire see each other on the map, coloured per department.
--  Set Enabled = false to turn the whole system off (no position broadcast,
--  no blips) if you'd rather run your own blip script.
-- ═══════════════════════════════════════════════════════════════════════════
Config.Blips = {
    Enabled = true,

    -- Which jobs broadcast a position and appear on the map.
    -- nil  → every job listed in Config.Departments (the usual choice)
    -- list → explicit override, e.g. { 'police', 'ambulance' }
    TrackedJobs = nil,

    -- true  → all departments see each other (PD sees EMS sees Fire)
    -- false → you only see units from your own department
    CrossDepartment = true,

    -- Only show units who are on duty. Independent of Config.OnDutyOnly so an
    -- off-duty officer can still read the MDT without appearing on the map.
    OnDutyOnly = true,

    UpdateInterval = 2000,  -- ms between position broadcasts (2000 is plenty)
    StaleAfter     = 15,    -- seconds without an update before a unit drops off

    Scale      = 0.82,
    ShortRange = false,     -- false = visible at every map zoom level
    ShowName   = true,
    ShowBadge  = true,
    ShowVehicle= true,      -- append [VEH] / [AIR] / [BOAT] to the label

    -- Per-department colour override. Falls back to the department's
    -- blipColor in Config.Departments when a job isn't listed here.
    JobColors = {
        -- ['swat'] = 27,   -- example: give SWAT its own colour
    },
}

-- Grade level (numeric) required for supervisor features:
-- editing penal codes, deleting incidents, marking citations paid, viewing body cams.
-- Per-department overrides live in Config.Departments[dept].supervisorGrade.
Config.SupervisorGrade = 3

-- Fine deduction from player bank accounts
Config.FineDeduction = {
    Enabled               = true,   -- Master toggle for all automatic fine deductions
    AutoDeductArrests     = true,   -- Deduct arrest fines immediately if player is online
    AutoDeductCitations   = false,  -- Deduct citation fines immediately on issue (false = pay-later model)
    AutoDeductOnMarkPaid  = true,   -- Deduct from bank when a supervisor marks citation paid
}

-- Body camera logging — records key officer actions
Config.BodyCam = {
    Enabled       = true,
    RetentionDays = 30,  -- Auto-purge logs older than this (0 = keep forever)
}

-- ox_target / qb-target integration — right-click players in-world
Config.Target = {
    Enabled     = true,
    MaxDistance = 3.0,
}

-- UI sound effects inside the MDT NUI
Config.Sounds = {
    Enabled = true,
    Volume  = 0.08,  -- 0.0 – 1.0
}

-- Jail integration — triggers when an arrest with jail time is logged
-- Options: 'qb-prison'  → TriggerEvent('qb-prison:server:sendToJail', src, minutes)
--          'ps-prison'  → TriggerEvent('prison:server:SendToJail', src, minutes)
--          'custom'     → exports['cipher-mdt']:OnJailPlayer(src, minutes) — implement your own handler
--          false        → disabled (fires client event only, handle in client/main.lua)
Config.JailResource = false
