# IosNoti

Theos project gồm **SpringBoard tweak** + **app UIKit (Objective-C)** dùng chung lớp dữ liệu.

- **Bước 1** — khung dự án + ConfigManager / SignatureHelper / DatabaseManager ✅
- **Bước 2** — hook `BBServer -publishBulletin:destinations:` → POST JSON lên server → lưu DB ✅
- **Bước 3** — App quản lý: TabBar (Lịch sử + Cấu hình), Detail có "Gửi lại", gửi thử + Darwin notification ✅
- **Bước 4** — rà soát Makefile/control/framework + `build_and_deploy.sh` ✅

## Cấu trúc

```
Makefile                  # aggregate: build cả tweak + app
control                   # metadata package
shared/
  IosNotiPaths.h/.m       # tự nhận rootless (/var/jb) vs rootful
  IosNotiLog.h            # macro INLog
  ConfigManager.h/.m      # server_url, app_id, sim_id, secret_key (+ reloadIfChanged)
  SignatureHelper.h/.m    # MD5/SHA256 chữ thường
  ChargeRecord.h/.m       # model 1 bản ghi
  DatabaseManager.h/.m    # SQLite3: charge_records (migrate v1 → v2)
  NetworkManager.h/.m     # NSURLSession POST JSON (sync + async)
  NotificationPayloadBuilder.h/.m   # dựng payload + chữ ký
  NotificationDispatcher.h/.m       # trích xuất → gửi → lưu, submitPayload/repost
  IosNotiDarwin.h/.m      # Darwin notification "com.iosnoti.config.changed"
tweak/
  Makefile, IosNotiTweak.plist, Tweak.xm
app/
  Makefile, entitlements.plist, main.m, AppDelegate
  MainTabBarController      # 2 tab
  HistoryViewController     # tab 1: danh sách + pull to refresh
  SettingsViewController    # tab 2: config + công thức + gửi thử
  DetailViewController      # JSON gửi đi + response + nút Gửi lại
  RecordStatus.h/.m         # text/màu trạng thái, format thời gian
  RootViewController.h/.m   # (cũ, không còn build — thay bằng HistoryViewController)
  Resources/Info.plist
build_and_deploy.sh
```

## Đường dẫn dữ liệu

| Loại | Rootless | Rootful |
|---|---|---|
| Config | `/var/jb/var/mobile/Library/Preferences/com.iosnoti.config.plist` | `/var/mobile/Library/Preferences/...` |
| DB | `/var/jb/var/mobile/Library/Preferences/com.iosnoti.records.db` | `/var/mobile/Library/Preferences/...` |

## Config mặc định

| Key | Mặc định |
|---|---|
| `server_url` | `http://domain:10007/api/MM/PutChargeNotify` |
| `app_id` | `bank_vietcombank` |
| `sim_id` | `bank_vietcombank\|123` |
| `secret_key` | `123456` |

Sửa file config bên App → Tweak tự `reloadIfChanged` ở lần gửi kế tiếp, không cần respring.

## Payload gửi lên server (Bước 2)

`POST <server_url>`, `Content-Type: application/json`

```json
{
  "app_id": "com.mo2pay.test",
  "sender": "[TEST] Thông báo thử nghiệm",
  "time": "1793884666515",
  "id": "1793884666515",
  "tracking_code": "bank_vietcombank|123",
  "message": "Kiểm tra kết nối ...",
  "signature": "cee29fbfdcc54853ff50c67fdb7e2ce9",
  "type": "NOTIFICATION",
  "sim": "bank_vietcombank|123"
}
```

| Field | Nguồn |
|---|---|
| `app_id` | `bulletin.sectionID` (fallback `section`, `bulletinID`) |
| `sender` | `bulletin.title`, fallback `bulletin.subtitle` |
| `message` | `bulletin.message` |
| `time` | Unix **milliseconds** dạng chuỗi |
| `id` | `bulletin.bulletinID`, fallback chính `time` |
| `sim` / `tracking_code` | `ConfigManager.simID` |
| `type` | cố định `"NOTIFICATION"` |
| `signature` | MD5 chữ thường, xem dưới |

