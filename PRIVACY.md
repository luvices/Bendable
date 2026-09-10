# Privacy

Bendable is local-only by construction, not by policy.

## What it does not do

There is no analytics, telemetry, crash reporting, remote configuration, A/B
testing, account system, user identifier, advertising identifier, fingerprinting,
or usage reporting. It makes no HTTP requests, opens no sockets, and has no
backend. It ships no third-party dependencies at all, so nothing can add any of
the above without being visible in this repository's own source.

The app works identically with networking disabled.

## How you can check

- `Bendable/Resources/Bendable.entitlements` is empty. Neither
  `com.apple.security.network.client` nor `com.apple.security.network.server` is
  requested. The CI build fails if a network entitlement ever appears in the
  signed app.
- `grep -ri "URLSession\|NWConnection\|CFStream\|Network\b" Bendable/` returns
  nothing.
- Little Snitch, LuLu or `nettop -p Bendable` will show no connections.

## What is stored on this Mac

Everything below lives in `~/Library/Preferences/com.bendable.app.plist`. That is
the only file the app writes.

| Key | Type | Meaning |
| --- | --- | --- |
| `enabled` | Bool | Whether animations run |
| `presetID` | String | Selected animation preset |
| `closingIntensity` | Double | Strength of the closing animation, 0–1 |
| `openingIntensity` | Double | Strength of the opening animation, 0–1 |
| `smoothing` | Double | Motion smoothing, 0–1 |
| `animatesClosing` | Bool | Animate when the lid closes |
| `animatesOpening` | Bool | Animate when the lid opens |
| `hingeCalibration` | Data (JSON) | Two numbers: the learned closed and fully-open hinge angles in degrees |
| `presetTuning` | Data (JSON) | Per-style effect strengths, all plain numbers between 0 and 1 |
| `hasCompletedFirstRun` | Bool | Whether the welcome screen has been dismissed |
| `debugLogging` | Bool | Whether verbose local logging is on |

Turning on "Launch at login" registers the app with `SMAppService`, which is
recorded by macOS outside the app's own storage. Turning it off removes it.

To remove everything Bendable has stored:

```bash
defaults delete com.bendable.app
```

## Hinge angles

Lid angles are read from the hardware, filtered, turned into an animation and
discarded. They are never written to disk, never aggregated, and never leave the
process, apart from the two calibration numbers above, which are bounds rather
than a history.

## Screen contents

The Fold and Crease presets capture a single still of the built-in display when the
lid starts moving. That image:

- is uploaded straight to GPU memory and never written to disk;
- is never transmitted anywhere;
- is never logged, and no logging category ever records screen contents;
- is discarded before the Mac sleeps and whenever the screen locks, so a
  pre-sleep desktop cannot survive into a locked session;
- is refreshed rather than reused once it is more than two seconds old.

Every other preset works without Screen Recording permission and never captures
anything.

## Logging

Logging uses `os.Logger` and stays on this Mac like any other system log.
Verbose tracing is off unless you enable Debug logging under Advanced in the
menu bar popover.
No log message contains screen contents.
