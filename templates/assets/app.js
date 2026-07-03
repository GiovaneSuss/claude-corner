const TYPES = {
  diary:       'Diary',
  writing:     'Writing',
  simulation:  'Simulations',
  interactive: 'Interactive',
  animation:   'Animations',
  cartography: 'Cartography',
  art:         'Art',
  code:        'Code',
  exploration: 'Explorations',
  other:       'Other',
};

const EXT_MODE = {
  html: 'iframe', htm: 'iframe',
  md: 'markdown', markdown: 'markdown',
  txt: 'raw', text: 'raw', ascii: 'raw', log: 'raw', asc: 'raw',
  js: 'animation', mjs: 'animation',
  svg: 'svg',
  json: 'json',
  py: 'code', sh: 'code', bash: 'code',
  ts: 'code', rs: 'code', go: 'code', rb: 'code',
  cpp: 'code', c: 'code', lua: 'code', r: 'code',
};

// Extension -> highlight.js language id (only where it differs from the ext itself)
const HLJS_LANG = {
  py: 'python', sh: 'bash', rs: 'rust', rb: 'ruby',
};

// Support files: present in the folder but never shown as tabs
const SUPPORT_EXTS = new Set(['css', 'map', 'lock']);

const EXT_COLOR = {
  js: '#f0b429', mjs: '#f0b429',
  html: '#e67e22', htm: '#e67e22',
  md: '#4a9edd', markdown: '#4a9edd',
  svg: '#a78bfa',
  json: '#34d399',
  py: '#4ade80', sh: '#4ade80', bash: '#4ade80',
  css: '#f472b6',
  ts: '#60a5fa',
};

// ── State ──────────────────────────────────────────

let entries     = [];
let activeEntry = null;
let folderFiles = [];
let splitMode   = false;
let panelAFile  = null;
let panelBFile  = null;

let filterPeriod = 'all';      // 'all' | 'today' | '7d' | '30d'
let filterType   = 'all';      // 'all' | a TYPES key
let groupMode    = 'category'; // 'category' | 'day'

const panels = {
  a: { frame: null, rendered: null },
  b: { frame: null, rendered: null },
};

let sandboxOn   = false;
let sandboxBusy = false;
const runInFlight = { a: false, b: false };
const RUNNABLE_EXTS = new Set(['py', 'sh', 'rb']);

// ── Init ───────────────────────────────────────────

function init() {
  panels.a.frame    = document.getElementById('frame-a');
  panels.a.rendered = document.getElementById('rendered-a');
  panels.b.frame    = document.getElementById('frame-b');
  panels.b.rendered = document.getElementById('rendered-b');

  document.getElementById('split-btn').addEventListener('click', enterSplit);
  document.getElementById('unsplit-btn').addEventListener('click', exitSplit);

  initInfoBar();
  initResize();
  initSandboxToggle();
  initFilters();
  loadManifest();
  setInterval(loadManifest, 30000);
}

// ── Sidebar filters ────────────────────────────────

function initFilters() {
  document.getElementById('filter-period').addEventListener('change', e => {
    filterPeriod = e.target.value;
    renderSidebar();
  });

  document.getElementById('filter-type').addEventListener('change', e => {
    filterType = e.target.value;
    renderSidebar();
  });

  document.getElementById('group-toggle').addEventListener('click', e => {
    const btn = e.target.closest('.group-toggle-btn');
    if (!btn) return;
    groupMode = btn.dataset.group;
    document.querySelectorAll('.group-toggle-btn').forEach(b => {
      const active = b === btn;
      b.classList.toggle('active', active);
      b.setAttribute('aria-selected', String(active));
    });
    renderSidebar();
  });
}

function populateTypeFilterOptions() {
  const select  = document.getElementById('filter-type');
  const present = new Set(entries.map(e =>
    TYPES[(e.type || '').toLowerCase()] ? (e.type || 'other').toLowerCase() : 'other'
  ));
  const opts = ['all', ...Object.keys(TYPES).filter(t => present.has(t))];

  select.innerHTML = opts
    .map(t => `<option value="${t}">${t === 'all' ? 'All types' : x(TYPES[t])}</option>`)
    .join('');

  filterType = opts.includes(filterType) ? filterType : 'all';
  select.value = filterType;
}

