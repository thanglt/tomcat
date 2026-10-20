#!/usr/bin/env bash
# Chuẩn bị Tomcat gốc: server.xml dùng ${port.*}, setenv.sh dùng chung. Chạy lại vẫn an toàn.
# - Port cũ trong server.xml được giữ làm mặc định cho chính Tomcat gốc (khi chạy không qua instance).
# - Nội dung setenv.sh cũ được giữ lại thành phần "option chung".
set -euo pipefail
TC_ROOT="${TC_ROOT:-$HOME/tomcat}"
CATALINA_HOME="${CATALINA_HOME:-$TC_ROOT/apache-tomcat-10.1.57}"
SX="$CATALINA_HOME/conf/server.xml"
SE="$CATALINA_HOME/bin/setenv.sh"
SE_MARK="TC-MULTI-INSTANCE v2"

[[ -x "$CATALINA_HOME/bin/catalina.sh" ]] || { echo "Không thấy $CATALINA_HOME"; exit 1; }

# 1) server.xml chung: thay port của <Server> và HTTP <Connector> đầu tiên (bỏ qua phần comment)
OLD_HTTP=""; OLD_SHUT=""
if ! grep -q '\${port.http}' "$SX"; then
  [[ -f "$SX.orig" ]] || cp "$SX" "$SX.orig"
  OLD_SHUT=$(perl -0ne 's/<!--.*?-->//gs; print $1 if /<Server\s+port="(\d+)"/' "$SX")
  OLD_HTTP=$(perl -0ne 's/<!--.*?-->//gs; print $1 if /<Connector\s+port="(\d+)"\s+protocol="HTTP\/1\.1"/' "$SX")
  perl -0pi -e 'my ($s, $c) = (0, 0);
    s{(<!--.*?-->)|<Server(\s+)port="\d+"|<Connector(\s+)port="\d+"(?=\s+protocol="HTTP/1\.1")}{
      defined $1 ? $1
      : defined $2 ? ($s++ ? $& : "<Server${2}port=\"\${port.shutdown}\"")
      : ($c++ ? $& : "<Connector${3}port=\"\${port.http}\"")
    }gse' "$SX"
  echo "Đã cập nhật $SX (port cũ: http=${OLD_HTTP:-?} shutdown=${OLD_SHUT:-?}; backup: $SX.orig)"
fi
grep -q '\${port.http}' "$SX" && grep -q '\${port.shutdown}' "$SX" || { echo "Không thay được port trong server.xml, kiểm tra thủ công"; exit 1; }

# 2) setenv.sh chung (chỉ ghi nếu chưa phải bản v2; luôn backup + giữ nội dung cũ)
if ! grep -qsF "$SE_MARK" "$SE"; then
  OLD_SE=""
  if [[ -f "$SE" ]]; then
    BAK="$SE.bak.$(date +%Y%m%d%H%M%S)"; cp "$SE" "$BAK"; echo "Đã backup setenv.sh cũ: $BAK"
    OLD_SE="# ---- giữ lại từ setenv.sh cũ ($(basename "$BAK")) ----
$(cat "$SE")
# ---- hết phần cũ ----"
  else
    OLD_SE='CATALINA_OPTS="$CATALINA_OPTS -Xms256m -Xmx1024m"
CATALINA_OPTS="$CATALINA_OPTS -Dfile.encoding=UTF-8 -Duser.timezone=Asia/Ho_Chi_Minh"'
  fi
  cat > "$SE.new" <<'EOS'
# TC-MULTI-INSTANCE v2 — setenv.sh dùng chung cho mọi instance
# Thứ tự: mặc định -> instance.env -> option chung -> override/setenv.sh -> port + EXTRA_OPTS

# 1) Mặc định (dùng khi chạy chính Tomcat gốc) + giá trị riêng của instance
HTTP_PORT=@@HTTP@@
SHUTDOWN_PORT=@@SHUT@@
EXTRA_OPTS=""
[ -r "$CATALINA_BASE/instance.env" ] && . "$CATALINA_BASE/instance.env"

CATALINA_PID="$CATALINA_BASE/temp/tomcat.pid"
CATALINA_OUT="$CATALINA_BASE/logs/catalina.out"

# 2) Option chung (sửa ở đây để áp dụng cho mọi instance)
# JAVA_HOME=/path/to/jdk
@@COMMON@@

# 3) Override riêng của instance (ưu tiên hơn phần chung)
if [ "$CATALINA_BASE" != "$CATALINA_HOME" ] && [ -r "$CATALINA_BASE/override/setenv.sh" ]; then
  . "$CATALINA_BASE/override/setenv.sh"
fi

# 4) Luôn thêm cuối: port cho server.xml chung + EXTRA_OPTS
CATALINA_OPTS="$CATALINA_OPTS -Dport.http=$HTTP_PORT -Dport.shutdown=$SHUTDOWN_PORT $EXTRA_OPTS"
EOS
  P_HTTP="${OLD_HTTP:-8080}" P_SHUT="${OLD_SHUT:-8005}" P_COMMON="$OLD_SE" \
    perl -0pi -e 's/\@\@HTTP\@\@/$ENV{P_HTTP}/; s/\@\@SHUT\@\@/$ENV{P_SHUT}/; s/\@\@COMMON\@\@/$ENV{P_COMMON}/' "$SE.new"
  mv -f "$SE.new" "$SE"; chmod +x "$SE"
fi
echo "OK: server.xml + setenv.sh chung tại $CATALINA_HOME"
