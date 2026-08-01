<h1 align="center">Cipher MDT</h1>

<p align="center">A full police MDT for <strong>QBox</strong> and <strong>QBCore</strong> — live CAD dispatch, civilian records, warrants, BOLOs and supervisor audit.</p>

<p align="center">
  <a href="https://github.com/XyraL/cipher-mdt/releases"><img src="https://img.shields.io/github/v/release/XyraL/cipher-mdt?style=flat-square&color=70baff&label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/framework-QBox%20%7C%20QBCore-55dcff?style=flat-square" alt="framework">
  <img src="https://img.shields.io/badge/price-free-30d158?style=flat-square" alt="price">
  <a href="https://xyralscripts.dev/docs-cipher-mdt"><img src="https://img.shields.io/badge/docs-xyralscripts.dev-a889ff?style=flat-square" alt="docs"></a>
  <a href="https://discord.gg/XRURAw4TM2"><img src="https://img.shields.io/badge/support-discord-5865F2?style=flat-square" alt="support"></a>
</p>

<p align="center">
  <a href="https://xyralscripts.dev/cipher-mdt">Website</a> &nbsp;·&nbsp;
  <a href="https://xyralscripts.dev/docs-cipher-mdt">Setup guide</a> &nbsp;·&nbsp;
  <a href="https://github.com/XyraL/cipher-mdt/releases">Releases</a> &nbsp;·&nbsp;
  <a href="https://discord.gg/XRURAw4TM2">Discord</a>
</p>

<!-- SCREENSHOTS: drop 2-3 in-game shots here once captured -->

---

## Features

- **CAD Dispatch** — Create, update, and respond to live calls with P1/P2/P3 priority, elapsed timer, unit notes, GPS routing, and call history
- **Civilian Lookup** — Full profiles with mugshot, flags, arrest history, citations, vehicles, warrants, and officer notes
- **Vehicle Lookup** — Plate search with registration details and traffic stop shortcut
- **Arrest Records** — Collapsible cards with charges, fine/jail info, tags, and officer/date filters
- **Citation Records** — Same as arrests; supervisor can mark citations paid with optional auto bank deduction
- **Incident Reports** — Narrative reports with severity, involved persons/officers, linked arrests/citations
- **Warrants** — Issue, clear, and expire warrants; active count badge on nav
- **BOLOs** — Person and vehicle lookups with active badge
- **Penal Codes** — Searchable, supervisor-editable code library used in arrest/citation modals
- **Department Bulletins** — Supervisor-posted notices with Normal/Urgent/Critical priority, pinning, and auto-expiry
- **Civilian Flags** — Chip-based flag editor with 9 presets and custom flags; flags display in profile banner
- **Tags** — Color-coded tags on arrests, citations, and incidents
- **Body Camera Log** — Auto-records key officer actions; viewable per-officer by supervisors
- **Audit Log** — Supervisor-only viewer with action/officer/date filters (also posts to Discord webhook)
- **Supervisor Stats** — Weekly arrests, citations, fines, and top officer leaderboard on the dashboard
- **ox_target / qb-target** — Right-click players in-world to open MDT or issue citation
- **Sound Effects** — Subtle Web Audio API sounds, no extra files required
- **Real-time CAD** — New calls and status changes broadcast live to all on-duty officers

---

## Dependencies

