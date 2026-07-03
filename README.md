# MyWatch ⌚️ — your wellness watch app

A beautiful Apple Watch app that shows your **stress level** (from heart-rate
variability, like StressWatch / Welltory) and reminds you to **drink water**,
**take medication**, and **eat regular meals** — all the paid-app features,
in an app that's 100% yours and free.

This guide assumes you've **never built an Apple app before**. Follow it top to
bottom and you'll have it running on the watch Simulator.

---

## What's inside

| Tab | What it does |
|-----|--------------|
| 🫀 **Stress** | A 0–100 stress score from your HRV + resting heart rate, with a color ring, advice, signal cards, and a trend sparkline. Alerts you when stress is high. |
| 💧 **Hydration** | Animated fill ring, one-tap quick-add (200/350/500 ml), daily goal, 🎉 celebration, and adjustable daily reminders. |
| 💊 **Medication** | Add meds with dose times, get reminders, tap "Taken" to log, see today's adherence. |
| 🍽️ **Meals** | Toggleable reminders for breakfast/lunch/dinner and one-tap meal logging. |

> **No real health data?** On the Simulator there's no real HRV, so the Stress
> tab shows a realistic simulated score so everything looks alive. On a real
> Apple Watch it uses your genuine Health data once you grant access.

---

## Step 1 — Install Xcode (one time, ~1 hour download)

You currently have only the *Command Line Tools*, not the full Xcode, so the app
can't be built yet.

1. Open the **App Store** on your Mac.
2. Search **Xcode** → **Get / Install** (it's free, but large — 10+ GB).
3. After it installs, open it once and accept the license. Then in Terminal run:
   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcodebuild -runFirstLaunch
   ```
4. Install a watchOS Simulator if prompted: Xcode ▸ Settings ▸ **Components** ▸
   add the latest **watchOS** runtime.

## Step 2 — Open the project

Double-click **`MyWatch.xcodeproj`** in this folder (or run `open MyWatch.xcodeproj`).

## Step 3 — Pick a run destination

At the top of Xcode, next to the ▶︎ button, click the device selector and choose
an **Apple Watch Series … (Simulator)** destination.

## Step 4 — Run it ▶︎

Press the ▶︎ **Run** button (or `Cmd+R`). The watch Simulator boots and MyWatch
launches. Swipe up/down to move between the four tabs.

> **If you see a signing error** ("requires a development team"): click the
> **MyWatch Watch App** target ▸ **Signing & Capabilities** ▸ set **Team** to
> your free personal Apple ID (Add an Account…). That's all that's needed for the
> Simulator and for installing on your own watch.
>
> Prefer to skip signing entirely for now? In **Signing & Capabilities** remove
> the **HealthKit** capability — the app still runs fully in simulated-stress
> demo mode.

## Step 5 — Install on your real Apple Watch *for free* (no $99/year)

A **free Apple ID** can sign and install the app on your own watch. The only
catch: a free "personal team" build **expires after 7 days** — just re-run from
Xcode (≈1 min) to renew it. Local notifications and HealthKit both work on a free
account; only App Store publishing needs the paid program.

|                | Free Apple ID | Paid program ($99/yr) |
|----------------|---------------|------------------------|
| Install on own watch | ✅ | ✅ |
| App validity   | ⚠️ 7 days, then re-install | 1 year |
| Max installed apps | 3 | unlimited |
| Local reminders / HealthKit | ✅ | ✅ |
| App Store release | ❌ | ✅ |

Steps:
1. **Xcode ▸ Settings ▸ Accounts** → add your Apple ID (free).
2. **MyWatch Watch App** target ▸ **Signing & Capabilities** ▸ **Team** = your
   personal account. Xcode auto-creates the certificate/profile. If the bundle ID
   is taken, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to something
   unique (e.g. `com.yourname.MyWatch.watchkitapp`) and re-run `xcodegen generate`.
3. Turn on **Developer Mode** on *both* iPhone and Watch:
   Settings ▸ Privacy & Security ▸ Developer Mode ▸ On (the watch reboots).
4. Connect the iPhone (that's paired with your watch) to the Mac via cable.
5. In Xcode pick your **real Apple Watch** as the destination and press ▶︎.
6. First launch shows "Untrusted Developer": on the watch go to
   Settings ▸ General ▸ VPN & Device Management ▸ trust your developer cert.
7. Accept the Health and Notifications prompts on the watch.

> **Renewing weekly (easiest):** when the app stops opening after ~7 days, make
> sure the watch is unlocked/on-wrist/same-Wi-Fi, then in this folder run:
> ```sh
> ./reinstall.sh
> ```
> It recompiles, reinstalls, and relaunches MyWatch on the watch in one step.
> Your logged data stays (it's stored on the watch). You can also just press ▶︎
> in Xcode with the watch selected — bundle ID and team are already configured.

**This app is configured for:** bundle ID `com.lichaochen.mywatch.wk7c33q9`,
team `4G3UA8VU4M` (Vincent Li, Personal Team).

---

## Project layout

```
MyWatch Watch App/
  MyWatchApp.swift        App entry point
  Theme.swift             Colors & gradients (the look)
  Models.swift            Data types (stress, hydration, meds, meals)
  HealthManager.swift     HealthKit → stress score
  NotificationManager.swift  Local reminder scheduling
  AppStore.swift          Single source of truth + persistence
  Views/                  One file per tab + reusable components
  Assets.xcassets/        App icon slot + accent color
project.yml               Project definition (regenerate with `xcodegen generate`)
```

### Regenerating the project

If you add/rename files or change settings, run:
```sh
xcodegen generate
```
(Install once with `brew install xcodegen`.) You normally don't need this — just
edit code in Xcode.

---

## Make it yours — easy tweaks

- **Colors:** edit the gradients in `Theme.swift`.
- **Default meals / meds:** see `seedDefaults()` in `AppStore.swift`.
- **Hydration goal & quick-add amounts:** `HydrationView.swift`.
- **Stress formula:** `stressScore(...)` in `HealthManager.swift`.
- **App name on the watch:** `CFBundleDisplayName` in `project.yml`.

## Add a real app icon

Drop a 1024×1024 PNG into `Assets.xcassets/AppIcon.appiconset/` and set it as the
icon image in Xcode's asset editor. (It runs fine without one.)
