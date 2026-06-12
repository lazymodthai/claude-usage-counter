# Implementation Plan — Multi-Provider Usage Counter (Claude / Gemini / Codex)

> เป้าหมาย: เปลี่ยน Claude Usage Counter ให้รองรับ 3 ผู้ให้บริการ (Claude, Gemini, Codex)
> โดยส่วนแสดง % บน menu bar เลือกได้ว่าจะดูจาก provider ไหน (เลือกได้เฉพาะที่เชื่อมต่อแล้ว)
> auth ทุกตัวผ่านหน้าเว็บ (WKWebView login) — เลิกใช้การวาง sessionKey
> ความถูกต้องของข้อมูลมาก่อน: เปลี่ยนจาก scrape DOM → เรียก JSON API ภายในของแต่ละเว็บเท่าที่ทำได้

---

## 1. สรุปวิธีดึงข้อมูลของแต่ละ provider (จากการ research, มิ.ย. 2026)

ทั้ง 3 เจ้าใช้โมเดล limit เหมือนกันแล้ว: **หน้าต่าง 5 ชั่วโมง (session) + limit รายสัปดาห์ (weekly)** → UI เดิมของแอป map ได้ตรง ๆ

### 1.1 Claude — JSON API ภายใน (แม่นสุด, เลิก scrape DOM ได้เลย)

| | |
|---|---|
| Auth | cookie `sessionKey` จาก web login ที่มีอยู่แล้ว (`LoginWindowController`) |
| หา org id | `GET https://claude.ai/api/organizations` → เอา `uuid` ตัวแรก (cache 24 ชม.) |
| ดึง usage | `GET https://claude.ai/api/organizations/{org_id}/usage` |

Response (ใช้โดย browser extension หลายตัว เช่น sshnox/Claude-Usage-Tracker):

```json
{
  "five_hour": { "utilization": 34, "resets_at": "2026-06-12T15:00:00+00:00" },
  "seven_day": { "utilization": 72, "resets_at": "2026-06-16T22:00:00+00:00" }
}
```

ข้อดีใหญ่: ได้ `resets_at` เป็น ISO timestamp ตรง ๆ → **ลบ `ResetTimeParser` ทั้งก้อน** (เลิกเดา "Tue 5:00 AM" / "57 min" จากข้อความ)
เรียกผ่าน `URLSession` ธรรมดาได้ (copy cookies จาก `WKWebsiteDataStore` → `HTTPCookieStorage` ของ session) ไม่ต้องเปิด WebView ทุกครั้ง → เบากว่าเดิมมาก

### 1.2 Codex (ChatGPT) — JSON API ภายใน + หน้าเว็บเป็น fallback

| | |
|---|---|
| Auth | login `https://chatgpt.com` ใน WKWebView → ได้ session cookies |
| ขอ access token | `GET https://chatgpt.com/api/auth/session` (cookie auth) → field `accessToken` |
| ดึง usage | `GET https://chatgpt.com/backend-api/wham/usage` + `Authorization: Bearer <accessToken>` |

Response (อ้างอิงจาก CodexBar):

- `rate_limit.primary_window` → session 5 ชม. (`used_percent`, reset time)
- `rate_limit.secondary_window` → weekly
- `additional_rate_limits[]` → limit เฉพาะรุ่น (ไม่ใช้ในเฟสแรก)
- `plan_type` → โชว์ชื่อแผนใน popup ได้

ข้อควรระวัง: chatgpt.com มี Cloudflare → ถ้า `URLSession` โดนบล็อก ให้รัน `fetch()` **ภายใน** hidden WKWebView (inherit cookies + TLS fingerprint ของ WebKit) แล้วส่งผลกลับผ่าน `evaluateJavaScript` — ใช้เป็นกลไกหลักของ Codex ไปเลยก็ได้เพื่อความชัวร์
Fallback สุดท้าย: scrape DOM หน้า `https://chatgpt.com/codex/settings/usage` (มี meter 5h / weekly / credits)

### 1.3 Gemini — scrape DOM (ยังไม่มี JSON API ที่รู้จัก)

| | |
|---|---|
| Auth | login Google ที่ `https://gemini.google.com` ใน WKWebView |
| ดึง usage | หน้า Settings → **Usage Limits** บน gemini.google.com (เพิ่มมา พ.ค. 2026: 5-hour window + weekly limit) |

