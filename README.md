# Claude Usage Counter

macOS menu bar app สำหรับติดตาม Claude Code usage แบบ real-time
ดีไซน์ dark theme คล้าย [Claude Sheep](https://www.mang.dev/products/claude-sheep) และ [Claude Usage Bar](https://www.claudeusagebar.com/)

ดึงข้อมูลได้ทั้งจาก **local JSONL** (`~/.claude/projects/`) และ **claude.ai/settings/usage** ผ่าน WKWebView โดยตรง

---

## Quick Look

**Menu Bar:**
```
⚡ 80.50% | 24.00%        ← session % | weekly %
⚡ 46m | 24.00%           ← session ที่ limit แล้ว countdown
⚡ 30s | 1d 22h           ← session ใกล้ reset (เป็นวินาที), weekly เหลือ 1d 22h
```

**Popup:**
```
⚡ Claude Usage   🟢 Signed in           [↻] [⚙]
─────────────────────────────────────────────────
🕐 Current Session                       80.50%
████████████████████░░░░░  
80.50% / 100%               Resets in 57 min

📅 Weekly — All Models                   24.00%
█████░░░░░░░░░░░░░░░░░░░░  
24.00% / 100%             Resets Tue 4:59 AM

🟢 Live from claude.ai · Updated 17:43:12
─────────────────────────────────────────────────
⬤ Opus   ⬤ Sonnet ✓   ⬤ Haiku
```

---

## Features

### 1. Live data จาก claude.ai (recommended)
- Login ผ่าน **Google SSO** (หรือวิธีอื่นๆ ที่ claude.ai รองรับ) ครั้งเดียว
- ดึง session % / weekly % จากหน้า `claude.ai/settings/usage` ตรง ๆ
- **ค่าตรงเป๊ะกับที่เห็นบนเว็บ** ไม่ต้องเดา limit
- Cookies เก็บไว้ใน `WKWebsiteDataStore.default()` (persist ข้ามการเปิดปิด app)
- รี­เฟรชทุก 60 วินาที

### 2. Local-only fallback (ไม่ต้อง login)
- อ่าน JSONL จาก `~/.claude/projects/` โดยตรง — **ไม่ใช้เน็ต**
- ใช้ FSEvents detect การเขียนไฟล์ใหม่ — update ภายใน ~1 วินาที
- **Limit ทำ auto-detect** จาก `rate_limit` error events ใน JSONL (วิธีที่ ccusage ใช้):
  ```
  เมื่อ Claude Code โดน rate limit จะเขียน
  {"error": "rate_limit", "message": {"content": [{"text": "You've hit your limit..."}]}}
  → tokens สะสมในช่วง 5h block ก่อนเจอ error = limit จริงของ plan
  ```

### 3. Countdown Mode (ใหม่)
เมื่อ session หรือ weekly **เต็ม limit (≥100%)**:
- หยุดดึง live data ทันที (ประหยัด bandwidth)
- ใช้เวลา reset ที่เก็บไว้ local มา **นับถอยหลัง**
- Tick ทุก 1 นาที — เมื่อเหลือ < 1 นาที สลับเป็น tick วินาทีอัตโนมัติ

**Session countdown format** (max 5h):
| เวลาที่เหลือ | แสดง |
|---|---|
| > 4 ชั่วโมง | `>4h` |
| 3–4 ชม. | `<4h` |
| 2–3 ชม. | `<3h` |
| 1–2 ชม. | `<2h` |
| 1–59 นาที | `59m`, `58m` ... `1m` |
| < 1 นาที | `59s`, `58s` ... `0s` |

**Weekly countdown format:**
| เวลาที่เหลือ | แสดง |
|---|---|
| ≥ 1 วัน | `1d 22h`, `4d 22h` |
| < 1 วัน | เหมือน session |

ตัวอย่าง menu bar ตอน countdown:
```
46m | 24.00%       ← session เต็ม รออีก 46 นาที, weekly ยังใช้ได้
24.00% | 1d 22h    ← weekly เต็ม รออีก 1d 22h, session ยังใช้ได้
46m | 1d 22h       ← เต็มทั้งคู่
```

### 4. Model Selector
ปุ่ม Opus / Sonnet / Haiku ที่ด้านล่าง popup
- คลิก → เขียน `"model": "opus"` ลงใน `~/.claude/settings.json`
- Claude Code จะใช้ model ใหม่ในการเปิด session ถัดไป

### 5. Login Status Indicator
- 🟢 `Signed in` — มี session cookie ของ claude.ai
- ⚪ `Not signed in` — ต้อง login ก่อนใช้ live data
- Toggle "Use claude.ai live data" disabled ถ้ายัง not signed in

---

## Requirements
- macOS 14 (Sonoma) ขึ้นไป
- Xcode Command Line Tools (สำหรับ build)

---

## Build & Install

```bash
./build.sh        # compile + สร้าง .app bundle (universal binary + icon)
./install.sh      # ติดตั้งไป /Applications + เปิด
./release.sh      # สร้าง .dmg สำหรับแจกจ่าย
```

ติดตั้งจาก DMG (สำหรับผู้ใช้ทั่วไป):
1. ดับเบิลคลิก `ClaudeUsageCounter-1.0.0.dmg`
2. ลาก `Claude Usage Counter.app` ลงโฟลเดอร์ `Applications`
3. เปิดจาก Launchpad/Spotlight

> ครั้งแรกที่เปิด macOS Gatekeeper อาจเตือนเพราะ app ไม่ได้ codesign กับ Apple ID
> วิธีแก้: **คลิกขวา → Open** ครั้งเดียวก็พอ

**Auto-start เมื่อ login Mac:**
System Settings → General → Login Items → `+` → เลือก `/Applications/Claude Usage Counter.app`

---

## วิธีใช้

1. เปิด app → คลิก ⚡ ใน menu bar
2. คลิก ⚙ Settings → ส่วน **Data Source**:
   - กดปุ่ม **"Sign in to claude.ai"** → login ด้วย Google SSO
   - หน้าต่างจะปิดอัตโนมัติเมื่อ login เสร็จ
   - เปิด toggle **"Use claude.ai live data"**
3. กลับมาดู menu bar — ค่าจะตรงกับ claude.ai/settings/usage 100%

ถ้าไม่อยาก login ก็ใช้ local mode ได้ (default) — แค่ค่า limit จะ auto-detect จาก rate_limit events เท่านั้น (ค่าอาจคลาดเคลื่อนเล็กน้อย)

---

## File Structure
```
claude-usage-counter/
├── Package.swift              # SPM config (macOS 14+)
├── Sources/
│   ├── main.swift            # Entry point
│   ├── AppDelegate.swift     # NSStatusItem + NSPopover
│   ├── ContentView.swift     # SwiftUI popup UI
│   ├── UsageStore.swift      # State + countdown logic + scraping
│   ├── UsageParser.swift     # JSONL parsing + 5h blocks
│   ├── Models.swift          # Data structs
│   ├── Pricing.swift         # Token pricing (Opus/Sonnet/Haiku)
│   ├── FileWatcher.swift     # FSEvents watcher
│   └── ClaudeAIScraper.swift # WKWebView scraper + login + auth check
├── build.sh                   # → build/Claude Usage Counter.app
├── install.sh                 # → /Applications/...
└── README.md
```

---

## Data Sources Compared

| | Local JSONL | claude.ai live |
|---|---|---|
| Internet required | ❌ | ✅ |
| Need login | ❌ | ✅ (Google SSO) |
| Accuracy | ~95% (detect limit จาก rate_limit) | 100% (ตรงกับเว็บ) |
| Update latency | <1s (FSEvents) | 60s (scrape) |
| Privacy | All local | Cookie อยู่ใน WKWebView |

---

## How Limit Auto-Detection Works (Local Mode)

1. Scan ทุก JSONL ใน `~/.claude/projects/`
2. Group records เป็น **5-hour billing blocks** (window = blockStart + 5h)
3. หา records ที่มี `"error": "rate_limit"`:
   ```json
   {
     "error": "rate_limit",
     "timestamp": "2026-05-05T10:02:59Z",
     "message": {
       "content": [{"text": "You've hit your limit · resets 7:20pm"}]
     }
   }
   ```
4. **Tokens ที่สะสมในช่วง block ก่อนเจอ error = plan session limit**
5. ใช้ค่าล่าสุด (filter outliers) เป็น `detectedSessionLimit`

ผลลัพธ์: ค่า limit ที่ได้ตรงกับ plan จริง โดยไม่ต้องรู้ tier ของ subscription

---

## Pricing Table (per million tokens, USD)

| Model | Input | Output | Cache Write | Cache Read |
|-------|-------|--------|-------------|------------|
| Opus  | $15.00 | $75.00 | $18.75 | $1.50 |
| Sonnet | $3.00 | $15.00 | $3.75 | $0.30 |
| Haiku | $0.80 | $4.00 | $1.00 | $0.08 |

---

## Caveats

- **claude.ai scraping ใช้ private API** — ถ้า claude.ai เปลี่ยน HTML/UI การดึงค่าอาจพัง (regex อาจไม่ match)
- App ไม่ได้ codesign → ครั้งแรกที่เปิดอาจติด Gatekeeper (คลิกขวา → Open ครั้งเดียวก็พอ)
- Cookies เก็บใน WKWebsiteDataStore ของ app นี้โดยเฉพาะ — ไม่ shared กับ Safari/Chrome

---

## License
MIT
