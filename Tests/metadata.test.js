const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const root = path.join(__dirname, '..');
const plist = (file) =>
  JSON.parse(
    execFileSync('/usr/bin/plutil', ['-convert', 'json', '-o', '-', path.join(root, file)], {
      encoding: 'utf8',
    }),
  );
const direct = plist('Sources/MojoMouse/Info.plist');
const store = plist('Distribution/Store-Info.plist');
for (const info of [direct, store]) {
  assert.equal(info.CFBundlePackageType, 'APPL');
  assert.equal(info.LSApplicationCategoryType, 'public.app-category.utilities');
  assert.equal(info.NSPrincipalClass, 'NSApplication');
  assert.equal(info.LSMinimumSystemVersion, '13.0');
  assert.equal(info.ITSAppUsesNonExemptEncryption, false);
  assert(info.NSHumanReadableCopyright);
  assert.match(info.CFBundleShortVersionString, /^\d+\.\d+(\.\d+)?$/);
  assert.match(info.CFBundleVersion, /^\d+$/);
  assert(!('devDependencies' in info));
  assert(!('scripts' in info));
}
assert.equal(
  direct.CFBundleShortVersionString,
  JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version,
);
assert.equal(store.CFBundleIdentifier, 'io.github.mkerkstra.PointerProfiles');
assert.equal(store.CFBundleDisplayName, 'Pointer Profiles');
assert.equal(store.CFBundleExecutable, '$(EXECUTABLE_NAME)');
const entitlements = plist('Distribution/Store.entitlements');
assert.deepEqual(
  Object.keys(entitlements).sort(),
  [
    'com.apple.security.app-sandbox',
    'com.apple.security.device.usb',
    'com.apple.security.files.user-selected.read-write',
    'com.apple.security.network.client',
  ].sort(),
);
assert(Object.values(entitlements).every((value) => value === true));
const privacy = plist('Sources/MojoMouse/Resources/PrivacyInfo.xcprivacy');
assert.equal(privacy.NSPrivacyTracking, false);
assert.deepEqual(privacy.NSPrivacyCollectedDataTypes, []);
console.log('Passed: app metadata, version consistency, store entitlement boundaries, and privacy manifest.');

// Screenshot captures may be JPEG bytes even when a caller gives them a PNG suffix.
for (const folder of ['docs/screenshots', 'Distribution/Assets.xcassets/AppIcon.appiconset']) {
  for (const name of fs.readdirSync(path.join(root, folder))) {
    const bytes = fs.readFileSync(path.join(root, folder, name));
    if (name.endsWith('.png'))
      assert(
        bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])),
        `Invalid PNG encoding: ${name}`,
      );
    if (/\.jpe?g$/.test(name))
      assert(bytes.subarray(0, 3).equals(Buffer.from([255, 216, 255])), `Invalid JPEG encoding: ${name}`);
  }
}
const iconFolder = path.join(root, 'Distribution/Assets.xcassets/AppIcon.appiconset');
for (const image of JSON.parse(fs.readFileSync(path.join(iconFolder, 'Contents.json'), 'utf8')).images) {
  const bytes = fs.readFileSync(path.join(iconFolder, image.filename));
  const expected = Number.parseFloat(image.size) * Number.parseFloat(image.scale);
  assert.equal(bytes.readUInt32BE(16), expected, `App icon width: ${image.filename}`);
  assert.equal(bytes.readUInt32BE(20), expected, `App icon height: ${image.filename}`);
}
console.log('Passed: image encodings match extensions and app icons match declared pixel sizes.');