- gemini.google.com ใช้ batchexecute RPC ที่ obfuscate → เฟสแรกใช้ DOM scrape ใน hidden WKWebView (แบบเดียวกับ `ClaudeAIScraper` เดิม แต่เขียน extraction script ใหม่สำหรับหน้า usage limits)
- ระหว่าง implement ให้เปิด Web Inspector ดัก network ของหน้านี้ — ถ้าเจอ RPC ที่คืน JSON ใช้ได้ ให้สลับไปเรียกตรง (ทำเป็น TODO ใน `GeminiProvider`)
- **ความเสี่ยง**: Google อาจบล็อก login ใน embedded WebView ("This browser may not be secure") — บรรเทาด้วย Safari user agent (แบบที่ทำกับ claude.ai อยู่แล้ว ปกติผ่านเพราะเป็น web login ธรรมดาไม่ใช่ OAuth embed) ถ้ายังโดนบล็อกค่อยพิจารณาแผนสำรองภายหลัง

---

## 2. สถาปัตยกรรมใหม่

### 2.1 Provider abstraction

```swift
// Sources/Providers/UsageProvider.swift
enum ProviderID: String, CaseIterable, Codable {
    case claude, codex, gemini
}

struct ProviderUsage: Sendable, Codable {
    var sessionPct: Double?        // 0–100, used (normalize ทุก provider ให้เป็น "ใช้ไปแล้ว")
    var weeklyPct: Double?
    var sessionResetAt: Date?      // absolute เสมอ (ได้จาก API หรือคำนวณตอน scrape)
    var weeklyResetAt: Date?
    var planName: String?
    var fetchedAt: Date
    var isStale: Bool { Date().timeIntervalSince(fetchedAt) > 600 }
    var sessionAtLimit: Bool { (sessionPct ?? 0) >= 99.99 }
    var weeklyAtLimit: Bool  { (weeklyPct ?? 0) >= 99.99 }
}

enum AuthState { case signedOut, signedIn, expired }

@MainActor
protocol UsageProvider: AnyObject {
    var id: ProviderID { get }
    var displayName: String { get }      // "Claude" / "Codex" / "Gemini"
    var symbol: String { get }           // SF Symbol ต่อ provider
    var authState: AuthState { get }

    func checkAuth() async -> AuthState
    func presentLogin()                  // เปิดหน้าต่าง web login
    func signOut() async
    func fetchUsage() async -> ProviderUsage?   // nil = ล้มเหลว (เก็บค่าเก่าไว้)
}
```

หมายเหตุการ normalize: Codex รายงานเป็น "เหลือ X%" ใน CLI แต่ field คือ `used_percent` — ใน `ProviderUsage` กำหนดความหมายเดียว: **เปอร์เซ็นต์ที่ใช้ไปแล้ว** แล้วให้แต่ละ provider แปลงเอง

### 2.2 แยก cookie store ต่อ provider

- ใช้ `WKWebsiteDataStore(forIdentifier: UUID)` (macOS 14+) คนละ UUID ต่อ provider → login Google ของ Gemini ไม่ปนกับ ChatGPT/Claude, sign out ทีละตัวได้สะอาด
- **ยกเว้น Claude ใช้ `.default()` ต่อไป** เพื่อไม่ให้ login เดิมของผู้ใช้หาย (migration ฟรี)
- UUID เก็บใน UserDefaults key `providerStore.codex` / `providerStore.gemini`

### 2.3 Web login กลาง (refactor จาก `LoginWindowController`)

`Sources/WebAuthController.swift` — generic ตัวเดียวใช้ทุก provider:

```swift
WebAuthController.show(
    title: "Sign in to ChatGPT",
    startURL: URL(string: "https://chatgpt.com/auth/login")!,
    dataStore: store,                       // ของ provider นั้น
    isLoggedIn: { url in ... }              // เงื่อนไขปิดหน้าต่างต่อ provider
)
```

- เก็บ logic เดิมไว้ทั้งหมด: `isReleasedWhenClosed = false`, handle `window.open()` popup (Google SSO), Safari UA, ปิดเองเมื่อ login สำเร็จ
- เงื่อนไข "login แล้ว" ต่อ provider:
  - Claude: URL ขึ้นต้น `https://claude.ai/` และไม่ใช่ `/login`,`/auth` (เดิม)
  - Codex: URL เป็น `https://chatgpt.com/` root หรือ `/codex` และมี cookie session
  - Gemini: URL ขึ้นต้น `https://gemini.google.com/app`

### 2.4 Fetch engine สองแบบ (เลือกต่อ provider)