| Resource | Required |
|---|---|
| [qbx_core](https://github.com/Qbox-project/qbx_core) | Yes |
| [ox_lib](https://github.com/overextended/ox_lib) | Yes |
| [oxmysql](https://github.com/overextended/oxmysql) | Yes |
| [ox_target](https://github.com/overextended/ox_target) **or** [qb-target](https://github.com/qbcore-framework/qb-target) | Optional |

> **Note:** qbx_core is required. Standard QBCore (`qb-core`) is not directly supported.

---

## Installation

### 1. Add the resource

Place the `cipher-mdt` folder in your `resources` directory (e.g. `resources/[standalone]/cipher-mdt`).

Add to your `server.cfg`:
```cfg
ensure cipher-mdt
```

### 2. Import the database

Run `sql/mdt.sql` against your database. It uses `CREATE TABLE IF NOT EXISTS` throughout, so it is safe to re-run.

If you are **upgrading from a previous version**, run only the commented `ALTER TABLE` lines at the top of the SQL file that match your current version.

### 3. Configure

Open `config.lua` and adjust the settings for your server (see [Configuration](#configuration) below).

### 4. Restart

```
restart cipher-mdt
```

---

## Configuration

All options are in `config.lua`.

```lua
-- Jobs allowed to access the MDT
Config.AuthorizedJobs = {
    ['police']      = true,
    ['sheriff']     = true,
    ['swat']        = true,
    ['statepolice'] = true,
}

-- Minimum job grade to access MDT (0 = all grades)
Config.MinGrade = 0

-- Key to open MDT (players can rebind in GTA Settings > Key Bindings)
Config.OpenKey = 'F9'

-- Require player to be on-duty to open MDT
Config.OnDutyOnly = true

-- Job grade required for supervisor features:
--   editing penal codes, deleting incidents, marking citations paid,
--   viewing audit log, posting bulletins, viewing body cam logs
Config.SupervisorGrade = 3

-- Fine deduction from player bank accounts
Config.FineDeduction = {
    Enabled               = true,
    AutoDeductArrests     = true,   -- deduct immediately when arrest is logged
    AutoDeductCitations   = false,  -- false = pay-later model (recommended)
    AutoDeductOnMarkPaid  = true,   -- deduct when supervisor marks citation paid
}

-- Jail integration
-- 'qb-prison'  → uses TriggerEvent('qb-prison:server:sendToJail', src, minutes)
-- 'ps-prison'  → uses TriggerEvent('prison:server:SendToJail', src, minutes)
-- false        → disabled (fires cipher-mdt:client:jailPlayer so you can handle it)
Config.JailResource = false

-- Discord webhook for audit log entries (leave empty '' to disable)
Config.AuditWebhook = ''

-- ox_target / qb-target integration
Config.Target = {
    Enabled     = true,
    MaxDistance = 3.0,
}

-- Body camera logging
Config.BodyCam = {
    Enabled       = true,
    RetentionDays = 30,  -- 0 = keep forever
}
```

---

## Dispatch Integration

CipherMDT includes auto-detection for common in-game events (gunshots, vehicle crashes, fights). To send a dispatch call **from another resource**, use any of the methods below.

### Server Export (recommended)
```lua
exports['cipher-mdt']:CreateDispatchCall({
    callType    = 'BANK_ROBBERY',
    description = 'Silent alarm triggered at Maze Bank.',
    coords      = { x = 148.0, y = -1044.0, z = 29.0 },
    street      = 'Alta Street',   -- optional, auto-detected if omitted
    callerName  = '911 Caller',    -- optional
})
```

### Client Event
```lua
TriggerEvent('cipher-mdt:client:dispatch:custom',
    'ROBBERY',                          -- call type key (see table below)
    'Armed robbery in progress.',       -- description
    vector3(24.8, -1347.3, 29.5)        -- coords
)
```

### Server Net Event
```lua
TriggerServerEvent('cipher-mdt:server:autoDispatch', {
    callType    = 'SHOTS_FIRED',
    description = 'Gunshots reported in the area.',
    street      = 'Forum Drive',
    coords      = { x = 80.0, y = -1283.0, z = 29.0 },
})
```

### Built-in Call Type Keys

| Key | Label |
|---|---|
| `SHOTS_FIRED` | Shots Fired |
| `FIGHT` | Fight / Assault |
| `VEHICLE_CRASH` | Vehicle Crash |
| `ROBBERY` | Robbery in Progress |
| `BANK_ROBBERY` | Bank Robbery |
| `STORE_ROBBERY` | Store Robbery |
| `TRAFFIC_STOP` | Traffic Stop |
| `MEDICAL` | Medical Emergency |
| `FIRE` | Structure Fire |
| `SUSPICIOUS` | Suspicious Activity |

Any other key will display the raw string as the call type label.

### Testing Dispatch (F8 Client Console)

```lua
TriggerServerEvent('cipher-mdt:server:autoDispatch', {
    callType = 'SHOTS_FIRED',
    description = 'Multiple shots fired near the bank.',
    street = 'Alta Street',
    coords = { x = 148.0, y = -1044.0, z = 29.0 }
})
```

> Auto-dispatch has a **60-second rate limit** per player per call type to prevent spam. If a test call doesn't appear, wait 60 seconds and try again.

---

## Jailing Through MDT

1. Set `Config.JailResource` in `config.lua` to match your jail resource:
   ```lua
   Config.JailResource = 'qb-prison'   -- or 'ps-prison'
   ```
2. When logging an arrest via **ox_target → Log Arrest** (targeting a player in-world), the arrest modal receives that player's server ID. If a jail time is filled in, the player is automatically jailed on submit.
3. Arrests filed from the civilian search panel (without a live target) do not have a source ID — jailing won't fire. This is by design; the suspect may not be online or present.

---

## Supervisor Features

Officers at or above `Config.SupervisorGrade` unlock:

| Feature | Location |
|---|---|
| Department Statistics | Dashboard |
| Department Bulletins | Bulletins panel |
| Audit Log Viewer | Dashboard → Audit Log button |
| Body Camera Log Viewer | Officers panel |
| Edit Penal Codes | Penal Codes panel |
| Mark Citations Paid | Citations panel |
| Delete Incidents | Incidents panel |

---

## Server Exports

```lua
-- Check if a player has MDT access
exports['cipher-mdt']:IsAuthorized(src)           -- returns bool

-- Get officer info for a player
exports['cipher-mdt']:GetOfficerInfo(src)
-- returns { citizenid, name, job, grade, gradeLabel, onduty }

-- Write to the audit log (also fires Discord webhook if configured)
exports['cipher-mdt']:AuditLog('Action Name', 'Officer Name', 'Details string')

-- Create a dispatch call from server-side
exports['cipher-mdt']:CreateDispatchCall({ callType, description, coords, ... })
```

---

## Troubleshooting

**MDT doesn't open**
- Check `Config.AuthorizedJobs` includes your job name — it is case-sensitive and must match the QBCore job name exactly.
- If `Config.OnDutyOnly = true`, the player must be clocked on duty.
- Check `Config.MinGrade` — the player's grade must be at or above this number.

**Dispatch alerts not appearing**
- Use the correct call type key format (`SHOTS_FIRED`, not `Shots Fired` or `shots_fired`).
- Auto-dispatch has a 60-second rate limit per player per call type.
- Verify the resource is running: `status cipher-mdt` in the server console.

**SQL errors on start**
- Ensure you ran `sql/mdt.sql` fully before starting the resource.
- If upgrading, run only the ALTER TABLE blocks for your previous version.

**Fine deduction not working**
- Set `Config.FineDeduction.Enabled = true`.
- The target player must be online for immediate deduction.
- For citations the default is `AutoDeductCitations = false` (pay-later model). Set to `true` to deduct on citation creation instead.

**Jailing not working**
- Verify `Config.JailResource` matches your jail resource name exactly.
- The arrest must be submitted via ox_target on a live, online player to carry a source ID for jailing.

---

Released under the MIT License. Free to use, modify, and redistribute with attribution.

---

## Documentation

Full setup guide, requirements and troubleshooting:
**[xyralscripts.dev/docs-cipher-mdt](https://xyralscripts.dev/docs-cipher-mdt)**

## Support

- **Found a bug?** [Open an issue](https://github.com/XyraL/cipher-mdt/issues)
- **Need setup help?** [Join the Discord](https://discord.gg/XRURAw4TM2) — check the setup guide first, it usually has the answer

## The rest of the Cipher line

All free, all source-available.

| Script | What it is |
|---|---|
| **[Cipher](https://github.com/XyraL/cipher)** | modular criminal device for QBox and QBCore — gang ops, blackmarket and boosting in one encrypted tablet. |
| **[Cipher Admin](https://github.com/XyraL/cipher-admin)** | advanced admin suite for QBox and QBCore — player management, bans, reports, inventory tools and entity inspection. |
| **[Cipher Drone](https://github.com/XyraL/cipher-drone)** | deployable police drone for QBox and QBCore — smooth flight, thermal, spotlight, tracker darts and real counterplay. |
| **[Cipher Trucking](https://github.com/XyraL/cipher-trucking)** | civilian trucking job for QBox and QBCore — live route map, truck ownership, fuel and maintenance, and companies. |

## License

Free to use on any server you own or operate, including commercial ones.
**Do not redistribute or resell** — see [LICENSE](LICENSE) for the full terms.
