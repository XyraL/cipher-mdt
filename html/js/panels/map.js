// CipherMDT Map Panel — live unit tracker, no external image required

const MAP_W = 1000, MAP_H = 1000;

// GTA V approximate world-to-canvas mapping
const WORLD = { minX: -3900, maxX: 4300, minY: -4500, maxY: 8100 };

function worldToCanvas(wx, wy) {
    return {
        x: ((wx - WORLD.minX) / (WORLD.maxX - WORLD.minX)) * MAP_W,
        y: ((WORLD.maxY - wy) / (WORLD.maxY - WORLD.minY)) * MAP_H,
    };
}

const JOB_COLOR = {
    police   : '#6366f1',
    sheriff  : '#818cf8',
    ambulance: '#22c55e',
    fire     : '#ef4444',
};
function jobColor(job) { return JOB_COLOR[job] || '#6366f1'; }

// Named landmarks for map reference (world coords)
const LANDMARKS = [
    { name: 'LS Airport',     x:  -979, y: -2920, icon: '✈' },
    { name: 'LSPD',           x:   428, y: -980,  icon: '⬡' },
    { name: 'Pillbox Hill',   x:   185, y: -935,  icon: '🏥' },
    { name: 'Legion Square',  x:   195, y: -1640, icon: '◈' },
    { name: 'Vinewood',       x:   610, y:  265,  icon: '★' },
    { name: 'Rockford Hills', x:  -750, y:  530,  icon: '◎' },
    { name: 'Sandy Shores',   x:  1900, y: 3700,  icon: '◈' },
    { name: 'Paleto Bay',     x: -248,  y: 6340,  icon: '◈' },
    { name: 'Del Perro',      x: -1700, y:  -310, icon: '◎' },
    { name: 'LS Port',        x:  -300, y: -2600, icon: '⚓' },
    { name: 'Maze Bank',      x:  -75,  y:  -820, icon: '▦' },
    { name: 'Mirror Park',    x:  1190, y:  -1480, icon: '◎' },
];

// Zone color fills (very rough bounding boxes, painted before grid)
const ZONES = [
    { name: 'Downtown LS',  x1: -400, y1: -2000, x2:  700, y2:  -600, color: 'rgba(99,102,241,0.04)' },
    { name: 'Vinewood',     x1:  300, y1:  -200,  x2:  950, y2:   700, color: 'rgba(168,85,247,0.04)' },
    { name: 'Sandy Shores', x1: 1300, y1: 2900,   x2: 3500, y2: 4700,  color: 'rgba(245,158,11,0.04)' },
    { name: 'Paleto Bay',   x1: -800, y1: 5600,   x2:  400, y2: 7000,  color: 'rgba(34,197,94,0.04)'  },
    { name: 'Del Perro',    x1:-2200, y1:  -700,  x2: -800, y2:   300, color: 'rgba(14,165,233,0.04)' },
    { name: 'LS Airport',   x1:-1600, y1:-3600,   x2:  -50, y2:-2200,  color: 'rgba(99,102,241,0.06)' },
];

let _mapUnits   = [];
let _mapCalls   = [];
let _mapCanvas  = null;
let _mapCtx     = null;
let _mapInterval= null;
let _selectedUnit = null;
let _panX = 0, _panY = 0, _zoom = 1;
let _isDragging = false, _dragStart = null;

