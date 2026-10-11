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
- `files` = ไฟล์/โฟลเดอร์ใน Plugins folder (ตัวแรกคือ loader) — ใช้ตอนถอน
- Release: tag `vX.Y.Z`, แนบ `.rbz` 1 ไฟล์, ใน `.rbz` มีเฉพาะสิ่งที่อยู่ใน `files`

## Development

    for t in tests/tc_*.rb; do ruby "$t"; done   # unit tests (ไม่ต้องใช้ SketchUp)
    ./build.sh                                   # ได้ skp_cm_extensions_hub_<VERSION>.rbz
