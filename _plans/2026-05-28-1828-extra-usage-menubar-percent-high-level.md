# Extra Usage % in Menu Bar Icon — High-Level Plan

## Starting Prompt

> Right now the menu try icon only shows percent consumption for session / week. It does not include "extra usage". However some accounts (like Enterprise through work) only have a dollar budget which shows up as "Extra Usage". It would be nice if the menu tray icon % UX also included "current spend / budget" percent.

---

## § Context Summary

### Current State

`ExtraUsageData` (in `UsageManager.swift`) already holds `usedCredits` and `monthlyLimit`
(both in cents) from the API, plus `isEnabled` and `currency`. A card in the
popover UI already displays these as dollar amounts. But:

- `quotas: [UsageQuota]` only contains token-quota entries (Session 5h, Weekly 7d, etc.)
- `extraUsage` is a separate `@Published` property, not a `UsageQuota`
- `primaryQuota` (used by all percentage display modes) only looks in `quotas`
- Enterprise accounts with a dollar-only budget have empty `quotas` → `menuBarTitle` returns "—"
- `allQuotas` mode only joins existing `quotas`; extra usage is invisible

### Key Types

```swift
// Already exists
struct ExtraUsageData: Decodable {
    let isEnabled: Bool
    let monthlyLimit: Double?   // nil = unlimited, value in cents
    let usedCredits: Double?    // in cents
    let currency: String?
}

// Already exists
struct UsageQuota: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let utilization: Double   // 0-100
    let resetsAt: Date?
}
```

---

## § High-Level Plan

### Modules Changed

| File | Change |
|------|--------|
| `Sources/UsageManager.swift` | Add `utilization` to `ExtraUsageData`; add `extraUsageQuota` and `allNotifiableQuotas`; update `primaryQuota`, `worstQuota`, `ringQuotaOptions`, `menuBarTitle`, `checkNotifications`, and `checkCustomAlerts` |
| `Sources/MenuBarView.swift` | Update custom alert "Add" button and quota picker to include extra usage; update `allQuotas` description |
| `CHANGELOG.md` | Add entry |

---

### Data Flow

```
API response
    └── extraUsage: ExtraUsageData?
            ├── isEnabled
            ├── usedCredits (cents)
            └── monthlyLimit (cents)

UsageManager (new)
    ├── extraUsageQuota: UsageQuota?
    │       Synthesized when isEnabled AND monthlyLimit != nil
    │       utilization = usedCredits / monthlyLimit * 100
    │       label = "Extra Usage"
    │       icon  = "dollarsign.circle.fill"
    │
    ├── primaryQuota (updated fallback)
    │       quotas[Session] ?? quotas.first ?? extraUsageQuota
    │
    ├── worstQuota (updated)
    │       max(quotas + [extraUsageQuota])
    │
    ├── allNotifiableQuotas (new)
    │       quotas + [extraUsageQuota?]
    │       Single source of truth for alert and ring systems
    │
    └── ringQuotaOptions (updated)
            [sessionTimerQuota?] + quotas + [extraUsageQuota?]

menuBarTitle
    .percentage      → "42%"  (via updated primaryQuota)
    .percentageAndTimer → "42% · 1h30m" (same)
    .sessionTimerAndWeek → "42% · 1h30m | W 31%" (same; no session? shows extra%)
    .allQuotas       → "15% | 31% | E 42%"  (new E prefix for extra)
```

---

### ASCII: Menu Bar Before / After

**Enterprise account (no token quotas, dollar budget only):**

```
Before:  [C] —
After:   [C] 42%      (.percentage mode)
         [C] 42% | E 42%   (.allQuotas mode, same source but labeled)
```

**Standard account (has session/week quotas AND extra usage):**

```
Before:  [C] 15%            (.percentage)
         [C] 15% | 31%      (.allQuotas — extraUsage absent)

After:   [C] 15%            (.percentage — unchanged)
         [C] 15% | 31% | E 42%  (.allQuotas — extraUsage appended)
```

---

### Core Changes (Key Signatures)

