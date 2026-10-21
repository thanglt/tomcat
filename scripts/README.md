# Tạo Tomcat instance mới bằng bộ script `~/tomcat/scripts`

Mỗi instance là một `CATALINA_BASE` riêng trong `~/tomcat/instance/<tên>` (port, log, work, temp riêng), dùng chung Tomcat gốc `~/tomcat/apache-tomcat-10.1.57` (`CATALINA_HOME`) cùng `setenv.sh` và `conf/` dùng chung.

Ví dụ bên dưới: instance **`myapp`**, port **`88`**, context **`/myapp`**, module **`sunnypoint-web-myapp`** — thay bằng giá trị của bạn. Mọi lệnh chạy trên Terminal của Mac.

## Instance hiện có

| Instance | HTTP port | Shutdown port | Context | `/` chuyển tới |
|---|---|---|---|---|
| server-api | 83 | 10083 | `/server` | — |
| admin | 84 | 10084 | `/admin` | `/admin/` |
| customer | 85 | 10085 | `/customer` | `/customer/` |
| retailer | 86 | 10086 | `/retailers`, `/takeout` | `/retailers/` |
| napoli | 87 | 10087 | `/napoli` | `/napoli/` |

Mọi instance đều tự có thêm `/cdn` (webapp dùng chung `sunnypoint-web-localcdn`). Xem danh sách mới nhất: `~/tomcat/scripts/tc.sh list` và `~/tomcat/scripts/status-all.sh`.

---

## Bước 0 — Kiểm tra điều kiện
```bash
ls ~/tomcat/apache-tomcat-10.1.57/bin/catalina.sh
ls ~/tomcat/scripts/{tc-init.sh,tc-create.sh,tc.sh,monitor-instances-tomcat.sh}
java -version
```

## Bước 1 — Khởi tạo Tomcat gốc (chỉ lần đầu)
```bash
~/tomcat/scripts/tc-init.sh
```
Đổi port trong `server.xml` gốc thành biến `${port.http}` / `${port.shutdown}` và tạo `setenv.sh` dùng chung (giữ nội dung cũ, có backup). Chạy lại nhiều lần vẫn an toàn.

## Bước 2 — Chọn port còn trống
```bash
lsof -nP -iTCP:88    -sTCP:LISTEN || echo "88 trống"
lsof -nP -iTCP:10088 -sTCP:LISTEN || echo "10088 trống"
```
Shutdown port mặc định = HTTP port + 10000.

## Bước 3 — Tạo instance
```bash
~/tomcat/scripts/tc-create.sh myapp 88
# tuỳ chọn: tc-create.sh <tên> <http-port> [shutdown-port] [empty|copy]
```
Kết quả:
- `~/tomcat/instance/myapp/` với `instance.env`, `conf/` (symlink tới conf gốc), `override/`, `apps/`, `logs/`, `temp/`, `work/`, `webapps/`
- Script tắt: `start-myapp.sh`, `stop-myapp.sh`, `restart-myapp.sh`, `status-myapp.sh`, `log-myapp.sh`, `conf-myapp.sh`, `clearlog-myapp.sh`
- Instance được thêm vào `monitor-instances-tomcat.sh` (và ingress Cloudflare nếu đã cấu hình tunnel)

## Bước 4 — Build và gắn webapp
```bash
cd ~/working/sunnypoint-v3/src/sunnypoint-web-myapp && mvn -q package -DskipTests   # tạo target/webapp-current
ln -s ~/working/sunnypoint-v3/src/sunnypoint-web-myapp/target/webapp-current ~/tomcat/instance/myapp/apps/myapp
~/tomcat/scripts/tc.sh webapps myapp
```
- Tên symlink trong `apps/` = tên context (`apps/myapp` → `/myapp`). Cần nhiều context thì tạo nhiều symlink.
- `tc.sh webapps` sinh `conf/Catalina/localhost/<context>.xml` (Context XML, `reloadable=true`) — sửa code/compile là Tomcat tự reload, không cần restart.
- `/cdn` được gắn tự động cho mọi instance (bỏ bằng `SHARED_WEBAPPS_SKIP="cdn"`).

