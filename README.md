# notime

notime blocks the apps and Safari websites you choose, using Screen Time. From the shield you
can open a blocked app or site for a few minutes after a short wait. Each opening makes the
next wait longer. There are no accounts and no network code. The only outbound link is
"Made by Patrick" at the bottom of the main screen; it opens stillh.art in Safari
only when tapped.

## Build

Requirements: Xcode 26+ (Swift 6), XcodeGen.

```sh
xcodegen generate
xcodebuild -project notime.xcodeproj -scheme notime \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Pure domain tests (run on the Mac host)
cd Packages/NotimeCore && swift test
```

Layout:

- `Notime/` – the SwiftUI app (`Features/<Screen>/`).
- `Extensions/` – `NotimeShieldConfiguration`, `NotimeShieldAction`, `NotimeMonitor`.
- `Packages/NotimeCore/` – shared core: `Domain/` (pure), `Persistence/`, `Service/` (`NotimeService`),
  `ScreenTime/` (the only files importing ManagedSettings/DeviceActivity, compiled on iOS only).
- `Config/` – Info.plists and entitlements, generated from `project.yml`, and the privacy
  manifest `PrivacyInfo.xcprivacy` shared by all four targets (no tracking, no collected data,
  app-group `UserDefaults` with reason `1C8F.1`). Xcode targets: `notime`
  (app), `notime-shield`, `notime-shield-action`, `notime-monitor`; folders and Swift types keep
  their `Notime…` names.

## Running on a device

- Screen Time APIs do not work in the Simulator. The simulator build only proves it compiles.
- The `com.apple.developer.family-controls` entitlement is required by the app and all three
  extensions. With a development team it works for development builds on a real device;
  the first launch asks for Screen Time authorization (`.individual`), which must be allowed.
- Distributing through TestFlight or the App Store requires requesting the **Family Controls
  (Distribution)** entitlement from Apple for each bundle id
  (`art.stillh.notime`, `.shieldconfiguration`, `.shieldaction`, `.monitor`).
- All four targets share the app group `group.art.stillh.notime`, where the state lives.

## The shield

A blocked app or site shows a shield in system colours (`.systemBackground` background,
`.label` text, the host's default button) that the host resolves at draw time, so it follows
light and dark; the extension never reads traits itself. The icon is a grey shield with the hands cut out, readable on both:

```
notime
Blocked. Opened 2× today.
[ Open for 12 min ]
```

- The one button opens the app or site for the access length from Settings (default 12 min).
- The first tap does not open. It starts the wait for this opening and the shield says, for
  example, "wait 1m 40s". A tap during the wait shows what is left ("wait 37s"). A tap once the wait is over opens. A wait not used within 5 minutes
  after it ended is dropped and the next tap starts over. A wait of 0 opens on the first tap.
- After an opening the action answers `.defer`, so the system asks for the shield again,
  finds the target unshielded and shows the app.
- There is no Close button; swipe home to leave.
- "Blocks shown" is counted when the shield is rendered: in `state.json` if possible,
  otherwise in the app group's shared `UserDefaults` (`impressions.<day>.<target>`,
  `lastImpression.<target>`), which the app's reconcile and every tap fold into `state.json`.
  On some devices the shield process can save neither, so every tap on "Open" also counts one
  impression for that app or site, unless one was already counted for it in the last 30 s.
  The re-renders the system asks for after a tap (`.defer`) are not counted: a render is
  skipped when that app or site had an impression in the last 30 s or its wait is running.
- The shield renders from a read of `state.json` without the lock, so it works even if that
  process may not take the lock or write files.

## The wait grows

Settings, on the main screen (tap a row to change it): access length (default 12 min, 1–120),
wait before opening (default 40 s, 0–180), added per opening (default 10 s, 0–300). The wait
never grows beyond 3 minutes (fixed, not a setting).

The wait before the n-th opening of an app or site today is
`min(wait + (n - 1) × added, 180)` seconds: 40 s, 50 s, 1 min, 1 min 10 s … up to 3 min
with the defaults. The length of an access does not matter, only the number of openings.
Counts reset at local midnight. After an access ends the app or site is shielded again and
can be opened at once after its (longer) wait.

The window ends, and the shield comes back, at whichever happens first:

- the target has been **used** for the N minutes it was opened for (a Device Activity usage threshold event);
- a **wall-clock** interval of `max(N, 15 min) + 1 min` ends (Device Activity rejects
  intervals shorter than 15 minutes, so a 5-minute access can take up to 16 minutes of
  *idle* time to close by this path);
