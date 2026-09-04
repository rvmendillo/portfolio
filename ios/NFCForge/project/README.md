# NFC Forge

A native SwiftUI + Core NFC reader/writer for iPhone.

## Features
- Read NDEF tags and decode Text, URI, phone, email, SMS, geo, vCard, JSON, MIME, external and raw records.
- Compose multi-record NDEF messages.
- Write writable NDEF tags with capacity checking.
- Permanently lock supported tags read-only with a confirmation step.
- Erase writable NDEF messages where the tag supports an empty NDEF message.
- Inspect ISO 7816, ISO 15693, FeliCa and MIFARE tag type / identifier data exposed by iOS.
- Scan history, templates, copy latest NDEF records back into the writer, custom raw records.
- Native iOS interface, dark mode, app icon.

## Important platform limits
- NFC scan sessions are foreground/user initiated and require a real supported iPhone.
- Core NFC does not give unrestricted access to payment-card or access-card secrets.
- NDEF copy copies standard NDEF records, not protected credential sectors.
- Some ISO 7816/FeliCa applications require specific AIDs/system codes in the app configuration and matching Apple entitlements.
- `writeLock` is irreversible on tags that implement it.

## Build
1. `brew install xcodegen`
2. `xcodegen generate`
3. Open `NFCForge.xcodeproj` in Xcode.
4. Set your Development Team and make sure the App ID has **Near Field Communication Tag Reading** enabled.
5. Run on a physical iPhone.

## GitHub Actions IPA
The included workflow produces:
- a **signed installable IPA** when signing secrets are configured; or
- an **unsigned IPA** fallback for later signing.

Signing secrets:
- `IOS_CERTIFICATE_BASE64` — base64 of your `.p12`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISION_PROFILE_BASE64` — base64 of `.mobileprovision`
- `IOS_PROVISION_PROFILE_NAME`
- `IOS_TEAM_ID`

The provisioning profile must include the NFC Tag Reading capability and match `com.rvmendillo.nfcforge` (or change the bundle ID in `project.yml`).
