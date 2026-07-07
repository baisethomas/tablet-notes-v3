---
name: sim-verify
description: Verify TabletNotes behavior on the iOS simulator and do forensics on its state — building/installing/launching via simctl, capturing print() output reliably, inspecting the SwiftData store with sqlite3, reading UserDefaults reset flags, and staging upgrade/fresh-install/migration-failure scenarios. Use when a change needs on-device verification (recording, sync, restore, migration), when reproducing a device-only bug, or when acceptance tests specify upgrade/reset scenarios.
---

# Simulator verification & forensics

Simulator work in this repo has hard-won quirks: `print()` doesn't reach `log show`, Xcode ⌘R silently dodges migration scenarios, and the interesting state lives in a sqlite store and a UserDefaults plist inside the app container. This skill encodes what actually works.

## 0. Ground rules

- **iOS 18.5 simulator required** (18.4 fails the deployment-target check). Known-good: `2BAC53A3-EC5B-40DE-A981-7F7A637A555E` (iPhone 17 Pro sim `974B2050…` was used for TAB-53 acceptance). Find one: `xcrun simctl list devices available | grep -i "18.5" -A 20`.
- **Simulators start with no signed-in account.** Anything behind auth (sync, restore, most flows) needs the owner's account — a fresh sim launches at Sign In and stops there. If the verification needs auth and you can't get past it, produce an exact manual test script for the owner and report the verification as *pending owner*, not done.
- Never fabricate a verification. "Build succeeds and the code reads right" is not "verified on device."

## 1. Build, install, launch

```bash
UDID=2BAC53A3-EC5B-40DE-A981-7F7A637A555E
xcrun simctl boot $UDID 2>/dev/null; open -a Simulator

xcodebuild build -scheme TabletNotes -destination "platform=iOS Simulator,id=$UDID"

# Locate the built .app (DerivedData path from build settings):
APP=$(xcodebuild -scheme TabletNotes -destination "platform=iOS Simulator,id=$UDID" \
      -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{d=$3}/ FULL_PRODUCT_NAME/{n=$3}END{print d"/"n}')

xcrun simctl install $UDID "$APP"
xcrun simctl launch $UDID Creative-Native.TabletNotes   # verify bundle id: check Info.plist / build settings if launch fails
```

**Critical distinction:** Xcode ⌘R (and reinstalling after `simctl uninstall`) creates a **fresh app container** — the old SwiftData store is gone, so migration/upgrade paths are silently skipped. To test against an existing store, `simctl install` the new build **over** the old one on the same device and launch with `simctl launch`. This exact mistake made a migration bug unreproducible until caught (TAB-53).

## 2. Capturing app output

`print()` output does **not** appear in `log show`/`os_log` streams. Options, in order of reliability:
1. **Xcode console** (run from Xcode) — reliable, use when interactivity is fine.
2. `xcrun simctl launch --console-pipe $UDID <bundle-id> | tee /path/to/log` — works but **flaky: often drops output after the first burst.** stdout is block-buffered; **terminate the app** (`xcrun simctl terminate $UDID <bundle-id>`) to flush the remainder. Expect partial capture; corroborate with state inspection (§3) rather than trusting the log alone.
3. For durable diagnostics, prefer asserting on *state* (store rows, plist flags) over log lines.

## 3. Forensics: inspecting app state

Find the app's data container:
```bash
CONTAINER=$(xcrun simctl get_app_container $UDID Creative-Native.TabletNotes data)
```

**SwiftData store** (Core Data-backed sqlite; entities are `Z`-prefixed, columns uppercase):
```bash
sqlite3 "$CONTAINER/Documents/TabletNotes.store" ".tables"
sqlite3 "$CONTAINER/Documents/TabletNotes.store" \
  "SELECT COUNT(*), ZSYNCSTATUS FROM ZSERMON GROUP BY ZSYNCSTATUS;"
sqlite3 "$CONTAINER/Documents/TabletNotes.store" \
  "SELECT ZTITLE, ZAUDIOFILENAME FROM ZSERMON ORDER BY ZCREATEDAT DESC LIMIT 10;"
```
Read-only by default; **close the app first** if you must write (you almost never should — and never on a store you're about to use as test evidence).

**UserDefaults / reset & recovery flags:**
```bash
plutil -p "$CONTAINER/Library/Preferences/Creative-Native.TabletNotes.plist" | grep -i -E "reset|recover|restore|migrat"
# Expect keys like did_reset_local_store, local_store_reset_reason
```

**Audio files:** recordings live under the container's Documents — compare filenames against `ZAUDIOFILENAME` to find orphans (audio without a row) or ghosts (row without audio).

**Cross-check against cloud** (read-only prod query, CLAUDE.md §8): local count vs cloud count for the signed-in user is the canonical "did restore/sync complete" check (e.g. 119 local vs 180 cloud exposed TAB-55).

## 4. Staging the standard scenarios

**A. Upgrade-in-place (existing store, new build)** — the regression that matters after any `@Model` change:
1. Install & use the *old* build (main) far enough to create data; confirm rows exist (§3).
2. `simctl install` the *new* build over it (same UDID, no uninstall) and `simctl launch`.
3. PASS = data intact, `did_reset_local_store` absent/false, no reset reason in the plist.

**B. Fresh install + cloud restore:**
1. `xcrun simctl uninstall $UDID <bundle-id>`, install new build, launch, sign in (owner account needed).
2. PASS = restore UX shows ("Loading your recordings…"), then local sermon count == cloud count for that user, flags cleared.

**C. Incompatible/corrupt store → graceful reset & lossless recovery:**
1. With the app terminated, corrupt the store: `printf 'garbage' > "$CONTAINER/Documents/TabletNotes.store"` (or truncate it). **This is destructive — only on a sim/store you own for testing.**
2. Launch via `simctl launch` — **not** Xcode ⌘R (fresh container would dodge the corrupt store entirely).
3. PASS = plist shows `local_store_reset_reason` + `did_reset_local_store=true` → restore runs → flags cleared only after complete restore, store rebuilt, local count == cloud count, **zero duplicate rows** (check `SELECT ZAUDIOFILENAME, COUNT(*) FROM ZSERMON GROUP BY 1 HAVING COUNT(*)>1;`).

**D. Sync-failure honesty checks:** while a restore/sync runs, kill connectivity (Simulator ▸ toggle network, or macOS Wi-Fi off) mid-flight; PASS = flags NOT cleared, retry recovers, no partial-success state persisted.

## 5. Reporting

For each scenario report: build sha, sim UDID + iOS version, scenario (A–D or custom), the evidence (queries + outputs, plist values, counts), and PASS/FAIL against the written expectation. Anything requiring the owner's account or judgment goes in a "manual steps for owner" block with expected observations — precise enough that the owner can run it in five minutes.
