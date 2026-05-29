# Claude Usage Counter

แอป macOS menu bar สำหรับติดตามการใช้งาน Claude แบบ real-time — ดีไซน์ dark theme อยู่บนแถบเมนู เห็นเปอร์เซ็นต์ที่เหลือได้ตลอดเวลา

ดึงข้อมูลได้ 2 ทาง: **claude.ai/settings/usage** (ตรงเป๊ะกับเว็บ) หรือ **local** จากไฟล์ของ Claude Code โดยไม่ต้องต่อเน็ต

---

## หน้าตา

**บนแถบเมนู:**
```
⚡ 80.50% | 24.00%        ← session % | weekly %
⚡ 46m | 24.00%           ← session เต็มแล้ว นับถอยหลัง, weekly ยังเหลือ
⚡ 30s | Tue 5:00AM       ← session ใกล้ reset, weekly เต็มโชว์เวลา reset
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
24.00% / 100%             Resets Tue 5:00AM

🟢 Live from claude.ai · Updated 17:43:12
```

---

## ความสามารถ

- **ค่าตรงกับ claude.ai 100%** — ดึง session % และ weekly % จากหน้า usage จริง
- **โหมด local (ไม่ต้อง login)** — อ่านการใช้งานจากไฟล์ Claude Code บนเครื่อง อัปเดตเกือบทันที
- **นับถอยหลังเมื่อเต็ม limit** — session โชว์เวลาที่เหลือ (เช่น `46m`), weekly โชว์วัน+เวลาที่จะ reset (เช่น `Tue 5:00AM`) เหมือนบนเว็บ
- **สถานะ login** — จุดเขียว 🟢 = พร้อมดึง live data

---

## ติดตั้ง

1. ดาวน์โหลด `ClaudeUsageCounter-x.y.z.dmg` จากหน้า [Releases](https://github.com/lazymodthai/claude-usage-counter/releases)
2. ดับเบิลคลิกไฟล์ DMG → ลาก **Claude Usage Counter.app** ลงโฟลเดอร์ **Applications**
3. เปิดจาก Launchpad / Spotlight → มองหาไอคอน ⚡ บนแถบเมนู

> ครั้งแรกที่เปิด macOS อาจเตือนว่าแอปไม่ได้เซ็นด้วย Apple ID
> วิธีแก้: **คลิกขวาที่แอป → Open** ครั้งเดียวก็พอ

**ให้เปิดเองตอน login เครื่อง:** System Settings → General → Login Items → กด `+` → เลือก `Claude Usage Counter.app`

---

## วิธีใช้

เปิดแอปแล้วใช้ได้เลยในโหมด local (default) ถ้าอยากให้ค่าตรงกับเว็บเป๊ะ ๆ ให้เปิด live data:

1. คลิก ⚡ บนแถบเมนู → ⚙ Settings → ส่วน **Data Source**
2. เชื่อมต่อ claude.ai ด้วยวิธีใดวิธีหนึ่ง:
   - **Sign in to claude.ai** — login ในหน้าต่างของแอป (รองรับ Google SSO ฯลฯ) หน้าต่างจะปิดเองเมื่อเสร็จ
   - **วาง sessionKey** — ถ้า login claude.ai ไว้ใน browser อยู่แล้ว เปิด DevTools (⌥⌘I) → Application → Cookies → `https://claude.ai` → คัดลอกค่า `sessionKey` → กลับมาที่แอปแล้วกด **Paste** → **Apply**
3. เปิด toggle **Use claude.ai live data**

จากนั้นค่าบนแถบเมนูจะตรงกับ `claude.ai/settings/usage`

---

## ความเป็นส่วนตัว

- Cookies เก็บอยู่ในแอปนี้เท่านั้น ไม่ได้แชร์กับ Safari/Chrome และไม่ส่งออกที่ไหน
- โหมด local ทำงานบนเครื่องล้วน ๆ ไม่ต่อเน็ต

---

## ความต้องการของระบบ

- macOS 14 (Sonoma) ขึ้นไป

---

## License

MIT
