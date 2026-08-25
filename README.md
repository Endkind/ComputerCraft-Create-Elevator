# ComputerCraft Create Elevator

A multi-elevator control system for **CC:Tweaked** and **Create**.

The system allows multiple elevator groups to communicate with each other and automatically selects an available elevator based on its current position.

It supports:

* Multiple elevator groups
* Multiple floors per group
* Automatic elevator selection
* Floor queueing
* Cabin lock
* Drive lock
* Automatic return to the master floor
* Automatic elevator position checks
* Wired modem networking
* Automatic elevator network discovery
* Automatic modem selection
* Master network bootstrap
* Manual modem selection fallback
* Automatic monitor detection
* Optional debug monitor
* Configurable display colors
* Call status display
* Direction animation when another elevator group serves the floor
* Automatic configuration generation
* Interactive installer
* Optional installer branch selection

## Requirements

* Minecraft with CC:Tweaked
* Create
* One ComputerCraft computer per floor
* Wired Modems connecting the elevator computers
* A monitor for the CALL interface
* Redstone connection between the computer and the Create elevator contact

## Installation

Download the installer on every floor computer:

```text
wget https://raw.githubusercontent.com/Endkind/ComputerCraft-Create-Elevator/refs/heads/main/install.lua
```

Then run:

```text
install
```

The installer downloads all required files and creates a fresh `config.json`.

The installer also uses cache-busting download URLs to reduce the chance of receiving outdated files from a GitHub CDN cache.

### Installing from another branch

By default, the installer downloads files from the `main` branch.

You can optionally specify another branch:

```text
install dev
```

For example:

```text
install feature/network-discovery
```

Running the installer without an argument is equivalent to:

```text
install main
```

## Installer Configuration

After installation you have 5 seconds to press Enter if you want to configure the computer.

If no input is made, the installer keeps the default configuration and reboots automatically.

When entering the configuration, the installer provides three modes.

### default

Only asks for the values required for a normal installation:

* `floor`
* `group`

### extended

Includes everything from `default` plus:

* `elevator_contact`
* `network_side`
* `cabin_lock`
* `drive_lock`

### advance

Allows configuration of all available options.

When a value is shown like this:

```text
floor (0):
```

pressing Enter without entering anything keeps the value shown in parentheses.

For nullable options, `null` can be used.

## Default Configuration

```json
{
    "floor": 0,
    "group": 1,
    "master_floor": 0,
    "elevator_contact": "bottom",
    "network_side": null,
    "display_side": null,
    "debug_display_side": null,
    "network_update": 300,
    "display_update": 0.1,
    "cabin_lock": 5,
    "drive_lock": 30,
    "wait": 30,
    "wait_tries": 4,
    "failure_timeout": 5,
    "elevator_check_delay_after_call": 0.5,
    "elevator_timeout": 300,
    "elevator_check": 60,
    "display_direction_arrow_count": 3,
    "display_direction_animation_repetitions": 3,
    "display_background_color": 1118481,
    "display_text_color": 16777215,
    "display_button_color": 2450411,
    "display_button_text_color": 16777215,
    "display_failure_button_color": 16711680,
    "display_failure_text_color": 16777215
}
```

## Basic Setup

Every elevator group consists of one master floor and any number of additional floor controllers.

By default:

```text
master_floor = 0
```

Therefore a computer configured with:

```json
{
    "floor": 0,
    "group": 1
}
```

becomes the master of elevator group 1.

Another floor could use:

```json
{
    "floor": 10,
    "group": 1
}
```

A second elevator could use the same floor numbers but a different group:

```json
{
    "floor": 0,
    "group": 2
}
```

Each elevator group has its own master.

## Networking

By default:

```json
"network_side": null
```

This enables automatic elevator network discovery.

The program does not simply select the first modem it finds.

Instead, it searches the available modems for another computer already running the elevator system.

This is useful when a computer has multiple modem connections, for example:

```text
left  -> elevator computer network
right -> remote monitor network
```

The program will try to identify the modem connected to the actual elevator network instead of accidentally using the monitor network.

### Explicit Network Modem

You can disable automatic network discovery by specifying the modem manually:

```json
"network_side": "left"
```

In this case the configured modem is used directly.

A modem selected manually during the master bootstrap process is also stored in `config.json`.

## Automatic Elevator Network Discovery

When `network_side` is `null`, computers use a dedicated discovery protocol before starting normal elevator communication.

The discovery protocol uses raw modem messages so the program can determine exactly which modem received a response.

Once the correct modem has been identified, normal elevator communication uses Rednet.

### Existing Network

If another elevator computer is already online, the new computer searches all available modems.

The first modem on which an active elevator computer responds becomes the network modem.

Example:

```text
Computer starts
    |
    +-- right modem -> no elevator response
    |
    +-- left modem  -> elevator computer responds
                         |
                         +-- left selected
```

## Master Network Bootstrap

The first master computer may start before any other elevator computer exists.

In that case there is no existing elevator network to discover.

