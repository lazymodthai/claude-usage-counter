# Claude Usage Counter

macOS menu bar app สำหรับดู Claude Code usage แบบ real-time
ดีไซน์ dark theme คล้าย Claude Sheep อ่านข้อมูลจาก `~/.claude/projects/` โดยตรง ไม่ต้องใช้ API key

## Screenshot (UI Preview)

```
Menu Bar:  ⚡ $0.42

┌── Popover ──────────────────────────┐
│ ⚡ Claude Code Usage        17:43   │
├──────────────────────────────────────┤
│ SPENDING LIMITS                      │
│                                      │
│ 🕰 Current 5-hour window             │
│   $0.18 · 42K tokens  resets in 3h  │
│                                      │
│ ☀ Today  May 12                      │
│   $0.42 / $5.00                      │
│   ████████░░░░  84%  🟡              │
│                                      │
│ 📆 This Week  May 6–12               │
│   $1.23 / $20.00                     │
│   ████░░░░░░░░  41%  🟢              │
│                                      │
│ 📅 This Month  May 2026              │
│   $3.21  (no limit)                  │
├──────────────────────────────────────┤
│ TODAY                      May 12    │
│  [⚡ 125K]  [💬 47]  [🔧 12]        │
├──────────────────────────────────────┤
│ LAST 7 DAYS  (messages)              │
│  ▃▅▇█▂▁▆  (bar chart, pink)         │
├──────────────────────────────────────┤
│ MODEL BREAKDOWN  (this month)        │
│ ● Sonnet  $2.80  in 800K · out 50K  │
│ ● Haiku   $0.41  in  91K · out 5K   │
│ ● Opus    $0.00           —          │
├──────────────────────────────────────┤
│ 📁 115 sessions    💬 342 msgs       │
│ Since Jan 17, 2026                   │
│          [↻ Refresh]  [✕ Quit]      │
└──────────────────────────────────────┘
```

## Requirements
- macOS 14 (Sonoma) ขึ้นไป
- ไม่ต้องการ API key หรือ config ใดๆ

## Build & Install

```bash
# Build
./build.sh

# Install to /Applications
./install.sh

# หรือ install ด้วยตัวเอง
cp -r "build/Claude Usage Counter.app" /Applications/
```

## ต้องการ dev tools สำหรับ build

```bash
xcode-select --install   # ถ้ายังไม่มี Command Line Tools
```

## Features

- **⚡ Menu bar** แสดงต้นทุนวันนี้ (`$0.42`)
- **5-hour window** — ติดตาม usage ของ session ปัจจุบัน + เวลา reset
- **Spending limits** — กำหนด daily/weekly/monthly limit ได้เอง
  - Progress bar พร้อม 🟡 warning ที่ 90% และ 🔴 over limit
- **Today stats** — tokens, messages, tool calls
- **Last 7 days** — bar chart จำนวน messages รายวัน
- **Model breakdown** — แยก Opus / Sonnet / Haiku + input/output tokens
- **Auto-refresh** ทุก 30 วินาที (ปรับได้ในหน้า Settings)
- **Universal binary** รองรับ Apple Silicon + Intel

## Settings

คลิก ⚙ (gear icon) ในหน้า Spending Limits เพื่อตั้ง:
- Daily limit ($) — ค่าเริ่มต้น $5.00
- Weekly limit ($) — ค่าเริ่มต้น $20.00
- Monthly limit ($) — ค่าเริ่มต้น ปิด
- Refresh interval (วินาที) — ค่าเริ่มต้น 30

การตั้งค่าเก็บไว้ใน `UserDefaults` (ไม่มี config file)

## Distribution

ส่งไฟล์ `build/Claude Usage Counter.app` ให้เครื่องอื่นได้เลย
เป็น universal binary รองรับทั้ง Apple Silicon และ Intel Mac

## Data Source

อ่านจาก `~/.claude/projects/**/*.jsonl` โดยตรง — ไม่ส่งข้อมูลออกอินเทอร์เน็ต

### Pricing table (per million tokens)

| Model | Input | Output | Cache Write | Cache Read |
|-------|-------|--------|-------------|------------|
| Opus  | $15.00 | $75.00 | $18.75 | $1.50 |
| Sonnet | $3.00 | $15.00 | $3.75 | $0.30 |
| Haiku | $0.80 | $4.00 | $1.00 | $0.08 |
