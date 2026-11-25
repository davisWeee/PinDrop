# PinDrop

Choose, test and move an iPhone's reported location from one Apple Maps interface — for development, QA and personal testing on a device you own.

Open-source iOS app (SwiftUI + a Rust bridge over [idevice](https://github.com/jkcoxson/idevice)). iOS 27+.

## Status
Derived from the MIT-licensed 0.9.0-beta.1 public snapshot of an earlier open-source project (see `LICENSE`, `THIRD_PARTY_NOTICES.md`), then extended independently.
Roadmap lives in [`ROADMAP.md`](ROADMAP.md).

## Get an IPA
Every push to `main` builds an **unsigned IPA** in GitHub Actions (runner `xcode-27`). Download it from the Actions run artifacts and sign/install it yourself (SideStore, AltStore, Sideloadly, LiveContainer, or Xcode).

## Build yourself
1. Open `RoamControl.xcodeproj` in Xcode 27+.
2. Set your Team in Signing & Capabilities (or `Configuration/Local.private.xcconfig`, see the `.example`).
3. Run on a device. The pairing engine (`Frameworks/RoamPairingFFI.xcframework`) is prebuilt; to rebuild it from `Native/RoamPairingFFI` run `scripts/build-pairing-engine.sh`.

## Responsible use
Location simulation affects every app on the phone. Use it only on devices you own, and restore the real location afterwards.
