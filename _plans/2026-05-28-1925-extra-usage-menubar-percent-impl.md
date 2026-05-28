# Extra Usage % in Menu Bar — Implementation Detail

Implements the high-level plan at `_plans/2026-05-28-1828-extra-usage-menubar-percent-high-level.md`.

---

## § Implementation Detail

### No test target

This project has no Swift test target. The implementation strategy note about TDD
cannot be applied literally. Verification is done by building and running the app
(`make build && make run`) and observing behavior.

---

### Step 1 — Add `utilization` to `ExtraUsageData` (`UsageManager.swift` lines 167-190)

**What:** Add a computed property that derives a 0-100 utilization percentage
from `usedCredits / monthlyLimit`. Returns `nil` when either field is absent
or limit is zero (unlimited plan).

**Replace** (lines 186-189, after `limitFormatted`):

```swift
    var limitFormatted: String {
        guard let cents = monthlyLimit else { return "Unlimited" }
        return String(format: "$%.2f", cents / 100.0)
    }
}
```

**With:**

```swift
    var limitFormatted: String {
        guard let cents = monthlyLimit else { return "Unlimited" }
        return String(format: "$%.2f", cents / 100.0)
    }

    var utilization: Double? {
        guard let cents = usedCredits, let limit = monthlyLimit, limit > 0 else { return nil }
        return min(cents / limit * 100, 100)
    }
}
```

---

### Step 2 — Add `extraUsageQuota` and `allNotifiableQuotas` (`UsageManager.swift` lines 419-424)

**What:** `extraUsageQuota` synthesizes a `UsageQuota` from `extraUsage` when
enabled and a limit exists. `allNotifiableQuotas` merges `quotas` and
`extraUsageQuota` — the single source of truth for alerts and ring options.

**Replace** (lines 419-424):

```swift
    /// All selectable ring options: timer (if available) + live API quotas.
    var ringQuotaOptions: [UsageQuota] {
        var opts = quotas
        if let t = sessionTimerQuota { opts.insert(t, at: 0) }
        return opts
    }
```

**With:**

```swift
    /// Synthesized quota for extra usage when enabled and a monthly limit is set.
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

    /// Token quotas + extra usage quota. Single source of truth for alerts and ring options.
    var allNotifiableQuotas: [UsageQuota] {
        var result = quotas
        if let e = extraUsageQuota { result.append(e) }
        return result
    }

    /// All selectable ring options: timer (if available) + live API quotas + extra usage.
    var ringQuotaOptions: [UsageQuota] {
        var opts = quotas
        if let t = sessionTimerQuota { opts.insert(t, at: 0) }
        if let e = extraUsageQuota { opts.append(e) }
        return opts
    }
```

---

### Step 3 — Update `primaryQuota` to fall back to `extraUsageQuota` (`UsageManager.swift` line 438)

**What:** Enterprise accounts with no token quotas need a fallback so all
percentage display modes show a value rather than "—".

**Replace** (line 438-440):

```swift
    var primaryQuota: UsageQuota? {
        quotas.first(where: { $0.label.contains("Session") }) ?? quotas.first
    }
```

**With:**

```swift
    var primaryQuota: UsageQuota? {
        quotas.first(where: { $0.label.contains("Session") })
            ?? quotas.first
            ?? extraUsageQuota
    }
```

---

### Step 4 — Update `worstQuota` to include extra usage (`UsageManager.swift` line 443)

**What:** Ensures the menu bar icon color and opacity react to high extra usage
spend, not just token quotas.

**Replace** (lines 443-445):

```swift
    /// The quota with the highest utilization (worst state)
    private var worstQuota: UsageQuota? {
        quotas.max(by: { $0.utilization < $1.utilization })
    }
```

**With:**

```swift
    /// The quota with the highest utilization (worst state) — includes extra usage.
    private var worstQuota: UsageQuota? {
        allNotifiableQuotas.max(by: { $0.utilization < $1.utilization })
    }
```

---

### Step 5 — Update `menuBarTitle` `.allQuotas` case (`UsageManager.swift` lines 469-471)

**What:** Appends extra usage percentage (prefixed "E") to the `allQuotas` title
when present, so users in "All" mode see it alongside token quotas.

**Replace** (lines 469-471):

```swift
        case .allQuotas:
            if quotas.isEmpty { return "—" }
            return quotas.map { "\(Int($0.utilization))%" }.joined(separator: " | ")
```

**With:**

```swift
        case .allQuotas:
            var parts = quotas.map { "\(Int($0.utilization))%" }
            if let e = extraUsageQuota { parts.append("E \(Int(e.utilization))%") }
            return parts.isEmpty ? "—" : parts.joined(separator: " | ")
```

---

### Step 6 — Update `checkNotifications` to use `allNotifiableQuotas` (`UsageManager.swift` line 1764)

**What:** Standard usage alerts now fire for extra usage the same way they fire
for token quotas.

**Replace** (line 1764):

```swift
        let pairs = quotas.flatMap { quota in
```

**With:**

```swift
        let pairs = allNotifiableQuotas.flatMap { quota in
```