function matchesPeriod(dateStr, period) {
  if (period === 'all') return true;
  if (!dateStr) return false;
  const day      = new Date(dateStr + 'T00:00:00');
  const now      = new Date();
  const today    = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const diffDays = Math.round((today - day) / 86400000);
  if (period === 'today') return diffDays === 0;
  if (period === '7d')    return diffDays >= 0 && diffDays <= 6;
  if (period === '30d')   return diffDays >= 0 && diffDays <= 29;
  return true;
}

function dayLabel(dateStr) {
  if (!dateStr) return 'Unknown date';
  const day      = new Date(dateStr + 'T00:00:00');
  const now      = new Date();
  const today    = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const diffDays = Math.round((today - day) / 86400000);
  if (diffDays === 0) return 'Today';
  if (diffDays === 1) return 'Yesterday';
  return fmt(dateStr);
}

// ── Sandbox toggle ─────────────────────────────────

function initSandboxToggle() {
  document.getElementById('sandbox-switch').addEventListener('click', () => {
    if (sandboxBusy) return;
    sandboxOn ? stopSandbox() : startSandbox();
  });
  refreshSandboxStatus();
}

async function refreshSandboxStatus() {
  try {
    const r    = await fetch('/__sandbox/status');
    const data = await r.json();
    setSandboxUI(!!data.running);
  } catch {
    setSandboxUI(false);
  }
}

async function startSandbox() {
  sandboxBusy = true;
  setSandboxUI(false, true);
  try {
    const r    = await fetch('/__sandbox/start', { method: 'POST' });
    const data = await r.json();
    setSandboxUI(!!data.ok);
  } catch {
    setSandboxUI(false);
  }
  sandboxBusy = false;
  refreshRunButtons();
}

async function stopSandbox() {
  sandboxBusy = true;
  try {
    await fetch('/__sandbox/stop', { method: 'POST' });
  } catch { /* ignore — UI goes to off regardless */ }
  sandboxBusy = false;
  setSandboxUI(false);
  refreshRunButtons();
}

function setSandboxUI(on, loading = false) {
  sandboxOn = on;
  const dot      = document.getElementById('sandbox-dot');
  const label    = document.getElementById('sandbox-label-text');
  const switchEl = document.getElementById('sandbox-switch');

  dot.classList.toggle('loading', loading);
  dot.classList.toggle('on', on && !loading);
  switchEl.setAttribute('aria-checked', String(on));
  switchEl.disabled = loading;
  label.textContent = loading ? 'Sandbox starting…' : (on ? 'Sandbox on' : 'Sandbox off');
}

function refreshRunButtons() {
  document.querySelectorAll('.run-btn').forEach(btn => {
    const panelId = btn.dataset.panel;
    if (runInFlight[panelId]) return;
    btn.disabled = !sandboxOn;
    btn.title    = sandboxOn ? '' : 'Sandbox off — turn it on in the sidebar';
  });
}

// ── Manifest ───────────────────────────────────────

async function loadManifest() {
  flash();
  try {
    const r = await fetch('pages/manifest.json?_=' + Date.now());
    if (!r.ok) throw 0;
    const fresh = await r.json();
    const changed = JSON.stringify(fresh) !== JSON.stringify(entries);
    entries = fresh;
    if (changed) renderSidebar();
  } catch {
    document.getElementById('entry-count').textContent = 'No pages yet';
  }
}

// ── Sidebar ────────────────────────────────────────

