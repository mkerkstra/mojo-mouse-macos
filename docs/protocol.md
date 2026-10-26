# MJ-189 protocol notes

These are interoperability facts used by independently written code, not a vendor SDK or a promise of support for every firmware revision. The repository does not contain the proprietary Windows software. Never use these commands on another model based only on its brand name.

## Transport

- USB vendor/product: `260d:1027`.
- Vendor-specific HID usage page/usage: `ff01:ff01`.
- Feature payload: 8 bytes, report ID 0. IOKit receives the 8 payload bytes without the extra report-ID prefix used by some HID libraries.
- Byte 0 is the command, followed by up to six parameter bytes, zero padding, and a checksum. The checksum is the bitwise complement of the modulo-256 sum of the first seven bytes.
- Bulk configuration data travels in 64-byte output/input reports. Profile and button maps use 128 bytes. Display images use four 128-byte pages.

Observed request examples:

```text
86 00 00 00 00 00 00 79    read profile 0
06 00 80 00 00 00 00 79    prepare 128-byte profile write
0A 05 00 00 00 00 00 F0    select custom-text display
```

## Commands in the app

| Command     | Use                                    | Verification                               |
| ----------- | -------------------------------------- | ------------------------------------------ |
| `84`        | Read active sensor-profile information | Feature reply                              |
| `86`        | Read 128-byte profile                  | Header plus two input reports              |
| `06`        | Write profile                          | Complete profile readback                  |
| `87`        | Read 128-byte button map               | Header plus two input reports              |
| `07`        | Write button map                       | Complete map readback                      |
| `83` / `03` | Read/write polling interval            | Feature readback; intervals 1, 2, 4, 8 ms  |
| `09`        | Upload a display-image page            | No reliable image readback                 |
| `0A`        | Select display content                 | Visual confirmation only                   |
| `08`        | Upload 128-byte macro slot             | Experimental; no reliable macro readback   |
| `04`        | Rapid-fire configuration               | Experimental; physical behavior unverified |
| `0B`        | Lift-off height                        | Experimental; no reliable readback         |

Readable replies are checked for the expected opcode, length, and profile identifier before being used. The connection is serialized within the process, and no exclusive access to normal input is taken. Do not run competing configuration utilities.

## Known profile offsets

Offsets are zero-based within the 128-byte profile:

| Offset       | Meaning                       |
| ------------ | ----------------------------- |
| 35–36        | X/Y scaling                   |
| 37–52, 53–68 | Eight DPI pairs in two banks  |
| 71           | Enabled DPI-stage bitmask     |
| 73–78        | Body effect, options, and RGB |
| 100–123      | Eight wheel RGB colors        |

Named controls preserve other bytes. Lighting-only profiles merge only 73–78 and 100–123 into a fresh snapshot. Raw editing is experimental. Profile validation requires one enabled DPI stage, a supported polling rate, and at least one Left click among the primary button assignments.

## Side-display pixels

The panel is 96 × 39 pixels. A monochrome pixel `(x, y)` is packed at byte `x + floor(y / 8) * 96`, bit `y % 8`, then padded to 512 bytes. Static text is rendered locally and transferred to text storage. Blanking sends a zero-filled text image; it does not erase picture storage.

No native marquee command was established. Repeated bitmap streaming is intentionally omitted.

## Evidence boundary

Byte readback establishes the stored configuration observed by the device. It does not establish that every possible button action or experimental command behaves as desired on macOS. See [hardware support](hardware-support.md) for actual testing and limitations. Future support needs captured packet fixtures, simulated failure tests, physical validation, and clear firmware scope.
