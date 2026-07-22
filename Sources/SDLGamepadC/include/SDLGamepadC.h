#ifndef SDL_GAMEPAD_C_H
#define SDL_GAMEPAD_C_H

#include <stdbool.h>
#include <stdint.h>

typedef struct CLSDLGamepad CLSDLGamepad;

typedef struct CLSDLGamepadState {
    int16_t left_x;
    int16_t left_y;
    int16_t right_x;
    int16_t right_y;
    uint8_t left_trigger;
    uint8_t right_trigger;
    uint8_t dpad;
    uint32_t buttons;
} CLSDLGamepadState;

CLSDLGamepad *CLSDLGamepadOpen(void);
bool CLSDLGamepadRead(CLSDLGamepad *handle, CLSDLGamepadState *state);
bool CLSDLGamepadConnected(CLSDLGamepad *handle);
bool CLSDLGamepadHasRGBLED(CLSDLGamepad *handle);
bool CLSDLGamepadSetRGBLED(CLSDLGamepad *handle, uint8_t red, uint8_t green,
                          uint8_t blue);
const char *CLSDLGamepadError(void);
void CLSDLGamepadClose(CLSDLGamepad *handle);

#endif
