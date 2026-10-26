'use strict';
let libraryData = null,
  rulesDraft = null,
  ruleSettings = null,
  rulesStatusTimer = 0;
const prefs = {
  getItem(key) {
    return window.mojoPreferences?.[key] ?? null;
  },
  setItem(key, value) {
    window.mojoPreferences = window.mojoPreferences || {};
    window.mojoPreferences[key] = String(value);
    rpc('preference', { key, value: String(value) }).catch((e) =>
      notice('Could not save preference: ' + e.message, true),
    );
  },
};
let counter = 0,
  pending = new Map(),
  base = null,
  draft = null,
  page = 'pointer',
  busy = false,
  textPixels = null,
  renderTimer,
  renderSequence = 0;
const $ = (s) => document.querySelector(s),
  $$ = (s) => [...document.querySelectorAll(s)];
function rpc(action, payload = {}) {
  return new Promise((resolve, reject) => {
    const id = ++counter;
    pending.set(id, { resolve, reject });
    window.webkit.messageHandlers.mojo.postMessage({ id, action, payload });
  });
}
window.receive = (r) => {
  const p = pending.get(r.id);
  if (!p) return;
  pending.delete(r.id);
  r.ok ? p.resolve(r.data) : p.reject(new Error(r.error));
};
const copy = (x) => JSON.parse(JSON.stringify(x)),
  esc = (s) =>
    String(s).replace(
      /[&<>"']/g,
      (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c],
    );
function notice(text, error = false) {
  $('#notice').textContent = text;
  $('#notice').classList.toggle('error', error);
}
function dirty() {
  return (
    base &&
    draft &&
    (JSON.stringify(base.data) !== JSON.stringify(draft.data) ||
      JSON.stringify(base.buttons) !== JSON.stringify(draft.buttons) ||
      base.rate !== draft.rate ||
      !!draft.liftOff)
  );
}
function updateDirty() {
  $('#dirty').textContent = dirty() ? 'Unapplied profile changes' : 'No unapplied changes';
  $('#apply').disabled = busy || !dirty();
}
async function operation(fn, message) {
  if (busy) return;
  busy = true;
  document.body.classList.add('busy');
  updateDirty();
  $('#reload').disabled = true;
  try {
    await fn();
    if (message) notice(message);
  } catch (e) {
    notice(e.message, true);
  } finally {
    busy = false;
    document.body.classList.remove('busy');
    $('#reload').disabled = false;
    updateDirty();
  }
}
async function load() {
  if (dirty() && !confirm('Discard unapplied changes and reload the mouse?')) return;
  await operation(async () => {
    libraryData = await rpc('library');
    window.mojoPreferences = libraryData.preferences || {};
    try {
      base = await rpc('load');
      draft = copy(base);
      draft.liftOff = 0;
      $('#connection').textContent = 'MJ-189 connected';
      $('#dot').style.background = '#84c89b';
      notice('Current profile, button map, and polling rate read from your mouse.');
    } catch (e) {
      $('#connection').textContent = 'Mouse not connected';
      $('#dot').style.background = '#d4a852';
      notice(e.message, true);
    }
    render();
  });
}

const pages = [
  ['pointer', 'Pointer & DPI'],
  ['buttons', 'Button assignments'],
  ['lights', 'Lighting'],
  ['display', 'Side display'],
  ['macros', 'Macros'],
  ['rapid', 'Rapid fire'],
  ['profiles', 'Saved profiles'],
  ['rules', 'App & time rules'],
  ['advanced', 'Advanced'],
];
function renderNav() {
  $('#nav').innerHTML = pages
    .filter(([id]) => prefs.getItem('experimental') === 'true' || !['macros', 'rapid'].includes(id))
    .map(([id, name]) => `<button data-page="${id}">${name}</button>`)
    .join('');
}
renderNav();
$('#nav').addEventListener('click', (e) => {
  if (e.target.dataset.page) {
    if (page === 'macros') {
      try {
        cacheMacro();
      } catch (e) {
        notice(e.message, true);
        return;
      }
    }
    page = e.target.dataset.page;
    prefs.setItem('lastPage', page);
    render();
  }
});
$('#reload').onclick = load;
$('#apply').onclick = () =>
  operation(async () => {
    const lift = draft.liftOff || 0;
    const result = await rpc('apply', {
      data: draft.data,
      buttons: draft.buttons,
      rate: draft.rate,
      liftOff: lift,
      baseData: base.data,
      baseButtons: base.buttons,
      baseRate: base.rate,
    });
    base = result;
    draft = copy(result);
    draft.liftOff = 0;
    render();
    notice(
      lift
        ? 'Profile, buttons, and polling verified. Lift-off height command sent; height cannot be read back.'
        : 'Profile, buttons, and polling rate saved and verified on your mouse.',
    );
  });
function input(id, value, min, max, step = 1) {
  return `<input id="${id}" type="number" min="${min}" max="${max}" step="${step}" value="${value}">`;
}
function select(id, options, value) {
  return `<select id="${id}">${options.map(([v, l]) => `<option value="${v}" ${String(v) === String(value) ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select>`;
}
function check(id, value) {
  return `<input type="checkbox" id="${id}" ${value ? 'checked' : ''}>`;
}
function hex(b) {
  return b.map((x) => x.toString(16).padStart(2, '0')).join('');
}
function rgb(b) {
  return '#' + hex(b);
}
function parseColor(s) {
  return s
    .slice(1)
    .match(/../g)
    .map((x) => parseInt(x, 16));
}
function bind(id, fn, event = 'change') {
  const el = $('#' + id);
  if (el)
    el.addEventListener(event, () => {
      try {
        fn(el);
        updateDirty();
      } catch (e) {
        notice(e.message, true);
      }
    });
}
function number(el, min, max) {
  const n = Number(el.value);
  if (!Number.isInteger(n) || n < min || n > max)
    throw new Error(`Enter a whole number from ${min} to ${max}.`);
  return n;
}
function dpi(i) {
  return draft.data[37 + 2 * i] * (draft.data[38 + 2 * i] === 1 ? 100 : 50);
}
function encodeDPI(i, n) {
  if (n % 50 || n < 100 || n > 12000)
    throw new Error('DPI must be 100–12000, in steps of 50 (steps of 100 above 7200).');
  if (n > 7200 && n % 100) throw new Error('Use steps of 100 above 7200 DPI.');
  for (const start of [37, 53]) {
    draft.data[start + 2 * i] = Math.floor(n / (n > 7200 ? 100 : 50));
    draft.data[start + 2 * i + 1] = n > 7200 ? 1 : 0;
  }
}
function render() {
  clearInterval(rulesStatusTimer);
  $('#title').textContent = pages.find((x) => x[0] === page)[1];
  $$('nav button').forEach((b) => b.classList.toggle('active', b.dataset.page === page));
  if (!draft && !['profiles', 'rules', 'advanced'].includes(page)) {
    $('#content').innerHTML = '<div class="empty">Connect your MJ-189 by USB, then reload.</div>';
    return;
  }
  ({
    pointer: renderPointer,
    buttons: renderButtons,
    lights: renderLights,
    display: renderDisplay,
    macros: renderMacros,
    rapid: renderRapid,
    profiles: renderProfiles,
    rules: renderRules,
    advanced: renderAdvanced,
  })[page]();
  updateDirty();
}
function renderPointer() {
  $('#content').innerHTML =
    `<div class="card"><h2>Tracking</h2><p>Changes stay in this draft until you apply them.</p><div class="row"><label>Polling rate<span class="help">How often the mouse reports its position</span></label>${select(
      'rate',
      [
        [1, '1000 Hz · 1 ms'],
        [2, '500 Hz · 2 ms'],
        [4, '250 Hz · 4 ms'],
        [8, '125 Hz · 8 ms'],
      ],
      draft.rate,
    )}</div><div class="row"><label>X sensitivity<span class="help">100 is the default scale</span></label><div class="inline">${input('sensX', draft.data[35], 1, 255)} %</div></div><div class="row"><label>Y sensitivity</label><div class="inline">${input('sensY', draft.data[36], 1, 255)} %</div></div><div class="row"><label>Lift-off height <span class="badge">Experimental</span><span class="help">The mouse does not report its current height</span></label>${select(
      'lift',
      [
        [0, 'Leave unchanged'],
        [2, '2 mm'],
        [3, '3 mm'],
      ],
      draft.liftOff || 0,
    )}</div></div><div class="card"><h2>DPI stages</h2><p>Enable the stages your DPI buttons cycle through. Each stage has its own wheel color.</p><table><thead><tr><th>Enabled</th><th>Stage</th><th>DPI</th><th>Wheel color</th></tr></thead><tbody>${Array.from({ length: 8 }, (_, i) => `<tr><td>${check('enabled' + i, !!(draft.data[71] & (1 << i)))}</td><td>${i + 1}</td><td>${input('dpi' + i, dpi(i), 100, 12000, 50)}</td><td><input id="wheelColor${i}" type="color" value="${rgb(draft.data.slice(100 + i * 3, 103 + i * 3))}"></td></tr>`).join('')}</tbody></table></div>`;
  bind('rate', (e) => (draft.rate = +e.value));
  bind('sensX', (e) => (draft.data[35] = number(e, 1, 255)));
  bind('sensY', (e) => (draft.data[36] = number(e, 1, 255)));
  bind('lift', (e) => (draft.liftOff = +e.value));
  $('#lift').disabled = prefs.getItem('experimental') !== 'true';
  for (let i = 0; i < 8; i++) {
    bind('dpi' + i, (e) => encodeDPI(i, number(e, 100, 12000)));
    bind('enabled' + i, (e) => {
      const v = e.checked ? draft.data[71] | (1 << i) : draft.data[71] & ~(1 << i);
      if (!v) {
        e.checked = true;
        throw new Error('Keep at least one DPI stage enabled.');
      }
      draft.data[71] = v;
    });
    bind('wheelColor' + i, (e) => draft.data.splice(100 + i * 3, 3, ...parseColor(e.value)));
  }
}
const actions = [
  ['0100f000', 'Left click'],
  ['0100f100', 'Right click'],
  ['0100f200', 'Middle click'],
  ['0100f400', 'Forward'],
  ['0100f300', 'Back'],
  ['07000100', 'DPI +'],
  ['07000200', 'DPI −'],
  ['07000300', 'Cycle DPI'],
  ['0a070000', 'Function layer (Fn)'],
  ['0af01e02', 'Double click'],
  ['0f002e00', 'Auto run'],
  ['0f000500', 'Fire mode'],
  ['0300cd00', 'Play / pause'],
  ['0300b500', 'Next track'],
  ['0300b600', 'Previous track'],
  ['0300b700', 'Stop media'],
  ['0300e200', 'Mute'],
  ['0300e900', 'Volume up'],
  ['0300ea00', 'Volume down'],
  ['03008301', 'Media player'],
  ['03002302', 'Browser home'],
  ['03002102', 'Search'],
  ['0100f700', 'Scroll up'],
  ['0100f800', 'Scroll down'],
  ['00000000', 'Disabled'],
  ['keyboard', 'Keyboard shortcut…'],
  ['macro', 'Macro slot…'],
  ['rapid', 'Rapid fire…'],
  ['custom', 'Keep / custom action code…'],
];
const buttonNames = [
  '1 · Left button',
  '2 · Right button',
  '3 · Wheel click',
  '4 · Side / sniper button',
  '5 · Side function button',
  '6 · DPI + button',
  '7 · DPI − button',
  '8 · Back button',
  '9 · Forward button',
];
function renderButtons() {
  $('#content').innerHTML =
    `<div class="card"><h2>Your nine buttons</h2><p>Assignments are read from the mouse. Keep one button as Left click.</p>${buttonNames.map((name, i) => buttonRow(i, name)).join('')}</div><details><summary>Additional assignments and wheel directions</summary><div class="card">${Array.from({ length: 23 }, (_, i) => buttonRow(i + 9, i + 9 === 30 ? 'Wheel up' : i + 9 === 31 ? 'Wheel down' : `Assignment ${i + 10}`)).join('')}</div></details>`;
  for (let i = 0; i < 32; i++) {
    const code = hex(draft.buttons.slice(i * 4, i * 4 + 4));
    let selected = actions.some((x) => x[0] === code)
      ? code
      : draft.buttons[i * 4] === 9
        ? 'macro'
        : draft.buttons[i * 4] === 11
          ? 'rapid'
          : 'custom';
    if (prefs.getItem('experimental') !== 'true' && ['macro', 'rapid'].includes(selected))
      selected = 'custom';
    $('#button' + i).value = selected;
    bind('button' + i, (e) => editButton(i, e.value));
  }
}
function buttonRow(i, name) {
  const bytes = draft.buttons.slice(i * 4, i * 4 + 4),
    code = hex(bytes),
    known = actions.find((x) => x[0] === code);
  const description = known
    ? known[1]
    : bytes[0] === 9
      ? `Existing macro · slot ${bytes[2]}`
      : bytes[0] === 11
        ? 'Existing rapid-fire action'
        : 'Existing custom action (kept)';
  return `<div class="row"><label>${esc(name)}<span class="help">${esc(prefs.getItem('experimental') === 'true' ? description + ' · ' + code : description)}</span></label>${select(
    'button' + i,
    actions.filter(
      (x) =>
        prefs.getItem('experimental') === 'true' ||
        !['macro', 'rapid', '0f002e00', '0f000500'].includes(x[0]),
    ),
    '',
  )}</div>`;
}

function setButton(i, data) {
  draft.buttons.splice(i * 4, 4, ...data);
  renderButtons();
  updateDirty();
}
function editButton(i, value) {
  if (/^[0-9a-f]{8}$/.test(value))
    return setButton(
      i,
      value.match(/../g).map((x) => parseInt(x, 16)),
    );
  if (value === 'keyboard') {
    const shortcut = prompt(
      'Enter a key or shortcut, for example: Command+C, Shift+F5, or Space.',
      'Command+C',
    );
    if (shortcut !== null) setButton(i, shortcutCode(shortcut));
    else renderButtons();
  }
  if (value === 'macro') {
    const slot = prompt(
      'Macro slot (1–16). Create or edit the macro in the Macros tab first.',
      String(i + 1),
    );
    if (slot === null) return renderButtons();
    const n = Number(slot);
    if (!Number.isInteger(n) || n < 1 || n > 16) throw new Error('Choose a macro slot from 1 to 16.');
    const mode = prompt(
      'Playback: 0 = once, 1 = loop until any button is pressed, 2 = loop until released',
      '0',
    );
    if (mode === null) return renderButtons();
    if (!['0', '1', '2'].includes(mode)) throw new Error('Choose mode 0, 1, or 2.');
    setButton(i, [9, +mode, n, 0]);
  }
  if (value === 'rapid') {
    const delay = prompt('Rapid-fire interval in milliseconds (10–255)', '64');
    if (delay === null) return renderButtons();
    const count = prompt('Repeat count (0 = unlimited, up to 255)', '0');
    if (count === null) return renderButtons();
    const d = +delay,
      n = +count;
    if (!Number.isInteger(d) || d < 10 || d > 255 || !Number.isInteger(n) || n < 0 || n > 255)
      throw new Error('Use a 10–255 ms interval and a 0–255 repeat count.');
    setButton(i, [11, 240, d, n]);
  }
  if (value === 'custom') {
    if (prefs.getItem('experimental') !== 'true') {
      renderButtons();
      return;
    }
    const code = prompt(
      'Four-byte action code (8 hexadecimal characters)',
      hex(draft.buttons.slice(i * 4, i * 4 + 4)),
    );
    if (code === null) return renderButtons();
    if (!/^[0-9a-f]{8}$/i.test(code)) throw new Error('Enter exactly 8 hexadecimal characters.');
    setButton(
      i,
      code.match(/../g).map((x) => parseInt(x, 16)),
    );
  }
}
const keys = {
  enter: 40,
  return: 40,
  escape: 41,
  esc: 41,
  backspace: 42,
  tab: 43,
  space: 44,
  minus: 45,
  equal: 46,
  leftbracket: 47,
  rightbracket: 48,
  backslash: 49,
  semicolon: 51,
  quote: 52,
  grave: 53,
  comma: 54,
  period: 55,
  slash: 56,
  capslock: 57,
  insert: 73,
  home: 74,
  pageup: 75,
  delete: 76,
  end: 77,
  pagedown: 78,
  right: 79,
  left: 80,
  down: 81,
  up: 82,
  control: 224,
  shift: 225,
  option: 226,
  alt: 226,
  command: 227,
  cmd: 227,
  'mouse-left': 240,
  'mouse-right': 241,
  'mouse-middle': 242,
  'mouse-back': 243,
  'mouse-forward': 244,
};
for (let i = 0; i < 26; i++) keys[String.fromCharCode(97 + i)] = 4 + i;
for (let i = 1; i <= 9; i++) keys[String(i)] = 29 + i;
keys['0'] = 39;
for (let i = 1; i <= 12; i++) keys['f' + i] = 57 + i;
function keyCode(name) {
  const key = keys[name.trim().toLowerCase().replace(/ /g, '')];
  if (key === undefined)
    throw new Error(`Unknown key “${name}”. Use a letter, number, F1–F12, or a named key such as Space.`);
  return key;
}
function shortcutCode(text) {
  const parts = text.split('+').map((x) => x.trim().toLowerCase()),
    code = keyCode(parts.pop());
  if (!parts.length) return [0, 0, code, 0];
  if (parts.length > 1) throw new Error('For a shortcut with multiple modifiers, use a macro.');
  const modifier = { ctrl: 224, control: 224, shift: 225, alt: 226, option: 226, cmd: 227, command: 227 }[
    parts[0]
  ];
  if (!modifier) throw new Error('Unknown shortcut modifier.');
  return [0, 0, modifier, code];
}
function renderLights() {
  $('#content').innerHTML =
    `<div class="card"><h2>Body lighting</h2><p>Choose a solid color or one of the mouse’s built-in effects.</p><div class="row"><label>Effect</label>${select(
      'effect',
      [
        [0, 'Off'],
        [1, 'Solid'],
        [2, 'Breathing'],
        [3, 'RGB cycle'],
        [4, 'Finger movement'],
      ],
      draft.data[73],
    )}</div><div class="row"><label>Color</label><input id="bodyColor" type="color" value="${rgb(draft.data.slice(76, 79))}"></div><div class="row"><label>Brightness / effect speed<span class="help">Solid: 2, 4, 6, 10 · Breathing: 2–10 · RGB: 6–30</span></label>${input('speed', draft.data[74], 0, 30)}</div><div class="row"><label>Effect option</label>${input('effectOption', draft.data[75], 0, 255)}</div></div><div class="card"><h2>Wheel lighting</h2><p>Colors follow the current DPI stage. Set all to black to turn the wheel off.</p><div class="inline">${Array.from({ length: 8 }, (_, i) => `<label>${i + 1} <input id="wc${i}" type="color" value="${rgb(draft.data.slice(100 + i * 3, 103 + i * 3))}"></label>`).join('')}</div><div class="row"><button id="wheelOff">All wheel colors off</button><button id="wheelDefault">Restore saved wheel colors</button></div></div>`;
  bind('effect', (e) => {
    draft.data[73] = +e.value;
    if (!draft.data[74]) draft.data[74] = 10;
    renderLights();
  });
  bind('bodyColor', (e) => draft.data.splice(76, 3, ...parseColor(e.value)));
  bind('speed', (e) => (draft.data[74] = number(e, 0, 30)));
  bind('effectOption', (e) => (draft.data[75] = number(e, 0, 255)));
  for (let i = 0; i < 8; i++)
    bind('wc' + i, (e) => draft.data.splice(100 + i * 3, 3, ...parseColor(e.value)));
  $('#wheelOff').onclick = () => {
    draft.data.splice(100, 24, ...Array(24).fill(0));
    renderLights();
    updateDirty();
  };
  $('#wheelDefault').onclick = () => {
    draft.data.splice(100, 24, ...base.data.slice(100, 124));
    renderLights();
    updateDirty();
  };
}
function renderDisplay() {
  const text = prefs.getItem('sideText') || '';
  $('#content').innerHTML =
    `<div class="card"><h2>Make it yours</h2><p>Your side display is 96 × 39 pixels. Short messages fit best. Text wraps and shrinks to fit.</p><label class="field">Your message<textarea id="sideText" rows="2" maxlength="120" placeholder="Type anything…">${esc(text)}</textarea></label><canvas id="preview" class="screen" width="96" height="39" aria-label="Side display pixel preview"></canvas><div id="previewHelp" class="small">Exact pixel preview</div><div class="row"><span class="small">Updates immediately when sent.</span><button id="sendText" class="primary">Send text to mouse</button></div></div><div class="card"><h2>Display mode</h2><div class="row">${select(
      'displayMode',
      [
        [-1, 'Blank display'],
        [6, 'Existing user picture'],
        [0, 'MOJO logo'],
        [1, 'Sensor information'],
        [2, 'DPI value'],
        [3, 'Firmware version'],
        [4, 'Polling rate'],
        [5, 'Your custom text'],
      ],
      -1,
    )}<button id="sendMode">Set display</button></div><p class="small">Blank display uses an empty text image and preserves your picture slot. The mouse cannot report back its displayed text or mode.</p></div>`;
  $('#sideText').addEventListener('input', () => {
    prefs.setItem('sideText', $('#sideText').value);
    clearTimeout(renderTimer);
    renderTimer = setTimeout(preview, 150);
  });
  $('#sendText').onclick = () =>
    operation(async () => {
      await preview();
      if (!textPixels) throw new Error('Enter a message that fits the display.');
      await rpc('text', { pixels: textPixels });
    }, 'Text sent to the side display. Check the mouse to confirm it looks right.');
  $('#sendMode').onclick = () =>
    operation(() => rpc('display', { mode: +$('#displayMode').value }), 'Display mode sent.');
  preview();
}
async function preview() {
  const sequence = ++renderSequence;
  const field = $('#sideText');
  if (!field) return;
  try {
    const pixels = await rpc('render', { text: field.value });
    if (sequence !== renderSequence || !$('#preview')) return;
    textPixels = pixels;
    const context = $('#preview').getContext('2d'),
      image = context.createImageData(96, 39);
    for (let y = 0; y < 39; y++)
      for (let x = 0; x < 96; x++) {
        const i = (y * 96 + x) * 4,
          on = pixels[x + Math.floor(y / 8) * 96] & (1 << (y % 8));
        image.data[i] = on ? 178 : 6;
        image.data[i + 1] = on ? 255 : 25;
        image.data[i + 2] = on ? 202 : 17;
        image.data[i + 3] = 255;
      }
    context.putImageData(image, 0, 0);
    $('#previewHelp').textContent = 'Exact pixel preview';
    $('#sendText').disabled = false;
  } catch (e) {
    if (sequence !== renderSequence) return;
    textPixels = null;
    if ($('#previewHelp')) $('#previewHelp').textContent = e.message;
    if ($('#sendText')) $('#sendText').disabled = true;
  }
}

function macroSaved(slot) {
  try {
    return JSON.parse(prefs.getItem('macro' + slot) || 'null');
  } catch {
    return null;
  }
}
let macroSlot = 1;
function renderMacros() {
  const saved = macroSaved(macroSlot);
  const steps = saved?.steps || [
    { action: 'press', key: 'A', delay: 50 },
    { action: 'release', key: 'A', delay: 50 },
  ];
  $('#content').innerHTML =
    `<div class="card"><h2>Build a macro</h2><p>Create a sequence, save it to a slot, then assign that slot to a button. Nothing plays automatically.</p><div class="row"><label>Mouse macro slot</label>${select(
      'macroSlot',
      Array.from({ length: 16 }, (_, i) => [i + 1, 'Slot ' + (i + 1)]),
      macroSlot,
    )}</div><p class="small">${saved ? 'Loaded your locally saved sequence.' : 'No local sequence is saved for this slot. Existing mouse macros cannot be read back; sending replaces this slot.'}</p><div class="row"><label>Repeat count<span class="help">Playback mode is chosen in Button assignments</span></label>${input('macroRepeat', saved?.repeat || 1, 1, 65535)}</div><div class="keyrow small"><span>Action</span><span>Key</span><span>Delay after (ms)</span><span></span></div><div id="steps"></div><button id="addStep">+ Add step</button><div class="row"><span id="macroSize" class="small"></span><button id="sendMacro" class="primary">Save macro to mouse</button></div></div><div class="card"><h2>Keys and timing</h2><p class="small">Use letters, numbers, F1–F12, Enter, Tab, Space, arrows, Command, Shift, Option, Control, or mouse-left / mouse-right / mouse-middle / mouse-back / mouse-forward. Pair every press with a release. Delays use 10 ms steps; longer waits are encoded automatically.</p></div>`;
  for (const step of steps) addStep(step);
  $('#macroSlot').onchange = (e) => {
    cacheMacro();
    macroSlot = +e.target.value;
    renderMacros();
  };
  $('#addStep').onclick = () => addStep({ action: 'press', key: 'A', delay: 50 });
  $('#sendMacro').onclick = () =>
    operation(async () => {
      const macro = readMacro();
      const bytes = compileMacro(macro);
      cacheMacro();
      await rpc('macro', { slot: macroSlot, data: bytes });
    }, 'Macro sent and saved locally. The firmware cannot read it back. Assign its slot to a button when ready.');
}
function addStep(step) {
  const row = document.createElement('div');
  row.className = 'keyrow';
  row.innerHTML = `${select(
    '',
    [
      ['press', 'Press'],
      ['release', 'Release'],
    ],
    step.action,
  )}<input type="text" value="${esc(step.key)}" aria-label="Macro key"><input type="number" value="${step.delay}" min="10" max="600000" step="10" aria-label="Delay in milliseconds"><button aria-label="Remove step">×</button>`;
  row.querySelector('button').onclick = () => {
    row.remove();
    macroMeter();
  };
  row.addEventListener('change', () => {
    macroMeter();
    try {
      cacheMacro();
    } catch {}
  });
  $('#steps').append(row);
  macroMeter();
}
function macroMeter() {
  try {
    const m = readMacro();
    const bytes = compileMacro(m);
    let used = 2;
    for (const step of m.steps) used += step.delay < 1270 ? 2 : 6;
    $('#macroSize').textContent = `${used + 2} / 128 bytes`;
    $('#sendMacro').disabled = false;
  } catch (e) {
    if ($('#macroSize')) $('#macroSize').textContent = e.message;
    if ($('#sendMacro')) $('#sendMacro').disabled = true;
  }
}
function readMacro() {
  return {
    repeat: number($('#macroRepeat'), 1, 65535),
    steps: $$('#steps .keyrow').map((row) => ({
      action: row.querySelector('select').value,
      key: row.querySelector('input[type=text]').value,
      delay: number(row.querySelector('input[type=number]'), 10, 600000),
    })),
  };
}
function cacheMacro() {
  if ($('#macroRepeat')) prefs.setItem('macro' + macroSlot, JSON.stringify(readMacro()));
}
function compileMacro(macro) {
  if (!macro.steps.length) throw new Error('Add at least one press and release.');
  const held = new Set();
  let bytes = [macro.repeat >> 8, macro.repeat & 255];
  for (const step of macro.steps) {
    const code = keyCode(step.key);
    if (step.action === 'press') {
      if (held.has(code)) throw new Error('A key was pressed twice without a release.');
      held.add(code);
    } else if (!held.delete(code)) throw new Error('A release needs a matching press.');
    const release = step.action === 'release' ? 128 : 0;
    let ticks = Math.max(1, Math.round(step.delay / 10));
    if (ticks < 127) bytes.push(ticks | release, code);
    else {
      bytes.push(release, code);
      let mode = 1,
        scale = 2;
      if (ticks >= 300000) {
        mode = 3;
        scale = 10;
      } else if (ticks >= 100000) {
        mode = 2;
        scale = 5;
      }
      ticks = Math.floor(ticks / scale);
      if (ticks > 65535) throw new Error('That delay is too long.');
      bytes.push(0, mode, ticks >> 8, ticks & 255);
    }
  }
  if (held.size) throw new Error('Release every key before the macro ends.');
  bytes.push(0, 0);
  if (bytes.length > 128) throw new Error('This macro exceeds the mouse’s 128-byte slot. Remove some steps.');
  while (bytes.length < 128) bytes.push(0);
  return bytes;
}
function renderRapid() {
  const recipe = JSON.parse(prefs.getItem('rapid') || 'null') || { key: 240, count: 0, x: 0, y: 0 };
  const trigger = Object.keys(keys).find((k) => keys[k] === recipe.key) || 'mouse-left';
  $('#content').innerHTML =
    `<div class="card"><h2>Rapid-fire configuration</h2><p>Set the repeated trigger and optional pointer movement. Sending this config does not start firing. Assign Rapid fire to a button separately.</p><div class="row"><label>Trigger key</label><input id="rapidKey" type="text" value="${esc(trigger)}"></div><div class="row"><label>Repeat count<span class="help">0 runs until released or stopped</span></label>${input('rapidCount', recipe.count, 0, 255)}</div><div class="row"><label>Horizontal movement per repeat</label>${input('rapidX', recipe.x, -127, 127)}</div><div class="row"><label>Vertical movement per repeat</label>${input('rapidY', recipe.y, -127, 127)}</div><div class="row"><span class="small">The interval is set on the button assignment.</span><button id="sendRapid" class="primary">Send rapid-fire config</button></div></div><div class="card"><h2>Assign the trigger</h2><p>In Button assignments, choose Rapid fire for a button, enter its interval and repeat count, then apply the profile. Keep a normal Left click assignment.</p></div>`;
  $('#sendRapid').onclick = () =>
    operation(async () => {
      const key = keyCode($('#rapidKey').value),
        count = number($('#rapidCount'), 0, 255),
        x = number($('#rapidX'), -127, 127),
        y = number($('#rapidY'), -127, 127);
      await rpc('rapidFire', { key, count, x, y });
      prefs.setItem('rapid', JSON.stringify({ key, count, x, y }));
    }, 'Rapid-fire configuration sent. It runs only when a configured button is used; firmware cannot read this configuration back.');
}

function renderAdvanced() {
  const experimental = prefs.getItem('experimental') === 'true';
  $('#content').innerHTML =
    `<div class="card"><h2>Experimental controls</h2><div class="row"><label>Show unverified features<span class="help">Macros, rapid fire, lift-off height, and raw byte editing</span></label>${check('experimental', experimental)}</div><p class="small">These commands are based on the vendor protocol. Playback and some settings cannot be read back or reliably verified. Automatic rules never upload macro or rapid-fire recipes.</p></div>${draft ? `<div class="card"><h2>Complete profile data</h2><p>All 128 bytes are visible for diagnosis. Named controls preserve the remaining vendor-specific fields.</p><textarea id="rawProfile" rows="8" spellcheck="false" ${experimental ? '' : 'readonly'} style="font-family:ui-monospace,monospace">${draft.data.map((b, i) => (i % 16 === 0 && i ? '\n' : '') + b.toString(16).padStart(2, '0')).join(' ')}</textarea>${experimental ? '<div class="row"><span class="small">128 bytes · independent of buttons and macros</span><button id="stageRaw">Stage byte edits</button></div>' : ''}<details><summary>Known field layout</summary><p class="small">35–36: X/Y scaling. 37–52 and 53–68: DPI banks. 71: enabled DPI stages. 73–78: body effect, options, RGB. 100–123: wheel colors.</p></details></div>` : ''}<div class="card"><h2>Compatibility & privacy</h2><p class="small">Supported: MOJO MJ-189, USB 260d:1027. This does not imply support for other MOJO models. Profile bytes, button maps, and polling rate are verified by readback. The side display is visually checked; existing content cannot be retrieved.</p><p class="small">Profiles, rules, and recipes stay in this Mac’s Application Support folder. No analytics, account, or network connection. Rules use app identifiers, without reading keystrokes or window contents.</p><button id="recentEvents">Show recent status events</button><pre id="events" class="small"></pre></div>`;
  bind('experimental', (e) => {
    prefs.setItem('experimental', e.checked ? 'true' : 'false');
    renderNav();
    renderAdvanced();
  });
  if ($('#stageRaw'))
    $('#stageRaw').onclick = () => {
      const parts = $('#rawProfile').value.trim().split(/\s+/);
      if (parts.length !== 128 || parts.some((x) => !/^[0-9a-f]{2}$/i.test(x)))
        return notice('Enter exactly 128 hexadecimal bytes.', true);
      draft.data = parts.map((x) => parseInt(x, 16));
      updateDirty();
      notice('Byte edits staged. Apply saves them to the mouse.');
    };
  $('#recentEvents').onclick = () =>
    operation(async () => {
      $('#events').textContent = (await rpc('events')).join('\n') || 'No status events yet.';
    });
}

window.addEventListener('beforeunload', () => {
  if (page === 'macros')
    try {
      cacheMacro();
    } catch {}
});
