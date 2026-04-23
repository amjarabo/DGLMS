/* ================================================================
   DGLMS Portal — shared portal.js
   Loaded by every HTML file. Handles:
     - Supabase client (singleton)
     - Auth guard (redirects to login.html if not signed in)
     - @dot.gov enforcement
     - Sidebar rendering
     - Theme toggle
     - Session persists across pages via default localStorage
     - Sign-out wipes session + redirects
   ================================================================ */

// ---- Supabase config ----
const SUPABASE_URL  = 'https://rnkfqtqnldiogmpfsbym.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJua2ZxdHFubGRpb2dtcGZzYnltIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY2NzczNzMsImV4cCI6MjA5MjI1MzM3M30.zqJlobaFzg9g-XDgeWJsxeZfaplbWF3lR8KC1yoKiN8';
const ALLOWED_DOMAIN = '@dot.gov';

// ---- Create Supabase client (window.supabase is the UMD global from the <script> tag) ----
if (!window.supabase || !window.supabase.createClient) {
  console.error('[portal.js] Supabase UMD library not loaded. Make sure supabase-js CDN <script> comes before portal.js.');
}
window.sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON, {
  auth: {
    persistSession: true,           // keep session across pages in same tab
    autoRefreshToken: true,
    detectSessionInUrl: true,       // handle email confirmation / password recovery URLs
    storage: window.localStorage,   // survives page navigation
  }
});

// ---- Current page detection (used for nav highlighting & login_audit) ----
function currentPage() {
  const p = location.pathname.split('/').pop() || 'index.html';
  return p.replace('.html', '') || 'index';
}

// ---- Auth guard: any page except login.html requires a session ----
async function requireAuth() {
  if (currentPage() === 'login') return null; // login page exempt
  const { data: { session } } = await window.sb.auth.getSession();
  if (!session) {
    const next = encodeURIComponent(location.pathname.split('/').pop() || 'index.html');
    location.replace(`login.html?next=${next}`);
    return null;
  }
  const email = (session.user.email || '').toLowerCase();
  if (!email.endsWith(ALLOWED_DOMAIN)) {
    // Wrong domain — force signout
    await window.sb.auth.signOut();
    location.replace('login.html?error=domain');
    return null;
  }
  return session;
}

// ---- Log this page view to login_audit (fires once per page load) ----
async function logPageView(session) {
  if (!session) return;
  try {
    await window.sb.from('login_audit').insert({
      user_id: session.user.id,
      email: session.user.email,
      page: currentPage(),
      user_agent: navigator.userAgent.slice(0, 500),
    });
  } catch (e) {
    console.warn('[portal.js] login_audit insert skipped:', e.message);
  }
}

// ---- Sidebar markup ----
const NAV_ITEMS = [
  { group: 'OVERVIEW', items: [
    { href: 'index.html',        icon: '◈', label: 'Dashboard' },
  ]},
  { group: 'QA WORKSTREAMS', items: [
    { href: 'smoke.html',        icon: '✓', label: 'Smoke' },
    { href: 'regression.html',   icon: '↻', label: 'Regression' },
    { href: 'testcases.html',    icon: '▤', label: 'Test Cases' },
    { href: 'checklist.html',    icon: '☐', label: 'Checklist' },
    { href: 'dashboard.html',    icon: '▦', label: 'Sprint Dashboard' },
  ]},
  { group: 'PROJECT DOCS', items: [
    { href: 'compliance.html',   icon: '§',  label: 'Compliance' },
    { href: 'scope.html',        icon: '◇',  label: 'Scope of Work' },
    { href: 'environment.html',  icon: '▣',  label: 'Environment' },
    { href: 'section508.html',   icon: '♿', label: 'Section 508' },
    { href: 'requirements.html', icon: '◉',  label: 'Requirements' },
  ]},
];

