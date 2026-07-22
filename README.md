# ControlLab

ControlLab provides experimental macOS interoperability support for the Flydigi Vader 5 Pro
2.4 GHz USB receiver and Xbox-compatible Bluetooth mode. The USB bridge activates
the controller's enhanced HID protocol; Bluetooth reads the standard gamepad
profile already exposed by macOS.

Static findings from the official Windows firmware updater, including the
update endpoint and recovered HID OTA packet format, are in
[`docs/windows-firmware-updater.md`](docs/windows-firmware-updater.md).

The app now includes a **Firmware Diagnostics** section that reads the connected
controller's current firmware versions over USB, checks those versions against
Flydigi's service, downloads available packages to a user-selected file, inspects
packages, and runs an in-memory OTA simulator. Downloads are storage-only;
attempts to request a real firmware update are refused. The app does not switch
USB modes, erase, or write controller firmware.

Flydigi currently returns package links using HTTP. The downloader upgrades the
known `api-web.cdn.flydigi.com` host to its working HTTPS endpoint and rejects
unrecognized insecure download hosts.

> [!IMPORTANT]
> The firmware update process still requires testing on Windows with the official
> Flydigi application. In particular, the NearLink `SwitchUsb` transition,
> boot-mode USB identity, `.fwpkg` validation, acknowledgements, failure recovery,
> and rollback behavior must be captured and verified before real firmware writes
> are enabled on macOS. Do not use Firmware Diagnostics as a production updater.

## Hardware

- Controller: Flydigi Vader 5 Pro
- USB vendor ID: `0x37D7`
- USB product ID: `0x2401`
- Transport: Flydigi 2.4 GHz USB receiver

The receiver exposes vendor-defined HID interfaces instead of a standard HID
gamepad collection. The bridge uses the `0xFFA0` interface, sends the documented
initialization sequence, and decodes the resulting `5A A5 EF` reports.

## Current status

Working and tested on Apple silicon:

- receiver discovery and user-space access
- Flydigi initialization handshake
- sticks, analog triggers, D-pad, and standard buttons
- M1-M4, LM/RM, Home, and Fn/O
- gyroscope and accelerometer decoding
- live controller, RF, SI, and dongle firmware-version reads
- Xbox-compatible Bluetooth input for sticks, triggers, D-pad, standard buttons,
  and Guide/Home

The physical reader and protocol decoder work without elevated privileges.
Creating the standard virtual gamepad requires Apple's restricted
`com.apple.developer.hid.virtual.device` entitlement. Running as root does not
bypass that requirement on current macOS releases.

Gyroscope, accelerometer, and rumble are not yet exposed through the virtual
gamepad.

Bluetooth mode is monitor-only because macOS already exposes it as a standard
gamepad. Vader-specific extra buttons, motion sensors, and firmware metadata are
not present in its Bluetooth report; use the USB receiver for those features.

## Architecture

The GUI branch keeps protocol and device access independent from presentation:

- `Vader5Core` — reusable Swift library for report parsing, receiver I/O, and
  optional virtual-gamepad output
- `controllab-cli` — small command-line client for diagnostics and automation
- `ControlLab` — native SwiftUI macOS client with connection controls and live
  input visualization
- `Vader5CoreTests` — synthetic protocol-report tests

Both clients use the same `Vader5Bridge` API. The bridge supports `.monitor`
mode, which reads and displays the physical controller without a restricted
entitlement, and `.virtualGamepad` mode for signed production builds.

## Build

Xcode command-line tools are required.

```sh
make test       # build the package and run core tests
make cli        # build controllab-cli
make gui        # build the SwiftUI executable
make app        # package build/ControlLab.app
```

Run the monitor-only CLI without the virtual-HID entitlement:

```sh
swift run controllab-cli --monitor --verbose
```

Monitor the paired Xbox-compatible Bluetooth profile:

```sh
swift run controllab-cli --bluetooth --verbose
```

Read the firmware versions currently reported by the connected device:

```sh
swift run controllab-cli --firmware
```

Open the packaged GUI:

```sh
open build/ControlLab.app
```

For virtual-gamepad output, sign the executable with a provisioning profile
that contains `com.apple.developer.hid.virtual.device`. A sample entitlement
file is included as `ControlLab.entitlements`. Set `SIGNING_IDENTITY` when packaging
an approved build:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" make app
```

## Protocol layout

Enhanced reports are 32 bytes and begin with `5A A5 EF`:

- bytes 3-10: four signed 16-bit stick axes
- bytes 11-12: D-pad and standard buttons
- bytes 13-14: extra buttons
- bytes 15-16: analog triggers
- bytes 17-22: three-axis gyroscope
- bytes 23-28: three-axis accelerometer

The protocol work was informed by the open-source
[BANANASJIM/flydigi-vader5](https://github.com/BANANASJIM/flydigi-vader5)
Linux driver and verified against physical hardware on macOS.

## License

MIT
