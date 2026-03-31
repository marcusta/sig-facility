#!/usr/bin/env bun
/**
 * Course Exclusion Picker - run with: bun scripts/course-sync/course-picker.ts
 * Fetches the manifest server-side (no CORS), serves picker UI on localhost.
 */

import { resolve, dirname } from "path";
import { readFileSync, writeFileSync, existsSync } from "fs";

const MANIFEST_URL = "https://simulatorgolftour.com/course_manifest.json";
const PORT = 3456;

const scriptDir = dirname(new URL(import.meta.url).pathname);
const repoRoot = resolve(scriptDir, "../..");
const excludedPath = resolve(repoRoot, "config/excluded-courses.json");

function loadExcluded(): string[] {
  if (!existsSync(excludedPath)) return [];
  try {
    return JSON.parse(readFileSync(excludedPath, "utf-8"));
  } catch {
    return [];
  }
}

function saveExcluded(list: string[]) {
  writeFileSync(excludedPath, JSON.stringify(list, null, 2) + "\n", "utf-8");
}

const server = Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/api/manifest") {
      const res = await fetch(MANIFEST_URL);
      const data = await res.json();
      return Response.json(data);
    }

    if (url.pathname === "/api/excluded") {
      if (req.method === "GET") {
        return Response.json(loadExcluded());
      }
      if (req.method === "PUT") {
        const body = await req.json();
        if (!Array.isArray(body)) return new Response("Expected array", { status: 400 });
        saveExcluded(body);
        return Response.json({ saved: body.length });
      }
    }

    if (url.pathname === "/" || url.pathname === "/index.html") {
      return new Response(HTML, { headers: { "Content-Type": "text/html; charset=utf-8" } });
    }

    return new Response("Not found", { status: 404 });
  },
});

console.log(`Course picker running at http://localhost:${PORT}`);

// Auto-open in default browser
Bun.spawn(
  process.platform === "darwin"
    ? ["open", `http://localhost:${PORT}`]
    : ["xdg-open", `http://localhost:${PORT}`]
);

