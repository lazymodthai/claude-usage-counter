# AI Usage Counter — Windows

Floating overlay ที่แสดง usage ของ Claude / Codex / Gemini / Antigravity บน Windows
สร้างด้วย [Tauri](https://tauri.app) (Rust + React)

> **branch นี้เป็นเวอร์ชัน Windows เท่านั้น** — เวอร์ชัน macOS (native Swift) อยู่บน branch `main`

## ติดตั้ง

ดาวน์โหลด `.msi` หรือ `.exe` จาก **[Releases](../../releases/latest)** แล้วดับเบิลคลิกติดตั้ง

## Build / พัฒนา

โค้ดทั้งหมดอยู่ในโฟลเดอร์ [`windows/`](./windows) — ดูวิธี build และรายละเอียดที่ [windows/README.md](./windows/README.md)

```powershell
cd windows
powershell -ExecutionPolicy Bypass -File release.ps1
```
