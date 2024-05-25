# Development

## How to replace binaries without reinstalling package

### Replace `karabiner_grabber`

```shell
cd src/core/grabber
make install
```

### Replace `karabiner_session_monitor`

```shell
cd src/core/session_monitor
make install
```

### Replace `karabiner_console_user_server`

```shell
cd src/core/console_user_server
make install
```

## Core Processes

-   `karabiner_grabber`
    -   Seize the input devices and modify events then post events using `Karabiner-DriverKit-VirtualHIDDevice`.
    -   It is run with root privileges which are required to seize the device and send events to the virtual driver.
-   `karabiner_session_monitor`
    -   It informs `karabiner_grabber` of the user currently using the console.
        karabiner_grabber will change the owner of the Unix domain socket that `karabiner_grabber` provides for `karabiner_console_user_server`.
    -   The methods for accurately detecting the console user, including when multiple people are logged in through Screen Sharing, are very limited.
        Even in macOS 14, there is no alternative to using the Core Graphics API `CGSessionCopyCurrentDictionary`.
        To use this API, it must be launched from a GUI session. Specifically, it needs to be started from LaunchAgents.
        Therefore, the function to detect the console user cannot be integrated into `karabiner_grabber` and is implemented as a separate process.
    -   It is run with root privileges because if the notification of the console user to `karabiner_grabber` can be done by anyone, the console user could be spoofed.
        This would allow a user who is not currently using the console to send requests to `karabiner_grabber` via `karabiner_console_user_server`.
-   `karabiner_console_user_server`
    -   `karabiner_console_user_server` connects to the Unix domain socket provided by `karabiner_grabber` and requests the start of processing input events.
        `karabiner_grabber` will not modify the input events until it receives a connection from `karabiner_console_user_server` (unless the system default configuration is enabled).
    -   The execution of `shell_command`, `software_function`, and `select_input_source` is carried out by karabiner_console_user_server.
    -   It notifies `karabiner_grabber` of the information needed to reference the filter function when modifying input events, such as the active application and the current input source.
    -   Run with the console user privilege.

![processes](images/processes.svg)

### program sequence

#### start up

`karabiner_grabber`

1.  Run `karabiner_grabber`.
2.  `karabiner_grabber` opens session_monitor_receiver Unix domain socket which only root can access.
3.  `karabiner_grabber` opens grabber server Unix domain socket.
4.  When a window server session state is changed, `karabiner_grabber` changes the Unix domain socket owner to console user.

`karabiner_session_monitor`

1.  Run `karabiner_session_monitor`.
2.  `karabiner_session_monitor` monitors a window server session state and notify it to `karabiner_grabber`.
3.  `karabiner_grabber` changes the owner of Unix domain socket for `karabiner_console_user_server` when the console user is changed.

#### device grabbing

1.  Run `karabiner_console_user_server`.
2.  Try to open console_user_server Unix domain socket.
3.  grabber seizes input devices.

### Other notes

IOHIDSystem requires the process is running with the console user privilege.
Thus, `karabiner_grabber` cannot send events to IOHIDSystem directly.

---

## The difference of event grabbing methods

### IOKit

IOKit allows you to read raw HID input events from kernel.<br />
The highest layer is IOHIDQueue which provides us the HID values.

`karabiner_grabber` uses this method.

#### IOKit with Apple Trackpads

IOKit cannot catch events from Apple Trackpads.<br />
(== Apple Trackpad driver does not send events to IOKit.)

Thus, we should use CGEventTap together for pointing devices.

#### `IOHIDQueueRegisterValueAvailableCallback` from multiple processes

We can use `IOHIDDeviceOpen` and `IOHIDQueueRegisterValueAvailableCallback` from multiple processes.

Generally, `ValueAvailableCallback` is not called for `IOHIDDeviceOpen(kIOHIDOptionsTypeNone)` while device is opened with `kIOHIDOptionsTypeSeizeDevice`.
However, it seems `ValueAvailableCallback` is called both seized `IOHIDDeviceRef` and normal `IOHIDDeviceRef` in some cases (e.g. after awake from sleep)

#### `IOHIDQueueRegisterValueAvailableCallback` from multiple IOHIDDeviceRef for one device

We can create multiple IOHIDDeviceRef for one device by using `IOHIDDeviceCreate`.
In this case, `ValueAvailableCallback` is called both seized `IOHIDDeviceRef` and normal `IOHIDDeviceRef`.

```c
// IOHIDDeviceRef device1 is passed by IOHIDManagerRegisterDeviceMatchingCallback
IOHIDDeviceRef device2 = IOHIDDeviceCreate(kCFAllocatorDefault, IOHIDDeviceGetService(device1));

IOHIDDeviceOpen(device1, kIOHIDOptionsTypeNone);
IOHIDDeviceOpen(device2, kIOHIDOptionsTypeSeizeDevice);

// ValueAvailableCallback is called both device1 and device2 even device2 seizes the device. (on macOS 10.13.4)
```

