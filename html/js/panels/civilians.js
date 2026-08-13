let civSearchTimeout = null;

// ── Civilian Flag Editor ───────────────────────────────────────────────────
const FLAG_PRESETS = [
    'Armed & Dangerous', 'Do Not Approach', 'Known Gang Member',
    'Violent History', 'Mental Health Concern', 'Parole / Probation',
    'Known Informant', 'Drug Offender', 'Warrant — Use Caution',
];
let _civFlagsList = [];

function initCivFlagsEditor(citizenid, initialFlags) {
    _civFlagsList = [...(initialFlags || [])];
    _renderCivFlagsEditor(citizenid);
}

function _renderCivFlagsEditor(citizenid) {
    const el = document.getElementById('civ-flags-editor');
    if (!el) return;
    el.innerHTML = `
        <div class="flag-presets">
            ${FLAG_PRESETS.map(f => `
                <button class="flag-preset-btn${_civFlagsList.includes(f) ? ' active' : ''}"
                        onclick="_toggleCivFlag('${citizenid.replace(/'/g,"\\'")}','${f.replace(/'/g,"\\'")}')">
                    ${f}
                </button>`).join('')}
        </div>
        <div class="flag-active-row">
            ${_civFlagsList.length === 0
                ? '<span class="text-muted text-sm">No flags set — click presets above or add a custom flag</span>'
                : _civFlagsList.map((f, i) => `
                    <span class="flag-chip">
                        ${f}
                        <button onclick="_removeCivFlag('${citizenid.replace(/'/g,"\\'")}',${i})">×</button>
                    </span>`).join('')}
        </div>
        <div style="display:flex;gap:8px;margin-top:8px;">
            <input class="input" id="civ-custom-flag-input" style="flex:1;"
                   placeholder="Custom flag..."
                   onkeydown="if(event.key==='Enter'){_addCustomCivFlag('${citizenid.replace(/'/g,"\\'")}');}">
            <button class="btn btn-ghost btn-sm" onclick="_addCustomCivFlag('${citizenid.replace(/'/g,"\\'")}')">+ Add</button>
        </div>`;
}

function _toggleCivFlag(citizenid, flag) {
    const idx = _civFlagsList.indexOf(flag);
    if (idx >= 0) _civFlagsList.splice(idx, 1);
    else _civFlagsList.push(flag);
    _renderCivFlagsEditor(citizenid);
}

function _removeCivFlag(citizenid, idx) {
    _civFlagsList.splice(idx, 1);
    _renderCivFlagsEditor(citizenid);
}

function _addCustomCivFlag(citizenid) {
    const input = document.getElementById('civ-custom-flag-input');
    if (!input) return;
    const val = input.value.trim();
    if (val && !_civFlagsList.includes(val)) _civFlagsList.push(val);
    input.value = '';
    _renderCivFlagsEditor(citizenid);
}