const HTML = /*html*/ `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Course Exclusion Picker</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --bg: #020617;
    --bg-secondary: #0f172a;
    --primary: #eab308;
    --primary-dim: #a37f06;
    --text: #e2e8f0;
    --text-muted: #64748b;
    --border: #1e293b;
    --row-hover: #1e293b;
    --excluded-bg: rgba(239, 68, 68, 0.08);
    --excluded-border: rgba(239, 68, 68, 0.2);
    --danger: #ef4444;
  }

  body {
    font-family: 'Inter', system-ui, -apple-system, sans-serif;
    background: var(--bg);
    color: var(--text);
    line-height: 1.5;
    min-height: 100vh;
  }

  .container {
    max-width: 1400px;
    margin: 0 auto;
    padding: 24px 32px;
  }

  header { margin-bottom: 24px; }
  header h1 { font-size: 1.5rem; font-weight: 700; color: var(--primary); margin-bottom: 4px; }
  header p { font-size: 0.875rem; color: var(--text-muted); }

  .toolbar {
    display: flex;
    flex-wrap: wrap;
    gap: 12px;
    align-items: center;
    margin-bottom: 16px;
  }

  .search-box {
    flex: 1;
    min-width: 260px;
    padding: 10px 14px;
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: 8px;
    color: var(--text);
    font-size: 0.875rem;
    font-family: inherit;
    outline: none;
    transition: border-color 0.15s;
  }
  .search-box:focus { border-color: var(--primary); }
  .search-box::placeholder { color: var(--text-muted); }

  .btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 9px 16px;
    border: 1px solid var(--border);
    border-radius: 8px;
    background: var(--bg-secondary);
    color: var(--text);
    font-family: inherit;
    font-size: 0.8125rem;
    font-weight: 500;
    cursor: pointer;
    transition: background 0.15s, border-color 0.15s;
    white-space: nowrap;
  }
  .btn:hover { background: var(--row-hover); border-color: var(--text-muted); }
  .btn-primary { background: var(--primary); color: #000; border-color: var(--primary); }
  .btn-primary:hover { background: var(--primary-dim); border-color: var(--primary-dim); }
  .btn-danger { border-color: var(--excluded-border); color: var(--danger); }
  .btn-danger:hover { background: var(--excluded-bg); }

  .stats-bar {
    display: flex;
    flex-wrap: wrap;
    gap: 16px;
    align-items: center;
    margin-bottom: 16px;
    font-size: 0.8125rem;
    color: var(--text-muted);
  }
  .stats-bar .count { color: var(--primary); font-weight: 600; }
  .stats-bar .saved-indicator { color: #22c55e; font-weight: 500; opacity: 0; transition: opacity 0.3s; }
  .stats-bar .saved-indicator.visible { opacity: 1; }

  .table-wrap { border: 1px solid var(--border); border-radius: 10px; overflow: hidden; }
  .table-scroll { overflow-x: auto; max-height: calc(100vh - 220px); overflow-y: auto; }

  table { width: 100%; border-collapse: collapse; font-size: 0.8125rem; }

  thead th {
    position: sticky;
    top: 0;
    z-index: 10;
    background: var(--bg-secondary);
    padding: 10px 14px;
    text-align: left;
    font-weight: 600;
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--text-muted);
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    user-select: none;
    white-space: nowrap;
    transition: color 0.15s;
  }
  thead th:hover { color: var(--text); }
  thead th.sorted { color: var(--primary); }
  thead th .sort-arrow { display: inline-block; margin-left: 4px; opacity: 0.4; font-size: 0.65rem; }
  thead th.sorted .sort-arrow { opacity: 1; }
  thead th:first-child { width: 48px; text-align: center; cursor: default; }

  tbody tr {
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    transition: background 0.1s;
  }
  tbody tr:last-child { border-bottom: none; }
  tbody tr:hover { background: var(--row-hover); }
  tbody tr.excluded { background: var(--excluded-bg); }
  tbody tr.excluded:hover { background: rgba(239, 68, 68, 0.14); }
  tbody tr.excluded td { color: var(--text-muted); }
  tbody tr.excluded td.name-cell { text-decoration: line-through; text-decoration-color: var(--danger); }

  td { padding: 9px 14px; vertical-align: middle; }
  td:first-child { text-align: center; }

  .folder-cell {
    font-size: 0.75rem;
    color: var(--text-muted);
    font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
    max-width: 220px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  input[type="checkbox"] { width: 16px; height: 16px; accent-color: var(--danger); cursor: pointer; }

  .loading {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 80px 20px;
    gap: 16px;
  }

  .spinner {
    width: 36px;
    height: 36px;
    border: 3px solid var(--border);
    border-top-color: var(--primary);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  .loading-text { color: var(--text-muted); font-size: 0.875rem; }
  .error-msg { padding: 24px; text-align: center; color: var(--danger); }
</style>
</head>
<body>

<div class="container">
  <header>
    <h1>Course Exclusion Picker</h1>
    <p>Select courses to exclude from sync. Changes save directly to config/excluded-courses.json.</p>
  </header>

  <div class="toolbar">
    <input type="text" class="search-box" id="searchBox" placeholder="Filter by name, designer, country, or folder...">
    <button class="btn" id="btnSelectFiltered">Exclude All Filtered</button>
    <button class="btn" id="btnDeselectFiltered">Include All Filtered</button>
    <button class="btn-primary btn" id="btnSave">Save to File</button>
  </div>

  <div class="stats-bar" id="statsBar">
    <span id="statExcluded"></span>
    <span id="statFiltered"></span>
    <span class="saved-indicator" id="savedIndicator">Saved!</span>
  </div>

  <div class="table-wrap">
    <div class="table-scroll">
      <div class="loading" id="loadingIndicator">
        <div class="spinner"></div>
        <div class="loading-text">Loading course manifest...</div>
      </div>
      <table id="courseTable" style="display:none">
        <thead>
          <tr>
            <th>&nbsp;</th>
            <th data-col="Name">Name <span class="sort-arrow">&#9650;</span></th>
            <th data-col="CourseDesigner">Designer <span class="sort-arrow">&#9650;</span></th>
            <th data-col="LastUpdated">Last Updated <span class="sort-arrow">&#9650;</span></th>
            <th data-col="Country">Country <span class="sort-arrow">&#9650;</span></th>
            <th data-col="Difficulty">Difficulty <span class="sort-arrow">&#9650;</span></th>
            <th data-col="Par">Par <span class="sort-arrow">&#9650;</span></th>
            <th data-col="CourseFolder">Course Folder <span class="sort-arrow">&#9650;</span></th>
          </tr>
        </thead>
        <tbody id="courseBody"></tbody>
      </table>
    </div>
  </div>
</div>

<div class="toast" id="toast"></div>

<script>
(function() {
  let allCourses = [];
  let excludedSet = new Set();
  let filteredIndices = [];
  let sortCol = 'Name';
  let sortAsc = true;
  let filterText = '';
  let dirty = false;

  const $ = id => document.getElementById(id);

  // ---- Toast ----
  let toastTimer;
  function showToast(msg) {
    const el = $('toast');
    el.textContent = msg;
    el.classList.add('visible');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('visible'), 2500);
  }

  // ---- Load data from server ----
  async function loadData() {
    try {
      const [manifestRes, excludedRes] = await Promise.all([
        fetch('/api/manifest'),
        fetch('/api/excluded')
      ]);
      if (!manifestRes.ok) throw new Error('Manifest: HTTP ' + manifestRes.status);
      allCourses = await manifestRes.json();
      const excluded = await excludedRes.json();
      excludedSet = new Set(excluded);

      $('loadingIndicator').style.display = 'none';
      $('courseTable').style.display = '';
      applySort();
      render();
    } catch (e) {
      $('loadingIndicator').innerHTML = '<div class="error-msg">Failed to load: ' + e.message + '</div>';
    }
  }

  // ---- Save to server ----
  async function saveExcluded() {
    const arr = Array.from(excludedSet).sort();
    try {
      const res = await fetch('/api/excluded', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(arr)
      });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const result = await res.json();
      dirty = false;
      const indicator = $('savedIndicator');
      indicator.classList.add('visible');
      setTimeout(() => indicator.classList.remove('visible'), 2000);
      showToast('Saved ' + result.saved + ' exclusions to config/excluded-courses.json');
    } catch (e) {
      showToast('Save failed: ' + e.message);
    }
  }

  // ---- Sorting ----
  function compareCourses(a, b) {
    let va = a[sortCol] ?? '';
    let vb = b[sortCol] ?? '';
    if (sortCol === 'Par' || sortCol === 'Difficulty') {
      va = parseFloat(va) || 0;
      vb = parseFloat(vb) || 0;
    } else if (sortCol === 'LastUpdated') {
      va = va ? new Date(va).getTime() : 0;
      vb = vb ? new Date(vb).getTime() : 0;
    } else {
      va = String(va).toLowerCase();
      vb = String(vb).toLowerCase();
    }
    if (va < vb) return sortAsc ? -1 : 1;
    if (va > vb) return sortAsc ? 1 : -1;
    return 0;
  }

  function applySort() {
    const indices = allCourses.map((_, i) => i);
    indices.sort((a, b) => compareCourses(allCourses[a], allCourses[b]));
    allCourses = indices.map(i => allCourses[i]);
  }

  // ---- Filtering ----
  function matchesFilter(c) {
    if (!filterText) return true;
    const hay = [c.Name, c.CourseDesigner, c.Country, c.CourseFolder]
      .map(v => (v || '').toLowerCase()).join('\\x00');
    return hay.includes(filterText);
  }

  // ---- Render ----
  function render() {
    const tbody = $('courseBody');
    const rows = [];
    filteredIndices = [];

    for (let i = 0; i < allCourses.length; i++) {
      const c = allCourses[i];
      if (!matchesFilter(c)) continue;
      filteredIndices.push(i);
      const ex = excludedSet.has(c.CourseFolder);
      const updated = c.LastUpdated ? new Date(c.LastUpdated).toLocaleDateString('en-CA') : '';
      rows.push(
        '<tr class="' + (ex ? 'excluded' : '') + '" data-idx="' + i + '">' +
        '<td><input type="checkbox" ' + (ex ? 'checked' : '') + ' tabindex="-1"></td>' +
        '<td class="name-cell">' + esc(c.Name) + '</td>' +
        '<td>' + esc(c.CourseDesigner) + '</td>' +
        '<td>' + esc(updated) + '</td>' +
        '<td>' + esc(c.Country) + '</td>' +
        '<td>' + esc(c.Difficulty) + '</td>' +
        '<td>' + esc(c.Par) + '</td>' +
        '<td class="folder-cell" title="' + esc(c.CourseFolder) + '">' + esc(c.CourseFolder) + '</td>' +
        '</tr>'
      );
    }

    tbody.innerHTML = rows.join('');
    updateStats();
    updateSortHeaders();
  }

  function esc(s) {
    if (s == null) return '';
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function updateStats() {
    const total = allCourses.length;
    $('statExcluded').innerHTML = '<span class="count">' + excludedSet.size + '</span> of ' + total + ' courses excluded' + (dirty ? ' (unsaved)' : '');
    if (filterText) {
      $('statFiltered').innerHTML = '<span class="count">' + filteredIndices.length + '</span> shown (filtered)';
    } else {
      $('statFiltered').textContent = '';
    }
  }

  function updateSortHeaders() {
    document.querySelectorAll('#courseTable thead th[data-col]').forEach(th => {
      const col = th.dataset.col;
      const arrow = th.querySelector('.sort-arrow');
      if (col === sortCol) {
        th.classList.add('sorted');
        arrow.textContent = sortAsc ? '\\u25B2' : '\\u25BC';
      } else {
        th.classList.remove('sorted');
        arrow.textContent = '\\u25B2';
      }
    });
  }

  // ---- Events ----

  $('courseBody').addEventListener('click', function(e) {
    const tr = e.target.closest('tr');
    if (!tr) return;
    const idx = parseInt(tr.dataset.idx);
    const c = allCourses[idx];
    if (!c) return;
    if (excludedSet.has(c.CourseFolder)) {
      excludedSet.delete(c.CourseFolder);
    } else {
      excludedSet.add(c.CourseFolder);
    }
    dirty = true;
    const ex = excludedSet.has(c.CourseFolder);
    tr.classList.toggle('excluded', ex);
    tr.querySelector('input[type="checkbox"]').checked = ex;
    updateStats();
  });

  document.querySelectorAll('#courseTable thead th[data-col]').forEach(th => {
    th.addEventListener('click', function() {
      const col = this.dataset.col;
      if (sortCol === col) {
        sortAsc = !sortAsc;
      } else {
        sortCol = col;
        sortAsc = true;
      }
      applySort();
      render();
    });
  });

  $('searchBox').addEventListener('input', function() {
    filterText = this.value.trim().toLowerCase();
    render();
  });

  $('btnSelectFiltered').addEventListener('click', function() {
    for (const i of filteredIndices) { excludedSet.add(allCourses[i].CourseFolder); }
    dirty = true;
    render();
  });

  $('btnDeselectFiltered').addEventListener('click', function() {
    for (const i of filteredIndices) { excludedSet.delete(allCourses[i].CourseFolder); }
    dirty = true;
    render();
  });

  $('btnSave').addEventListener('click', saveExcluded);

  // Ctrl+S / Cmd+S to save
  document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 's') {
      e.preventDefault();
      saveExcluded();
    }
  });

  loadData();
})();
</script>
</body>
</html>`;
