# Vader 5 Pro macOS bridge

Experimental macOS interoperability support for the Flydigi Vader 5 Pro
2.4 GHz USB receiver. The bridge activates the controller's enhanced HID
protocol, decodes its input reports, and forwards them through a standard
virtual HID gamepad.

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
- M1-M4, Home, and Fn/O
- gyroscope and accelerometer decoding

The physical reader and protocol decoder work without elevated privileges.
Creating the standard virtual gamepad requires Apple's restricted
`com.apple.developer.hid.virtual.device` entitlement. Running as root does not
bypass that requirement on current macOS releases.

Gyroscope, accelerometer, and rumble are not yet exposed through the virtual
gamepad.

## Build

Xcode command-line tools are required.

```sh
make
./vader5-macos
```

For virtual-gamepad output, sign the executable with a provisioning profile
that contains `com.apple.developer.hid.virtual.device`. A sample entitlement
file is included as `Vader5.entitlements`.

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
