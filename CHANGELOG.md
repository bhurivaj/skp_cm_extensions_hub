# Changelog

## [0.5.1] - 2026-10-12

### Fixed
- ปุ่ม "เปิดใช้งาน" แสดงค้างทั้งที่ plugin เปิดอยู่ และปุ่ม "ถอน" โผล่ให้ถอน plugin ที่ยังเปิดอยู่ได้ — SketchUp ตอบ `load_on_start?` เป็น false เสมอ จึงเปลี่ยนไปดูว่า plugin ถูกโหลดอยู่ไหม (+ จำค่าที่เปิด/ปิดจาก Hub ใน session นั้น)

## [0.5.0] - 2026-10-12

### Added
- Ruby API `SkpCm::ExtensionsHub::Auth.execute_kw(model, method, args, kwargs) { |ok, result_or_error| }` ให้ plugins อื่นเรียก model ของ Odoo ด้วยบัญชีที่ login ไว้ใน Hub (ไม่เห็น password) — login ใหม่ให้เองถ้ายังไม่ได้เชื่อมต่อรอบนี้

## [0.4.0] - 2026-10-12

### Added
- Login บัญชี Odoo ที่ Hub (ใช้ปลดล็อคฟีเจอร์พิเศษใน plugins ของ SKP CM) — บันทึกบัญชีใน `SkpCm/extensions_hub/auth.json`
- การ์ด "บัญชี" ใน Hub: Login / Logout, ตั้งค่า API Base URL, login อัตโนมัติตอนเปิด SketchUp, ปุ่ม "เชื่อมต่อใหม่" เมื่อออฟไลน์
- Ruby API `SkpCm::ExtensionsHub::Auth` ให้ plugins อื่นเช็กสถานะ login / `uid` ของ Odoo
- Login ผ่าน Odoo JSON-RPC (`/jsonrpc`, `common.authenticate`) — ตั้ง API Base URL + Database ได้ (ค่าเริ่มต้น `odoo_ci`)

## [0.3.0] - 2026-10-11

### Added
- ปุ่ม "ปิดใช้งาน" / "เปิดใช้งาน" plugin จากใน Hub (Extension Manager) — ปิดใช้งานมีผลสมบูรณ์หลัง restart SketchUp

### Changed
- กันเผลอถอน: ปุ่ม "ถอน" ซ่อนไว้จนกว่าจะปิดใช้งาน plugin ก่อน และ Ruby ปฏิเสธการถอน plugin ที่ยังเปิดใช้งานอยู่ (ยังมี confirm dialog เหมือนเดิม)
- plugin ที่มีไฟล์แต่ SketchUp ไม่รู้จัก (โหลดไม่ขึ้น) ยังถอนได้ทันที

## [0.2.0] - 2026-10-11

### Added
- Author line on each plugin card (`author` field in `index.json`, optional — shows "-" when missing)
- "เรียงตาม" dropdown to sort plugins by name, author or status

## [0.1.0] - 2026-10-11

### Added
- Hub dialog: list SKP CM plugins from `index.json` with installed / latest version
- Install, update and remove plugins from GitHub Releases
- Release notes per plugin
- Daily update check on SketchUp start with a notification