function renderSidebar(activeHref, userEmail) {
  const initials = (userEmail || '?').split('@')[0].slice(0, 2).toUpperCase();
  const groupsHtml = NAV_ITEMS.map(g => `
    <div class="sl">${g.group}</div>
    ${g.items.map(i => `
      <a href="${i.href}" class="nav-item ${i.href === activeHref ? 'active' : ''}">
        <span class="ico">${i.icon}</span>
        <span>${i.label}</span>
      </a>
    `).join('')}
  `).join('');

  return `
    <div class="sidebar-header">
      <a href="index.html" class="brand">
        <div class="brand-icon">DOT</div>
        <div>
          <div class="brand-name">DGLMS Portal</div>
          <div class="brand-sub">QA / SPRINT OPS</div>
        </div>
      </a>
    </div>
    <nav>${groupsHtml}</nav>
    <div class="sidebar-footer">
      <div class="user-info">
        <div class="av">${initials}</div>
        <div>
          <div class="un">${userEmail || 'signed out'}</div>
          <div class="ur2">@dot.gov</div>
        </div>
      </div>
      <button class="signout-btn" onclick="portalSignOut()">SIGN OUT</button>
    </div>
  `;
}

async function portalSignOut() {
  await window.sb.auth.signOut();
  location.replace('login.html');
}

// ---- Theme toggle ----
function initTheme() {
  const saved = localStorage.getItem('dglms-theme') || 'dark';
  if (saved === 'light') document.body.classList.add('light');
  const btn = document.getElementById('themeToggle');
  if (btn) {
    btn.addEventListener('click', () => {
      document.body.classList.toggle('light');
      const mode = document.body.classList.contains('light') ? 'light' : 'dark';
      localStorage.setItem('dglms-theme', mode);
    });
  }
}

// ---- Topbar markup ----
function renderTopbar(title, subtitle) {
  return `
    <div class="tb-title">${title}</div>
    <div class="tb-sub">// ${subtitle || currentPage()}</div>
    <div class="tb-right">
      <span class="live-pill"><span class="dot"></span>LIVE</span>
      <button id="themeToggle" aria-label="Toggle theme">
        <span class="toggle-track"><span class="toggle-thumb"></span></span>
        <span id="themeLabel">DARK</span>
      </button>
    </div>
  `;
}

// ---- Main initializer — call from each page ----
// Usage:
//   await Portal.init({ title: 'Smoke Tests', subtitle: 'Sprint 6' });
//   // then render your page-specific content
window.Portal = {
  async init({ title, subtitle } = {}) {
    // Apply theme BEFORE auth check so login redirect isn't a flash of dark
    initTheme();

    // Auth guard
    const session = await requireAuth();
    if (!session && currentPage() !== 'login') return null; // redirect already happened
    if (currentPage() === 'login') return null;

    // Render sidebar + topbar into placeholders
    const sb = document.getElementById('sidebar');
    if (sb) sb.innerHTML = renderSidebar(location.pathname.split('/').pop() || 'index.html', session.user.email);
    const tb = document.querySelector('.topbar');
    if (tb) tb.innerHTML = renderTopbar(title || 'DGLMS Portal', subtitle);

    // Re-bind theme toggle after topbar render
    const btn = document.getElementById('themeToggle');
    if (btn) {
      btn.addEventListener('click', () => {
        document.body.classList.toggle('light');
        const mode = document.body.classList.contains('light') ? 'light' : 'dark';
        localStorage.setItem('dglms-theme', mode);
        const lbl = document.getElementById('themeLabel');
        if (lbl) lbl.textContent = mode.toUpperCase();
      });
      const lbl = document.getElementById('themeLabel');
      if (lbl) lbl.textContent = document.body.classList.contains('light') ? 'LIGHT' : 'DARK';
    }

    // Audit log (fire and forget)
    logPageView(session);

    return session;
  },

  // ---- Helpers exposed to page code ----
  get client() { return window.sb; },

  async currentUser() {
    const { data: { session } } = await window.sb.auth.getSession();
    return session?.user || null;
  },
};

// Expose signout globally for the sidebar button
window.portalSignOut = portalSignOut;
