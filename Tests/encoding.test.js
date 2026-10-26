const fs = require('fs'),
  vm = require('vm'),
  assert = require('assert');
let code = fs
  .readFileSync(require('path').join(__dirname, '../Sources/MojoMouse/Resources/settings.js'), 'utf8')
  .replace(/load\(\);\s*$/, '');
const fields = new Map();
const element = () => ({
  innerHTML: '',
  disabled: false,
  textContent: '',
  classList: { toggle() {} },
  addEventListener() {},
  style: {},
});
const context = {
  document: {
    querySelector(s) {
      if (!fields.has(s)) fields.set(s, element());
      return fields.get(s);
    },
    querySelectorAll() {
      return [];
    },
  },
  window: { addEventListener() {}, webkit: { messageHandlers: { mojo: { postMessage() {} } } } },
  localStorage: {
    getItem() {
      return null;
    },
    setItem() {},
  },
  setTimeout,
  clearTimeout,
  console,
  confirm: () => true,
  prompt: () => null,
};
vm.createContext(context);
vm.runInContext(code, context);
const run = (s) => vm.runInContext(s, context);
assert.equal(run('hex(shortcutCode("Command+C"))'), '0000e306');
assert.equal(run('hex(shortcutCode("A"))'), '00000400');
assert.equal(run('hex(shortcutCode("Shift+F5"))'), '0000e13e');
assert.throws(() => run('shortcutCode("Command+Shift+A")'), /macro/);
const m = run(
  'compileMacro({repeat:1,steps:[{action:"press",key:"A",delay:50},{action:"release",key:"A",delay:50}]})',
);
assert.equal(m.length, 128);
assert.deepEqual(Array.from(m.slice(0, 8)), [0, 1, 5, 4, 133, 4, 0, 0]);
assert.throws(() => run('compileMacro({repeat:1,steps:[{action:"press",key:"A",delay:50}]})'), /Release/);
const long = run(
  'compileMacro({repeat:1,steps:[{action:"press",key:"A",delay:600000},{action:"release",key:"A",delay:50}]})',
);
assert.equal(long.length, 128);
assert.deepEqual(Array.from(long.slice(2, 8)), [0, 4, 0, 1, 117, 48]);
run('draft={data:Array(128).fill(0)};encodeDPI(0,12000)');
assert.equal(run('dpi(0)'), 12000);
assert.equal(run('draft.data[38]'), 1);
assert.equal(run('draft.data[54]'), 1);
assert.throws(() => run('encodeDPI(0,7250)'), /steps of 100/);
console.log(
  'Passed: shortcut encoding, paired macro events, long delays, 128-byte limits, DPI banks and ranges.',
);