function initMapPanel() {
    const panel = document.getElementById('tab-map');
    panel.style.display = 'flex';
    panel.style.flexDirection = 'column';
    panel.style.height = '100%';

    panel.innerHTML = `
        <div class="panel-header" style="flex-shrink:0;">
            <div class="panel-header-left">
                <div class="panel-title">Unit Tracker</div>
                <div class="panel-subtitle" id="map-unit-count">Loading units…</div>
            </div>
            <div class="panel-actions" style="gap:6px;">
                <button class="btn btn-ghost btn-sm" onclick="mapResetView()">⊡ Reset</button>
                <button class="btn btn-ghost btn-sm" onclick="mapZoom(1.35)" style="font-size:16px;padding:4px 12px;">+</button>
                <button class="btn btn-ghost btn-sm" onclick="mapZoom(0.74)" style="font-size:16px;padding:4px 12px;">−</button>
                <button class="btn btn-primary btn-sm" onclick="refreshMapData()">↻ Refresh</button>
            </div>
        </div>
        <div style="display:grid;grid-template-columns:1fr 280px;gap:14px;flex:1;min-height:0;overflow:hidden;">
            <!-- Map Canvas -->
            <div style="position:relative;overflow:hidden;border-radius:var(--radius);
                        border:1px solid var(--border-light);background:#060810;min-height:0;">
                <canvas id="mdt-map-canvas" width="${MAP_W}" height="${MAP_H}"
                        style="width:100%;height:100%;cursor:grab;display:block;"></canvas>
                <div id="map-tooltip" style="
                    display:none;position:absolute;background:var(--bg-panel);
                    border:1px solid var(--border-light);border-radius:8px;
                    padding:8px 12px;font-size:12px;pointer-events:none;
                    box-shadow:0 8px 32px rgba(0,0,0,.6);z-index:10;min-width:140px;
                "></div>
                <div style="position:absolute;bottom:10px;left:12px;font-size:10px;color:rgba(255,255,255,.2);
                            font-family:var(--font-mono);user-select:none;">
                    Scroll to zoom · Drag to pan
                </div>
                <div style="position:absolute;top:10px;right:10px;font-size:10px;color:rgba(255,255,255,.2);
                            font-family:var(--font-mono);user-select:none;" id="map-zoom-display">
                    ×1.0
                </div>
            </div>

            <!-- Sidebar -->
            <div style="display:flex;flex-direction:column;gap:10px;overflow:hidden;min-height:0;">
                <div style="font-size:10px;font-weight:800;letter-spacing:.1em;color:var(--text-muted);
                            text-transform:uppercase;flex-shrink:0;">On-Duty Units</div>
                <div id="map-unit-list" style="flex:1;overflow-y:auto;display:flex;flex-direction:column;gap:5px;min-height:0;"></div>
                <div style="border-top:1px solid var(--border);padding-top:10px;flex-shrink:0;">
                    <div style="font-size:10px;font-weight:800;letter-spacing:.1em;color:var(--text-muted);
                                text-transform:uppercase;margin-bottom:8px;">Legend</div>
                    <div style="display:flex;flex-direction:column;gap:5px;">
                        ${Object.entries(JOB_COLOR).map(([job, color]) => `
                            <div style="display:flex;align-items:center;gap:8px;font-size:12px;">
                                <div style="width:9px;height:9px;border-radius:50%;background:${color};flex-shrink:0;
                                            box-shadow:0 0 5px ${color};"></div>
                                <span style="color:var(--text-muted);text-transform:capitalize;">${job}</span>
                            </div>`).join('')}
                        <div style="display:flex;align-items:center;gap:8px;font-size:12px;">
                            <div style="width:9px;height:9px;background:#f59e0b;transform:rotate(45deg);flex-shrink:0;
                                        box-shadow:0 0 5px #f59e0b;"></div>
                            <span style="color:var(--text-muted);">Active CAD Call</span>
                        </div>
                    </div>
                </div>
            </div>
        </div>`;

    _mapCanvas = document.getElementById('mdt-map-canvas');
    _mapCtx    = _mapCanvas.getContext('2d');

    _mapCanvas.addEventListener('wheel',     onMapWheel,     { passive: false });
    _mapCanvas.addEventListener('mousedown', onMapMouseDown);
    _mapCanvas.addEventListener('mousemove', onMapMouseMove);
    _mapCanvas.addEventListener('mouseup',   () => { _isDragging = false; _mapCanvas.style.cursor = 'grab'; });
    _mapCanvas.addEventListener('mouseleave',() => { _isDragging = false; document.getElementById('map-tooltip').style.display='none'; });

    mapResetView();
    refreshMapData();

    if (_mapInterval) clearInterval(_mapInterval);
    _mapInterval = setInterval(refreshMapData, 6000);
}

