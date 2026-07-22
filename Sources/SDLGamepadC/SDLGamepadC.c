#include "SDLGamepadC.h"

#include <SDL3/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct CLSDLGamepad {
    SDL_Gamepad *gamepad;
};

static char last_error[256];

static void save_error(const char *message) {
    SDL_strlcpy(last_error, message && *message ? message : "Unknown SDL error",
                sizeof(last_error));
}

static int16_t inverted_axis(SDL_Gamepad *gamepad, SDL_GamepadAxis axis) {
    const int value = SDL_GetGamepadAxis(gamepad, axis);
    return (int16_t)(value == INT16_MIN ? INT16_MAX : -value);
}

static uint8_t trigger_value(SDL_Gamepad *gamepad, SDL_GamepadAxis axis) {
    int value = SDL_GetGamepadAxis(gamepad, axis);
    if (value < 0) value = 0;
    return (uint8_t)((value * 255 + 16383) / 32767);
}

static bool button(SDL_Gamepad *gamepad, SDL_GamepadButton value) {
    return SDL_GetGamepadButton(gamepad, value);
}

static bool supported_gamepad(SDL_JoystickID id) {
    const char *name = SDL_GetGamepadNameForID(id);
    const Uint16 vendor = SDL_GetGamepadVendorForID(id);
    const Uint16 product = SDL_GetGamepadProductForID(id);
    return (name && (strcmp(name, "Xbox Wireless Controller") == 0 ||
                     strstr(name, "Vader") != NULL)) ||
           (vendor == 0x045e && product == 0x02e0) || vendor == 0x37d7;
}

CLSDLGamepad *CLSDLGamepadOpen(void) {
    last_error[0] = '\0';
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_THREAD, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_MFI, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI_XBOX, "1");
    SDL_SetHint(SDL_HINT_JOYSTICK_IOKIT, "1");
    if (!SDL_InitSubSystem(SDL_INIT_EVENTS | SDL_INIT_GAMEPAD)) {
        save_error(SDL_GetError());
        return NULL;
    }

    // GameController discovery on macOS may arrive asynchronously after the
    // subsystem starts. Give SDL's backends a short opportunity to enumerate.
    int count = 0;
    SDL_JoystickID *ids = NULL;
    for (int attempt = 0; attempt < 10 && count == 0; ++attempt) {
        SDL_PumpEvents();
        SDL_UpdateGamepads();
        if (ids) SDL_free(ids);
        ids = SDL_GetGamepads(&count);
        if (count == 0) SDL_Delay(50);
    }
    if (!ids) {
        save_error(SDL_GetError());
        SDL_QuitSubSystem(SDL_INIT_EVENTS | SDL_INIT_GAMEPAD);
        return NULL;
    }

    SDL_Gamepad *gamepad = NULL;
    for (int index = 0; index < count; ++index) {
        if (!supported_gamepad(ids[index])) continue;
        gamepad = SDL_OpenGamepad(ids[index]);
        if (gamepad) break;
    }
    // macOS can present Xbox-compatible devices under a GameController name
    // that differs from their raw HID product. With exactly one gamepad there
    // is no ambiguity, so use it after trying the known Vader identities.
    if (!gamepad && count == 1) gamepad = SDL_OpenGamepad(ids[0]);
    SDL_free(ids);

    if (!gamepad) {
        if (count == 0) {
            save_error("No SDL gamepads are connected");
        } else {
            snprintf(last_error, sizeof(last_error),
                     "No Vader-compatible gamepad found among %d SDL gamepads", count);
        }
        SDL_QuitSubSystem(SDL_INIT_EVENTS | SDL_INIT_GAMEPAD);
        return NULL;
    }

    CLSDLGamepad *handle = malloc(sizeof(*handle));
    if (!handle) {
        SDL_CloseGamepad(gamepad);
        save_error("Could not allocate the SDL gamepad handle");
        SDL_QuitSubSystem(SDL_INIT_EVENTS | SDL_INIT_GAMEPAD);
        return NULL;
    }
    handle->gamepad = gamepad;
    return handle;
}

