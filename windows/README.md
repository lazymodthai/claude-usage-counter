# AI Usage Counter — Windows/macOS Overlay

Floating overlay แสดง usage ของ Claude / Codex / Gemini ที่ลากย้ายตำแหน่งได้ทุกที่บนหน้าจอ  
สร้างด้วย [Tauri](https://tauri.app) (Rust + React) — รองรับทั้ง **Windows** และ **macOS**

---

## ติดตั้ง

### macOS

```bash
# 1. Clone และเข้า folder นี้
cd windows

# 2. รัน install script
chmod +x install.sh
./install.sh

# 3. Dev mode
npm run tauri dev

# 4. Build .app
npm run tauri build
# → ได้ไฟล์ที่ src-tauri/target/release/bundle/macos/
```

> **Prerequisites ที่ script จัดการให้อัตโนมัติ:**  
> Xcode CLT · Rust · npm packages · App icons

### Windows

```powershell
# 1. Clone และเข้า folder นี้
cd windows

# 2. รัน install script
powershell -ExecutionPolicy Bypass -File install.ps1

# 3. Dev mode
npm run tauri dev

# 4. Build .exe installer
npm run tauri build
# → ได้ไฟล์ที่ src-tauri\target\release\bundle\msi\
```

> **Prerequisites ที่ script จัดการให้อัตโนมัติ:**  
> Rust · Node.js · WebView2 · MSVC Build Tools · npm packages · App icons

---

## ติดตั้ง dependencies ด้วยตนเอง (ถ้าไม่ใช้ script)

```bash
# npm packages (frontend + Tauri CLI)
npm install

# สร้าง icons จาก icon.png ที่ root ของ repo
npm run tauri icon ../icon.png
```

**Cargo.toml จัดการ Rust dependencies อัตโนมัติตอน build**

| Rust crate | ความหมาย |
|---|---|
| `tauri` | core framework |
| `tauri-plugin-shell` | รัน shell command |
| `tauri-plugin-fs` | อ่านไฟล์ |
| `tauri-plugin-http` | HTTP requests |
| `tauri-plugin-notification` | system notifications |
| `tauri-plugin-global-shortcut` | keyboard shortcuts |
| `chrono` | parse timestamp จาก JSONL |
| `dirs` | หา home directory |
| `serde / serde_json` | JSON parsing |

---

## หน้าตา

```
┌─────────────────────────────────────┐
│ ⚡ AI Usage               [↻]  [⚙] │  ← ลาก header นี้เพื่อย้าย overlay
│─────────────────────────────────────│
│ ⚡ Claude        [local estimate]   │
│   🕐 Current Session               │
│   ████████░░  78.20%               │
│   7.0M / 8.8M          Resets 46m  │
│   📅 Weekly                        │
│   ████░░░░░░  41.00%               │
│   36.1M / 88M    Resets Tue 5:00AM │
│─────────────────────────────────────│
│ </> Codex              [Sign in]   │
│ ✦  Gemini              [Sign in]   │
│─────────────────────────────────────│
│ ◉ Live · Claude · Updated 17:43:12 │
└─────────────────────────────────────┘
```

---

## วิธีใช้งาน

### ย้ายตำแหน่ง overlay
- **ลากที่แถบบนสุด** (ส่วนที่เขียนว่า "AI Usage") เพื่อย้าย overlay ไปวางไว้มุมไหนของจอก็ได้
- แอปจำตำแหน่งล่าสุดอัตโนมัติ ปิดแล้วเปิดใหม่ยังอยู่ที่เดิม

### ซ่อน / แสดง
- คลิก **tray icon** ที่ system tray (มุมขวาล่าง Windows / menu bar macOS) เพื่อสลับซ่อน-แสดง
- คลิกขวา tray icon → **Hide** หรือ **Show**
- คลิกขวา tray icon → **Quit** เพื่อปิดแอป

### ปรับแต่ง (⚙ Settings)
คลิกปุ่ม ⚙ ที่มุมขวาบนของ overlay

| ตัวเลือก | ความหมาย |
|---|---|
| **Always on Top** | เปิด = ลอยเหนือทุก window ตลอด (default: เปิด) |
| **Opacity** | ปรับความโปร่งแสง 30%–100% (default: 95%) |

### Refresh ข้อมูล
- กด **↻** เพื่อ refresh ทันที
- แอป refresh อัตโนมัติทุก 60 วินาที

### Claude — local estimate
ถ้า Claude ยังไม่ได้ sign in จะแสดงป้าย `local estimate` — คำนวณจากไฟล์ Claude Code ที่อยู่ใน `~/.claude/projects/**/*.jsonl` บนเครื่องโดยตรง ไม่ต้องเชื่อมต่ออินเทอร์เน็ต

---

## ความต้องการของระบบ

| OS | เวอร์ชันต่ำสุด |
|---|---|
| **Windows** | Windows 10 (1803+) พร้อม WebView2 |
| **macOS** | macOS 11 (Big Sur) ขึ้นไป |

> WebView2 บน Windows 10/11 ส่วนใหญ่มีอยู่แล้ว (มาพร้อม Microsoft Edge) — install script จัดการให้ถ้ายังไม่มี

---

## Features

| Feature | รายละเอียด |
|---|---|
| **Overlay** | หน้าต่างลอยเหนือทุก app |
| **Draggable** | ลาก header เพื่อย้ายตำแหน่ง |
| **Position memory** | จำตำแหน่งล่าสุดอัตโนมัติ |
| **Opacity** | ปรับความโปร่งแสงได้ใน Settings |
| **Always on Top** | toggle ได้ใน Settings |
| **System tray** | คลิก tray icon เพื่อซ่อน/แสดง |
| **Claude local** | อ่านจาก `~/.claude/projects/**/*.jsonl` |

---

## โครงสร้าง

```
windows/
├── src/                    React frontend
│   ├── components/         Header, ProviderSection, UsageBar, Footer, Settings
│   ├── store.ts            Zustand state + Tauri invoke calls
│   ├── types.ts            TypeScript types
│   └── utils.ts            format helpers
└── src-tauri/              Rust backend
    ├── src/
    │   ├── main.rs         entry point
    │   ├── lib.rs          Tauri setup + commands
    │   ├── claude_parser.rs อ่าน .jsonl → คำนวณ session/weekly
    │   ├── models.rs       data structs
    │   └── tray.rs         system tray
    └── tauri.conf.json     window config (frameless, transparent, alwaysOnTop)
```