1. **`CookieAPIFetcher`** — `URLSession` + cookies ที่ copy มาจาก data store ของ provider → ใช้กับ **Claude** (เบา, ไม่มี WebView ค้างใน memory)
2. **`WebViewFetcher`** — hidden WKWebView ของ provider, โหลดหน้าแล้ว `evaluateJavaScript`:
   - โหมด `fetch-json`: รัน `fetch()` ใน page context เรียก API ภายใน (→ **Codex**)
   - โหมด `scrape-dom`: extraction script อ่าน DOM (→ **Gemini**, และ fallback ของ Codex)
   - แชร์โครงจาก `ClaudeAIScraper` เดิม (poll + timeout + cleanup) แต่ทำเป็น generic รับ script จาก provider

### 2.5 Store / state (refactor `UsageStore`)

```swift
@MainActor final class ProviderStore: ObservableObject {
    @Published var usages: [ProviderID: ProviderUsage] = [:]
    @Published var authStates: [ProviderID: AuthState] = [:]

    // provider ที่โชว์บน menu bar — เลือกได้เฉพาะตัวที่ signedIn
    @Published var menubarSource: ProviderID {
        didSet { UserDefaults… ; updateStatusBar() }
    }
    var connectedProviders: [ProviderID] { /* authState == .signedIn */ }
}
```

กติกา `menubarSource`:
- default = `claude`
- ถ้า provider ที่เลือกอยู่ถูก sign out → auto-fallback ไป provider แรกที่ยังเชื่อมต่อ; ถ้าไม่เหลือเลย → menu bar โชว์ `—` พร้อม tooltip "Sign in via settings"
- Picker ใน Settings (และคลิกขวาที่ไอคอน menu bar เป็น shortcut) แสดงเฉพาะ `connectedProviders`

### 2.6 Local JSONL mode (ของเดิม)

- **เก็บไว้เป็น offline fallback ของ Claude เท่านั้น** — ถ้า Claude ยังไม่ login หรือ fetch fail ติดกัน ใช้ค่า local (`UsageParser` + `FileWatcher` เดิม) พร้อม indicator "local estimate" ใน popup
- ไม่ลบโค้ด `UsageParser`/`FileWatcher`/`Pricing` แต่ย้ายไปอยู่ใต้ `ClaudeProvider` (เป็น detail ของ provider เดียว ไม่ใช่ของแอป)
- **ลบ UI วาง sessionKey** (`applyManualSession`, ช่อง paste ใน Settings) ตามโจทย์ auth ผ่านเว็บทั้งหมด — คง `ClaudeAIAuth.setSessionKey` ไว้เป็น internal ก็ไม่จำเป็น ลบทิ้ง

---

## 3. UI

### 3.1 Menu bar

- รูปแบบเดิม: `<icon> 64.00% | 32.00%` (session | weekly) แต่ icon เปลี่ยนตาม provider ที่เลือก:
  - Claude `bolt.fill` (เดิม) · Codex `chevron.left.forwardslash.chevron.right` · Gemini `sparkle`
- countdown mode เดิมใช้ต่อได้ทุก provider (logic อยู่บน `ProviderUsage` กลางแล้ว)

### 3.2 Popup

```
⚡ Usage                                  [↻] [⚙]
──────────────────────────────────────────────
● Claude   (on menu bar)
  🕐 Session  ███████░░░  64.00%   resets in 1h 12m
  📅 Weekly   ███░░░░░░░  32.00%   resets Tue 5:00AM
──────────────────────────────────────────────
● Codex
  🕐 Session  ██░░░░░░░░  18.00%   resets in 3h 02m
  📅 Weekly   █████░░░░░  51.00%   resets Wed 9:00AM
──────────────────────────────────────────────
○ Gemini — Not connected        [Sign in]
──────────────────────────────────────────────
Updated 17:43:12
```

- แสดง **ทุก provider** ใน popup (ตัวที่ไม่ได้เชื่อมต่อเป็นแถว "Sign in")
- คลิกชื่อ provider = ตั้งเป็น `menubarSource` (เฉพาะที่เชื่อมต่อ)
- ส่วน Claude local stats เดิม (cost/tokens/blocks) ย้ายไปแท็บ/ส่วนพับเก็บ "Claude · Local details" ไม่ให้รก

### 3.3 Settings

- ต่อ provider: ปุ่ม Sign in / Sign out + สถานะ 🟢/⚪️
- Picker "Menu bar shows: [Claude ▾]" (เฉพาะที่เชื่อมต่อ)
- Refresh interval รวม (default 60s)
- ลบ: toggle "Use claude.ai live data" (live เป็น default เมื่อ login แล้ว), ช่อง sessionKey, ช่อง token limit manual (คงไว้เฉพาะใน local-fallback section)