## Công thức chữ ký (port sang server C#)

```
plain     = app_id + "|" + id + "|" + time + "|" + sim + "|" + secret_key
signature = MD5_hex_lowercase(UTF8(plain))
```

- `sim` là `sim_id` nguyên vẹn — bản thân nó đã chứa dấu `|` (`bank_vietcombank|123`),
  nên plain có 5 dấu `|`.
- Field rỗng/nil → chuỗi `""`, không bỏ field.

```csharp
var plain = $"{app_id}|{id}|{time}|{sim}|{secret_key}";
var sig = Convert.ToHexString(System.Security.Cryptography.MD5.HashData(
              System.Text.Encoding.UTF8.GetBytes(plain))).ToLowerInvariant();
```

> ⚠️ **Chữ ký mẫu `cee29fbfdcc54853ff50c67fdb7e2ce9` trong tài liệu KHÔNG khớp công thức trên.**
> Với `secret_key = "123456"`, MD5 của chuỗi mẫu là `5a5edaab8762018a69f43d5a03742126`.
> Tweak in `plain` + `md5` ra syslog ở mỗi lần khởi động, dùng log đó để chốt đúng
> `secret_key` / thứ tự field với server.

## Luồng bắt thông báo

```
SpringBoard
  └─ %hook BBServer -publishBulletin:destinations:
       └─ NotificationDispatcher handleBulletin:
            ├─ trích xuất sectionID/bulletinID/title/subtitle/message (respondsToSelector + @try)
            ├─ dedup theo id (giữ 256 id gần nhất)
            ├─ NotificationPayloadBuilder → payload + signature
            ├─ insert DB  (http_status = 0 pending)   ← trước khi gửi
            └─ queue nền: NetworkManager POST
                 ├─ lỗi mạng  → retry 2 lần, cách 2s, cùng rowID
                 └─ xong       → update http_status + response_body
                                  (200 → 200; lỗi mạng → -1)
```

Lúc SpringBoard khởi động, sau 10 giây sẽ gửi lại tối đa 20 bản ghi `http_status = 0`.
DB tự trim còn 2000 bản ghi mới nhất.

Hook phụ `-publishBulletin:destinations:featurizationContext:` được cài bằng
`MSHookMessageEx` **chỉ khi** method tồn tại và đúng 5 argument — không crash trên iOS
không có selector đó.

## Bảng `charge_records`

`row_id | id | app_id | sender | message | time | tracking_code | signature | sim | type | http_status | response_body | payload_json | created_at`

`http_status`: `0` = pending, `-1` = lỗi mạng, còn lại là HTTP status thực.

## Build & cài

### Cách 1 — script tự động (khuyến nghị)

```bash
chmod +x build_and_deploy.sh
./build_and_deploy.sh 192.168.1.25            # port mặc định 22
./build_and_deploy.sh 192.168.1.25 2222       # port khác
IP=192.168.1.25 PORT=2222 THEOS=/opt/theos ./build_and_deploy.sh
```

Script làm: kiểm tra SSH → nhận diện rootless/rootful → `make clean` + `make package FINALPACKAGE=1`
→ chọn `.deb` mới nhất → `scp` sang `/tmp` → `dpkg -i` → `uicache` → `killall SpringBoard`.

### Cách 2 — thủ công

```bash
export THEOS=/opt/theos
make clean package            # tạo .deb trong packages/
scp -P 22 packages/*.deb root@192.168.1.25:/tmp/
ssh root@192.168.1.25 "/var/jb/usr/bin/dpkg -i /tmp/com.iosnoti.pack_1.0.0_iphoneos-arm64.deb"
ssh root@192.168.1.25 "uicache -a; killall -9 SpringBoard"
```

Máy test: iOS `[điền iOS]` — mặc định cấu hình là **iOS 15/16 rootless**.
Nếu là iOS 14 rootful: bỏ `THEOS_PACKAGE_SCHEME = rootless` trong `Makefile` gốc
và hạ `TARGET` / `MinimumOSVersion` xuống `14.0`.

