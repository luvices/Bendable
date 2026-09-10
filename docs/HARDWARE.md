# The lid angle sensor

Notes on what the hardware actually does, gathered by probing a MacBook Air (M4,
`Mac16,12`) on macOS 27. Everything here is reachable with the public `IOHIDManager`
API: no entitlement, no TCC prompt, no helper tool, no kernel extension, and SIP stays
on.

## Finding it

Apple silicon MacBooks publish a HID device under `AppleSPU`:

```
+-o AppleSPUHIDDevice
    "Product"           = "las"
    "VendorID"          = 1452          (0x05AC)
    "ProductID"         = 33028
    "Transport"         = "SPU"
    "PrimaryUsagePage"  = 32            (0x20, HID Sensors)
    "PrimaryUsage"      = 138           (0x8A)
    "ReportInterval"    = 8000          (microseconds)
```

Matching on the vendor plus that usage pair is enough. If the device is absent,
`IOHIDManagerCopyDevices` returns nothing and there is no lid angle to be had.

## Report 1

Report 1 carries the angle in whole degrees. Three bytes: the report id, then the
angle little-endian. A reading of `01 68 00` is 104 degrees.

The report descriptor declares the field as 9 bits with a logical range of 0 to 360,
though a lid only ever occupies the bottom half of that. Values outside 0 to 180 are
worth rejecting; a negative value shows up occasionally while the sensor is still
working out where it is.

## Push and pull, which is the important part

The device will talk two ways, and only one of them is any use for an animation.

**Pushed input reports** arrive when the whole-degree angle changes, plus a heartbeat
roughly once a second. That sounds fine until you work out the cadence: the angle is
quantised to whole degrees, so a lid moved at 20 degrees a second is heard from every
50 milliseconds, and one moved slowly at 2 degrees a second every 500. Several display
refreshes apart, and nothing at all in between.

**Report 1 read as a feature report** answers with the angle as it is now, whenever you
ask. Measured here over 200 consecutive reads: every one succeeded, mean 0.62 ms, worst
0.76 ms.

So the angle is polled at display rate while the lid moves. The pushed reports are
still useful, but as a doorbell rather than as data: they say movement has begun, and
the polling thread waits on a condition the rest of the time.

This distinction is the single thing that decides whether the effect feels attached to
the hinge. Building on the pushed reports means guessing what happened between them,
and a guess that runs past where the lid actually went is far more obvious than a
little lag. The approach came from [DuoBook](https://github.com/askmaddyy/DuoBook),
which got there first.

## Input value callbacks

`IOHIDDeviceRegisterInputValueCallback` on the angle element produces nothing while the
lid is still, and nothing at all until it first moves. The driver coalesces unchanged
values. Not useful here, but it costs an afternoon to discover.

## Without the sensor

Intel MacBooks, and any Mac where the match fails, still expose lid state.
`IOPMrootDomain` publishes `AppleClamshellState`, and posts
`kIOPMMessageClamshellStateChange` as a general interest notification on every lid
edge, delivered through `IOServiceAddInterestNotification`. That is open and closed
with no polling, which is as much as the platform offers.

Note that this is not `IORegisterForSystemPower`, which carries sleep and wake but no
clamshell edges. The message constant is a C macro and so unavailable to Swift; it
expands to `iokit_family_msg(sub_iokit_powermanagement, 0x100)`, which is `0xE0034100`.
