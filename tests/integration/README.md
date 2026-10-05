# On-request echo-cancellation validation

This is a candidate for WirePlumber issue #1031. It is not an accepted upstream
fix or a claim of successful Librem 5 acoustic testing.

## Reproduce the automated exercise

The fork workflow `on-request-validation.yml` builds pinned PipeWire and this
WirePlumber branch on Ubuntu 24.04. It runs the complete Meson test suite and
starts a separate PipeWire/PulseAudio/WirePlumber session for the integration
exercise. The session uses a private temporary runtime directory, synthetic
source/sink nodes and real WebRTC AEC nodes. It does not access a host microphone.

The Python exercise requires an installation prefix containing `pipewire`,
`pipewire-pulse`, `pw-dump`, `wireplumber` and the WebRTC AEC SPA plugin, plus
`pacat` and `parec` in PATH:

```sh
WP_TEST_PREFIX=/path/to/prefix dbus-run-session -- \
  python3 tests/integration/echo-cancel-on-request.py
```

Checks cover normal playback, simultaneous capture/playback requests,
`filter.apply`, suppression, shared instances, final teardown and repeated calls.
The Lua tests additionally exercise request precedence, the phone-role heuristic,
permanent-chain isolation, target mismatches and failed module-load lifetimes.

## Boundaries to review

- `filter.smart.on-request` defaults to false, preserving ordinary smart filters.
- Request-only entries do not become shared stages after permanent filters.
- The optional loader supports one configured or default microphone/speaker pair.
  It does not allocate arbitrary per-application device pairs.
- An explicit reference to the current default honors a filter request without
  adding unrelated permanent filters. Both configured and default pairs are tested.
- Explicit unrelated targets, role-policy targets and audio groups retain their
  existing policies; these cases need device-policy review, not silent overrides.
- Missing configured targets do not cause the filter's internal streams to fall
  back to another device. Application route preferences are not rewritten.
- PulseAudio-specific parameter strings are not injected into module arguments.

## Device validation still required

A reviewer with an existing Mobian/PureOS test device should first review the
patch and the project's AI contribution requirements. No one should replace
production audio components just because synthetic CI passed.

On an isolated/test installation, record the PipeWire and WirePlumber versions,
`wpctl status -n`, `pw-dump` and the exact communication application/operation.
Compare the same call with the original and candidate policy. Check that:

1. The requesting call uses AEC and acoustic echo is actually reduced.
2. Other playback/capture streams keep their device and saved route.
3. Switching speaker/headset routes obeys the phone's intended-role policy.
4. Closing, reopening and cancelling calls releases/recreates the filter cleanly.
5. Removing a selected device does not produce an unintended target or feedback.
6. The application recognizes the filtered source correctly; for example, Jami
   has its own PulseAudio driver-name-based AEC detection which merits checking.

Keep test-device dumps private or redact identifying device/application data
before sharing. Upstream acceptance and the sponsor's done criteria remain
separate from automated test success.
