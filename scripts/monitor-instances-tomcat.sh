#!/usr/bin/env bash
# monitor-instances-tomcat.sh — Quét log + trạng thái của mọi Tomcat instance
# ALERT chỉ khi: (1) có dòng lỗi mới trong log, (2) instance vừa khởi động / webapp vừa auto-reload xong.
# Usage: monitor-instances-tomcat.sh [--logs-only] [--json] [--quiet] [--no-notify]
#   --logs-only  chỉ quét log, không kiểm tra process/HTTP (dùng cho Claude agent);
#                dùng state riêng monitor/state-agent và file *-agent
#   --json       in JSON     --quiet  chỉ in khi có alert     --no-notify  không popup macOS
# Exit code (trạng thái): 0 = OK, 1 = WARN, 2 = CRIT
#
# An toàn khi start/stop/restart/clearlog instance:
#  - offset lưu theo từng file + chữ ký đầu file -> phát hiện truncate/xoá/tạo lại, không đọc trùng, không bỏ sót
#  - chỉ đọc tới dòng hoàn chỉnh cuối cùng (không cắt nửa dòng khi Tomcat đang ghi)
#  - lỗi phát sinh trong lúc shutdown (sau "Stopping service") không bị tính là lỗi
#  - instance stop thủ công không bị coi là lỗi; instance mới được đọc log từ đầu
set -o pipefail

TC_ROOT="${TC_ROOT:-$HOME/tomcat}"
INSTANCES_DIR="$TC_ROOT/instance"
MON_DIR="$TC_ROOT/monitor"

# ===== Ngưỡng / tuỳ chọn (sửa tuỳ ý) =====
HTTP_TIMEOUT=5
ERROR_PATTERN='SEVERE|ERROR|Exception|OutOfMemoryError|StackOverflowError|Address already in use|Too many open files'
CRIT_PATTERN='OutOfMemoryError|StackOverflowError|Address already in use|Too many open files'
IGNORE_PATTERN='ClientAbortException|Broken pipe|appears to have started a thread named|failed to stop it\. This is very likely to create a memory leak|registered the JDBC driver'
STARTUP_PATTERN='Server startup in \[?[0-9.,]+\]? ?(milliseconds|ms)'
RELOAD_PATTERN='Reloading Context with name \[[^]]*\] is completed'   # auto-reload (reloadable=true)
SHUTDOWN_BEGIN='Stopping service \[Catalina\]|Pausing ProtocolHandler|Stopping ProtocolHandler'
SHUTDOWN_END='Starting service \[Catalina\]|Server version name|Starting ProtocolHandler|Initializing ProtocolHandler|Server startup in|Reloading Context with name'
IGNORE_SHUTDOWN_ERRORS=1   # 1 = bỏ qua lỗi xuất hiện trong lúc Tomcat đang dừng
MAX_ERROR_LINES=8          # số dòng lỗi mẫu mỗi instance
MAX_READ_MB=50             # đọc tối đa N MB log mới mỗi file mỗi lần
LOG_DIR_WARN_MB=1024       # báo WARN (trong report) khi thư mục logs lớn hơn
HTTP_5XX_WARN=20           # báo WARN (trong report) khi số request 5xx mới >=
ALERT_ON_STATUS=0          # 1 = alert cả khi process chết / HTTP lỗi / 5xx / logs lớn (chế độ đầy đủ)
NOTIFY_MACOS=1             # popup macOS khi có alert
AUTO_RESTART=0             # 1 = tự start instance bị chết (chế độ đầy đủ, không áp dụng khi stop thủ công)
ALERTS_KEEP=5000           # số dòng giữ lại trong alerts*.jsonl

# ===== Danh sách instance =====
# BEGIN INSTANCES (tự sinh bởi tc-create.sh / "tc.sh wrappers" — chỉ sửa cột health_path và on/off)
# name|http_port|health_path|on/off
INSTANCES_CONF=(
  "admin|84|/|on"
  "batch|89|/|on"
  "customer|85|/|on"
  "liquibase|91|/|on"
  "napoli|87|/|on"
  "retailer|86|/|on"
  "sender|88|/|on"
  "server-api|83|/|on"
)
# END INSTANCES