function initCivilianPanel() {
    const panel = document.getElementById('tab-civilians');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="panel-title">Civilian Lookup</div>
                <div class="panel-subtitle">Search by name, DOB, or Citizen ID</div>
            </div>
        </div>
        <div class="search-wrap">
            <div class="search-bar">
                <span class="search-icon">🔍</span>
                <input type="text" id="civ-search" placeholder="Search name, date of birth, or citizen ID..." autocomplete="off">
            </div>
            <span class="search-shortcut">↵ Enter</span>
        </div>
        <div class="panel-body" id="civ-results">
            <div class="empty-state">
                <div class="empty-icon">👤</div>
                <div class="empty-title">Search for a civilian</div>
                <div class="empty-subtitle">Enter a name or DOB above to begin</div>
            </div>
        </div>`;

    const input = document.getElementById('civ-search');
    input.addEventListener('input', (e) => {
        clearTimeout(civSearchTimeout);
        const q = e.target.value.trim();
        if (q.length < 2) {
            document.getElementById('civ-results').innerHTML = `
                <div class="empty-state">
                    <div class="empty-icon">👤</div>
                    <div class="empty-title">Type at least 2 characters</div>
                </div>`;
            return;
        }
        document.getElementById('civ-results').innerHTML =
            `<div>${Array(4).fill(0).map(() => `<div class="card mb-2">${skeletonLines(2)}</div>`).join('')}</div>`;
        civSearchTimeout = setTimeout(() => { addSearchHistory('name', q); searchCivilians(q); }, 320);
    });
    input.focus();
}

function searchCivilians(query) {
    nuiFetch('searchCivilians', query).then(results => {
        const el = document.getElementById('civ-results');
        if (!el) return;
        if (!results || results.length === 0) {
            el.innerHTML = `
                <div class="empty-state">
                    <div class="empty-icon">🔍</div>
                    <div class="empty-title">No results found</div>
                    <div class="empty-subtitle">Try a different name or Citizen ID</div>
                </div>`;
            return;
        }
        // The warrant/arrest columns are dropped entirely for departments that
        // can't see criminal data — showing "None / 0 records" would read as a
        // clean record rather than "not available to you".
        const showCriminal = (MDT.panels || []).includes('warrants');

        el.innerHTML = `
            <div class="data-table-wrap">
                <table class="data-table">
                    <thead>
                        <tr><th>Name</th><th>Date of Birth</th><th>Citizen ID</th>${
                            showCriminal ? '<th>Warrants</th><th>Arrests</th>' : '<th>Phone</th>'}<th></th></tr>
                    </thead>
                    <tbody>
                        ${results.map(c => `
                            <tr onclick="openCivilianProfile('${c.citizenid}')">
                                <td>
                                    <div class="font-bold">${c.firstname} ${c.lastname}</div>
                                    ${showCriminal && c.active_warrants > 0 ? '<div class="text-xs text-red mt-1">⚠ Active Warrant</div>' : ''}
                                </td>
                                <td class="font-mono">${c.dob || '—'}</td>
                                <td class="font-mono text-muted text-sm">${c.citizenid}</td>
                                ${showCriminal ? `
                                <td>${c.active_warrants > 0
                                    ? `<span class="tag tag-red">⚠ ${c.active_warrants} Active</span>`
                                    : '<span class="tag tag-green">None</span>'}</td>
                                <td><span class="tag tag-gray">${c.arrest_count || 0} records</span></td>`
                                : `<td class="font-mono text-muted text-sm">${c.phone || '—'}</td>`}
                                <td><button class="btn btn-ghost btn-xs" onclick="event.stopPropagation();openCivilianProfile('${c.citizenid}')">View →</button></td>
                            </tr>`).join('')}
                    </tbody>
                </table>
            </div>`;
    });
}

function openCivilianProfile(citizenid) {
    const panel = document.getElementById('tab-civilians');
    panel.innerHTML = `
        <div class="panel-header">
            <div class="panel-header-left">
                <div class="breadcrumb">
                    <span class="cursor-pointer text-accent" onclick="initCivilianPanel()">Civilians</span>
                    <span class="breadcrumb-sep">›</span>
                    <span class="breadcrumb-current">Profile</span>
                </div>
                <div class="panel-title" style="margin-top:2px;">Civilian Profile</div>
            </div>
            <div class="panel-actions" id="civ-profile-actions">
                <button class="btn btn-ghost btn-sm" onclick="initCivilianPanel()">← Back</button>
            </div>
        </div>
        <div class="panel-body" id="civ-profile-body">
            <div class="profile-banner">${skeletonLines(3)}</div>
            ${Array(2).fill(0).map(() => `<div class="card">${skeletonLines(3)}</div>`).join('')}
        </div>`;

    nuiFetch('getCivilianProfile', citizenid).then(data => {
        if (!data) {
            document.getElementById('civ-profile-body').innerHTML =
                `<div class="empty-state"><div class="empty-icon">⚠</div><div class="empty-title">Civilian not found</div></div>`;
            return;
        }
        renderCivilianProfile(data);

        if (data.canSeeCriminal) {
            const bar = document.getElementById('civ-profile-actions');
            if (bar) bar.insertAdjacentHTML('beforeend', `
                <button class="btn btn-warning btn-sm" onclick="openIssueWarrantModal('${citizenid}')">⚖ Issue Warrant</button>
                <button class="btn btn-success btn-sm" onclick="openNewCitationModal('${citizenid}')">📄 Citation</button>
                <button class="btn btn-danger btn-sm" onclick="openNewArrestModal('${citizenid}')">🔒 Log Arrest</button>`);
        }
    });
}

// The profile is shared by all departments, so its summary cards, tabs and
// tab bodies are assembled from what the server actually returned. Police get
// the criminal view; EMS (any department with the 'medhistory' panel) gets the
// medical one. A department with neither just sees identity details.
function civSummaryCards(data) {
    if (data.canSeeCriminal) {
        const active = (data.warrants || []).filter(w => w.status === 'active').length;
        return `
            <div class="card" style="padding:10px 14px;margin:0;min-width:120px;text-align:center;">
                <div class="stat-label">Warrants</div>
                <div style="font-size:22px;font-weight:800;color:${active ? 'var(--red)' : 'var(--green)'};">${active}</div>
            </div>
            <div class="card" style="padding:10px 14px;margin:0;min-width:120px;text-align:center;">
                <div class="stat-label">Arrests</div>
                <div style="font-size:22px;font-weight:800;color:var(--text-primary);">${(data.arrests || []).length}</div>
            </div>`;
    }
    if (data.canSeeMedical) {
        const med = data.medical || {};
        const allergies = (med.allergies || []).length;
        return `
            <div class="card" style="padding:10px 14px;margin:0;min-width:120px;text-align:center;">
                <div class="stat-label">Blood Type</div>
                <div style="font-size:22px;font-weight:800;color:var(--red);">${med.blood_type || '—'}</div>
            </div>
            <div class="card" style="padding:10px 14px;margin:0;min-width:120px;text-align:center;">
                <div class="stat-label">Allergies</div>
                <div style="font-size:22px;font-weight:800;color:${allergies ? 'var(--orange)' : 'var(--text-primary)'};">${allergies}</div>
            </div>
            ${Number(med.dnr) ? '<span class="tag tag-orange">⚠ DNR ON FILE</span>' : ''}`;
    }
    return '';
}

function civProfileTabs(data) {
    const tabs = [];
    if (data.canSeeCriminal) {
        tabs.push(['civ-warrants',  'Warrants',  (data.warrants  || []).length]);
        tabs.push(['civ-arrests',   'Arrests',   (data.arrests   || []).length]);
        tabs.push(['civ-citations', 'Citations', (data.citations || []).length]);
        tabs.push(['civ-vehicles',  'Vehicles',  (data.vehicles  || []).length]);
    }
    if (data.canSeeMedical) {
        tabs.push(['civ-medical', 'Medical', null]);
        tabs.push(['civ-medhist', 'History', (data.medical_history || []).length]);
    }
    if (data.canSeeCriminal) tabs.push(['civ-officer-notes', 'Notes', null]);

    return tabs.map(([id, label, count], i) => `
        <div class="profile-tab ${i === 0 ? 'active' : ''}" onclick="showCivTab(this,'${id}')">
            ${label}${count !== null ? ` <span class="profile-tab-count">${count}</span>` : ''}
        </div>`).join('');
}

function civProfileBodies(data) {
    const out = [];
    let first = true;
    const wrap = (id, html) => {
        out.push(`<div id="${id}" class="${first ? '' : 'hidden'}">${html}</div>`);
        first = false;
    };

    if (data.canSeeCriminal) {
        wrap('civ-warrants',  renderWarrantsList(data.warrants || [], data.citizenid));
        wrap('civ-arrests',   renderArrestsList(data.arrests || []));
        wrap('civ-citations', renderCitationsList(data.citations || []));
        wrap('civ-vehicles',  renderVehiclesList(data.vehicles || []));
    }
    if (data.canSeeMedical) {
        wrap('civ-medical', renderCivMedical(data));
        wrap('civ-medhist', renderCivMedHistory(data));
    }
    if (!out.length) {
        out.push('<div class="empty-state"><div class="empty-icon">🔒</div>' +
                 '<div class="empty-title">No records available</div>' +
                 '<div class="empty-subtitle">Your department can only see identity details</div></div>');
    }
    return out.join('');
}

function renderCivMedical(data) {
    const med = data.medical;
    if (!med) {
        return '<div class="empty-state"><div class="empty-icon">❤</div>' +
               '<div class="empty-title">No medical record on file</div></div>';
    }
    const block = (title, items, tagClass) => (items && items.length) ? `
        <div class="mb-2">
            <div class="form-label">${title}</div>
            <div style="display:flex;gap:6px;flex-wrap:wrap;">
                ${items.map(i => `<span class="tag ${tagClass}">${i}</span>`).join('')}
            </div>
        </div>` : '';

    return `
        <div class="card">
            <div class="card-header">
                <div class="card-title">Medical Record</div>
                <button class="btn btn-ghost btn-sm" onclick="switchTab('medhistory')">Open in Medical Records →</button>
            </div>
            <div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:10px;">
                ${med.blood_type ? `<span class="tag tag-red">🩸 ${med.blood_type}</span>` : ''}
                ${Number(med.dnr) ? '<span class="tag tag-orange">⚠ DNR</span>' : ''}
                ${Number(med.organ_donor) ? '<span class="tag tag-green">ORGAN DONOR</span>' : ''}
            </div>
            ${block('Allergies', med.allergies, 'tag-red')}
            ${block('Conditions', med.conditions, 'tag-orange')}
            ${block('Medications', med.medications, 'tag-blue')}
            ${med.notes ? `<div class="mt-2"><div class="form-label">Notes</div>
                <div style="font-size:12.5px;color:var(--text-secondary);">${med.notes}</div></div>` : ''}
        </div>`;
}

function renderCivMedHistory(data) {
    const rows = data.medical_history || [];
    if (!rows.length) {
        return '<div class="empty-state"><div class="empty-icon">📋</div>' +
               '<div class="empty-title">No history entries</div></div>';
    }
    return `<div class="card">${rows.map(h => `
        <div style="padding:8px 0;border-bottom:1px solid var(--border);">
            <div style="display:flex;gap:8px;align-items:center;">
                <span class="tag tag-gray">${h.entry_type}</span>
                <span class="text-xs text-muted font-mono">${fmtDateShort(h.created_at)}</span>
                <span class="text-xs text-muted">— ${h.author_name}</span>
            </div>
            <div style="font-size:12.5px;color:var(--text-secondary);margin-top:4px;">${h.entry}</div>
        </div>`).join('')}</div>`;
}

function renderCivilianProfile(data) {
    const flags = data.flags ? (Array.isArray(data.flags) ? data.flags : Object.values(data.flags)) : [];
    const hasWarrant = data.warrants && data.warrants.some(w => w.status === 'active');
    const totalFines = [...(data.citations||[])].reduce((s, c) => s + (c.fine || 0), 0);

    document.getElementById('civ-profile-body').innerHTML = `
        <div class="profile-banner">
            <div class="mugshot-wrap" onclick="openMugshotModal('${data.citizenid}','${(data.image||'').replace(/'/g,"\\'")}')">
                ${data.image
                    ? `<img src="${data.image}" class="mugshot-img" alt="Mugshot">`
                    : '<span class="mugshot-placeholder">👤</span>'}
                <div class="mugshot-edit-btn">📷</div>
            </div>
            <div class="profile-info">
                <div class="profile-name">
                    ${data.firstname} ${data.lastname}
                    ${hasWarrant ? '<span class="tag tag-red">ACTIVE WARRANT</span>' : ''}
                    ${flags.map(f => `<span class="tag tag-orange">${f}</span>`).join('')}
                </div>
                <div class="profile-meta">
                    <span>📅 DOB: ${data.dob || '—'}</span>
                    <span>⚧ ${data.gender || '—'}</span>
                    <span>📍 ${data.address || 'No address'}</span>
                    <span>📞 ${data.phone || 'No phone'}</span>
                </div>
            </div>
            <div style="display:flex;flex-direction:column;gap:6px;align-items:flex-end;flex-shrink:0;">
                ${civSummaryCards(data)}
            </div>
        </div>

        ${(data.canSeeCriminal && data.notes) ? `
            <div class="alert alert-warn">
                <span>📌</span>
                <div><strong>Officer Notes:</strong> ${data.notes}</div>
            </div>` : ''}

        <div class="profile-tabs">${civProfileTabs(data)}</div>

        ${civProfileBodies(data)}
        ${!data.canSeeCriminal ? '' : `
        <div id="civ-officer-notes" class="hidden">
            <div class="card">
                <div class="card-header"><div class="card-title">Officer Notes</div></div>
                <div class="form-group">
                    <label class="form-label">Internal Notes (visible to all officers)</label>
                    <textarea class="textarea" id="civ-notes-input" style="min-height:140px;" placeholder="Add notes about this individual...">${data.notes || ''}</textarea>
                </div>
                <div class="form-group">
                    <label class="form-label">Flags / Alerts</label>
                    <div class="form-hint" style="margin-bottom:8px;">Flags appear on the profile banner. Click a preset or add a custom flag.</div>
                    <div id="civ-flags-editor"></div>
                </div>
                <button class="btn btn-primary btn-sm" onclick="saveCivNotes('${data.citizenid}')">Save Notes &amp; Flags</button>
            </div>
        </div>`}`;

    // Init flag editor after HTML renders (works even though Notes tab is hidden initially)
    setTimeout(() => initCivFlagsEditor(data.citizenid, flags), 0);
}

function showCivTab(el, id) {
    document.querySelectorAll('.profile-tab').forEach(t => t.classList.remove('active'));
    el.classList.add('active');
    ['civ-warrants','civ-arrests','civ-citations','civ-vehicles','civ-officer-notes'].forEach(t => {
        document.getElementById(t)?.classList.toggle('hidden', t !== id);
    });
}

function renderVehiclesList(vehicles) {
    if (!vehicles || !vehicles.length) return `<div class="empty-state"><div class="empty-icon">🚗</div><div class="empty-title">No registered vehicles</div></div>`;
    const stateMap = { 0: ['Out', 'tag-yellow'], 1: ['Garaged', 'tag-green'], 2: ['Impounded', 'tag-red'] };
    return `
        <div class="data-table-wrap">
            <table class="data-table">
                <thead>
                    <tr><th>Plate</th><th>Model</th><th>Garage</th><th>Status</th><th>Fuel</th><th></th></tr>
                </thead>
                <tbody>
                    ${vehicles.map(v => {
                        const [stateLabel, stateTag] = stateMap[v.state] || ['Unknown','tag-gray'];
                        return `
                        <tr>
                            <td class="font-mono" style="font-weight:700;letter-spacing:.08em;">${v.plate}</td>
                            <td>${v.label || v.vehicle || '—'}</td>
                            <td class="text-muted text-sm">${v.garage || '—'}</td>
                            <td><span class="tag ${stateTag}">${stateLabel}</span></td>
                            <td class="text-sm">${v.fuel ? Math.round(v.fuel) + '%' : '—'}</td>
                            <td>
                                <button class="btn btn-ghost btn-xs"
                                    onclick="switchTab('vehicles');setTimeout(()=>{const i=document.getElementById('plate-search');if(i){i.value='${v.plate}';lookupPlate();}},80);">
                                    Lookup →
                                </button>
                            </td>
                        </tr>`;
                    }).join('')}
                </tbody>
            </table>
        </div>`;
}

function renderWarrantsList(warrants, citizenid) {
    if (!warrants.length) return `<div class="empty-state"><div class="empty-icon">⚖</div><div class="empty-title">No warrants on file</div></div>`;
    return warrants.map(w => `
        <div class="record-item warrant-item">
            <div class="record-item-header">
                <span class="tag ${w.status==='active'?'tag-red':'tag-green'}">${w.status.toUpperCase()}</span>
                <span class="record-date">${fmtDate(w.created_at)}</span>
                ${w.status==='active' ? `<button class="btn btn-ghost btn-xs ml-auto" onclick="clearWarrantFromProfile(${w.id},'${citizenid}')">Clear Warrant</button>` : ''}
            </div>
            <div class="record-charges">${(w.charges||[]).map(c=>`<span class="tag tag-red">${c.code} — ${c.name}</span>`).join('')}</div>
            ${w.description ? `<div class="record-narrative">${w.description}</div>` : ''}
            <div class="record-officer">Issued by: <strong>${w.issued_by_name}</strong></div>
        </div>`).join('');
}

function renderArrestsList(arrests) {
    if (!arrests.length) return `<div class="empty-state"><div class="empty-icon">🔒</div><div class="empty-title">No arrest records</div></div>`;
    return arrests.map(a => `
        <div class="record-item arrest-item">
            <div class="record-item-header">
                <span class="tag tag-red">ARREST</span>
                ${a.fine ? `<span class="tag tag-yellow">${dollarFmt(a.fine)} fine</span>` : ''}
                ${a.jail_time ? `<span class="tag tag-orange">${a.jail_time} min jail</span>` : ''}
                <span class="record-date">${fmtDate(a.created_at)}</span>
            </div>
            <div class="record-charges">${(a.charges||[]).map(c=>`<span class="tag tag-red">${c.code} — ${c.name}</span>`).join('')}</div>
            ${a.narrative ? `<div class="record-narrative">${a.narrative}</div>` : ''}
            <div class="record-officer">Arresting Officer: <strong>${a.officer_name}</strong>${a.location ? ` · 📍 ${a.location}` : ''}</div>
        </div>`).join('');
}

function renderCitationsList(citations) {
    if (!citations.length) return `<div class="empty-state"><div class="empty-icon">📄</div><div class="empty-title">No citations on file</div></div>`;
    return citations.map(c => `
        <div class="record-item citation-item">
            <div class="record-item-header">
                <span class="tag tag-yellow">CITATION</span>
                <span class="tag ${c.paid?'tag-green':'tag-red'}">${c.paid?'PAID':'UNPAID'}</span>
                <span class="record-date">${fmtDate(c.created_at)}</span>
            </div>
            <div class="record-charges">${(c.charges||[]).map(ch=>`<span class="tag tag-yellow">${ch.code} — ${ch.name}</span>`).join('')}</div>
            <div style="margin-top:6px;font-size:13px;">Fine: <strong class="text-green">${dollarFmt(c.fine)}</strong></div>
            <div class="record-officer">Officer: <strong>${c.officer_name}</strong>${c.location ? ` · 📍 ${c.location}` : ''}</div>
        </div>`).join('');
}

async function clearWarrantFromProfile(warrantId, citizenid) {
    const result = await nuiFetch('clearWarrant', warrantId);
    if (result) { showToast('Warrant Cleared', '', 'success'); openCivilianProfile(citizenid); }
    else showToast('Error', 'Could not clear warrant.', 'error');
}

async function saveCivNotes(citizenid) {
    const notes = document.getElementById('civ-notes-input')?.value.trim() || '';
    const result = await nuiFetch('updateCivilianNotes', { citizenid, notes, flags: _civFlagsList || [] });
    if (result) {
        showToast('Notes Saved', '', 'success');
        // Refresh banner flags without full reload
        const flagBanner = document.querySelector('.profile-name');
        if (flagBanner) {
            // Remove old flag spans, re-add current ones
            flagBanner.querySelectorAll('.tag-orange').forEach(t => t.remove());
            _civFlagsList.forEach(f => {
                const span = document.createElement('span');
                span.className = 'tag tag-orange';
                span.textContent = f;
                flagBanner.appendChild(span);
            });
        }
    } else showToast('Error', 'Could not save notes.', 'error');
}

// ── Mugshot Upload ────────────────────────────────────────────────────────
function openMugshotModal(citizenid, currentImage) {
    const escaped = (currentImage || '').replace(/"/g, '&quot;');
    const modal = createModal('Update Civilian Photo', `
        <div class="form-group">
            <label class="form-label">Image URL</label>
            <input class="input" id="mugshot-url" value="${escaped}"
                   placeholder="Paste a direct image URL (Discord CDN, Imgur, etc.)"
                   oninput="previewMugshot()">
            <div class="form-hint">Use a direct link ending in .jpg, .png, or .webp</div>
        </div>
        <div id="mugshot-preview" style="display:flex;justify-content:center;padding:12px 0;min-height:80px;align-items:center;">
            ${currentImage
                ? `<img src="${escaped}" class="mugshot-modal-preview" alt="Preview">`
                : '<span class="text-muted text-sm">Enter a URL above to preview</span>'}
        </div>
        <button class="btn btn-ghost btn-sm w-full" style="margin-top:4px;"
                onclick="document.getElementById('mugshot-url').value='';previewMugshot()">
            ✕ Remove Photo
        </button>`,
        async () => {
            const url = document.getElementById('mugshot-url')?.value.trim() || null;
            const ok = await nuiFetch('updateCivilianImage', { citizenid, image: url || null });
            if (ok) {
                showToast('Photo Updated', '', 'success');
                closeModal(modal);
                openCivilianProfile(citizenid);
            } else {
                showToast('Error', 'Could not update photo.', 'error');
            }
        }, 'Save Photo', '📷');
}

function previewMugshot() {
    const url = (document.getElementById('mugshot-url')?.value || '').trim();
    const el = document.getElementById('mugshot-preview');
    if (!el) return;
    if (!url) {
        el.innerHTML = '<span class="text-muted text-sm">Enter a URL above to preview</span>';
        return;
    }
    el.innerHTML = `
        <img src="${url}" class="mugshot-modal-preview" alt="Preview"
             onerror="document.getElementById('mugshot-preview').innerHTML='<span style=\\'color:var(--red);font-size:12px;\\'>Invalid URL — image could not load</span>'">`;
}

window.initCivilianPanel       = initCivilianPanel;
window.searchCivilians         = searchCivilians;
window.openCivilianProfile     = openCivilianProfile;
window.renderCivilianProfile   = renderCivilianProfile;
window.showCivTab              = showCivTab;
window.renderWarrantsList      = renderWarrantsList;
window.renderArrestsList       = renderArrestsList;
window.renderCitationsList     = renderCitationsList;
window.renderVehiclesList      = renderVehiclesList;
window.clearWarrantFromProfile = clearWarrantFromProfile;
window.saveCivNotes            = saveCivNotes;
window.initCivFlagsEditor      = initCivFlagsEditor;
window._renderCivFlagsEditor   = _renderCivFlagsEditor;
window._toggleCivFlag          = _toggleCivFlag;
window._removeCivFlag          = _removeCivFlag;
window._addCustomCivFlag       = _addCustomCivFlag;
window.openMugshotModal        = openMugshotModal;
window.previewMugshot          = previewMugshot;
