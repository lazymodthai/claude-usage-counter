# AI Usage Counter (Claude / Codex / Gemini)

แอป macOS menu bar สำหรับติดตามการใช้งาน AI แบบ real-time — รองรับ **Claude**, **Codex (ChatGPT)** และ **Gemini** ในแอปเดียว เลือกได้ว่าจะให้ menu bar แสดง % ของเจ้าไหน

ทุก provider ใช้โมเดล limit เดียวกัน: **หน้าต่าง 5 ชั่วโมง (session) + limit รายสัปดาห์ (weekly)**

---

## หน้าตา

**บนแถบเมนู** (ไอคอนเปลี่ยนตาม provider ที่เลือก):
```
⚡ 80.50% | 24.00%        ← session % | weekly %
⚡ 46m | 24.00%           ← session เต็มแล้ว นับถอยหลัง, weekly ยังเหลือ
⚡ 30s | Tue 5:00AM       ← session ใกล้ reset, weekly เต็มโชว์เวลา reset
```

**Popup** แสดงครบทุก provider ที่เชื่อมต่อ:
```
⚡ AI Usage                              [↻] [⚙]
─────────────────────────────────────────────────
⚡ Claude                        [menu bar]
  🕐 Current Session  ███████░░░  64.00%
  📅 Weekly           ███░░░░░░░  32.00%   Resets Tue 5:00AM
─────────────────────────────────────────────────
</> Codex                        [menu bar]
  🕐 Current Session  ██░░░░░░░░  18.00%
  📅 Weekly           █████░░░░░  51.00%   Resets Wed 9:00AM
─────────────────────────────────────────────────
✦ Gemini — Not connected              [Sign in]
─────────────────────────────────────────────────
🟢 Live · Claude · Updated 17:43:12
```

---

## วิธีดึงข้อมูล (ความถูกต้องมาก่อน)

| Provider | วิธี | ความแม่น |
|---|---|---|
| **Claude** | JSON API ภายในของ claude.ai (`/api/organizations/{org}/usage`) ผ่าน URLSession + cookie | ตรงกับ claude.ai/settings/usage เป๊ะ รวมเวลา reset |
| **Codex** | JSON API ภายในของ chatgpt.com (`backend-api/wham/usage`) รันใน WebView ที่ login ไว้ | ตรงกับ chatgpt.com/codex/settings/usage |
| **Gemini** | อ่านจากหน้า Usage Limits ของ gemini.google.com (beta — Google ยังไม่มี API) | ตามที่หน้าเว็บแสดง |

- **Claude โหมด local (ไม่ต้อง login)** — ถ้ายังไม่เชื่อมต่อ claude.ai จะประมาณการจากไฟล์ Claude Code บนเครื่อง (ติดป้าย `local estimate`)
- **นับถอยหลังเมื่อเต็ม limit** — session โชว์เวลาที่เหลือ (เช่น `46m`), weekly โชว์วัน+เวลา reset (เช่น `Tue 5:00AM`) แล้วกลับมาดึงข้อมูลใหม่อัตโนมัติหลัง reset
- **ประหยัดเครื่อง** — provider ที่อยู่บน menu bar refresh ทุก 60 วิ (ปรับได้), ตัวอื่น ๆ ทุก 10 นาที + ตอนเปิด popup, หยุดทำงานตอนจอหลับ, มี backoff เมื่อ error

---

## ติดตั้ง

1. ดาวน์โหลด DMG จากหน้า [Releases](https://github.com/lazymodthai/claude-usage-counter/releases)
2. ลากแอปลงโฟลเดอร์ **Applications** → เปิดจาก Launchpad
3. มองหาไอคอน ⚡ บนแถบเมนู

> ครั้งแรกที่เปิด macOS อาจเตือนว่าแอปไม่ได้เซ็นด้วย Apple ID — **คลิกขวาที่แอป → Open** ครั้งเดียวก็พอ

**ให้เปิดเองตอน login เครื่อง:** System Settings → General → Login Items → กด `+` → เลือกแอป

---

## วิธีใช้

1. คลิกไอคอนบนแถบเมนู → ⚙ Settings → ส่วน **Accounts**
2. กด **Sign in** ของ provider ที่ต้องการ → login ในหน้าต่างของแอป (รองรับ Google SSO ฯลฯ) หน้าต่างปิดเองเมื่อเสร็จ
3. เลือก **Menu Bar Shows** ว่าจะให้แถบเมนูแสดงของเจ้าไหน (เลือกได้เฉพาะที่เชื่อมต่อแล้ว) — หรือกดป้าย `menu bar` ใน popup ก็ได้

ถ้า session หมดอายุจะขึ้นป้ายเหลือง `session expired` → กด **Re-sign in**

---

## ความเป็นส่วนตัว

- Cookies ของแต่ละ provider เก็บแยก store ภายในแอปนี้เท่านั้น ไม่แชร์กับ Safari/Chrome และไม่ส่งออกที่ไหน
- ข้อมูล usage วิ่งตรงระหว่างเครื่องคุณกับเว็บของ provider เท่านั้น
- โหมด local ของ Claude ทำงานบนเครื่องล้วน ๆ ไม่ต่อเน็ต

---

## ข้อจำกัดที่ควรรู้

- ใช้ endpoint ภายในของแต่ละเว็บ (undocumented) — ถ้า provider เปลี่ยนระบบ ค่าอาจหายไปชั่วคราวจนกว่าจะอัปเดตแอป
- Gemini ยังเป็น **beta**: อ่านจากหน้าเว็บโดยตรง และการ login Google ใน WebView อาจถูกบล็อกในบางบัญชี

---

## ความต้องการของระบบ

- macOS 14 (Sonoma) ขึ้นไป

---

## License

MIT