---

## 4. Optimization

1. **เลิกเปิด WebView ทุก 60 วิ ของ Claude** → `URLSession` ล้วน (CPU/RAM ลดชัดเจน — เดิมสร้าง WKWebView 1000×900 ทุกนาที)
2. **Hidden WebView ของ Codex/Gemini ใช้ instance เดียวค้างไว้** (ไม่สร้างใหม่ทุกรอบ) โหลดหน้าครั้งแรกครั้งเดียว รอบถัดไปแค่ re-run `fetch()`/reload เบา ๆ; ปล่อยทิ้ง (nil) เมื่อไม่ได้เป็น `menubarSource` และ popup ปิด > 10 นาที
3. **Adaptive polling**
   - provider ที่อยู่บน menu bar: ทุก `refreshInterval` (60s)
   - provider อื่นที่เชื่อมต่อ: ทุก 5 นาที (และ refresh ทันทีเมื่อเปิด popup)
   - at-limit → countdown mode เดิม (หยุด fetch จน reset)
   - error → exponential backoff 60s → 2m → 5m → 10m (cap), reset เมื่อสำเร็จ
4. **หยุด timer ตอนจอหลับ**: ฟัง `NSWorkspace.screensDidSleepNotification` / `didWakeNotification` → pause/resume + fetch ทันทีตอนตื่น
5. **Stagger**: เริ่ม fetch แต่ละ provider ห่างกัน 2–3 วิ ไม่ยิงพร้อมกัน
6. **Persist `usages` ลง UserDefaults (Codable)** → เปิดแอปมาโชว์ค่าล่าสุดทันที (ติด stale indicator) ระหว่างรอ fetch แรก
7. **ตรวจ auth expired จาก response**: HTTP 401/403 หรือ redirect ไปหน้า login → ตั้ง `authState = .expired`, โชว์จุดเหลือง 🟡 บน popup + หยุด poll provider นั้น (ไม่ retry รัว ๆ ให้โดน rate limit)

---

## 5. โครงไฟล์หลังแก้

```
Sources/
  main.swift                      (เดิม)
  AppDelegate.swift               (แก้เล็กน้อย: ProviderStore แทน UsageStore)
  ProviderStore.swift             (ใหม่ — refactor จาก UsageStore: scheduler, menubar, countdown)
  WebAuthController.swift         (ใหม่ — generic login window, refactor จาก LoginWindowController)
  WebViewFetcher.swift            (ใหม่ — hidden WKWebView: fetch-json / scrape-dom)
  CookieAPIFetcher.swift          (ใหม่ — URLSession + cookies จาก data store)
  Providers/
    UsageProvider.swift           (ใหม่ — protocol + ProviderUsage + ProviderID)
    ClaudeProvider.swift          (ใหม่ — JSON API + local JSONL fallback)
    CodexProvider.swift           (ใหม่ — auth/session → wham/usage, DOM fallback)
    GeminiProvider.swift          (ใหม่ — DOM scrape usage limits)
  ContentView.swift               (แก้ — popup multi-provider, settings ใหม่)
  Models.swift                    (เดิม — ใช้กับ local fallback)
  UsageParser.swift, FileWatcher.swift, Pricing.swift   (เดิม — ของ Claude local)
ลบ: ClaudeAIScraper.swift (แตกร่างเป็น WebAuthController + WebViewFetcher + ClaudeProvider)
```

---

## 6. ลำดับงาน (แต่ละเฟส build + ใช้งานได้จริง)

### Phase 1 — Foundation + Claude เปลี่ยนเป็น JSON API
1. สร้าง `UsageProvider` protocol, `ProviderUsage`, `ProviderStore` (รองรับ provider เดียวก่อน)
2. `CookieAPIFetcher` + `ClaudeProvider`: `/api/organizations` → `/usage` → map `five_hour`/`seven_day`
3. ลบ DOM scraping + `ResetTimeParser` + sessionKey UI; ย้าย local JSONL เป็น fallback ใน `ClaudeProvider`
4. ตรวจว่า menu bar / popup / countdown ทำงานเท่าเดิม (ค่าควรตรงเว็บเป๊ะเหมือนเดิมแต่เร็ว/เบากว่า)

