#!/usr/bin/env bash
# Monitor các Tomcat instance v3 (~/tomcat/instance/*) + log ứng dụng ~/logs/sunnypoint, lặp mỗi 30s.
#   monitorv3.sh          chạy vòng lặp ở foreground (Ctrl-C hoặc "monitorv3.sh stop")
#   monitorv3.sh stop     dừng monitor đang chạy
#   monitorv3.sh status   monitor có đang chạy không
# Log instance (lỗi mới, khởi động, auto-reload): monitor-instances-tomcat.sh --quiet (tự popup macOS + alerts.jsonl)
# Thêm ở đây: instance DOWN/UP theo port, và log ứng dụng ~/logs/sunnypoint/*.log ([ERROR / Exception).
# Bỏ qua lỗi: thêm regex (mỗi dòng một regex) vào ~/tomcat/scripts/monitorv3-ignore.txt rồi restart monitor.
TC_ROOT="${TC_ROOT:-$HOME/tomcat}"
INTERVAL="${MONITORV3_INTERVAL:-30}"
STATE="$HOME/logs/monitorv3"; PID_FILE="$STATE/monitorv3.pid"; ALERT_LOG="$STATE/alerts.log"
APP_LOG_DIR="$HOME/logs/sunnypoint"
IGNORE_FILE="$TC_ROOT/scripts/monitorv3-ignore.txt"
MON="$TC_ROOT/scripts/monitor-instances-tomcat.sh"
mkdir -p "$STATE/off" "$STATE/up"; touch "$IGNORE_FILE"

running() { [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; }
case "${1:-}" in
  stop) if running; then kill "$(cat "$PID_FILE")"; echo "monitorv3 stopped (pid $(cat "$PID_FILE"))"; else echo "monitorv3 is not running"; fi; rm -f "$PID_FILE"; exit 0 ;;
  status) running && echo "monitorv3 running (pid $(cat "$PID_FILE"))" || echo "monitorv3 is not running"; exit 0 ;;
esac
running && { echo "monitorv3 already running (pid $(cat "$PID_FILE")), use: monitorv3.sh stop"; exit 1; }
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"; echo "monitorv3 stopped"; exit 0' INT TERM

ts() { date '+%Y-%m-%d %H:%M:%S'; }
alert() {  # <title> <msg>
  echo "$(ts) ALERT [$1] $2" | tee -a "$ALERT_LOG"
  osascript -e "display notification \"${2//\"/\'}\" with title \"monitorv3: ${1//\"/\'}\" sound name \"Basso\"" 2>/dev/null
}
filt() { grep -vEf "$IGNORE_FILE" || true; }
[[ -s "$IGNORE_FILE" ]] || filt() { cat; }

# Bắt đầu từ cuối mỗi file log ứng dụng: chỉ báo dòng mới
off_file() { echo "$STATE/off/$(echo "$1" | tr '/ ' '__')"; }
app_logs() { for f in "$APP_LOG_DIR"/*.log; do [[ -f "$f" && "$f" != *-json.log ]] && echo "$f"; done; }
for f in $(app_logs); do stat -f %z "$f" > "$(off_file "$f")" 2>/dev/null; done
"$MON" --quiet --no-notify >/dev/null 2>&1   # đặt mốc đọc log instance

echo "$(ts) monitorv3 started (pid $$, every ${INTERVAL}s). Stop: monitorv3.sh stop"
while true; do
  # 1) instance UP/DOWN theo port
  for d in "$TC_ROOT"/instance/*/; do
    [[ -f "$d/instance.env" ]] || continue; n=$(basename "$d")
    port=$(sed -n 's/^HTTP_PORT=//p' "$d/instance.env" | head -1)
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then now=up; else now=down; fi
    prev=$(cat "$STATE/up/$n" 2>/dev/null)
    if [[ "$now" == up && "$prev" == down ]]; then echo "$(ts) OK [$n] UP again (port $port)"
    elif [[ "$now" == down && "$prev" == up && ! -f "$d/.manual-stop" ]]; then alert "$n DOWN" "instance $n (port $port) stopped listening"
    fi
    echo "$now" > "$STATE/up/$n"
  done
  # 2) log instance (lỗi mới / khởi động / reload) — lọc thêm bằng ignore file khi in
  out=$("$MON" --quiet 2>&1); [[ -n "$out" ]] && echo "$out" | filt | tee -a "$ALERT_LOG"
  # 3) log ứng dụng
  for f in $(app_logs); do
    of=$(off_file "$f"); size=$(stat -f %z "$f" 2>/dev/null || echo 0); o=$(cat "$of" 2>/dev/null || echo 0)
    (( size < o )) && o=0
    if (( size > o )); then
      hits=$(tail -c +$((o + 1)) "$f" | grep -E '\[ERROR |Exception' | grep -vE '^[[:space:]]+at ' | filt | head -5 | cut -c1-300)
      [[ -n "$hits" ]] && alert "$(basename "$f")" "$(echo "$hits" | head -1)" && echo "$hits" | tail -n +2 | sed 's/^/    | /' | tee -a "$ALERT_LOG"
    fi
    echo "$size" > "$of"
  done
  sleep "$INTERVAL"
done