OUT=text; QUIET=0; LOGS_ONLY=0
for a in "$@"; do case "$a" in --json) OUT=json;; --quiet) QUIET=1;; --no-notify) NOTIFY_MACOS=0;; --logs-only) LOGS_ONLY=1;; esac; done
SUFFIX=""; MODE="full"
if (( LOGS_ONLY )); then SUFFIX="-agent"; MODE="logs-only"; fi
STATE_DIR="$MON_DIR/state$SUFFIX"
mkdir -p "$STATE_DIR"

# Khoá tránh 2 lần chạy chồng nhau (mỗi chế độ một file khoá chứa PID).
# Không cần quyền xoá file (agent chạy trong VM không xoá được file trong folder kết nối).
# Khoá bị bỏ lại (process đã chết, hoặc cũ hơn 10 phút) được bỏ qua -> monitor không bao giờ bị kẹt.
LOCK="$MON_DIR/.lock$SUFFIX.pid"
lpid=$(cat "$LOCK" 2>/dev/null)
if [[ -n "$lpid" && "$lpid" != "$$" ]] && kill -0 "$lpid" 2>/dev/null && [[ -z "$(find "$LOCK" -mmin +10 2>/dev/null)" ]]; then
  echo "monitor đang chạy (pid $lpid), bỏ qua lần này"; exit 0
fi
echo $$ > "$LOCK"
trap ': > "$LOCK"' EXIT

json_esc() { printf '%s' "$1" | perl -0pe 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r//g; s/\n/\\n/g; s/[\x00-\x08\x0b\x0c\x0e-\x1f]//g'; }
sev_label() { case "$1" in 0) echo OK;; 1) echo WARN;; *) echo CRIT;; esac; }