- the notime app is opened, the shield action or monitor extension runs, or the daily sweep
  fires: each of these reconciles state (expires grants, drops old waits, prunes stats,
  re-applies shields from the saved state, stops orphaned monitoring). The shield
  configuration extension only renders and counts; it never writes shields.

A grant whose Device Activity is no longer monitored is ended at the next reconcile even
before its time is up, since nothing else would re-shield it (a grant younger than a minute
is kept, while its monitoring starts).

**Daily sweep:** a repeating daily Device Activity, `sweep` (00:00–23:59), wakes the monitor
extension at the start and end of every day to reconcile, even if notime is never opened
again. The app starts it on every reconcile if it is missing, and the monitor extension
whenever it runs.

A usage threshold reported earlier than N minutes minus 30 seconds is ignored (iOS 17/18
can fire one right after monitoring starts); the wall-clock interval end then covers it.
On iOS 17.4+ the threshold event is created with `includesPastActivity: false`.

Each access gets its own Device Activity (`grant-<uuid>`), so several can run at once and
none is stopped by another. If monitoring cannot be started, the access is refused and the
shield stays (fail closed).

**Categories:** if you block a whole category, its shields only offer **Close** and say
"Blocked." notime never opens an entire category. Home says so under the blocked list.
Pick individual apps or sites to be able to open them.

## Persistence and failing closed

Two JSON files in the app group container, each written atomically (temp file + rename):

- `state.json` – the small "hot" state (settings, selection, open grants, waits, today's
  counters). Read and written by the app and all extensions. Every load-change-save runs under
  an exclusive `flock` on `state.lock`; shields are applied and orphaned monitoring stopped
  right after the save, before the lock is released, so they always match the saved state.
  Monitoring is started only after the lock is released; a new grant unshields its target
  only once its monitoring runs. The
  extensions keep at most today and the 7 days before it here.
- `history.json` – past days' counters, at most 90 days. When the app or the monitor
  extension reconciles, past days move from the hot state into history, inside the state lock
  (which serializes every history writer); counts for a day already in history are added to
  it. The shield extensions (about 6 MB) never decode it. The Stats screen sums both.

Only the app may start fresh or recover. In the app, a missing `state.json` means a fresh
start, and a corrupt one is moved aside (by the first load or save that finds it) to `state.corrupt.json`; notime then starts fresh and
Home says "Settings could not be read and were reset. Choose apps again."

The extensions never create, recover or move these files. Unless `state.json` exists and
decodes, they save nothing and leave the shields exactly as they are. The shield for an app
or site still offers both buttons and says why it shows nothing more:
"Blocked. notime could not read its settings." (unreadable) or "Blocked. Open notime once
to finish setup." (no file yet). The shield action extension is the gate: without readable
state it refuses with `.close`. The same applies when the app group container is missing.

The state, history and lock files are written with no data protection
(`FileProtectionType.none`): they hold only opaque Screen Time tokens and counters, and this
lets the monitor extension re-shield before the first unlock after a reboot.

## Main screen

Two intro steps share one centred layout: Screen Time access, then (while nothing is blocked)
"Choose what to block", which opens Apple's picker.

One screen, top to bottom: **Blocked** (the selection, "Choose apps and websites", and the
category notice when categories are selected), **Settings** (the three rows above, each opens
a number field), **Today** (blocks shown, times opened, and a link to Stats), and the
"Made by Patrick" link.

**Stats** has a full-width period picker, a bar chart of blocks shown per day (the last 7 days
for "Today" and "Last 7 days", the last 30 for "All time"; counts are kept per day, so there
is no hourly chart), the totals, and a list per app or website.

## App icon

The app icon is a hand-drawn black shield with clock hands at ten past ten, in
`Notime/Assets.xcassets/AppIcon.appiconset/` (with a dark variant). The same shield, with the
hands transparent, is `Shared/ShieldMark.xcassets/ShieldMark.imageset/ShieldMark.png`, a
template image bundled with the app and the shield extension: the in-app mark draws it in the
text colour, the shield's icon in a fixed grey.

## Known limits

- notime refuses a selection of more than 50 apps and websites combined (categories excluded),
  because a shield set holds at most 50; the previous selection is kept.
- iOS allows about 20 concurrently monitored activities; the daily sweep uses one.
- The shield text only changes when the shield is shown again (after a tap or on reopening),
  so the wait does not count down live.
- An access is not shortened when the app is closed early; it ends after its usage time or
  its wall-clock interval.
- Changing the device clock skips the wait (waits are measured against the wall clock).
