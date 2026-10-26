const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
function clock(minutes) {
  return `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
}
function minutes(text) {
  if (!/^\d{2}:\d{2}$/.test(text)) throw new Error('Choose a valid time.');
  const [hour, minute] = text.split(':').map(Number);
  if (hour > 23 || minute > 59) throw new Error('Choose a valid time.');
  return hour * 60 + minute;
}
function ruleSummary(rule) {
  const parts = [];
  if (rule.bundleID) parts.push(rule.bundleID);
  if (rule.startMinute !== null && rule.startMinute !== undefined)
    parts.push(
      `${clock(rule.startMinute)}–${clock(rule.endMinute)} · ${rule.weekdays.map((d) => dayNames[d - 1]).join(', ')}`,
    );
  return parts.join(' AND ');
}
function renderRules() {
  clearInterval(rulesStatusTimer);
  const profiles = libraryData?.profiles || [];
  if (rulesDraft === null) rulesDraft = copy(libraryData?.rules || []);
  if (ruleSettings === null)
    ruleSettings = {
      enabled: !!libraryData?.automationEnabled,
      fallbackProfileID: libraryData?.fallbackProfileID || '',
    };
  $('#content').innerHTML =
    `<div class="card"><h2>Right profile, right moment</h2><p>Match an app, a local-time window, or both. The first enabled matching rule wins. The fallback profile applies when none match. The app must remain open.</p><div class="row"><label>Automatic switching</label>${check('rulesEnabled', ruleSettings.enabled)}</div><div class="row"><label>Fallback profile<span class="help">Required before enabling rules</span></label>${select('fallback', [['', 'Choose a profile…'], ...profiles.map((p) => [p.id, p.name])], ruleSettings.fallbackProfileID)}</div><div class="inline"><button id="saveRules" class="primary">Save rules & switching setting</button><button id="discardRules">Reload saved rules</button></div><p id="automationStatus" class="small">Reading switching status…</p><div class="inline"><button id="pauseRules">Pause for 1 hour</button><button id="resumeRules">Resume</button></div></div><div class="card"><h2>Rules, in priority order</h2><p class="small">Changes below are staged until Save rules. Manual mouse edits pause switching for an hour. Switching also waits while you edit in Mojo Mouse.</p>${rulesDraft.map((r, i) => `<div class="ruleEntry"><div class="inline"><input type="checkbox" data-rule-enabled="${i}" ${r.enabled ? 'checked' : ''} aria-label="Enable ${esc(r.name)}"><b>${esc(r.name)}</b><span class="badge">${esc(profiles.find((p) => p.id === r.profileID)?.name || 'Missing profile')}</span></div><p class="small">${esc(ruleSummary(r))}</p><div class="inline"><button data-up="${i}" ${i === 0 ? 'disabled' : ''}>Move up</button><button data-down="${i}" ${i === rulesDraft.length - 1 ? 'disabled' : ''}>Move down</button><button data-edit="${i}">Edit</button><button data-remove="${i}" class="danger">Remove rule</button></div></div>`).join('') || '<p>No rules yet.</p>'}</div><div class="card"><h2 id="ruleFormTitle">Add a rule</h2><div class="field"><label for="ruleName">Name</label><input type="text" id="ruleName" maxlength="80" placeholder="Quiet evenings"></div><div class="row"><label>Apply profile</label>${select('ruleProfile', [['', 'Choose a profile…'], ...profiles.map((p) => [p.id, p.name])], '')}</div><div class="field"><label for="ruleApp">App identifier (optional)</label><input id="ruleApp" type="text" placeholder="com.apple.Safari"><select id="runningApps"><option value="">Or choose a running app…</option></select><small class="small">An app and a schedule together must both match.</small></div><div class="row"><label>Use a time window</label>${check('useTime', false)}</div><div id="timeFields" hidden><div class="inline"><label>From <input id="ruleStart" type="time" value="22:00"></label><label>Until <input id="ruleEnd" type="time" value="07:00"></label></div><div class="inline days">${dayNames.map((name, i) => `<label><input type="checkbox" data-day="${i + 1}" checked>${name}</label>`).join('')}</div><p class="small">Times use this Mac’s current time zone. Overnight windows belong to their starting day. End times are exclusive.</p></div><button id="addRule" class="primary" ${profiles.length ? '' : 'disabled'}>Add to rule list</button><p class="small">Create saved profiles first. Adding a rule does not activate it until you save.</p></div>`;
  $('#rulesEnabled').onchange = (e) => (ruleSettings.enabled = e.target.checked);
  $('#fallback').onchange = (e) => (ruleSettings.fallbackProfileID = e.target.value);
  $('#saveRules').onclick = () =>
    operation(async () => {
      libraryData = await rpc('saveRules', {
        rules: rulesDraft,
        enabled: ruleSettings.enabled,
        fallbackProfileID: ruleSettings.fallbackProfileID || null,
      });
      rulesDraft = copy(libraryData.rules);
      ruleSettings = {
        enabled: libraryData.automationEnabled,
        fallbackProfileID: libraryData.fallbackProfileID || '',
      };
      renderRules();
      notice(
        libraryData.automationEnabled
          ? 'Rules saved. Switching begins when you return to another app.'
          : 'Rules saved. Automatic switching remains off.',
      );
    });
  $('#discardRules').onclick = () =>
    operation(async () => {
      libraryData = await rpc('library');
      rulesDraft = null;
      ruleSettings = null;
      renderRules();
    });
  $('#pauseRules').onclick = () =>
    operation(async () => {
      await rpc('pauseRules');
      await refreshRulesStatus();
    });
  $('#resumeRules').onclick = () =>
    operation(async () => {
      await rpc('resumeRules');
      await refreshRulesStatus();
    });
  $$('[data-rule-enabled]').forEach(
    (el) => (el.onchange = () => (rulesDraft[+el.dataset.ruleEnabled].enabled = el.checked)),
  );
  $$('[data-up]').forEach(
    (b) =>
      (b.onclick = () => {
        const i = +b.dataset.up;
        [rulesDraft[i - 1], rulesDraft[i]] = [rulesDraft[i], rulesDraft[i - 1]];
        renderRules();
      }),
  );
  $$('[data-down]').forEach(
    (b) =>
      (b.onclick = () => {
        const i = +b.dataset.down;
        [rulesDraft[i + 1], rulesDraft[i]] = [rulesDraft[i], rulesDraft[i + 1]];
        renderRules();
      }),
  );
  $$('[data-remove]').forEach(
    (b) =>
      (b.onclick = () => {
        rulesDraft.splice(+b.dataset.remove, 1);
        renderRules();
      }),
  );
  let editIndex = null;
  $$('[data-edit]').forEach(
    (b) =>
      (b.onclick = () => {
        editIndex = +b.dataset.edit;
        const r = rulesDraft[editIndex];
        $('#ruleName').value = r.name;
        $('#ruleProfile').value = r.profileID;
        $('#ruleApp').value = r.bundleID || '';
        $('#useTime').checked = r.startMinute !== null && r.startMinute !== undefined;
        $('#timeFields').hidden = !$('#useTime').checked;
        $('#ruleStart').value = clock(r.startMinute ?? 22 * 60);
        $('#ruleEnd').value = clock(r.endMinute ?? 7 * 60);
        $$('[data-day]').forEach((c) => (c.checked = r.weekdays.includes(+c.dataset.day)));
        $('#ruleFormTitle').textContent = 'Edit rule';
        $('#addRule').textContent = 'Update rule in list';
        $('#ruleName').focus();
      }),
  );
  $('#useTime').onchange = () => ($('#timeFields').hidden = !$('#useTime').checked);
  $('#addRule').onclick = () => {
    try {
      const timed = $('#useTime').checked,
        name = $('#ruleName').value.trim(),
        app = $('#ruleApp').value.trim(),
        profileID = $('#ruleProfile').value,
        days = $$('[data-day]:checked').map((x) => +x.dataset.day);
      if (!name || !profileID) throw new Error('Give the rule a name and choose a profile.');
      if (!app && !timed) throw new Error('Choose an app, a time window, or both.');
      const start = timed ? minutes($('#ruleStart').value) : null,
        end = timed ? minutes($('#ruleEnd').value) : null;
      if (timed && (start === end || !days.length))
        throw new Error('Choose different start/end times and at least one day.');
      const rule = {
        id: editIndex === null ? crypto.randomUUID() : rulesDraft[editIndex].id,
        name,
        enabled: editIndex === null ? true : rulesDraft[editIndex].enabled,
        profileID,
        bundleID: app || null,
        startMinute: start,
        endMinute: end,
        weekdays: timed ? days : [],
      };
      if (editIndex === null) rulesDraft.push(rule);
      else rulesDraft[editIndex] = rule;
      renderRules();
      notice('Rule staged. Save rules to activate the changes.');
    } catch (e) {
      notice(e.message, true);
    }
  };
  rpc('apps')
    .then((apps) => {
      if (!$('#runningApps')) return;
      $('#runningApps').innerHTML =
        '<option value="">Or choose a running app…</option>' +
        apps.map((a) => `<option value="${esc(a.bundleID)}">${esc(a.name)}</option>`).join('');
      $('#runningApps').onchange = () => {
        if ($('#runningApps').value) $('#ruleApp').value = $('#runningApps').value;
      };
    })
    .catch((e) => notice(e.message, true));
  refreshRulesStatus();
  rulesStatusTimer = setInterval(refreshRulesStatus, 2000);
}
async function refreshRulesStatus() {
  try {
    const state = await rpc('automationStatus');
    if ($('#automationStatus')) $('#automationStatus').textContent = state.message;
  } catch (e) {
    if ($('#automationStatus')) $('#automationStatus').textContent = e.message;
  }
}
