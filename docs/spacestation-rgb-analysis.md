# Space Station RGB protocol notes

ControlLab's USB lighting implementation was verified against the official
Flydigi Space Station 4.2.0.9 Windows package downloaded from Flydigi's software
page. The installer analyzed during development had SHA-256:

`8e003ed47c762a7a9047ce06d8eb39aacfa82b796331d0e0dc5532ccf43d72e8`

The Electron UI sends a protobuf `LedConfigBean` to `SpaceStationService.exe`.
The bundled `Flydigi.ControllerSdk.dll` identifies the Vader 5 receiver as a
New XInput device and uses this HID sequence:

- `A7`: read the selected lighting configuration in 20-byte chunks
- `A8`: begin a lighting write (`config ID`, start index, chunk count, size)
- `A9`: write one numbered chunk

macOS IOKit receives and sends the payload after the Windows HID report ID
`06`, so packets on ControlLab's already-open `FFA0:0001` interface start with
`5A A5`. Each command uses an eight-bit additive checksum from its command byte
through the final payload byte.

Space Station supports LED data versions 2 and 3. Both begin with version,
feedback, loop, brightness, LED-count, and mode fields followed by reserved
bytes. Version 2 uses 16 fixed groups of ten RGB units. Version 3 stores a
variable number of RGB triples per frame. Steady mode is `5`.

For the Vader 5 (`f5`) screen, Space Station offers Default, Flow, Breathing,
Feedback, Gradient, Steady, and Off. It hides colors for Default and Flow, uses
one color for Feedback and Steady, permits 1–5 colors for Breathing, and 2–5
colors for Gradient. Brightness is available for active modes and cycle time is
available for animated modes. The grip-vibration lighting-sync control is gated
to device code `k5`, so it is intentionally absent from ControlLab's Vader 5 UI.

ControlLab does not guess the device's version or LED count. It enables USB
lighting only after `A7` returns a recognized version 2 or 3 configuration, and
uses those reported values to build a steady-color payload. Color selection is
local until the user explicitly presses **Apply**.

SDL has a separate, standard `SDL_SetGamepadLED` API. ControlLab calls it only
when `SDL_PROP_GAMEPAD_CAP_RGB_LED_BOOLEAN` is true. SDL 3.4.12's Flydigi HIDAPI
driver reports rumble but implements its LED callback as unsupported, and the
Vader's macOS Xbox-compatible Bluetooth profile therefore does not currently
offer RGB control through SDL.

Related independent implementation: `pipe01/flydigictl` documents the earlier
XInput/DInput versions of the same LED configuration model and helped confirm
the field meanings and mode numbers. Space Station 4.2.0.9 was treated as the
authority for the Vader 5 New XInput packet framing.