function renderSidebar() {
  const list  = document.getElementById('sidebar-entries');
  const count = document.getElementById('entry-count');

  populateTypeFilterOptions();

  if (!entries.length) {
    count.textContent = 'No creations yet';
    list.innerHTML = '<div class="no-entries">Corner sessions will appear here as Claude creates things.</div>';
    return;
  }

  const filtered = entries.filter(e => {
    const type = TYPES[(e.type || '').toLowerCase()] ? (e.type || 'other').toLowerCase() : 'other';
    return matchesPeriod(e.date, filterPeriod) && (filterType === 'all' || type === filterType);
  });

  count.textContent = filtered.length === entries.length
    ? (entries.length === 1 ? '1 creation' : `${entries.length} creations`)
    : `${filtered.length} of ${entries.length}`;

  if (!filtered.length) {
    list.innerHTML = '<div class="no-entries">No creations match this filter.</div>';
    return;
  }

  const groups = {};
  const order  = [];

  if (groupMode === 'day') {
    // `filtered` is already newest-first (manifest.json is kept sorted that
    // way), so days come out in descending order without an extra sort.
    for (const e of filtered) {
      const k = e.date || 'unknown';
      if (!groups[k]) { groups[k] = []; order.push(k); }
      groups[k].push(e);
    }
    order.sort((a, b) => (a < b ? 1 : a > b ? -1 : 0));
  } else {
    [...filtered].reverse().forEach(e => {
      const k = TYPES[(e.type || '').toLowerCase()] ? (e.type || 'other').toLowerCase() : 'other';
      if (!groups[k]) { groups[k] = []; order.push(k); }
      groups[k].push(e);
    });
  }

  list.innerHTML = '';
  for (const groupKey of order) {
    const items = groups[groupKey];
    const label = groupMode === 'day' ? dayLabel(groupKey === 'unknown' ? null : groupKey) : (TYPES[groupKey] || 'Other');

    const section = document.createElement('div');
    section.className = 'category';
    section.innerHTML = `<div class="category-label">${x(label)}</div>`;

    for (const e of items) {
      const eKey = getKey(e);
      const ext  = getExt(e);
      const el   = document.createElement('div');
      el.className   = 'entry' + (activeEntry && getKey(activeEntry) === eKey ? ' active' : '');
      el.dataset.key = eKey;
      el.innerHTML   = `
        <div class="entry-title">${x(e.title)}</div>
        <div class="entry-meta">
          <span class="entry-date">${x(fmt(e.date))}</span>
          ${ext ? `<span class="entry-ext">.${x(ext)}</span>` : ''}
        </div>`;
      el.addEventListener('click', () => openEntry(e));
      section.appendChild(el);
    }
    list.appendChild(section);
  }
}

// ── Open entry ─────────────────────────────────────

async function openEntry(e) {
  activeEntry = e;

  document.querySelectorAll('.entry').forEach(el =>
    el.classList.toggle('active', el.dataset.key === getKey(e))
  );

  if (e.folder) {
    if (e.files && e.files.length) {
      folderFiles = e.files;
    } else {
      folderFiles = await fetchFolderFiles(e.folder);
      if (!folderFiles.length) folderFiles = e.entry ? [e.entry] : [];
    }
    folderFiles = folderFiles.filter(f => !SUPPORT_EXTS.has(f.split('.').pop().toLowerCase()));
  } else if (e.file) {
    folderFiles = [e.file.split('/').pop()];
  } else {
    folderFiles = [];
  }

  // Put the entry file first
  if (e.entry && folderFiles.includes(e.entry)) {
    folderFiles = [e.entry, ...folderFiles.filter(f => f !== e.entry)];
  }

  panelAFile = e.entry || folderFiles[0] || null;
  panelBFile = folderFiles.find(f => f !== panelAFile) || folderFiles[0] || null;

  if (!splitMode) {
    document.getElementById('tab-bar').style.display = folderFiles.length ? 'flex' : 'none';
  }
  document.getElementById('split-btn').style.display = folderFiles.length > 1 ? '' : 'none';

  buildTabs();
  updateInfoBar(e);

  document.getElementById('empty-state').style.display = 'none';

  if (panelAFile) await renderFile('a', panelAFile);
  if (splitMode && panelBFile) await renderFile('b', panelBFile);
}

// ── Fetch folder files ─────────────────────────────

async function fetchFolderFiles(folder) {
  try {
    const r = await fetch(`pages/${folder}/`);
    if (!r.ok) return [];
    const html = await r.text();
    const doc  = new DOMParser().parseFromString(html, 'text/html');
    return [...doc.querySelectorAll('a[href]')]
      .map(a => decodeURIComponent(a.getAttribute('href') || ''))
      .filter(h => h && h !== '../' && h !== './' && !h.endsWith('/') && !h.startsWith('?') && !h.startsWith('http'));
  } catch {
    return [];
  }
}

