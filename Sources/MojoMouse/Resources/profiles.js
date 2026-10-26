function profilePackage() {
  if (!draft) throw new Error('Connect and reload a mouse, or import a profile first.');
  return {
    formatVersion: 1,
    device: 'MOJO MJ-189 (260d:1027)',
    profile: base?.profile ?? draft.profile ?? 0,
    data: copy(draft.data),
    buttons: copy(draft.buttons),
    rate: draft.rate,
  };
}
function validBytes(b, n) {
  return Array.isArray(b) && b.length === n && b.every((v) => Number.isInteger(v) && v >= 0 && v <= 255);
}
function loadPackage(value) {
  const p = value?.snapshot ?? value;
  if (
    !p ||
    p.formatVersion !== 1 ||
    p.device !== 'MOJO MJ-189 (260d:1027)' ||
    !validBytes(p.data, 128) ||
    !validBytes(p.buttons, 128) ||
    ![1, 2, 4, 8].includes(p.rate)
  )
    throw new Error('This is not a valid MJ-189 profile.');
  if (dirty() && !confirm('Replace the current unapplied draft?')) return;
  draft = { ...copy(p), profile: base?.profile ?? p.profile ?? 0, liftOff: 0 };
  render();
  notice('Profile loaded into the draft. Review it before applying it to the mouse.');
}
async function saveNamed(profile) {
  libraryData = await rpc('saveProfile', profile);
  renderProfiles();
  notice('Profile saved on this Mac. Automatic rules can now use it.');
}
function renderProfiles() {
  const profiles = libraryData?.profiles || [];
  $('#content').innerHTML =
    `<div class="card"><h2>A setup for every task</h2><p>Profiles live on your Mac. Apply one manually or select it in an app or time rule. Lighting-only profiles preserve buttons, sensitivity, DPI, and polling.</p><div class="field"><label for="profileName">Save this draft as</label><input id="profileName" type="text" maxlength="64" placeholder="Work, Games, Quiet evenings…"></div><div class="row"><label>Settings to include</label>${select(
      'profileScope',
      [
        ['all', 'Complete readable settings'],
        ['lighting', 'Lighting only'],
      ],
      'all',
    )}</div><div class="row"><label>Side display</label>${select(
      'profileDisplay',
      [
        ['unchanged', 'Leave unchanged'],
        ['blank', 'Blank display'],
        ['logo', 'MOJO logo'],
        ['text', 'Custom text'],
      ],
      'unchanged',
    )}</div><div class="field" id="profileTextField" hidden><label for="profileText">Profile’s side text</label><textarea id="profileText" rows="2" maxlength="120">${esc(prefs.getItem('sideText') || '')}</textarea></div><div class="inline"><button id="saveProfile" class="primary" ${draft ? '' : 'disabled'}>Save new profile</button><button id="quietProfile" ${draft ? '' : 'disabled'}>Create “Lights off” profile</button></div></div><div class="card"><h2>Your profiles <span class="badge">${profiles.length}</span></h2><div>${profiles.map((p, i) => `<div class="profileEntry"><div><b>${esc(p.name)}</b><span class="help">${p.scope === 'lighting' ? 'Lighting only' : 'Complete settings'} · Side: ${esc(p.display.mode)}</span></div><div class="inline"><button data-now="${i}">Apply now</button><button data-load="${i}">Load draft</button><button data-update="${i}">Update from draft</button><button data-rename="${i}">Rename</button><button data-copy="${i}">Duplicate</button><button data-export="${i}">Export…</button><button data-delete="${i}" class="danger">Delete</button></div></div>`).join('') || '<p>No saved profiles yet. Create one from your current mouse settings.</p>'}</div></div><div class="card"><h2>Backup & transfer</h2><p>Imports change the draft, without touching the mouse or enabling automatic switching. The app backs up readable settings before changing them.</p><div class="inline"><button id="exportDraft" ${draft ? '' : 'disabled'}>Export current draft…</button><button id="importProfile">Import profile…</button><button id="originalProfile">Load original mouse backup</button></div><p class="small">Macros and rapid-fire recipes are separate experimental features. They are never automatically uploaded with a profile.</p></div>`;
  $('#profileDisplay').onchange = () =>
    ($('#profileTextField').hidden = $('#profileDisplay').value !== 'text');
  $('#saveProfile').onclick = () =>
    operation(async () => {
      const name = $('#profileName').value.trim();
      if (!name) throw new Error('Give the profile a name.');
      const display = { mode: $('#profileDisplay').value, text: $('#profileText').value };
      if (display.mode === 'text') await rpc('render', { text: display.text });
      await saveNamed({
        id: crypto.randomUUID(),
        name,
        scope: $('#profileScope').value,
        snapshot: profilePackage(),
        display,
      });
    });
  $('#quietProfile').onclick = () =>
    operation(async () => {
      const snapshot = profilePackage();
      snapshot.data.splice(73, 3, 0, 0, 0);
      snapshot.data.splice(100, 24, ...Array(24).fill(0));
      await saveNamed({
        id: crypto.randomUUID(),
        name: 'Lights off',
        scope: 'lighting',
        snapshot,
        display: { mode: 'blank', text: '' },
      });
    });
  $$('[data-now]').forEach(
    (b) =>
      (b.onclick = () =>
        operation(async () => {
          if (dirty() && !confirm('Applying this profile will replace the current draft. Continue?')) return;
          const p = profiles[+b.dataset.now];
          base = await rpc('applySaved', { id: p.id });
          draft = { ...copy(base), liftOff: 0 };
          render();
          notice(
            `${p.name} applied. Readable settings verified; manual changes pause automatic switching for one hour.`,
          );
        })),
  );
  $$('[data-load]').forEach(
    (b) =>
      (b.onclick = () => {
        try {
          loadPackage(profiles[+b.dataset.load]);
        } catch (e) {
          notice(e.message, true);
        }
      }),
  );
  $$('[data-update]').forEach(
    (b) =>
      (b.onclick = () =>
        operation(async () => {
          const p = copy(profiles[+b.dataset.update]);
          if (!confirm(`Replace “${p.name}” with the current draft settings?`)) return;
          p.snapshot = profilePackage();
          await saveNamed(p);
        })),
  );
  $$('[data-rename]').forEach(
    (b) =>
      (b.onclick = () =>
        operation(async () => {
          const p = copy(profiles[+b.dataset.rename]),
            name = prompt('Profile name', p.name);
          if (name === null) return;
          p.name = name.trim();
          await saveNamed(p);
        })),
  );
  $$('[data-copy]').forEach(
    (b) =>
      (b.onclick = () =>
        operation(async () => {
          const p = copy(profiles[+b.dataset.copy]);
          p.id = crypto.randomUUID();
          p.name = (p.name + ' copy').slice(0, 64);
          await saveNamed(p);
        })),
  );
  $$('[data-export]').forEach(
    (b) => (b.onclick = () => operation(() => rpc('export', profiles[+b.dataset.export]))),
  );
  $$('[data-delete]').forEach(
    (b) =>
      (b.onclick = () =>
        operation(async () => {
          const p = profiles[+b.dataset.delete];
          if (!confirm(`Delete the saved profile “${p.name}”?`)) return;
          libraryData = await rpc('deleteProfile', { id: p.id });
          renderProfiles();
          notice('Saved profile deleted. The mouse was not changed.');
        })),
  );
  $('#exportDraft').onclick = () => operation(() => rpc('export', profilePackage()));
  $('#importProfile').onclick = () =>
    operation(async () => {
      const p = await rpc('import');
      if (p) loadPackage(p);
    });
  $('#originalProfile').onclick = () => operation(async () => loadPackage(await rpc('original')));
}
