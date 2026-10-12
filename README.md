# SKP CM Extensions Hub

ติดตั้ง / อัปเดต / ถอน plugins ของ SKP CM จาก GitHub Releases ได้จากใน SketchUp

- รองรับ: SketchUp 2024+
- ต้องต่ออินเทอร์เน็ต (ใช้ GitHub)
- เมนู: Extensions → SKP CM Extensions Hub
- เปิด SketchUp แล้วเช็คอัปเดตให้วันละครั้ง ถ้ามีจะแจ้งเตือนที่มุมจอ

## ติดตั้งครั้งแรก

SketchUp → Extensions → Extension Manager → Install Extension → เลือก `skp_cm_extensions_hub_<version>.rbz`
(หลังจากนั้น Hub อัปเดตตัวเองได้)

## เพิ่ม plugin เข้า Hub

แก้ `index.json` แล้ว push ที่ branch `main` — ไม่ต้องปล่อย Hub ใหม่

กติกาของ plugin ที่อยู่ใน Hub:

- `name` ต้องตรงกับชื่อใน `SketchupExtension.new(name, ...)`
- `author` = ชื่อผู้พัฒนา (แสดงในการ์ด + ใช้เรียงลำดับ; plugin ของคนอื่นใส่ชื่อเจ้าของจริง)
- `files` = ไฟล์/โฟลเดอร์ใน Plugins folder (ตัวแรกคือ loader) — ใช้ตอนถอน
- Release: tag `vX.Y.Z`, แนบ `.rbz` 1 ไฟล์, ใน `.rbz` มีเฉพาะสิ่งที่อยู่ใน `files`

## บัญชี (login กลาง)

Login ด้วยบัญชี Odoo (JSON-RPC `common.authenticate`, database ตั้งได้ใน "ตั้งค่าบัญชี" — ค่าเริ่มต้น `odoo_ci`) ที่การ์ด "บัญชี" ด้านบนของ Hub — plugins อื่นของ SKP CM ใช้สถานะนี้ปลดล็อคฟีเจอร์พิเศษ
บัญชีเก็บใน `SkpCm/extensions_hub/auth.json` (Windows `%APPDATA%`, macOS `~/Library/Application Support`)
เปิด SketchUp ครั้งต่อไปจะ login ให้อัตโนมัติ; ออฟไลน์ยังปลดล็อคอยู่ แต่ฟีเจอร์ที่ต้องเรียก Odoo ใช้ไม่ได้

### สำหรับ plugin อื่น (Ruby API)

เช็ก Hub ตอนใช้งาน (ไม่ใช่ตอนโหลด — SketchUp โหลด plugin ตามลำดับชื่อไฟล์):

```ruby
auth = defined?(SkpCm::ExtensionsHub::Auth) ? SkpCm::ExtensionsHub::Auth : nil
auth && auth.logged_in?            # ปลดล็อคฟีเจอร์
auth.uid                           # Integer หรือ nil (ยังเชื่อมต่อ server ไม่ได้ / ออฟไลน์)
auth.relogin { |ok, error| }       # ลองเชื่อมต่อใหม่ด้วยบัญชีที่บันทึกไว้
listener = auth.on_change { |logged_in| }   # ถอดด้วย auth.off_change(listener)
auth.show_login                    # เปิดหน้า Hub
```
spec: `docs/specs/2026-10-12-hub-auth-design.md` (ใน workspace)

## Development

    for t in tests/tc_*.rb; do ruby "$t"; done   # unit tests (ไม่ต้องใช้ SketchUp)
    ./build.sh                                   # ได้ skp_cm_extensions_hub_<VERSION>.rbz