// ── Build tab bars ─────────────────────────────────

function buildTabs() {
  const targets = splitMode
    ? [{ id: 'tab-list-a', panel: 'a' }, { id: 'tab-list-b', panel: 'b' }]
    : [{ id: 'tab-list-single', panel: 'a' }];

  for (const { id, panel } of targets) {
    const container = document.getElementById(id);
    if (!container) continue;
    container.innerHTML = '';

    const activeFile = panel === 'a' ? panelAFile : panelBFile;

    for (const filename of folderFiles) {
      const ext   = filename.split('.').pop().toLowerCase();
      const color = EXT_COLOR[ext] || '#4E4A46';

      const tab = document.createElement('div');
      tab.className = 'tab' + (filename === activeFile ? ' active' : '');
      tab.innerHTML = `<span class="tab-dot" style="background:${color}"></span>${x(filename)}`;
      tab.addEventListener('click', () => selectFile(panel, filename));
      container.appendChild(tab);
    }
  }
}

async function selectFile(panelId, filename) {
  if (panelId === 'a') panelAFile = filename;
  else panelBFile = filename;
  buildTabs();
  await renderFile(panelId, filename);
}

// ── Render file into panel ─────────────────────────

async function renderFile(panelId, filename) {
  const e = activeEntry;
  if (!e || !filename) return;

  const url  = e.folder ? `pages/${e.folder}/${filename}` : `pages/${e.file}`;
  const ext  = filename.split('.').pop().toLowerCase();
  const mode = EXT_MODE[ext] || 'raw';

  const { frame, rendered } = panels[panelId];

  frame.style.display    = 'none';
  rendered.style.display = 'none';
  frame.removeAttribute('srcdoc');
  frame.removeAttribute('src');

  try {
    if (mode === 'iframe') {
      frame.src = url;
      frame.style.display = 'block';

    } else if (mode === 'markdown') {
      await ensureMarked();
      const text = await fetch(url + '?_=' + Date.now()).then(r => r.text());
      rendered.innerHTML     = `<div class="md-body">${marked.parse(text)}</div>`;
      rendered.style.display = 'block';

    } else if (mode === 'animation') {
      const code = await fetch(url + '?_=' + Date.now()).then(r => r.text());
      frame.srcdoc        = wrapAnimation(code);
      frame.style.display = 'block';

    } else if (mode === 'svg') {
      const svg = await fetch(url + '?_=' + Date.now()).then(r => r.text());
      rendered.innerHTML     = `<div class="svg-body">${svg}</div>`;
      rendered.style.display = 'block';

    } else if (mode === 'json') {
      const raw = await fetch(url + '?_=' + Date.now()).then(r => r.text());
      try {
        rendered.innerHTML = `<pre class="json-body">${x(JSON.stringify(JSON.parse(raw), null, 2))}</pre>`;
      } catch {
        rendered.innerHTML = `<pre class="raw-body">${x(raw)}</pre>`;
      }
      rendered.style.display = 'block';

    } else if (mode === 'code') {
      const text = await fetch(url + '?_=' + Date.now()).then(r => r.text());
      let html;
      try {
        await ensureHighlight();
        const lang = HLJS_LANG[ext] || ext;
        html = hljs.getLanguage(lang)
          ? hljs.highlight(text, { language: lang }).value
          : hljs.highlightAuto(text).value;
      } catch {
        html = x(text);
      }

      if (RUNNABLE_EXTS.has(ext)) {
        rendered.innerHTML = `
          <div class="run-bar">
            <button class="run-btn" id="run-btn-${panelId}" data-panel="${panelId}">Run</button>
            <span class="run-status" id="run-status-${panelId}"></span>
          </div>
          <pre class="code-body hljs"><code>${html}</code></pre>
          <div class="run-output" id="run-output-${panelId}" style="display:none"></div>`;
        wireRunButton(panelId, url);
      } else {
        rendered.innerHTML = `<pre class="code-body hljs"><code>${html}</code></pre>`;
      }
      rendered.style.display = 'block';

    } else {
      const text = await fetch(url + '?_=' + Date.now()).then(r => r.text());
      rendered.innerHTML     = `<pre class="raw-body">${x(text)}</pre>`;
      rendered.style.display = 'block';
    }
  } catch {
    rendered.innerHTML     = `<pre class="raw-body">Could not load: ${x(url)}</pre>`;
    rendered.style.display = 'block';
  }
}

