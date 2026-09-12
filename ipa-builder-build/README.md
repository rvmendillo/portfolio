# ReyForge 2.7

Native SwiftUI rebuild of the final 2.6 source, commit
56b885c2e24889acb1beb1871281866762d0ad85.

Preserves the component editor, templates, Apple Foundation Models screen
planner, live preview, WidgetKit configuration, GitHub IPA builds, local
signing and installation without a custom root certificate.

## Changes

- ReyForge has its own bundle ID: `com.rvmendillo.reyforge`. The old released
  binary used the built-in profile's fixed App ID. That shared identity can
  cause app switching and installation collisions. No Spotify URL scheme is
  registered by this app.
- The signer reads the imported profile, checks expiration and identity
  authorization, and rejects identities belonging to the running app.
- Signed output is one immutable record containing the file, actual app
  identity and version. It survives relaunch, and is invalidated when another
  IPA or profile is imported or a new signing attempt starts.
- Signing imports are staged before replacement. IPA imports get unique
  filenames. The selected generated IPA can be restored after importing one.
- The installer uses the signed file's metadata, token-scoped loopback URLs,
  bounded request headers, streamed file transfers and HTTP byte ranges.
  Connection state is isolated from the UI and old server callbacks cannot
  restart a cancelled installation. It reports handoff, not installation
  success.
- New and duplicated projects receive distinct bundle IDs. Projects can be
  switched from the iPhone toolbar. The editor opens on its canvas and editing
  taps are no longer intercepted by the preview controls.

## Build and validation

The workflow `.github/workflows/build-reyforge-2-7.yml` runs on macOS 26.
It compiles the actual identity/manifest code with regression fixtures,
generates the Xcode project, applies the two existing Zsign compatibility
fixes, builds arm64 iOS, and validates the packaged identity.

The artifact is **unsigned**. It requires iOS 26 or later and signing with a
profile that permits `com.rvmendillo.reyforge` (or a matching wildcard).
The old fixed profile cannot authorize this new identity. No signing keys
or fixed provisioning profile are embedded in the build.

An iOS device is required to verify the reported Spotify status-bar return
behavior and the final installation handoff. Those behaviors cannot be
confirmed solely by a compiler or archive check.

Changing the app identity gives the app a separate iOS data container.
Existing projects in the old installation are not automatically migrated.
Keep the old installation until any needed project data has been recovered.