### Phase 2 — Codex
1. `WebAuthController` generic + data store แยก
2. `WebViewFetcher` โหมด fetch-json: `api/auth/session` → `wham/usage` (ลอง `URLSession` ก่อน ถ้าโดน Cloudflare ใช้ in-WebView fetch)
3. map `primary_window`/`secondary_window` → `ProviderUsage` (ระวังทิศ used/remaining)
4. fallback scrape `chatgpt.com/codex/settings/usage`

### Phase 3 — Gemini
1. login flow gemini.google.com (ทดสอบ Google login ใน WKWebView ให้ผ่านก่อนทำอย่างอื่น — เป็นความเสี่ยงหลัก)
2. เปิดหน้า usage limits + เขียน extraction script (ดู network ไปด้วย — เจอ JSON RPC เมื่อไรสลับ)
3. แปลง reset text → absolute Date ฝั่ง scrape (กรณี Gemini ให้เป็น relative text)

### Phase 4 — UI multi-provider
1. popup แบบหลายแถว + ปุ่ม sign in ต่อ provider + เลือก menubar source
2. icon ต่อ provider บน menu bar + fallback rule เมื่อ sign out
3. Settings ใหม่, ย้าย local details ไปส่วนพับเก็บ

### Phase 5 — Optimization + เก็บงาน
1. adaptive polling, backoff, sleep/wake, stagger, persist cache
2. จัดการ `authState == .expired` (จุดเหลือง + ปุ่ม re-login)
3. อัปเดต README (วิธีเชื่อมต่อ 3 เจ้า), bump version, ทดสอบ build release

---

## 7. การทดสอบ

- ต่อ provider: login → ค่าตรงกับหน้าเว็บของเจ้านั้น (เทียบด้วยตาทั้ง session/weekly + เวลา reset)
- กรณี limit เต็ม: mock `utilization = 100` → menu bar เข้าโหมด countdown ถูกตัว
- sign out ตัวที่เป็น menubar source → fallback ถูกต้อง
- ปิด/เปิดแอป → โชว์ค่า cache ทันที แล้วอัปเดตตามจริง
- ถอด LAN/Wi-Fi → Claude ตกไป local estimate, ตัวอื่นโชว์ stale ไม่ crash
- ปล่อยข้ามคืน → memory ไม่โต (WebView ถูกปล่อยตามกติกาข้อ 4.2)

## 8. ความเสี่ยง / ข้อจำกัด

| ความเสี่ยง | ผลกระทบ | แผนรับมือ |
|---|---|---|
| ทุก endpoint เป็น undocumented internal API | เปลี่ยน/พังได้ทุกเมื่อ | แยก parsing ไว้ที่เดียวต่อ provider + fallback DOM scrape (Codex) / local (Claude); fail แล้วโชว์ stale ไม่ crash |
| Google บล็อก login ใน WKWebView | Gemini ใช้ไม่ได้ | Safari UA; ทดสอบเป็นอย่างแรกของ Phase 3; ถ้าตันจริงค่อยหาทางอื่น (เช่น Default browser + cookie import) แล้วแจ้งผู้ใช้ตรง ๆ ใน UI |
| Cloudflare บน chatgpt.com | URLSession โดนบล็อก | ใช้ in-WebView `fetch()` เป็นทางหลักของ Codex |
| Codex `plan_type` ใหม่ ๆ (เคยมีเคส `prolite` ทำ decoder พัง) | fetch fail | decode แบบ tolerant — field ไหนไม่รู้จักให้ข้าม ไม่ throw |
| Gemini DOM เปลี่ยนบ่อย | scrape พัง | extraction script ยึด label text + ตัวเลข % ใกล้เคียง (แบบ pctNear เดิม) ไม่ยึด class name |

## 9. แหล่งอ้างอิง

- Claude internal usage API: [sshnox/Claude-Usage-Tracker](https://github.com/sshnox/Claude-Usage-Tracker), [hamed-elfayome/Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker)
- Codex `wham/usage`: [CodexBar docs/codex.md](https://github.com/steipete/CodexBar/blob/main/docs/codex.md), [openai/codex#10869](https://github.com/openai/codex/issues/10869)
- Codex usage page บนเว็บ: [How to Check Your Codex Usage](https://www.jdhodges.com/blog/how-to-check-codex-usage-chatgpt-plus/), [Codex rate card](https://help.openai.com/en/articles/20001106-codex-rate-card)
- Gemini usage limits (5h + weekly, พ.ค. 2026): [Gemini Apps limits](https://support.google.com/gemini/answer/16275805?hl=en), [9to5google](https://9to5google.com/2026/05/28/gemini-new-usage-limits/)
