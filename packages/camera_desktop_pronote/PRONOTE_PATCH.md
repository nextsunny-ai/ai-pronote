# AI PRONOTE camera_desktop patch

This package is vendored from `camera_desktop` 1.2.1 under its MIT license.

AI PRONOTE changes:

- Select the camera frame rate closest to the requested rate at the chosen
  resolution instead of always selecting the highest available rate.
- Preserve the device media type's exact fractional frame-rate ratio in the
  Media Foundation record sink. This avoids accumulated timestamp drift and
  non-monotonic DTS values in long Windows recordings.

The upstream license is retained in `LICENSE`.