// ── Split ──────────────────────────────────────────

function enterSplit() {
  if (!activeEntry || folderFiles.length < 2) return;
  splitMode = true;

  document.getElementById('tab-bar').style.display        = 'none';
  document.getElementById('panel-a-tabrow').style.display = 'flex';
  document.getElementById('panel-b').style.display        = 'flex';
  document.getElementById('panel-b-tabrow').style.display = 'flex';
  document.getElementById('resize-handle').style.display  = 'block';

  buildTabs();
  if (panelBFile) renderFile('b', panelBFile);
}

function exitSplit() {
  splitMode = false;

  document.getElementById('tab-bar').style.display        = folderFiles.length ? 'flex' : 'none';
  document.getElementById('panel-a-tabrow').style.display = 'none';
  document.getElementById('panel-b').style.display        = 'none';
  document.getElementById('panel-b-tabrow').style.display = 'none';
  document.getElementById('resize-handle').style.display  = 'none';

  document.getElementById('panel-a').style.flex = '';
  document.getElementById('panel-b').style.flex = '';

  buildTabs();
}

// ── Info bar ───────────────────────────────────────

function updateInfoBar(e) {
  const bar = document.getElementById('info-bar');
  if (!e) { bar.style.display = 'none'; return; }

  const typeName  = TYPES[(e.type || '').toLowerCase()] || (e.type || 'Other');
  const dateStr   = fmt(e.date);
  const fileCount = folderFiles.length;

  document.getElementById('info-type-badge').textContent    = typeName;
  document.getElementById('info-summary-date').textContent  = dateStr;
  document.getElementById('info-summary-files').textContent = fileCount > 1 ? `${fileCount} files` : '';

  document.getElementById('info-title-full').textContent  = e.title || '';
  document.getElementById('info-meta-type').textContent   = typeName;
  document.getElementById('info-meta-date').textContent   = dateStr;
  document.getElementById('info-meta-files').textContent  =
    fileCount === 1 ? `${fileCount} file` : `${fileCount} files`;

  bar.style.display       = 'flex';
  bar.style.flexDirection = 'column';
}

function initInfoBar() {
  document.getElementById('info-summary').addEventListener('click', () => {
    document.getElementById('info-bar').classList.toggle('expanded');
  });
}

// ── Resize drag ────────────────────────────────────

function initResize() {
  const handle  = document.getElementById('resize-handle');
  const panelA  = document.getElementById('panel-a');
  const panelB  = document.getElementById('panel-b');
  const viewers = document.getElementById('viewers');
  let dragging  = false;

  handle.addEventListener('mousedown', e => {
    dragging = true;
    handle.classList.add('dragging');
    document.body.style.cursor     = 'col-resize';
    document.body.style.userSelect = 'none';
    e.preventDefault();
  });

  document.addEventListener('mousemove', e => {
    if (!dragging) return;
    const rect    = viewers.getBoundingClientRect();
    const handleW = handle.offsetWidth;
    const total   = rect.width - handleW;
    const pct     = Math.min(Math.max((e.clientX - rect.left) / total * 100, 15), 85);
    panelA.style.flex = `0 0 ${pct}%`;
    panelB.style.flex = `0 0 ${100 - pct}%`;
  });

  document.addEventListener('mouseup', () => {
    if (!dragging) return;
    dragging = false;
    handle.classList.remove('dragging');
    document.body.style.cursor     = '';
    document.body.style.userSelect = '';
  });
}

// ── Run button (Python sandbox) ────────────────────

