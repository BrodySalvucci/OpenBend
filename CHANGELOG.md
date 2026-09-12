# Changelog

## 0.1.0

First release.

- Lid angle from the MacBook's own hinge sensor, polled at 120 Hz.
- Live desktop capture with ScreenCaptureKit, rendered with Metal.
- Pane-of-glass projection: the desktop holds its place in space while the panel tilts over it.
- Silk, Shade and Frost styles; Perspective, Blur and Shadow sliders; adjustable clear angle.
- Step tracker for smooth, low-latency motion from a whole-degree sensor.
- Soft click when the desktop clears. Esc or the menu bar to pause. Launch at login.
- Preview Bend, for seeing the effect without touching the lid.

## 0.2.0

- Adaptive trigger: the bend starts after a few degrees of closing from wherever the lid was,
  instead of at a fixed angle. Rest above the stay-on angle and it relaxes away so you can keep
  working; below it, it holds.
- Motion tracker rebuilt around the sensor's own timestamps, with replay tests.
- Duo style, now the default: clear at the hinge, softer toward the edge.
- Settings redesigned as a native grouped window; first-run onboarding flow.
- OpenBend only takes keyboard focus once a close is committed, so lid adjustments never
  swallow typing.

## Unreleased

- True Duo style: the screen becomes the foldable, creased across the middle. The lower half stays
  put and sharp; the upper half folds down toward you and frosts over with a hard edge at the crease,
  shrinking toward it as the lid comes down.
- A custom mix now remembers which optics it started from (`optics`), so Duo and True Duo mixes keep
  their look. The old `useDuoOptics` flag is migrated.
