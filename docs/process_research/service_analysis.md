# REAPER Service Analysis

Deep research on each service category with evidence-based recommendations.

---

## Xbox Services - **VERDICT: DISABLE ALL**

| Service | Name | Research Finding | Recommendation |
|---------|------|------------------|----------------|
| XblAuthManager | Xbox Live Auth | Only for MS Store games/Game Pass. Steam/Epic don't use it. | **DISABLE** |
| XblGameSave | Xbox Cloud Saves | Only syncs saves for Xbox Play Anywhere titles | **DISABLE** |
| XboxNetApiSvc | Xbox Networking | Peer-to-peer for Xbox Live multiplayer only | **DISABLE** |
| XboxGipSvc | Xbox Accessories | Only if using Xbox controller. Standard gamepads work without. | **DISABLE** |

**Source**: Xbox services are specifically for Microsoft's gaming ecosystem. If you use Steam, Epic, or GOG, these provide zero functionality.

**Impact of disabling**: Cannot sign into Xbox App, cannot use Game Pass, cannot sync Xbox cloud saves. Standard PC gaming unaffected.

---

## Steam Services - **VERDICT: SET MANUAL**

| Service | Research Finding | Recommendation |
|---------|------------------|----------------|
| Steam Client Service | Steam starts this on-demand when needed for game installs/updates. Does NOT need to run constantly. | **MANUAL** |

**Impact**: Steam launches ~1 second slower. Games work normally.

---

## Microsoft Office - **VERDICT: SET MANUAL**

| Service | Research Finding | Recommendation |
|---------|------------------|----------------|
| ClickToRunSvc | Only actively needed during Office updates/repairs. Office apps start it on-demand. | **MANUAL** |

**Impact**: Office apps may take 1-2 seconds longer to launch first time. Updates still work.

---

## ASUS/ROG Services - **VERDICT: MOSTLY DISABLE**

| Service | Research Finding | Recommendation |
|---------|------------------|----------------|
| ArmouryCrateService | RGB, performance profiles. Bloatware. Hardware works without it. | **DISABLE** |
| AsusFanControlService | Controls fan curves. **If using custom curves, KEEP.** If using BIOS defaults, disable. | **CAUTION** |
| ROG Live Service | Auto-updates, "features". Pure bloat. | **DISABLE** |
| AsusCertService | Certificate management for ASUS software | **DISABLE** |
| asComSvc | COM interface for ASUS apps | **DISABLE** |
| asus | Software manager | **DISABLE** |

**Impact**: Lose RGB control, performance profiles. Hardware runs fine on BIOS defaults.

---

## Razer Services - **VERDICT: DISABLE ALL**

| Service | Research Finding | Recommendation |
|---------|------------------|----------------|
| Razer Chroma SDK Service | RGB sync with games. Games work fine without RGB. | **DISABLE** |
| Razer Chroma SDK Server | Hosts Chroma apps | **DISABLE** |
| Razer Chroma Stream Server | Streams RGB to other apps | **DISABLE** |
| CortexLauncherService | "Game booster" - placebo effect, no real benefit | **DISABLE** |
| Razer Game Manager Service | Detects games for profiles | **DISABLE** |
| RzActionSvc | Macro handling. Only if you use complex macros. | **DISABLE** |
| Razer Elevation Service | Admin tasks for Synapse | **DISABLE** |

**Impact**: Lose RGB sync and custom DPI profiles stored in cloud. Device-onboard memory profiles still work.

---

## WSL Service - **VERDICT: CONDITIONAL**

| Service | Research Finding | Recommendation |
|---------|------------------|----------------|
| WSLService | Only needed if actively using WSL or Docker with WSL2 backend | **KEEP if using Docker/WSL** |

**Impact**: Cannot start WSL distros or Docker containers (if using WSL2 backend).

---

## Updater Services - **VERDICT: DISABLE ALL**

| Service | Research Finding | Recommendation |
|---------|------------------|----------------|
| edgeupdate/edgeupdatem | Edge updates via Windows Update anyway | **DISABLE** |
| GoogleUpdater* | Chrome updates when launched | **DISABLE** |
| LGHUBUpdaterService | G Hub updates when launched | **DISABLE** |
| brave | Brave updates when launched | **DISABLE** |
| EpicGamesUpdater | Launcher updates when opened | **DISABLE** |

**Impact**: Apps update when you open them instead of constantly polling in background.

---

## Telemetry Services - **VERDICT: DISABLE**

| Service | Research Finding | Recommendation |
|---------|------------------|----------------|
| DiagTrack | Primary telemetry. Causes disk spikes. | **DISABLE** |
| dmwappushservice | WAP push for telemetry | **DISABLE** |

**Impact**: Microsoft receives less usage data. No functional impact.

---

## KEEP List - Do Not Disable

| Service | Why Keep |
|---------|----------|
| SecurityHealth | Windows Defender tray. Security monitoring. |
| RtkAudUService | Realtek audio driver service |
| Spooler | Only if you have a printer |
| Bluetooth Support | Only if using Bluetooth |
| WSearch | Windows Search. Disable only if never searching files. |

---

## Profile Recommendations

### Developer Workstation
```yaml
disable:
  - All Xbox services
  - All Razer/ASUS RGB services
  - All updater services
  - Telemetry
keep:
  - WSL (if using Docker)
  - Audio services
  - Security
```

### Gaming PC (Steam/Epic)
```yaml
disable:
  - Xbox services (not using Game Pass)
  - Telemetry
  - Updater services
manual:
  - Steam Client Service
  - RGB services (if you want RGB, set to manual)
```

### Gaming PC (Game Pass)
```yaml
keep:
  - XblAuthManager
  - XblGameSave
  - GamingServices
disable:
  - Everything else from bloat list
```