---

### Step 7 — Update `checkCustomAlerts` to use `allNotifiableQuotas` (`UsageManager.swift` line 1819)

**What:** Custom alert rules targeting "Extra Usage" label now resolve correctly.

**Replace** (line 1819):

```swift
            guard let quota = quotas.first(where: { $0.label == rule.quotaLabel }) else { continue }
```

**With:**

```swift
            guard let quota = allNotifiableQuotas.first(where: { $0.label == rule.quotaLabel }) else { continue }
```

---

### Step 8 — Update Custom Alerts UI in `MenuBarView.swift` (lines 461-467)

**What:** The "Add" button guard and default-label selection now use
`allNotifiableQuotas` so "Extra Usage" appears as an option when available.

**Replace** (lines 461-468):

```swift
                        if !manager.quotas.isEmpty {
                            SHButton(label: "Add", icon: "plus", style: .ghost) {
                                // Pick a quota that doesn't already have a rule at 80%
                                let existing = Set(manager.customAlertRules.map { "\($0.quotaLabel)-\(Int($0.threshold))" })
                                let available = manager.quotas.first(where: { !existing.contains("\($0.label)-80") })
                                let quotaLabel = available?.label ?? manager.quotas.first?.label ?? "Session (5h)"
                                manager.customAlertRules.append(AlertRule(quotaLabel: quotaLabel, threshold: 80))
                            }
                        }
```

**With:**

```swift
                        if !manager.allNotifiableQuotas.isEmpty {
                            SHButton(label: "Add", icon: "plus", style: .ghost) {
                                // Pick a quota that doesn't already have a rule at 80%
                                let existing = Set(manager.customAlertRules.map { "\($0.quotaLabel)-\(Int($0.threshold))" })
                                let available = manager.allNotifiableQuotas.first(where: { !existing.contains("\($0.label)-80") })
                                let quotaLabel = available?.label ?? manager.allNotifiableQuotas.first?.label ?? "Session (5h)"
                                manager.customAlertRules.append(AlertRule(quotaLabel: quotaLabel, threshold: 80))
                            }
                        }
```

---

### Step 9 — Update `CHANGELOG.md`

Add a new version section at the top (after the `# Changelog` heading and before
the current latest entry). Use the next patch version after `2.22.2` → `2.22.3`.

```markdown
## [2.22.3] - 2026-05-28

### Changed
- Extra Usage (dollar budget) now shows as a percentage in all menu bar display
  modes. Enterprise accounts with no token quotas see their spend/budget % instead
  of "—". The "All" mode appends `E X%` for accounts that have both token quotas
  and a dollar budget.
- Extra Usage is now available as a ring option in Icon+ Rings mode.
- Usage alerts ("Alert when usage is high") and custom alert rules now fire for
  Extra Usage, just like token quotas.
```

---

### Step 10 — Build verification

Run: `make build`

Expected: zero errors, zero warnings introduced by these changes.
Then: `make run` to launch the app and confirm the menu bar title updates.

---

## § Consistency Cross-Check (High-Level vs. Impl)

| High-level item | Impl step | Status |
|----------------|-----------|--------|
| `ExtraUsageData.utilization` | Step 1 | ✓ |
| `extraUsageQuota` computed property | Step 2 | ✓ |
| `allNotifiableQuotas` computed property | Step 2 | ✓ |
| `primaryQuota` fallback | Step 3 | ✓ |
| `worstQuota` includes extra usage | Step 4 | ✓ |
| `ringQuotaOptions` includes extra usage | Step 2 | ✓ |
| `menuBarTitle .allQuotas` appends E% | Step 5 | ✓ |
| `checkNotifications` uses `allNotifiableQuotas` | Step 6 | ✓ |
| `checkCustomAlerts` uses `allNotifiableQuotas` | Step 7 | ✓ |
| Custom Alert "Add" button UI | Step 8 | ✓ |
| `CHANGELOG.md` | Step 9 | ✓ |

One item from the high-level plan is intentionally not in the impl: updating the
`description` string on `MenuBarDisplayMode`. To see why this is fine, look at
`UsageManager.swift` line 62:

```swift
case .allQuotas: return "C 15% | 31% | 22%"
```

These strings are hardcoded example previews that appear in the Settings UI under
the mode picker to give users a quick visual hint of what each mode looks like.
They are **not** the actual menu bar title — that is computed dynamically by
`menuBarTitle`. Updating the static example strings to say `"C 15% | 31% | E 42%"`
would be misleading for users who have no extra usage, since the example would
claim a quota they don't have. Leaving them as static illustrations is correct;
the real behavior is visible in the live menu bar after the change.

No ambiguities found.

---

### Feedback Log

**Comment on:** "One item from the high-level plan is intentionally not in the impl...They were listed as 'optional' in the high-level plan."
**Feedback:** `^^ help me understand this ^^`
**Resolution:** Expanded the explanation to clarify that `description` strings on `MenuBarDisplayMode` are hardcoded preview examples in the Settings UI, not the live menu bar title. Updating them to mention extra usage would be misleading for users without it.