# In phần log mới (chỉ tới dòng hoàn chỉnh cuối cùng) và cập nhật offset.
# State: "<offset> <sig_len> <sig>" — sig = checksum của sig_len byte đầu file.
# File bị truncate / xoá rồi tạo lại / thay nội dung -> đọc lại từ đầu.
# BASELINE=1: chỉ đánh dấu vị trí cuối file, không in gì.
new_content() {
  BASELINE="${3:-0}" MAXB=$((MAX_READ_MB * 1048576)) perl -e '
    my ($f, $st) = @ARGV;
    open(my $fh, "<", $f) or exit 0; binmode $fh;
    my $size = -s $fh;
    my ($off, $slen, $sig) = (0, 0, "");
    if (open(my $s, "<", $st)) { my $l = <$s> // ""; chomp $l; ($off, $slen, $sig) = split / /, $l; close $s; }
    $off = 0 unless defined $off && $off =~ /^\d+$/;
    $slen = 0 unless defined $slen && $slen =~ /^\d+$/;
    $sig = "" unless defined $sig;
    sub sig_of { my ($fh, $n) = @_; return "" if $n <= 0; seek($fh, 0, 0); read($fh, my $b, $n); return unpack("%32C*", $b) . "x" . length($b); }
    if ($size < $off || ($slen > 0 && sig_of($fh, $slen) ne $sig)) { $off = 0; }
    my $used = 0; my $data = "";
    if ($ENV{BASELINE}) {
      $used = $size - $off;
    } elsif ($size > $off) {
      my $len = $size - $off;
      if ($len > $ENV{MAXB}) { $off = $size - $ENV{MAXB}; $len = $ENV{MAXB}; }
      seek($fh, $off, 0); read($fh, $data, $len);
      my $nl = rindex($data, "\n");
      $used = $nl >= 0 ? $nl + 1 : 0;
      $used = length($data) if $used == 0 && length($data) > 1048576;   # 1 dòng > 1MB: lấy luôn
      print substr($data, 0, $used);
    }
    my $noff = $off + $used;
    my $nslen = $noff < 256 ? $noff : 256;
    open(my $o, ">", "$st.tmp") or exit 0;
    print $o $noff . " " . $nslen . " " . sig_of($fh, $nslen) . "\n"; close $o;
    rename("$st.tmp", $st);
  ' "$1" "$2/$(basename "$1").off"
}

# Bỏ các dòng nằm trong giai đoạn shutdown (từ "Stopping service" tới lần "Starting service" kế tiếp).
# Trạng thái "đang shutdown" được lưu theo file log, nên vẫn đúng khi lần quét rơi vào giữa lúc dừng.
drop_shutdown() {
  local sf="$1"
  if (( IGNORE_SHUTDOWN_ERRORS )); then
    SB="$SHUTDOWN_BEGIN" SE="$SHUTDOWN_END" S0="$(cat "$sf" 2>/dev/null)" SF="$sf" awk '
      BEGIN { s = ENVIRON["S0"] + 0 }
      $0 ~ ENVIRON["SE"] { s = 0 }
      $0 ~ ENVIRON["SB"] { s = 1 }
      !s { print }
      END { print s > ENVIRON["SF"] }'
  else cat; fi
}

OVERALL=0; ALERT=0; HAS_ERR=0
TEXT_ROWS=(); TEXT_DETAILS=(); JSON_ITEMS=(); ALERT_SUMMARY=()
ROW_FMT='%-16s %-5s %-8s %-7s %-5s %-6s %-7s %-7s %-5s %-5s %s'

check_instance() {
  local name="$1" port="$2" path="$3" base="$INSTANCES_DIR/$1" sdir="$STATE_DIR/$1"
  local sev=0 state="RUNNING" pid="" http="-" cpu="-" rss="-" logmb=0 errs=0 h5xx=0 first=0 stopped_log=0
  local startup_ms="" reloaded="" ialert=0 msgs=() reasons=() samples="" all_err="" f n content matched
  raise() { (( $1 > sev )) && sev=$1; msgs+=("$2"); }

  [[ -n "$EXTRA_MSG" ]] && { raise 1 "$EXTRA_MSG"; EXTRA_MSG=""; }

  if [[ ! -f "$base/instance.env" ]]; then
    state="MISSING"; raise 2 "instance không tồn tại ($base) — chạy tc.sh wrappers"
  else
    [[ -d "$sdir" ]] || { first=1; mkdir -p "$sdir"; }

    if (( LOGS_ONLY )); then
      # Agent không thấy process của Mac: chỉ ghi nhận trạng thái theo file
      state="-"; [[ -f "$base/.manual-stop" ]] && state="STOPPED"
      [[ -f "$base/temp/tomcat.pid" ]] && pid=$(cat "$base/temp/tomcat.pid" 2>/dev/null)
    else
      [[ -f "$base/temp/tomcat.pid" ]] && pid=$(cat "$base/temp/tomcat.pid" 2>/dev/null)
      if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        pid=""
        if [[ -f "$base/.manual-stop" ]]; then
          state="STOPPED"; msgs+=("đã stop thủ công lúc $(cat "$base/.manual-stop")")
        else
          state="DOWN"; raise 2 "process không chạy (không phải stop thủ công)"
          if (( AUTO_RESTART )); then
            if "$TC_ROOT/scripts/tc.sh" start "$name" >/dev/null 2>&1; then msgs+=("AUTO_RESTART: đã start lại"); else msgs+=("AUTO_RESTART: start lại thất bại"); fi
          fi
        fi
      else
        http=$(curl -s -o /dev/null -m "$HTTP_TIMEOUT" -w '%{http_code}' "http://localhost:$port$path" 2>/dev/null)
        http=${http:-000}
        if [[ "$http" == "000" ]]; then raise 2 "HTTP không phản hồi tại :$port$path"
        elif (( http >= 500 )); then raise 1 "HTTP $http tại :$port$path"; fi
        read -r rss cpu < <(ps -o rss=,%cpu= -p "$pid" 2>/dev/null)
        if [[ -n "$rss" ]]; then rss=$(( rss / 1024 )); else rss="-"; fi
        cpu=${cpu:--}
      fi
    fi

    if [[ -d "$base/logs" ]]; then
      logmb=$(( $(du -sk "$base/logs" | cut -f1) / 1024 ))
      (( logmb > LOG_DIR_WARN_MB )) && raise 1 "logs ${logmb}MB > ${LOG_DIR_WARN_MB}MB (chạy clearlog-$name.sh 7)"
      while IFS= read -r -d '' f; do
        if (( first )); then new_content "$f" "$sdir" 1; continue; fi
        content=$(new_content "$f" "$sdir")
        [[ -z "$content" ]] && continue
        case "$(basename "$f")" in
          *access_log*)
            n=$(grep -cE '" 5[0-9]{2} ' <<<"$content"); h5xx=$((h5xx + ${n:-0})) ;;
          *)
            n=$(grep -oE "$STARTUP_PATTERN" <<<"$content" | grep -oE '[0-9][0-9.,]*' | tail -1)
            [[ -n "$n" ]] && startup_ms="$n"
            n=$(grep -oE "$RELOAD_PATTERN" <<<"$content" | grep -oE '\[[^]]*\]' | tr -d '[]' | sort -u | tr '\n' ' ')
            [[ -n "$n" ]] && reloaded="${reloaded}${n}"
            grep -qE "$SHUTDOWN_BEGIN" <<<"$content" && stopped_log=1
            matched=$(drop_shutdown "$sdir/$(basename "$f").shut" <<<"$content" | grep -E "$ERROR_PATTERN")
            [[ -n "$IGNORE_PATTERN" && -n "$matched" ]] && matched=$(grep -vE "$IGNORE_PATTERN" <<<"$matched")
            if [[ -n "$matched" ]]; then
              n=$(grep -c '' <<<"$matched"); errs=$((errs + n))
              if grep -qE "$CRIT_PATTERN" <<<"$matched"; then
                raise 2 "$(basename "$f"): $(grep -oE "$CRIT_PATTERN" <<<"$matched" | sort -u | tr '\n' ' ')"
              fi
              all_err+="$(sed "s|^|$(basename "$f"): |" <<<"$matched")"$'\n'
            fi ;;
        esac
      done < <(find "$base/logs" -type f ! -name '*.gz' \( -name 'catalina.out' -o -mtime -2 \) -print0)
      # dọn offset của file log đã bị xoá
      for f in "$sdir"/*.off "$sdir"/*.shut; do [[ -e "$f" ]] || continue; [[ -e "$base/logs/$(basename "${f%.*}")" ]] || rm -f "$f"; done
      (( h5xx >= HTTP_5XX_WARN )) && raise 1 "$h5xx request HTTP 5xx mới"
      samples=$(grep -v '^$' <<<"$all_err" | tail -n "$MAX_ERROR_LINES" | cut -c1-300)
    fi
    (( first )) && msgs+=("lần đầu theo dõi: đọc log từ thời điểm này")
    (( stopped_log )) && msgs+=("có dừng Tomcat trong khoảng này (theo log)")
  fi

  # ----- Quyết định ALERT -----
  if [[ -n "$startup_ms" ]] && (( errs == 0 )); then
    msgs+=("khởi động thành công trong ${startup_ms} ms"); ialert=1; reasons+=("khởi động OK ${startup_ms}ms")
  elif [[ -n "$startup_ms" ]]; then
    msgs+=("khởi động xong trong ${startup_ms} ms nhưng có lỗi"); reasons+=("khởi động có lỗi ${startup_ms}ms")
  fi
  reloaded=$(echo $reloaded)
  if [[ -n "$reloaded" ]] && (( errs == 0 )); then
    msgs+=("auto-reload xong: $reloaded"); ialert=1; reasons+=("reload OK $reloaded")
  elif [[ -n "$reloaded" ]]; then
    msgs+=("auto-reload $reloaded nhưng có lỗi"); reasons+=("reload có lỗi $reloaded")
  fi
  if (( errs > 0 )); then
    raise 1 "$errs dòng lỗi mới trong log"; ialert=1; HAS_ERR=1; reasons+=("$errs lỗi log")
  fi
  if (( ALERT_ON_STATUS && ! LOGS_ONLY && sev >= 1 && errs == 0 )); then
    ialert=1; reasons+=("trạng thái $(sev_label "$sev")")
  fi

  (( sev > OVERALL )) && OVERALL=$sev
  local label s jm="" js="" jr="" mtxt="" rtxt=""
  label=$(sev_label "$sev")
  TEXT_ROWS+=("$(printf "$ROW_FMT" "$name" "$label" "$state" "${pid:--}" "$http" "$cpu" "$rss" "$logmb" "$errs" "$h5xx" "${startup_ms:--}")")
  for s in "${msgs[@]}"; do jm+="\"$(json_esc "$s")\","; mtxt+="$s; "; done
  for s in "${reasons[@]}"; do jr+="\"$(json_esc "$s")\","; rtxt+="$s, "; done
  while IFS= read -r s; do [[ -n "$s" ]] && js+="\"$(json_esc "$s")\","; done <<<"$samples"
  if [[ -n "$mtxt" || -n "$samples" ]]; then
    TEXT_DETAILS+=("[$label]$( (( ialert )) && echo ' [ALERT]') $name: ${mtxt%; }")
    [[ -n "$samples" ]] && TEXT_DETAILS+=("$(sed 's/^/    | /' <<<"$samples")")
  fi
  if (( ialert )); then ALERT=1; ALERT_SUMMARY+=("$name: ${rtxt%, }"); fi
  local ja=false; (( ialert )) && ja=true
  JSON_ITEMS+=("{\"name\":\"$name\",\"status\":\"$label\",\"alert\":$ja,\"state\":\"$state\",\"port\":\"$port\",\"pid\":\"$pid\",\"http\":\"$http\",\"cpu\":\"$cpu\",\"rss_mb\":\"$rss\",\"log_mb\":$logmb,\"new_errors\":$errs,\"http_5xx\":$h5xx,\"startup_ms\":\"$startup_ms\",\"reloaded\":\"$reloaded\",\"stopped_in_window\":$( (( stopped_log )) && echo true || echo false),\"alert_reasons\":[${jr%,}],\"messages\":[${jm%,}],\"error_samples\":[${js%,}]}")
}

# ===== Chạy =====
HOST=$(hostname -s 2>/dev/null || hostname); NOW=$(date '+%Y-%m-%dT%H:%M:%S%z')
EXTRA_MSG=""; seen=" "
for entry in "${INSTANCES_CONF[@]}"; do
  IFS='|' read -r n p hp en <<<"$entry"
  [[ -z "$n" ]] && continue
  seen+="$n "
  [[ "$en" == "off" ]] && continue
  check_instance "$n" "$p" "${hp:-/}"
done
# Instance có trên đĩa nhưng chưa có trong danh sách -> vẫn kiểm tra + nhắc cập nhật
for d in "$INSTANCES_DIR"/*/; do
  [[ -f "$d/instance.env" ]] || continue
  n=$(basename "$d"); [[ "$seen" == *" $n "* ]] && continue
  p=$(sed -n 's/^HTTP_PORT=//p' "$d/instance.env" | head -1)
  EXTRA_MSG="chưa có trong danh sách monitor — chạy: ~/tomcat/scripts/tc.sh wrappers"
  check_instance "$n" "$p" "/"