async function refreshMapData() {
    const [units, calls] = await Promise.all([
        nuiFetch('getUnits', {}),
        nuiFetch('getActiveCalls', {}),
    ]);
    _mapUnits = Array.isArray(units) ? units : [];
    _mapCalls = Array.isArray(calls) ? calls : [];
    drawMap();
    renderUnitList();
    const sub = document.getElementById('map-unit-count');
    if (sub) sub.textContent = `${_mapUnits.length} unit${_mapUnits.length !== 1 ? 's' : ''} online · ${_mapCalls.length} active call${_mapCalls.length !== 1 ? 's' : ''}`;
}

function mapResetView() { _panX = 0; _panY = 0; _zoom = 1; drawMap(); }

function mapZoom(factor) {
    _zoom = Math.min(8, Math.max(0.4, _zoom * factor));
    drawMap();
}

function onMapWheel(e) {
    e.preventDefault();
    const f = e.deltaY < 0 ? 1.15 : 0.87;
    const rect = _mapCanvas.getBoundingClientRect();
    const mx = (e.clientX - rect.left) / rect.width  * MAP_W;
    const my = (e.clientY - rect.top)  / rect.height * MAP_H;
    _panX = mx - f * (mx - _panX);
    _panY = my - f * (my - _panY);
    _zoom = Math.min(8, Math.max(0.4, _zoom * f));
    drawMap();
}

function onMapMouseDown(e) {
    _isDragging = true;
    _dragStart  = { x: e.clientX, y: e.clientY, px: _panX, py: _panY };
    _mapCanvas.style.cursor = 'grabbing';
}

function onMapMouseMove(e) {
    const rect   = _mapCanvas.getBoundingClientRect();
    const scaleX = MAP_W / rect.width;
    const scaleY = MAP_H / rect.height;

    if (_isDragging && _dragStart) {
        _panX = _dragStart.px + (e.clientX - _dragStart.x) * scaleX;
        _panY = _dragStart.py + (e.clientY - _dragStart.y) * scaleY;
        drawMap();
        return;
    }

    // Tooltip hover
    const mx  = (e.clientX - rect.left) * scaleX;
    const my  = (e.clientY - rect.top)  * scaleY;
    const tt  = document.getElementById('map-tooltip');
    if (!tt) return;
    let hit = null;

    for (const unit of _mapUnits) {
        if (!unit.coords) continue;
        const cp = worldToCanvas(unit.coords.x, unit.coords.y);
        const sx = (cp.x * _zoom + _panX);
        const sy = (cp.y * _zoom + _panY);
        if (Math.hypot(mx - sx, my - sy) < 14) { hit = { type: 'unit', data: unit }; break; }
    }
    if (!hit) {
        for (const call of _mapCalls) {
            if (!call.coords) continue;
            const cp = worldToCanvas(call.coords.x, call.coords.y);
            const sx = (cp.x * _zoom + _panX);
            const sy = (cp.y * _zoom + _panY);
            if (Math.hypot(mx - sx, my - sy) < 14) { hit = { type: 'call', data: call }; break; }
        }
    }

    if (hit) {
        tt.style.display = 'block';
        tt.style.left = ((e.clientX - rect.left) / rect.width  * 100 + 1) + '%';
        tt.style.top  = ((e.clientY - rect.top)  / rect.height * 100 - 4) + '%';
        if (hit.type === 'unit') {
            const u = hit.data;
            tt.innerHTML = `
                <div style="font-weight:700;font-size:13px;color:var(--text-primary);margin-bottom:4px;">${u.name}</div>
                <div style="font-size:11px;color:var(--text-muted);">Badge: <strong style="color:${jobColor(u.job)};">${u.badge || '—'}</strong></div>
                <div style="font-size:11px;color:var(--text-muted);text-transform:capitalize;">${u.job}</div>`;
        } else {
            const c = hit.data;
            tt.innerHTML = `
                <div style="font-weight:700;font-size:12px;color:#f59e0b;margin-bottom:4px;">${c.call_number || c.id}</div>
                <div style="font-size:11px;color:var(--text-primary);">${c.call_type || c.type || 'Call'}</div>
                <div style="font-size:11px;color:var(--text-muted);">📍 ${c.location || '—'}</div>`;
        }
    } else {
        tt.style.display = 'none';
    }
}