### CGEventTapCreate

`CGEventTapCreate` is a limited approach.<br />
It does not work with Secure Keyboard Entry even if we use `kCGHIDEventTap` and root privillege.<br />
Thus, it does not work in Terminal.<br />
You can confirm this behavior in `appendix/eventtap`.

There is another problem with `CGEventTapCreate`.<br />
`Shake mouse pointer to locate` feature will be stopped after we call `CGEventTapCreate` with `kCGEventTapOptionDefault`.<br />
(We confirmed the problem at least on macOS 10.13.1.)<br />

`karabiner_grabber` uses `CGEventTapCreate` with `kCGEventTapOptionListenOnly` in order to catch Apple mouse/trackpad events which we cannot catch in IOKit.
(See above note.)

---

## The difference of event posting methods

### IOKit device report in dext

It requires posting HID events.<br />
The IOHIKeyboard processes the reports by passing reports to `handleReport`.

`karabiner_grabber` uses this method by using `Karabiner-DriverKit-VirtualHIDDevice`.

Note: `handleReport` fails to treat events which usage page are `kHIDPage_AppleVendorKeyboard` or `kHIDPage_AppleVendorTopCase` on macOS 10.11 or earlier.

### IOHIDPostEvent

It requires posting coregraphics events.<br />

`IOHIDPostEvent` will be failed if the process is not running in the current session user.
(The root user is also forbidden.)

### CGEventPost

It requires posting coregraphics events.<br />

`CGEventPost` does not support some key events in OS X 10.12.

-   Mission Control key
-   Launchpad key
-   Option-Command-Escape

Thus, `karabiner_grabber` does not use `CGEventPost`.

---

## Modifier flags handling in kernel

The modifier flag events are handled in the following sequence in macOS 10.12.

1.  Receive HID reports from device.
2.  Treat reports in the keyboard device driver.
3.  Treat flags in accessibility functions. (eg. sticky keys, zoom)
4.  Treat flags in mouse events.
5.  Treat flags in IOHIDSystem.
6.  Treat flags in Coregraphics.

Thus, `IOHIDPostEvent` will be ignored in accessibility functions and mouse events.

---

## About hid reports

We can get hid reports from devices via `IOHIDDeviceRegisterInputReportCallback`.<br />
The hid report contains a list of pressed keys, so it seems suitable information to observe.

But `karabiner_grabber` does not use it in order to reduce the device dependancy.

### The limitation of device reports

#### Apple devices reports

Apple keyboards does not use generic HID keyboard report descriptor.<br />
Thus, we have to handle them by separate way.

##### Generic HID keyboard report descriptor

```c
uint8_t modifiers;
uint8_t reserved;
uint8_t keys[6];
```

###### modifiers bit

```text
0x1 << 0 : left control
0x1 << 1 : left shift
0x1 << 2 : left option
0x1 << 3 : left command
0x1 << 4 : right control
0x1 << 5 : right shift
0x1 << 6 : right option
0x1 << 7 : right command
```

##### Apple HID keyboard report descriptor

```c
uint8_t record_id;
uint8_t modifiers;
uint8_t reserved;
uint8_t keys[6];
uint8_t extra_modifiers; // fn
```

---

## Session

### About console user detection

There are several way to get the session information, however, the reliable way is limited.

-   The owner of `/dev/console`
    -   The owner of `/dev/console` becomes wrong value after remote user is logged in via Screen Sharing.<br />
        How to reproduce the problem.
        1.  Restart macOS.
        2.  Log in from console as Guest user.
        3.  Log in from Screen Sharing as another user.
        4.  The owner of `/dev/console` is changed to another user even the console user is Guest.
-   `SCDynamicStoreCopyConsoleUser`
    -   `SCDynamicStoreCopyConsoleUser` has same problem of `/dev/console`.
-   `SessionGetInfo`
    -   `SessionGetInfo` cannot get uid of session.
        Thus, `SessionGetInfo` cannot determine the console user.
-   `CGSessionCopyCurrentDictionary`
    -   `karabiner_session_monitor` uses it to avoid the above problems.

---

## Caps lock handling

The caps lock is quite different from the normal modifier.

-   The caps lock might be used another purpose. (e.g., switch input source)
    -   We should refer the caps lock LED to determine caps lock is on/off.
-   The caps lock modifier is not synchronized with the physical state of key down/up.
    -   We should send key_down and key_up event to change the caps lock state.