done

LABEL=$(sev_label "$OVERALL")
JA=false; (( ALERT )) && JA=true
TXT="Tomcat monitor ($MODE) — $HOST — $NOW — $LABEL$( (( ALERT )) && echo ' — ALERT')"$'\n'
TXT+="$(printf "$ROW_FMT" NAME STATUS STATE PID HTTP CPU% RSS_MB LOG_MB ERR 5XX STARTUP_MS)"$'\n'
for r in "${TEXT_ROWS[@]}"; do TXT+="$r"$'\n'; done
(( ${#TEXT_ROWS[@]} == 0 )) && TXT+="(chưa có instance nào)"$'\n'
if (( ${#TEXT_DETAILS[@]} > 0 )); then TXT+=$'\n'; for r in "${TEXT_DETAILS[@]}"; do TXT+="$r"$'\n'; done; fi
JSON="{\"time\":\"$NOW\",\"host\":\"$(json_esc "$HOST")\",\"mode\":\"$MODE\",\"status\":\"$LABEL\",\"alert\":$JA,\"instances\":[$(IFS=,; echo "${JSON_ITEMS[*]}")]}"

printf '%s' "$TXT" > "$MON_DIR/last-report$SUFFIX.txt"
printf '%s\n' "$JSON" > "$MON_DIR/last-report$SUFFIX.json"
if (( ALERT )); then
  AL="$MON_DIR/alerts$SUFFIX.jsonl"
  printf '%s\n' "$JSON" >> "$AL"
  if (( $(wc -l < "$AL") > ALERTS_KEEP )); then
    tail -n "$ALERTS_KEEP" "$AL" > "$AL.tmp" && mv "$AL.tmp" "$AL"
  fi
  if (( NOTIFY_MACOS )) && command -v osascript >/dev/null 2>&1; then
    if (( HAS_ERR )); then title="Tomcat: có lỗi log"; sound="Basso"; else title="Tomcat: khởi động / reload xong"; sound="Glass"; fi
    msg=$(json_esc "$(IFS=';'; echo "${ALERT_SUMMARY[*]}")")
    osascript -e "display notification \"$msg\" with title \"$title\" sound name \"$sound\"" >/dev/null 2>&1
  fi
fi

if (( QUIET == 0 || ALERT )); then
  if [[ "$OUT" == json ]]; then printf '%s\n' "$JSON"; else printf '%s' "$TXT"; fi
fi
exit "$OVERALL"
