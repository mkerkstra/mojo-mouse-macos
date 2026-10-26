# Third-party notices

The app has no third-party runtime dependencies. Its Swift HID++ implementation and exact USB product allowlist are informed by the MIT-licensed libratbag project, pinned for this work to [8235b5bb6032dea15901ab58a8218956f4494d08](https://github.com/libratbag/libratbag/tree/8235b5bb6032dea15901ab58a8218956f4494d08), specifically `src/hidpp20.c`, `src/hidpp20.h` and `data/devices/logitech-*.device`. No libratbag daemon, Python/GTK runtime, vendor installer, proprietary SDK, firmware, fonts, logos, or artwork is bundled.

The notices below are preserved with the source and executable distributions. The project's own code remains under [MIT](LICENSE). Logitech and MOJO names identify compatible products; they do not imply endorsement or affiliation.

## libratbag — MIT

Copyright 2015 Benjamin Tissoires <benjamin.tissoires@gmail.com>
Copyright 2015 Red Hat, Inc.
Copyright © 2015–2017 Red Hat, Inc.
Copyright © 2015 David Herrmann <dh.herrmann@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice (including the next paragraph) shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Development tools

Prettier is an exact, lockfile-pinned development-only dependency under MIT. XcodeGen is an optional MIT-licensed project generator; the generated Xcode project is committed. Neither is bundled in the app. GitHub Actions execute only during CI/release builds, with full commit pins. See `package-lock.json`, the workflow files, and [CONTRIBUTING.md](CONTRIBUTING.md).