If the master cannot find an active elevator network, it offers a manual modem selection for `failure_timeout` seconds.

With the default configuration:

```json
"failure_timeout": 5
```

the master displays a message similar to:

```text
No active elevator network found.
Press ENTER within 5 seconds to select a modem manually.
```

### Manual Selection

If Enter is pressed, all available modems are displayed.

For example:

```text
Available modems:

1. left
2. right

Select modem:
```

The selected modem is then:

* Used as the elevator network modem
* Saved permanently to `config.json` as `network_side`

For example:

```json
"network_side": "left"
```

Future starts will then use that modem directly without automatic discovery.

### Automatic Bootstrap

If no manual selection is made before the timeout expires, the master enters automatic bootstrap mode.

The master temporarily listens for elevator discovery requests on every available modem.

Example:

```text
Master
  |
  +-- left modem  -> waiting
  |
  +-- right modem -> waiting
```

When another elevator computer starts and sends a discovery request, the master can determine which modem received it.

For example:

```text
Master
  |
  +-- left modem  <- Floor -20 joins
  |
  +-- right modem -> no elevator traffic
```

The master then:

1. Selects the modem where the first elevator computer joined
2. Closes discovery on the other modems
3. Uses the selected modem as its elevator network
4. Continues normal startup

The automatically selected bootstrap modem is **not written to `config.json`**.

This allows the network to be discovered again after future wiring changes.

## Non-Master Network Startup

Normal floor computers do not create new elevator networks.

They search for an existing elevator network.

If no elevator network can be found, the computer waits for `failure_timeout` seconds and reboots.

This allows a master currently waiting in bootstrap mode to be discovered when the floor computer starts again.

## Displays

### Main Display

The main display contains the elevator CALL button.

By default:

```json
"display_side": null
```

The program automatically searches for a monitor.

You can also configure one explicitly:

```json
"display_side": "left"
```

or use a monitor connected through a Wired Modem:

```json
"display_side": "monitor_12"
```

### Debug Display

The debug display is optional.

By default:

```json
"debug_display_side": null
```

This disables it completely.

To enable it:

```json
"debug_display_side": "top"
```

or:

```json
"debug_display_side": "monitor_13"
```

When the main display uses automatic detection, the configured debug monitor is excluded from the search.

For example:

```json
"display_side": null,
"debug_display_side": "top"
```

means that `top` is reserved for the debug display and cannot automatically become the CALL display.

## Elevator Contact

The default elevator contact side is:

```json
"elevator_contact": "bottom"
```

The same redstone connection is used both to detect the elevator and to call it.

The program temporarily ignores the sensor after generating a call pulse so that its own redstone output is not interpreted as an arriving elevator.

## Cabin Lock

```json
"cabin_lock": 5
```

After the elevator arrives at a floor, the group remains locked for the configured number of seconds.

This prevents another floor from immediately calling the elevator while passengers are entering or leaving.

## Drive Lock

```json
"drive_lock": 30
```

When the elevator leaves a floor, a drive lock is activated.

This prevents the elevator from being called to another destination while it is already travelling.

The drive lock is released immediately when the elevator reaches another floor and is replaced by the normal cabin lock.

The elevator also remains marked as busy while travelling, even if the drive lock itself expires.

## Elevator Timeout

```json
"elevator_timeout": 300
```

When an elevator remains away from its master floor for too long, it is automatically returned to the master floor.

Use:

```json
"elevator_timeout": -1
```

to disable this feature.

The timeout does not run while the elevator is already parked at its master floor.

## Position Check

```json
"elevator_check": 60
```

The master periodically asks all floor controllers for the current elevator position.

This can recover the elevator state if a redstone event or network message was missed.

Use:

```json
"elevator_check": -1
```

to disable position checks.

## Multiple Elevator Groups

All masters announce their current state over the network.

When the CALL button is pressed, the system compares the known elevator positions and normally chooses the closest elevator.

If two elevators are equally far away, the floor's own group is preferred.

If the closest elevator cannot currently accept a call, the floor falls back to its own elevator group.

## Call States

The main monitor can display:

```text
CALL
QUEUED
WAIT 12.4s
CALL FAILED
```

When another elevator group serves the floor, an arrow animation is displayed after the elevator arrives.

For example:

```text
  >
 >>
>>>
 >>
  >
```

The direction depends on the group number of the elevator that served the request.

## Files

```text
install.lua
startup.lua
config.lua
network.lua
display.lua
debug_display.lua
config.json
```

`config.json` is generated locally and should normally not be part of the repository.

## Development

This project was developed with the assistance of ChatGPT by OpenAI.

The elevator system has been tested in-game throughout development and the implemented functionality has been verified during practical use.

At the time of writing this README, the repository owner has not yet completed a full manual code review of the generated code.

The current state can therefore be considered functionally tested, but not yet fully code-reviewed.

## Repository

```text
https://github.com/Endkind/ComputerCraft-Create-Elevator
```
