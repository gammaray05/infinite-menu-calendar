# InfiniteCalendar

A native, offline macOS menu bar calendar with continuous bidirectional month scrolling. Swift, SwiftUI and AppKit; macOS 14+; Apple Silicon. No external dependencies, events, accounts, networking, permissions or telemetry.

## Download and install

In GitHub **Actions → Build Release DMG**, open the latest successful run and download **InfiniteCalendar-macOS-AppleSilicon** under Artifacts. Extract the ZIP, open `InfiniteCalendar.dmg`, and drag the app into Applications. GitHub requires sign-in for artifact downloads. See [installation instructions](INSTALL.md), including first-launch approval for this ad-hoc signed, non-notarized build.

## Architecture

- `Sources/CalendarCore/CalendarEngine.swift`: Foundation calendar arithmetic, variable week rows, DST-aware days and a bounded 121-month coordinate window.
- `CalendarScrollView.swift`: native NSScrollView and a virtual document view drawing only visible months. At either edge it rebuilds around the visible month and compensates the clip origin by the exact pixel offset. Native wheel and momentum events continue over the entire view, including day numbers. Date metadata is bounded; there is no growing view hierarchy.
- `AppDelegate.swift`: NSStatusItem, transient NSPopover, settings window, Escape handling, day/timezone/locale refresh and remembered scroll position. No primary window and no Dock icon.
- `Views.swift`: SwiftUI header and settings; colors, themes, sizes, local language, week numbers and SMAppService login registration.
- `Preferences.swift`: local UserDefaults persistence; system calendar and timezone, regional first weekday and calendar language. Calendars with leap months are handled by Foundation month intervals rather than a fixed twelve-month assumption.

Hover animations run for 120 ms only while changing hovered days. Reduce Motion disables hover and popover animation. Today navigation animates nearby movement and jumps directly over distant dates. VoiceOver exposes the visible dates with full localized labels. Arrow keys navigate dates; Page Up/Down scroll; Home returns to today.

## Build with Xcode (optional)

Open `InfiniteCalendar.xcodeproj`, select the `InfiniteCalendar` scheme, choose My Mac, and Build / Run. The project is included and needs no project-generation dependencies. The Swift package can also be opened in Xcode. To regenerate the included project after adding source files, run `python3 scripts/generate_project.py`.

```sh
swift test --configuration release
bash scripts/build-release.sh
```

The release script invokes Xcode's Release compiler for arm64, creates the native app icon, signs the bundle ad hoc, validates it, creates the compressed DMG, and verifies the image. GitHub Actions additionally mounts the image, checks its contents, launches a copied app and checks process survival. The DMG and SHA-256 checksum are retained as an artifact for 90 days. Push to `main` or choose **Run workflow** to rebuild.

## Validation scope

Automated tests cover leap years including century rules, Monday/Sunday alignment, four/five/six-week months, DST across four timezones, December/January, Gregorian/Hebrew/Islamic/Buddhist/Japanese calendars, 1,000 coordinate recentrings and large scroll jumps. CI validates compilation, packaging, signatures and basic process launch. Trackpad feel, VoiceOver interaction, multi-monitor behavior and login registration require interactive testing on a Mac; automated process launch does not certify these experiences. Foundation's representable date range is finite, but navigation is not limited to a fixed user-facing date range.

Notarized distribution requires an Apple Developer ID certificate and notarization credentials; this repository's default workflow uses no signing secrets.