function wireRunButton(panelId, url) {
  runInFlight[panelId] = false;

  const btn     = document.getElementById(`run-btn-${panelId}`);
  const status  = document.getElementById(`run-status-${panelId}`);
  const output  = document.getElementById(`run-output-${panelId}`);
  const relPath = url.replace(/^pages\//, '');

  btn.disabled = !sandboxOn;
  btn.title    = sandboxOn ? '' : 'Sandbox off — turn it on in the sidebar';

  btn.addEventListener('click', async () => {
    if (runInFlight[panelId] || !sandboxOn) return;
    runInFlight[panelId]  = true;
    btn.disabled          = true;
    btn.textContent       = 'Running…';
    status.textContent    = '';
    output.style.display  = 'block';
    output.innerHTML      = '<div class="run-pending">Running…</div>';

    try {
      const r = await fetch('/__run', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ path: relPath }),
      });
      const data = await r.json();

      if (!data.ok) {
        if (data.error === 'sandbox_off') setSandboxUI(false);
        output.innerHTML = `<div class="run-error">Error: ${x(data.error || 'unknown')}</div>`;
      } else {
        let html = '';
        if (data.timed_out) html += `<div class="run-timeout">Timed out after 15s</div>`;
        if (data.stdout)    html += `<pre class="run-stdout">${x(data.stdout)}</pre>`;
        if (data.stderr)    html += `<pre class="run-stderr">${x(data.stderr)}</pre>`;
        html += `<div class="run-meta">exit code: ${data.exit_code ?? '—'}</div>`;
        if (data.truncated) html += `<div class="run-truncated">Output truncated</div>`;
        output.innerHTML = html;
      }
    } catch {
      output.innerHTML = `<div class="run-error">Could not reach server</div>`;
    } finally {
      runInFlight[panelId] = false;
      btn.disabled          = !sandboxOn;
      btn.textContent       = 'Run';
    }
  });
}

// ── Helpers ────────────────────────────────────────

function wrapAnimation(code) {
  const escaped = code.replace(/<\/script>/gi, '<\\/script>');
  return `<!DOCTYPE html><html><head>
<meta charset="UTF-8">
<style>*{margin:0;padding:0;box-sizing:border-box}body{background:#191714;overflow:hidden}canvas{display:block}
#_err{display:none;position:fixed;inset:0;margin:0;padding:16px;font:12px/1.6 'SF Mono','Cascadia Code',monospace;color:#ff8a80;background:#1a0f0f;white-space:pre-wrap;overflow:auto}</style>
</head><body>
<canvas id="canvas"></canvas>
<pre id="_err"></pre>
<script>
const canvas=document.getElementById('canvas');
const ctx=canvas.getContext('2d');
function _resize(){canvas.width=window.innerWidth;canvas.height=window.innerHeight;}
_resize();
const _resizeCallbacks=[];
function resize(fn){ if (typeof fn==='function') _resizeCallbacks.push(fn); }
window.addEventListener('resize',()=>{
  _resize();
  for (const fn of _resizeCallbacks) { try { fn(); } catch(e) {} }
});
try {
${escaped}
} catch(e) {
  const el=document.getElementById('_err');
  el.textContent='Script error: '+e.message;
  el.style.display='block';
}
<\/script>
</body></html>`;
}

function getKey(e) { return e.folder || e.file || ''; }

function getExt(e) {
  const name = (e.entry || (e.file ? e.file.split('/').pop() : '')) || '';
  const parts = name.split('.');
  return parts.length > 1 ? parts.pop().toLowerCase() : '';
}

function flash() {
  const p = document.getElementById('pulse');
  p.classList.add('on');
  setTimeout(() => p.classList.remove('on'), 500);
}

function fmt(s) {
  if (!s) return '';
  try {
    return new Date(s + 'T12:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  } catch { return s; }
}

function x(s) {
  return String(s ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

async function ensureMarked() {
  if (typeof marked !== 'undefined') return;
  return new Promise((resolve, reject) => {
    const s   = document.createElement('script');
    s.src     = 'https://cdn.jsdelivr.net/npm/marked/marked.min.js';
    s.onload  = resolve;
    s.onerror = () => reject(new Error('Could not load marked.js'));
    document.head.appendChild(s);
  });
}

async function ensureHighlight() {
  if (typeof hljs !== 'undefined') return;
  return new Promise((resolve, reject) => {
    const s   = document.createElement('script');
    s.src     = 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js';
    s.onload  = resolve;
    s.onerror = () => reject(new Error('Could not load highlight.js'));
    document.head.appendChild(s);
  });
}

init();
