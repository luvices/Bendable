# Contributing

## Getting set up

```bash
git clone <your fork>
cd Bendable
scripts/test.sh          # the suite, no hardware needed
scripts/run.sh           # build, install to /Applications and restart it
```

Xcode 16 or later, macOS 14 or later. There are no package dependencies to
resolve, first-party frameworks only, and that is deliberate.

`run.sh` installs rather than launching in place, because Screen Recording is
granted per bundle path and a build run straight out of DerivedData has to be
allowed again every time.

If your checkout is on exFAT or a network share, code signing will fail there.
`run.sh` spots that and builds in `/tmp`; `build.sh` wants telling:

```bash
DERIVED_DATA=/tmp/bendable-build OUTPUT_DIR=/tmp/bendable scripts/build.sh
```

## Working without a lid

You do not need to open and close your laptop to develop. Debug builds add a
Developer section to the menu bar popover with:

- a hinge simulator that replaces the hardware provider and drives the whole
  pipeline from a slider, including a disconnect switch;
- buttons that inject every power event (sleep, wake, display off, display on,
  lock, unlock);
- live sensor readouts: raw angle, normalized progress, velocity, direction,
  update rate, capability;
- frame time and frames per second.

The popover's preview scrubber and its style thumbnails both go through the real
`AnimationEngine` and the real shader, so what they show is what the lid will show.
When something feels wrong with the tracking, measure it before changing anything:

```bash
Bendable --trace-close     # drives a simulated close through the real pipeline
```

It reports sensor samples, display link callbacks, frames drawn, frame intervals and
the step between consecutive frames. Several rounds of plausible-sounding diagnoses
were wrong before this existed.

To review a layout change without clicking through the menu bar, Debug builds
accept `--render-ui <output.png> [style|hinge|status]`, which snapshots one tab of
the popover. The Metal-backed preview does not appear in that capture, but
everything laid out around it does. To check the popover's real size and where it
lands relative to the status item:

```bash
Bendable --open-popover --exit-after      # prints geometry to stderr
```

To look at a preset across its whole travel:

```bash
scripts/render-sheet.sh fold          # -> build/snapshots/fold.png
scripts/render-sheet.sh crease
```

The app icon is drawn in code too, so it can be changed rather than replaced:

```bash
scripts/make-icon.sh                  # redraws and recuts every catalogue size
```

That runs the real presets through the real renderer (Debug builds accept
`--render-sheet <preset-id> <output.png>`), so there is no second copy of the
geometry to drift out of step.

## Adding an animation preset

This is the easiest way in, and it does not touch the sensor pipeline.

1. Add a type conforming to `AnimationPreset` in `Bendable/Animation/Presets`.
2. Implement `frame(progress:velocity:direction:context:)` as a pure function.
   Two rules: return an identity frame at `progress == 1`, or the overlay flashes
   when it appears; and handle `context.reduceMotion`, for which
   `ReduceMotionFallback` exists.
3. Add it to `AnimationPresetCatalog.all`.

The suite sweeps every catalogued preset across the full travel and checks the
output stays finite and in range, so a new preset is covered the moment it is
listed. Add its own tests for whatever it does that is interesting.

## Working on the hinge pipeline

This is where the product lives, so changes here need care.

- `HingeNormalizer` and `OneEuroFilter` are plain structs with no I/O. Keep them
  that way; the whole sensor to frame contract is tested through them.
- Latency is the feature. If a change adds smoothing, show what it costs in lag.
  `EndToEndPipelineTests` has a fast-close test for exactly this.
- New hardware paths belong behind `HingeProvider`. Nothing above that layer may
  learn where readings come from.
- The sensor is polled while the lid moves and only while it moves. The polling
  thread parks on a condition when nothing is happening, so idle cost is zero.
  Keep it that way: a timer that ticks with the lid shut is not acceptable here.
- The sensor reports whole degrees. Anything that renders straight off a reading
  will step. Frames come from the display link, and `ProgressAnimator` carries the
  value between readings.
- Nothing on the path from a sensor reading to a drawn frame may write
  `@Observable` state. That invalidates the popover and its thumbnails at the
  sensor's rate, on the same thread that is drawing. Diagnostics go through
  `publishDiagnostics`, which throttles.

## Style

Write like the surrounding code. A few things this project cares about:

- Comments explain *why* something non-obvious exists, not what the syntax does.
  Most code needs none.
- Swift concurrency: actors and `@MainActor` where they solve real isolation,
  not as decoration. No dispatch queue chains, no arbitrary delays, no sleeps.
- No force unwraps without an invariant that justifies them.
- Views stay small. If a SwiftUI view is getting long, it wants splitting. The
  popover is assembled from one file per section.
- New user-facing effect parameters belong in `PresetTuning`, with the preset
  declaring them through `supportedControls`; the popover builds its sliders from
  that, so nothing needs wiring by hand.
- Strict concurrency is on and the build is warning-free. Keep it that way.

## Before opening a pull request

```bash
scripts/test.sh
scripts/build.sh
```

Leave `MARKETING_VERSION` alone unless you mean to cut a release: pushing a change to
it publishes one.

Both must pass with no new warnings. CI runs the same thing on every push and
uploads a DMG artifact, so reviewers can try your build.

Describe what you changed and, if it touches timing or feel, how you checked it.
The preview scrubber and the contact sheet are both fair evidence.

## Reporting bugs

The Status tab of the popover has a Copy button that puts the detected capability,
the raw sensor reading, the calibration and your macOS version on the clipboard.
Please paste that in, along with your Mac model. If the hinge behaves oddly, turn on
Debug logging and attach the relevant output from
`log show --predicate 'subsystem == "com.bendable.app"'`.
