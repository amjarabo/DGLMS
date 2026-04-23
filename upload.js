/* ================================================================
   DGLMS Portal — upload.js
   Shared Excel/CSV drop-zone with live Supabase push.
   Depends on: portal.js (for window.sb), SheetJS (window.XLSX)

   Usage in a page:
     <div id="myUpload"></div>
     <script>
       Upload.mount('#myUpload', {
         section: 'testcases',            // which table bucket
         onParsed: (rows, filename) => {  // optional preview hook
           renderMyTable(rows);
         }
       });
     </script>
   ================================================================ */

window.Upload = {
  mount(selector, opts = {}) {
    const root = document.querySelector(selector);
    if (!root) { console.error('[upload.js] mount target not found:', selector); return; }
    const section = opts.section || 'general';
    const onParsed = typeof opts.onParsed === 'function' ? opts.onParsed : () => {};

    root.innerHTML = `
      <div class="card">
        <div class="ch">
          <div class="ct">Upload workbook</div>
          <span class="mono">${section}</span>
        </div>
        <label class="dropzone" id="dz-${section}">
          <input type="file" accept=".xlsx,.xls,.xlsm,.csv" id="fi-${section}" />
          <div class="dropzone-icon">⬆</div>
          <div class="dropzone-text">Drop an Excel or CSV file here</div>
          <div class="dropzone-sub">or click to browse — .xlsx, .xls, .xlsm, .csv</div>
        </label>
        <div id="preview-${section}" style="margin-top:14px"></div>
      </div>
    `;

    const dz = root.querySelector(`#dz-${section}`);
    const fi = root.querySelector(`#fi-${section}`);
    const preview = root.querySelector(`#preview-${section}`);

    let parsedRows = [];
    let currentFilename = '';

    function showAlert(type, msg) {
      preview.insertAdjacentHTML('afterbegin', `<div class="al ${type}">${msg}</div>`);
      setTimeout(() => {
        const first = preview.querySelector('.al');
        if (first) first.remove();
      }, 4000);
    }

    async function handleFile(file) {
      if (!file) return;
      currentFilename = file.name;
      try {
        const buf = await file.arrayBuffer();
        const wb = XLSX.read(buf, { type: 'array' });
        const firstSheet = wb.Sheets[wb.SheetNames[0]];
        parsedRows = XLSX.utils.sheet_to_json(firstSheet, { defval: '' });

        renderPreview();
        onParsed(parsedRows, currentFilename);
      } catch (e) {
        showAlert('err', `Could not parse ${file.name}: ${e.message}`);
      }
    }

    function renderPreview() {
      if (!parsedRows.length) { preview.innerHTML = '<div class="al info">File parsed but no rows found.</div>'; return; }
      const cols = Object.keys(parsedRows[0]);
      const head = cols.slice(0, 6).map(c => `<th>${escapeHtml(c)}</th>`).join('');
      const body = parsedRows.slice(0, 5).map(r => `
        <tr>${cols.slice(0, 6).map(c => `<td>${escapeHtml(String(r[c] ?? ''))}</td>`).join('')}</tr>
      `).join('');
      const moreCols = cols.length > 6 ? ` +${cols.length - 6} more cols` : '';
      preview.innerHTML = `
        <div class="al info"><strong>${currentFilename}</strong> — parsed ${parsedRows.length} rows, ${cols.length} columns${moreCols}.</div>
        <div style="overflow-x:auto;margin-bottom:12px"><table class="dt">
          <thead><tr>${head}</tr></thead>
          <tbody>${body}</tbody>
        </table></div>
        ${parsedRows.length > 5 ? `<div class="sm" style="margin-bottom:10px">Showing first 5 of ${parsedRows.length} rows</div>` : ''}
        <div class="brow">
          <button class="btn btn-p" id="push-${section}">Push to team</button>
          <button class="btn btn-o" id="clear-${section}">Clear</button>
        </div>
      `;
      preview.querySelector(`#push-${section}`).addEventListener('click', pushToSupabase);
      preview.querySelector(`#clear-${section}`).addEventListener('click', () => {
        parsedRows = []; currentFilename = ''; preview.innerHTML = ''; fi.value = '';
      });
    }

    async function pushToSupabase() {
      if (!parsedRows.length) return;
      const btn = preview.querySelector(`#push-${section}`);
      btn.disabled = true; btn.textContent = 'Pushing...';
      try {
        const user = await Portal.currentUser();
        if (!user) throw new Error('Not signed in');
        const { error } = await window.sb.from('shared_workbooks').insert({
          uploaded_by: user.id,
          uploader_email: user.email,
          section,
          filename: currentFilename,
          parsed_data: parsedRows,
        });
        if (error) throw error;
        showAlert('ok', `Pushed ${parsedRows.length} rows to team. Everyone on ${section} sees it live.`);
        btn.textContent = 'Pushed ✓'; btn.classList.remove('btn-p'); btn.classList.add('btn-g');
      } catch (e) {
        showAlert('err', `Push failed: ${e.message}`);
        btn.disabled = false; btn.textContent = 'Push to team';
      }
    }

    // Drag & drop wiring
    dz.addEventListener('click', () => fi.click());
    fi.addEventListener('change', e => handleFile(e.target.files[0]));
    ['dragenter','dragover'].forEach(ev => dz.addEventListener(ev, e => { e.preventDefault(); dz.classList.add('drag'); }));
    ['dragleave','drop'].forEach(ev => dz.addEventListener(ev, e => { e.preventDefault(); dz.classList.remove('drag'); }));
    dz.addEventListener('drop', e => { if (e.dataTransfer.files[0]) handleFile(e.dataTransfer.files[0]); });
  },

  // Subscribe a callback to new shared_workbooks rows for this section
  subscribe(section, onNew) {
    const channel = window.sb.channel(`shared_workbooks:${section}`)
      .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'shared_workbooks', filter: `section=eq.${section}` },
        payload => onNew(payload.new))
      .subscribe();
    return channel;
  },

  // Fetch all workbooks for a section (newest first)
  async list(section, limit = 20) {
    const { data, error } = await window.sb.from('shared_workbooks')
      .select('*')
      .eq('section', section)
      .order('created_at', { ascending: false })
      .limit(limit);
    if (error) throw error;
    return data || [];
  }
};

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
}