### Framework / thư viện được link

| Target | Frameworks | Libraries |
|---|---|---|
| tweak | Foundation, UIKit, CoreFoundation | `-lsqlite3` |
| app | Foundation, UIKit, CoreFoundation | `-lsqlite3` |

CoreFoundation cần cho `CFNotificationCenterGetDarwinNotifyCenter` (nút "Lưu cấu hình"
báo Tweak không cần respring). App được sign kèm `app/entitlements.plist`
(`platform-application`, `com.apple.private.security.no-container`) để ghi được vào
thư mục Preferences dùng chung với tweak.

## App: Tab 1 "Lịch sử"

- `UITableView` các gói tin đã gửi: `app_id`, nội dung tóm tắt, thời gian, trạng thái
  (`Thành công (200)` xanh · `Thất bại (500)` đỏ · `Lỗi mạng` đỏ · `Chờ gửi` cam).
- Kéo xuống để làm mới; nút thùng rác xoá toàn bộ lịch sử.
- Chạm vào dòng → màn hình chi tiết: JSON đã gửi, response server, status, signature.
  Nút hành động → **Gửi lại (Repost)** gửi lại **đúng** payload đã lưu (cùng `id`,
  `time`, `signature`), cập nhật lại kết quả và refresh danh sách.

## App: Tab 2 "Cấu hình"

- 3 ô nhập: **URL Server**, **SIM**, **Khóa bí mật**.
- Ngay dưới là khung ghi chú công thức Signature + preview `plain` và `MD5` mẫu,
  cập nhật theo từng ký tự bạn gõ — tiện đối chiếu với server C#.
- **Lưu cấu hình**: ghi plist + bắn Darwin notification `com.iosnoti.config.changed`
  → tweak gọi `reload` ngay, không cần respring.
- **Gửi thử dữ liệu lên Server**: dựng gói mẫu `app_id = com.mo2pay.test`, ký bằng khóa
  hiện tại, POST, lưu vào lịch sử, rồi `UIAlertController` hiện HTTP code + body server trả về.

## Kiểm tra sau khi cài

1. Resprring → log: `loaded. server=...`, `db ready: ...`, `signature sample plain=...`,
   `signature sample md5=...`.
2. Gửi thử 1 notification bất kỳ (Zalo, SMS, Telegram...) → log:
   `captured app=... id=... sender=...` → `POST attempt 1/3 -> ...` → `result status=200 ...`.
3. Mở app **IosNoti** → Tab **Lịch sử** có bản ghi mới; chạm vào để xem
   payload JSON + response body + chữ ký, nút **Copy** hoặc **Gửi lại**.
4. Tab **Cấu hình** → sửa URL/SIM/Secret Key → **Lưu cấu hình** → log
   `darwin notification received` + `config reloaded via darwin notification`.
5. Tab **Cấu hình** → **Gửi thử dữ liệu lên Server** → alert hiện HTTP code + body.

Xem log:

```bash
idevicesyslog | grep IosNoti
```

## Giới hạn đã biết

- Tweak hook `BBServer` trong SpringBoard: bắt được bulletin mà bulletin-system **publish
  cho SpringBoard**. App dùng Notification Service Extension riêng hoặc bị kill
  notification hoàn toàn có thể không đi qua đường này.
- Cấm respring sau khi cài đặt: `%ctor` chạy rất sớm, nếu bạn đổi cấu trúc DB nhiều lần
  thì nên xoá file `.db` cũ để tránh migrate lỗi.
- Server phải là HTTP hoặc HTTPS có cert hợp lệ — App đã bật `NSAllowsArbitraryLoads`,
  tweak dùng `NSURLSession` trong SpringBoard nên ATS của SpringBoard áp dụng (SPRINGBOARD
  bình thường đã cho phép HTTP trong nhiều trường hợp, nếu lỗi hãy thử HTTPS).