function drawMap() {
    if (!_mapCtx) return;
    const ctx = _mapCtx;
    ctx.clearRect(0, 0, MAP_W, MAP_H);
    ctx.save();
    ctx.translate(_panX, _panY);
    ctx.scale(_zoom, _zoom);

    // Background
    ctx.fillStyle = '#060810';
    ctx.fillRect(-_panX / _zoom, -_panY / _zoom, MAP_W / _zoom, MAP_H / _zoom);

    // Zone fills
    for (const z of ZONES) {
        const a = worldToCanvas(z.x1, z.y1);
        const b = worldToCanvas(z.x2, z.y2);
        ctx.fillStyle = z.color;
        ctx.fillRect(Math.min(a.x, b.x), Math.min(a.y, b.y),
                     Math.abs(b.x - a.x), Math.abs(b.y - a.y));
    }

    // Grid lines
    ctx.strokeStyle = 'rgba(99,102,241,0.07)';
    ctx.lineWidth = 0.5;
    for (let gx = 0; gx <= MAP_W; gx += 50) {
        ctx.beginPath(); ctx.moveTo(gx, 0); ctx.lineTo(gx, MAP_H); ctx.stroke();
    }
    for (let gy = 0; gy <= MAP_H; gy += 50) {
        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(MAP_W, gy); ctx.stroke();
    }

    // Axis lines
    const center = worldToCanvas(0, 0);
    ctx.strokeStyle = 'rgba(99,102,241,0.18)';
    ctx.lineWidth = 0.8;
    ctx.setLineDash([4, 4]);
    ctx.beginPath(); ctx.moveTo(center.x, 0); ctx.lineTo(center.x, MAP_H); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(0, center.y); ctx.lineTo(MAP_W, center.y); ctx.stroke();
    ctx.setLineDash([]);

    // Landmark markers
    for (const lm of LANDMARKS) {
        const cp = worldToCanvas(lm.x, lm.y);
        ctx.fillStyle = 'rgba(99,102,241,0.1)';
        ctx.beginPath(); ctx.arc(cp.x, cp.y, 6, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = 'rgba(99,102,241,0.3)';
        ctx.lineWidth = 0.8;
        ctx.stroke();

        if (_zoom > 0.9) {
            ctx.fillStyle = 'rgba(148,163,184,0.55)';
            ctx.font = `${Math.round(7 / _zoom * 11)}px sans-serif`;
            ctx.textAlign = 'center';
            ctx.fillText(lm.name, cp.x, cp.y + 14 / _zoom);
        }
    }

    // CAD call markers (diamond shape)
    for (const call of _mapCalls) {
        if (!call.coords) continue;
        drawCallMarker(ctx, worldToCanvas(call.coords.x, call.coords.y), call);
    }

    // Unit blips
    for (const unit of _mapUnits) {
        if (!unit.coords) continue;
        drawUnitBlip(ctx, worldToCanvas(unit.coords.x, unit.coords.y), unit);
    }

    ctx.restore();

    // Zoom indicator
    const zd = document.getElementById('map-zoom-display');
    if (zd) zd.textContent = `×${_zoom.toFixed(1)}`;
}

function drawUnitBlip(ctx, cp, unit) {
    const color = jobColor(unit.job);
    const sel   = _selectedUnit && _selectedUnit.citizenid === unit.citizenid;
    const r     = sel ? 10 : 7;

    ctx.save();
    ctx.shadowColor = color;
    ctx.shadowBlur  = sel ? 18 : 10;

    ctx.beginPath();
    ctx.arc(cp.x, cp.y, r, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();

    ctx.beginPath();
    ctx.arc(cp.x, cp.y, r, 0, Math.PI * 2);
    ctx.strokeStyle = sel ? '#fff' : 'rgba(255,255,255,0.6)';
    ctx.lineWidth   = sel ? 2 : 1.2;
    ctx.stroke();

    if (_zoom > 1.8) {
        ctx.fillStyle = '#fff';
        ctx.font      = `bold ${Math.round(8 / _zoom * 13)}px monospace`;
        ctx.textAlign = 'center';
        ctx.shadowBlur= 0;
        ctx.fillText(unit.badge || '?', cp.x, cp.y - r - 3);
    }

    ctx.restore();
}

function drawCallMarker(ctx, cp, call) {
    const s = 8;
    ctx.save();
    ctx.shadowColor = '#f59e0b';
    ctx.shadowBlur  = 12;
    ctx.beginPath();
    ctx.moveTo(cp.x,     cp.y - s);
    ctx.lineTo(cp.x + s, cp.y);
    ctx.lineTo(cp.x,     cp.y + s);
    ctx.lineTo(cp.x - s, cp.y);
    ctx.closePath();
    ctx.fillStyle   = 'rgba(245,158,11,0.85)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.7)';
    ctx.lineWidth   = 1;
    ctx.stroke();
    ctx.restore();
}

function renderUnitList() {
    const list = document.getElementById('map-unit-list');
    if (!list) return;
    if (!_mapUnits.length) {
        list.innerHTML = `<div style="color:var(--text-muted);font-size:12px;text-align:center;padding:20px 0;">
            No units currently online</div>`;
        return;
    }
    list.innerHTML = _mapUnits.map(u => {
        const color = jobColor(u.job);
        const sel   = _selectedUnit && _selectedUnit.citizenid === u.citizenid;
        return `
            <div onclick="selectMapUnit('${u.citizenid}')" style="
                display:flex;align-items:center;gap:9px;padding:8px 10px;cursor:pointer;
                background:${sel ? 'var(--bg-hover)' : 'var(--bg-input)'};
                border:1px solid ${sel ? 'var(--accent)' : 'var(--border)'};
                border-radius:8px;transition:all .15s;flex-shrink:0;">
                <div style="width:9px;height:9px;border-radius:50%;background:${color};flex-shrink:0;
                            box-shadow:0 0 6px ${color};"></div>
                <div style="flex:1;min-width:0;">
                    <div style="font-size:12px;font-weight:600;color:var(--text-primary);
                                white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${u.name}</div>
                    <div style="font-size:10px;color:var(--text-muted);font-family:var(--font-mono);">
                        #${u.badge || '—'}</div>
                </div>
                <div style="font-size:9px;color:${color};font-weight:700;text-transform:uppercase;
                            flex-shrink:0;">${u.job}</div>
            </div>`;
    }).join('');
}

function selectMapUnit(citizenid) {
    _selectedUnit = _mapUnits.find(u => u.citizenid === citizenid) || null;
    if (_selectedUnit && _selectedUnit.coords) {
        const cp = worldToCanvas(_selectedUnit.coords.x, _selectedUnit.coords.y);
        _zoom = Math.max(_zoom, 2.5);
        _panX = MAP_W / 2 - cp.x * _zoom;
        _panY = MAP_H / 2 - cp.y * _zoom;
    }
    drawMap();
    renderUnitList();
}

// Receive live pushes from blips.lua
window.addEventListener('message', e => {
    if (e.data && e.data.type === 'updateUnits') {
        _mapUnits = e.data.units || [];
        drawMap();
        renderUnitList();
        const sub = document.getElementById('map-unit-count');
        if (sub) sub.textContent = `${_mapUnits.length} unit${_mapUnits.length !== 1 ? 's' : ''} online · ${_mapCalls.length} active call${_mapCalls.length !== 1 ? 's' : ''}`;
    }
});

window.initMapPanel   = initMapPanel;
window.refreshMapData = refreshMapData;
window.mapResetView   = mapResetView;
window.mapZoom        = mapZoom;
window.selectMapUnit  = selectMapUnit;