bool CLSDLGamepadRead(CLSDLGamepad *handle, CLSDLGamepadState *state) {
    if (!handle || !state || !SDL_GamepadConnected(handle->gamepad)) return false;
    SDL_UpdateGamepads();

    state->left_x = SDL_GetGamepadAxis(handle->gamepad, SDL_GAMEPAD_AXIS_LEFTX);
    state->left_y = inverted_axis(handle->gamepad, SDL_GAMEPAD_AXIS_LEFTY);
    state->right_x = SDL_GetGamepadAxis(handle->gamepad, SDL_GAMEPAD_AXIS_RIGHTX);
    state->right_y = inverted_axis(handle->gamepad, SDL_GAMEPAD_AXIS_RIGHTY);
    state->left_trigger = trigger_value(handle->gamepad, SDL_GAMEPAD_AXIS_LEFT_TRIGGER);
    state->right_trigger = trigger_value(handle->gamepad, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER);

    uint32_t buttons = 0;
    if (button(handle->gamepad, SDL_GAMEPAD_BUTTON_SOUTH)) buttons |= 1u << 0;
    if (button(handle->gamepad, SDL_GAMEPAD_BUTTON_EAST)) buttons |= 1u << 1;
    if (button(handle->gamepad, SDL_GAMEPAD_BUTTON_WEST)) buttons |= 1u << 2;
    if (button(handle->gamepad, SDL_GAMEPAD_BUTTON_NORTH)) buttons |= 1u << 3;
    if (button(handle->gamepad, SDL_GAMEPAD_BUTTON_LEFT_SHOULDER)) buttons |= 1u << 4;
    if (button(handle->gamepad, SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER)) buttons |= 1u << 5;
    if (button(handle->gamepad, SDL_GAMEPAD_BUTTON_BACK)) buttons |= 1u << 6;
    if (button(handle->gamepad, SDL_GAMEPAD_BUTTON_START)) buttons |= 1u << 7;
    if (button(handle->gamepad, SDL_GAMEPAD_BUTTON_LEFT_STICK)) buttons |= 1u << 8;
    if (button(handle->gamepad, SDL_GAMEPAD_BUTTON_RIGHT_STICK)) buttons |= 1u << 9;
    if (button(handle->gamepad, SDL_GAMEPAD_BUTTON_GUIDE)) buttons |= 1u << 14;
    state->buttons = buttons;

    const bool up = button(handle->gamepad, SDL_GAMEPAD_BUTTON_DPAD_UP);
    const bool down = button(handle->gamepad, SDL_GAMEPAD_BUTTON_DPAD_DOWN);
    const bool left = button(handle->gamepad, SDL_GAMEPAD_BUTTON_DPAD_LEFT);
    const bool right = button(handle->gamepad, SDL_GAMEPAD_BUTTON_DPAD_RIGHT);
    if (up && right) state->dpad = 1;
    else if (right && down) state->dpad = 3;
    else if (down && left) state->dpad = 5;
    else if (left && up) state->dpad = 7;
    else if (up) state->dpad = 0;
    else if (right) state->dpad = 2;
    else if (down) state->dpad = 4;
    else if (left) state->dpad = 6;
    else state->dpad = 8;
    return true;
}

bool CLSDLGamepadConnected(CLSDLGamepad *handle) {
    return handle && SDL_GamepadConnected(handle->gamepad);
}

bool CLSDLGamepadHasRGBLED(CLSDLGamepad *handle) {
    if (!handle || !SDL_GamepadConnected(handle->gamepad)) return false;
    SDL_PropertiesID properties = SDL_GetGamepadProperties(handle->gamepad);
    return properties != 0 && SDL_GetBooleanProperty(
        properties, SDL_PROP_GAMEPAD_CAP_RGB_LED_BOOLEAN, false);
}

bool CLSDLGamepadSetRGBLED(CLSDLGamepad *handle, uint8_t red, uint8_t green,
                          uint8_t blue) {
    last_error[0] = '\0';
    if (!CLSDLGamepadHasRGBLED(handle)) {
        save_error("This SDL gamepad does not expose an RGB LED");
        return false;
    }
    if (!SDL_SetGamepadLED(handle->gamepad, red, green, blue)) {
        save_error(SDL_GetError());
        return false;
    }
    return true;
}

const char *CLSDLGamepadError(void) {
    return last_error[0] ? last_error : SDL_GetError();
}

void CLSDLGamepadClose(CLSDLGamepad *handle) {
    if (!handle) return;
    SDL_CloseGamepad(handle->gamepad);
    free(handle);
    SDL_QuitSubSystem(SDL_INIT_EVENTS | SDL_INIT_GAMEPAD);
}
