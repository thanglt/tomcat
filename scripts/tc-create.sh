#!/usr/bin/env bash
# Usage: tc-create.sh <name> <http_port> [shutdown_port] [empty|copy]
set -euo pipefail
TC_ROOT="${TC_ROOT:-$HOME/tomcat}"
CATALINA_HOME="${CATALINA_HOME:-$TC_ROOT/apache-tomcat-10.1.57}"
INSTANCES="$TC_ROOT/instance"
SCRIPTS="$TC_ROOT/scripts"

NAME="${1:?Thiếu tên instance}"
HTTP_PORT="${2:?Thiếu HTTP port}"
SHUTDOWN_PORT="${3:-$((HTTP_PORT + 10000))}"
WEBAPPS_MODE="${4:-empty}"
BASE="$INSTANCES/$NAME"

[[ "$NAME" =~ ^[A-Za-z0-9_-]+$ && "$NAME" != "all" ]] || { echo "Tên không hợp lệ: $NAME"; exit 1; }
[[ -e "$BASE" ]] && { echo "Instance đã tồn tại: $BASE"; exit 1; }
"$SCRIPTS/tc-init.sh" >/dev/null

port_in_use() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
for p in "$HTTP_PORT" "$SHUTDOWN_PORT"; do
  port_in_use "$p" && { echo "Port $p đang được dùng"; exit 1; }
  grep -qs "_PORT=$p$" "$INSTANCES"/*/instance.env && { echo "Port $p đã gán cho instance khác"; exit 1; }
done

# Cảnh báo nếu trùng port mặc định của chính Tomcat gốc (setenv chung)
HOME_HTTP=$(sed -n 's/^HTTP_PORT=//p' "$CATALINA_HOME/bin/setenv.sh" 2>/dev/null | head -1)
HOME_SHUT=$(sed -n 's/^SHUTDOWN_PORT=//p' "$CATALINA_HOME/bin/setenv.sh" 2>/dev/null | head -1)
if [[ "$HTTP_PORT" == "$HOME_HTTP" || "$SHUTDOWN_PORT" == "$HOME_SHUT" ]]; then
  echo "CẢNH BÁO: port trùng với Tomcat gốc ($CATALINA_HOME: http=$HOME_HTTP shutdown=$HOME_SHUT)."
  echo "          Đừng chạy Tomcat gốc (startup.sh) cùng lúc với instance '$NAME'."
fi

mkdir -p "$BASE"/{conf,override,apps,logs,temp,webapps,work}

if [[ "$WEBAPPS_MODE" == "copy" ]]; then
  for app in ROOT manager host-manager; do
    [[ -d "$CATALINA_HOME/webapps/$app" ]] && cp -R "$CATALINA_HOME/webapps/$app" "$BASE/webapps/"
  done
fi

cat > "$BASE/instance.env" <<EOS
INSTANCE_NAME=$NAME
HTTP_PORT=$HTTP_PORT
SHUTDOWN_PORT=$SHUTDOWN_PORT
# JVM options thêm cuối cùng, vd: EXTRA_OPTS="-Dspring.profiles.active=dev"
EXTRA_OPTS=""
# Webapp (khai báo bằng symlink trong apps/<context>) — tự reload khi code thay đổi
AUTO_RELOAD=true          # Context reloadable: reload khi WEB-INF/classes hoặc WEB-INF/lib đổi
DEV_CLASSES=true          # mount <module>/target/classes (IDE compile) vào /WEB-INF/classes
STATIC_CACHE_TTL=2000     # ms; file tĩnh đổi là thấy sau tối đa N ms
SHARED_WEBAPPS_SKIP=""    # vd "cdn" để không dùng webapp chung
# ROOT_REDIRECT="/admin/"  # redirect / -> context chính (tuỳ chọn)
EOS

cat > "$BASE/override/README.txt" <<'EOS'
Đặt file cần override vào đây:
- setenv.sh    : được source SAU setenv chung -> giá trị ở đây thắng.
                 Nối thêm: CATALINA_OPTS="$CATALINA_OPTS -Xmx2g"   | Thay hẳn: CATALINA_OPTS="-Xmx4g"
- *.properties : chỉ ghi các key cần đổi -> merge, key ở đây thắng.
- File khác (web.xml, context.xml, tomcat-users.xml, server.xml...) : thay toàn bộ file chung.
Sau khi sửa: tc.sh restart <name>
EOS

# Monitor đọc log của instance mới từ đầu (không bỏ qua lần khởi động đầu tiên)
for st in "$TC_ROOT/monitor/state" "$TC_ROOT/monitor/state-agent"; do
  mkdir -p "$st/$NAME"; rm -f "$st/$NAME"/*.off
done

"$SCRIPTS/tc.sh" sync "$NAME" >/dev/null
"$SCRIPTS/tc.sh" webapps "$NAME" >/dev/null   # sinh Context XML cho apps/ + shared-webapps/ (vd cdn)
"$SCRIPTS/tc.sh" wrappers                     # sinh script prefix + cập nhật monitor

echo "Đã tạo '$NAME' tại $BASE  (HTTP $HTTP_PORT, shutdown $SHUTDOWN_PORT)"
echo "  Thêm webapp: ln -s <.../target/webapp-current> $BASE/apps/<context> && $SCRIPTS/tc.sh webapps $NAME"
echo "  $SCRIPTS/start-$NAME.sh | stop-$NAME.sh | clearlog-$NAME.sh"