## Bước 5 — Tuỳ chỉnh (nếu cần)
Sửa `~/tomcat/instance/myapp/instance.env`:
```bash
EXTRA_OPTS="-Dspring.profiles.active=dev"   # JVM options riêng
ROOT_REDIRECT="/myapp/"                      # "/" redirect 302 sang /myapp/ (dùng cho myapp.amanotesunny.com)
AUTO_RELOAD=true                             # tự reload khi class/jar đổi
DEV_CLASSES=true                             # dùng luôn target/classes do IDE compile
STATIC_CACHE_TTL=2000                        # ms, file tĩnh đổi là thấy
SHARED_WEBAPPS_SKIP=""                       # vd "cdn"
```
Override cấu hình chỉ cho instance này — đặt file vào `~/tomcat/instance/myapp/override/`:
- `override/setenv.sh` → chạy **sau** `setenv.sh` dùng chung
- `override/<file>.properties` → gộp theo key (key của instance thắng)
- file khác (vd `context.xml`) → thay hẳn file gốc

Kiểm tra cấu hình thực tế: `~/tomcat/scripts/conf-myapp.sh`.

## Bước 6 — Start và kiểm tra
```bash
lsof -nP -iTCP:6379 -sTCP:LISTEN || brew services start redis   # app cần Redis
~/tomcat/scripts/start-myapp.sh          # chờ: "KHỞI ĐỘNG THÀNH CÔNG trong X ms"
curl -sI http://localhost:88/myapp/ | head -1
curl -sI http://localhost:88/ | grep -i location   # nếu có ROOT_REDIRECT
~/tomcat/scripts/log-myapp.sh            # theo dõi catalina.out
```
Lỗi khởi động: xem `~/tomcat/instance/myapp/logs/catalina.out` và `localhost.<ngày>.log`, tìm dòng `Caused by` cuối cùng.

## Bước 7 — (Tuỳ chọn) Mở ra Internet qua Cloudflare Tunnel
```bash
~/tomcat/scripts/tc-tunnel.sh all    # thêm myapp.amanotesunny.com -> http://localhost:88, tạo DNS, restart cloudflared
```
Đổi hostname: `CF_HOSTNAME="..."` trong `instance.env`; không mở ra ngoài: `CF_TUNNEL=off`.

---

## Thao tác hằng ngày
```bash
~/tomcat/scripts/start-myapp.sh | stop-myapp.sh | restart-myapp.sh | status-myapp.sh
~/tomcat/scripts/start-all.sh  | stop-all.sh   | restart-all.sh   | status-all.sh
~/tomcat/scripts/clearlog-myapp.sh   # xoá log 1 instance (an toàn khi đang chạy)
~/tomcat/scripts/clearlog-all.sh
~/tomcat/scripts/tc.sh webapps myapp # sau khi thêm/bớt symlink trong apps/ (rồi restart)
~/tomcat/scripts/tc.sh reload myapp myapp   # redeploy 1 context không cần restart
~/tomcat/scripts/cdn-reload.sh       # build sunnypoint-web-localcdn + redeploy /cdn mọi instance
~/tomcat/scripts/monitor-instances-tomcat.sh   # trạng thái + lỗi log mọi instance
```

## Lỗi thường gặp
| Hiện tượng | Nguyên nhân / cách xử lý |
|---|---|
| `Address already in use` | Port bị chiếm — `lsof -nP -iTCP:<port> -sTCP:LISTEN`, chọn port khác hoặc dừng tiến trình đó |
| `RedisConnectionException localhost:6379` | Redis chưa chạy — `brew services start redis` |
| `/cdn/webjars/...` 404 sau khi build localcdn, log lặp `NoSuchFileException .../WEB-INF/lib/*.jar` | Jar đổi version, Tomcat không tự reload — `~/tomcat/scripts/cdn-reload.sh --no-build` |
| Context không xuất hiện | Chưa build (`target/webapp-current` chưa có) hoặc chưa chạy `tc.sh webapps <tên>` rồi restart |
| `OutOfMemoryError: Metaspace` sau nhiều lần reload | Restart instance; instance chạy lâu đặt `AUTO_RELOAD=false` |