```swift
// 1. ExtraUsageData — add computed utilization
extension ExtraUsageData {
    var utilization: Double? {
        guard let cents = usedCredits, let limit = monthlyLimit, limit > 0 else { return nil }
        return min(cents / limit * 100, 100)
    }
}

// 2. UsageManager — new computed property
var extraUsageQuota: UsageQuota? {
    guard let extra = extraUsage,
          extra.isEnabled,
          let util = extra.utilization else { return nil }
    return UsageQuota(
        label: "Extra Usage",
        icon: "dollarsign.circle.fill",
        utilization: util,
        resetsAt: nil
    )
}

// 3. primaryQuota — add fallback
private var primaryQuota: UsageQuota? {
    quotas.first(where: { $0.label.contains("Session") })
        ?? quotas.first
        ?? extraUsageQuota
}

// 4. worstQuota — include extra usage in icon color calculation
private var worstQuota: UsageQuota? {
    var candidates = quotas
    if let e = extraUsageQuota { candidates.append(e) }
    return candidates.max(by: { $0.utilization < $1.utilization })
}

// 5. ringQuotaOptions — surface extra usage as a ring option
var ringQuotaOptions: [UsageQuota] {
    var opts = quotas
    if let t = sessionTimerQuota { opts.insert(t, at: 0) }
    if let e = extraUsageQuota { opts.append(e) }
    return opts
}

// 6. menuBarTitle .allQuotas case — append extra usage
case .allQuotas:
    var parts = quotas.map { "\(Int($0.utilization))%" }
    if let e = extraUsageQuota { parts.append("E \(Int(e.utilization))%") }
    return parts.isEmpty ? "—" : parts.joined(separator: " | ")

// 7. allNotifiableQuotas — unified quota list for alert + ring systems
var allNotifiableQuotas: [UsageQuota] {
    var result = quotas
    if let e = extraUsageQuota { result.append(e) }
    return result
}

// 8. checkNotifications — use allNotifiableQuotas instead of quotas
// Before: let pairs = quotas.flatMap { ... }
// After:
let pairs = allNotifiableQuotas.flatMap { quota in
    thresholds.map { threshold in (quota: quota, threshold: threshold, key: "\(quota.label)-\(Int(threshold))") }
}

// 9. checkCustomAlerts — resolve label against allNotifiableQuotas
// Before: guard let quota = quotas.first(where: { $0.label == rule.quotaLabel }) else { continue }
// After:
guard let quota = allNotifiableQuotas.first(where: { $0.label == rule.quotaLabel }) else { continue }
```

**`MenuBarView.swift` — Custom Alert UI**

```swift
// 10. "Add" button guard + default label — use allNotifiableQuotas
// Before: if !manager.quotas.isEmpty { ... manager.quotas.first ... }
// After:
if !manager.allNotifiableQuotas.isEmpty {
    SHButton(label: "Add", ...) {
        let available = manager.allNotifiableQuotas.first(where: { !existing.contains("\($0.label)-80") })
        let quotaLabel = available?.label ?? manager.allNotifiableQuotas.first?.label ?? "Session (5h)"
        ...
    }
}

// 11. Quota picker for each custom alert rule — source from allNotifiableQuotas
// (the Picker that lets users change which quota a rule targets)
// Before: ForEach(manager.quotas, ...) { Text($0.label).tag($0.label) }
// After:  ForEach(manager.allNotifiableQuotas, ...) { Text($0.label).tag($0.label) }
```

---

### Tests

This project has no test targets. No test changes required.

---

### Documentation Updates

- **`CHANGELOG.md`**: Add `### Changed` entry under a new version section.
- **`README.md`**: No dedicated section on display modes; no change needed.
- **`docs/index.html`**: No display mode documentation; no change needed.

---

## § Cross-Check

### Red Flags

| Flag | Assessment |
|------|-----------|
| **Information Leakage** | `extraUsageQuota` synthesis lives in one place (`UsageManager`). No leakage. |
| **Temporal Decomposition** | No ordering dependency introduced. `extraUsageQuota` is computed on demand from already-decoded state. |
| **Pass-Through Method** | `extraUsageQuota` is a meaningful transformation (cents → normalized 0-100 utilization); not a pass-through. |
| **Punting Complexity** | Handled inline: nil `monthlyLimit` (unlimited) produces nil quota rather than requiring callers to guard. |
| **Shallow Module** | `ExtraUsageData.utilization` is simple but purposeful; the complexity is pulled down into the type rather than scattered across `menuBarTitle` switch branches. |

### High-Level Cross-Checks

| Check | Assessment |
|-------|-----------|
| **Correctness** | Existing token-quota users are unaffected: `primaryQuota` only falls back to `extraUsageQuota` when `quotas` is empty. `worstQuota` now also reflects extra usage (icon color) which is correct — a user at 90% dollar budget should see a warning icon. `checkNotifications` and `checkCustomAlerts` both route through `allNotifiableQuotas`, so standard and custom alerts fire for extra usage just like any token quota. |
| **Performance** | All new properties are `O(1)` computed properties on already-loaded in-memory state. No new I/O, no new API calls. |
| **Data Integrity** | `usedCredits / monthlyLimit` division guarded against `limit == 0`. Result clamped to 100. `nil` limit (unlimited plan) correctly produces no quota (no percentage shown). |

### Visual Styling

No new views or styling introduced. All display changes are string formatting
within `menuBarTitle`. The existing `UsageLevel` color system applies automatically
to `extraUsageQuota` via `UsageLevel(utilization:)`.
