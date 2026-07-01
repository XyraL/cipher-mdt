Config = {}

-- Jobs that can access the MDT
Config.AuthorizedJobs = {
    ['police'] = true,
    ['sheriff'] = true,
    ['swat'] = true,
    ['statepolice'] = true,
}

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

-- Grade level (numeric) required for supervisor features:
-- editing penal codes, deleting incidents, marking citations paid, viewing body cams
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
