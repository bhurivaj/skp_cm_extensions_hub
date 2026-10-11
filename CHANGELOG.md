# Changelog

## [Unreleased]

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