-   The caps lock will be treated as both generic key event and modifier key event due to the above reasons.
    -   If the caps lock is specified as "to.key_code: caps_lock", the caps lock event is treated as generic key event.
        -   For example, `key_event_dispatcher` manages in `key_event_dispatcher::pressed_keys_`.
    -   If the caps lock is specified as "from.modifiers" or "to.modifiers", the caps lock event is treated as modifier key event.
        -   For example, `key_event_dispatcher` manages in `key_event_dispatcher::pressed_modifier_flags_`.

### Events related with caps lock in Karabiner-Elements

-   `hid::usage::keyboard_or_keypad::keyboard_caps_lock`
    -   The event is sent when the physical caps lock key is pressed.
    -   The event does not change the state of `modifier_flag_manager` because the event might be used another purpose.
    -   `event::type::caps_lock_state_changed` might be sent due to the LED state change.
-   `event::type::caps_lock_state_changed`
    -   This event happens when the caps lock LED is changed.
    -   The event changes the state of `modifier_flag_manager`.
        -   `hid::usage::keyboard_or_keypad::keyboard_caps_lock` might be sent due to the `modifier_flag_manager` state change.
-   `event::type::sticky_modifier`
    -   `basic > from.modifiers.mandatory` and `basic > to.modifiers` also send this event in order to change the state of `modifier_flag_manager`,
    -   The event changes the state of `modifier_flag_manager`.
        -   `hid::usage::keyboard_or_keypad::keyboard_caps_lock` might be sent due to the `modifier_flag_manager` state change.

### The flow of updating `modifier_flag_manager`

-   karabiner_grabber receives `hid::usage::keyboard_or_keypad::keyboard_caps_lock`.
-   Send the event via virtual hid keyboard.
-   macOS update the caps lock LED of virtual hid keyboard.
-   Virtual hid keyboard sends the LED updated event.
-   karabiner_grabber observes events from the virtual hid keyboard.
    When an event {usage_page::leds, usage::led::caps_lock} is detected, karabiner_grabber generates an `event::type::caps_lock_state_changed` and adds it to the queue.
-   The state of `modifier_flag_manager` is changed by `event::type::caps_lock_state_changed`.

### modifier state holders

-   `modifier_flag_manager`
    -   Keep ideal modifiers state for event modification.
-   `key_event_dispatcher`
    -   Keep actually sent modifiers.

For example, `modifier_flag_manager` contains the lazy modifiers, but `key_event_dispatcher` does not.

### The flow of handling caps lock as modifier

Example:

```json
{
    "from": {
        "key_code": "down_arrow",
        "modifiers": {
            "mandatory": ["caps_lock"],
            "optional": ["any"]
        }
    },
    "to": [
        {
            "key_code": "d"
        }
    ],
    "type": "basic"
}
```

-   Press the physical caps_lock key (`hid::usage::keyboard_or_keypad::keyboard_caps_lock`)
    -   `key_event_dispatcher` is updated.
        -   `pressed_keys_.insert(caps_lock)`
    -   macOS update the caps lock LED state (on).
    -   `event::type::caps_lock_state_changed (on)` is sent via `krbn::event_queue::utility::make_queue` in `karabiner_grabber`.
        -   `modifier_flag_manager increase_led_lock (caps_lock)`
        -   `key_event_dispatcher` is updated.
            -   `pressed_modifier_flags_.insert(caps_lock)`
-   Release the physical caps_lock key (`hid::usage::keyboard_or_keypad::keyboard_caps_lock`)
    -   `key_event_dispatcher` is updated.
        -   `pressed_keys_.erase(caps_lock)`
-   Press `down_arrow` key.j
    -   `sticky_modifier caps_lock false` is sent by `modifiers.mandatory`.
        -   `modifier_flag_manager decrease_sticky (caps_lock)`
    -   `hid::usage::keyboard_or_keypad::keyboard_caps_lock` is sent via virtual hid keyboard.
    -   `key_event_dispatcher` is updated.
        -   `pressed_modifier_flags_.erase(caps_lock)`
    -   `d` is sent via virtual hid keyboard.
    -   sticky_modifiers are erased.
    -   `sticky_modifier caps_lock true` is sent by `modifiers.mandatory`.
        -   `modifier_flag_manager increase_sticky (caps_lock)`
    -   macOS update the caps lock LED state (off).
    -   `event::type::caps_lock_state_changed (off)` is sent via `krbn::event_queue::utility::make_queue` in `karabiner_grabber`.
        -   `modifier_flag_manager decrease_led_lock (caps_lock)`
            -   Note: led_lock will be ignored while other counter is active in modifier_flag_manager.
-   Release `down_arrow` key.
    -   `d` is sent via virtual hid keyboard.
-   Press `tab` key.
    -   `hid::usage::keyboard_or_keypad::keyboard_caps_lock` is sent via virtual hid keyboard by sticky_modifier.
    -   sticky_modifiers are erased.
    -   `tab` is sent via virtual hid keyboard.
