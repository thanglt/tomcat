#!/usr/bin/env bash
# tc-tunnel.sh — Cloudflare Tunnel cho các Tomcat instance: <instance>.<DOMAIN> -> http://localhost:<HTTP_PORT>
# Usage: tc-tunnel.sh <gen|apply|show|dns|validate|restart|all|token>
#   gen       sinh khối ingress từ instance/*/instance.env -> $TC_ROOT/cloudflare/ingress-tomcat.yml (chạy được cả trong VM)
#   apply     gen + chèn/thay khối đó trong config.yml của cloudflared (giữa 2 marker, trước rule catch-all), có backup
#   show      in khối ingress hiện tại
#   remote    (tunnel chạy bằng --token) đọc ingress trên Cloudflare, BỎ QUA hostname/port đã có, thêm phần thiếu + DNS;
#             `remote --dry-run` chỉ in kế hoạch. Cần API token.
#   dns       tạo CNAME <hostname> -> <tunnel-id>.cfargotunnel.com (có API token: qua Cloudflare API;
#             không có: cloudflared tunnel route dns). Không ghi đè record đã có.
#   token     lưu Cloudflare API token vào macOS Keychain (thay cho cloudflared tunnel login)
#   validate  cloudflared tunnel ingress validate + kiểm tra rule khớp từng hostname
#   restart   restart cloudflared (brew services / launchd) để nhận config mới
#   all       apply + validate + dns + restart
# Cấu hình: $TC_ROOT/cloudflare/tunnel.env (DOMAIN; CF_CONFIG, TUNNEL tự dò nếu để trống; ORIGIN_HOST)
# Tuỳ chỉnh theo instance (instance.env): CF_HOSTNAME=api.example.com (đổi hostname), CF_TUNNEL=off (không expose)
set -uo pipefail
TC_ROOT="${TC_ROOT:-$HOME/tomcat}"
INSTANCES="$TC_ROOT/instance"
CF_DIR="$TC_ROOT/cloudflare"
CF_ENV="$CF_DIR/tunnel.env"
BLOCK_FILE="$CF_DIR/ingress-tomcat.yml"
MARK_BEGIN="# BEGIN TOMCAT INSTANCES (tự sinh bởi tc-tunnel.sh — không sửa tay)"
MARK_END="# END TOMCAT INSTANCES"
ACTION="${1:-}"

mkdir -p "$CF_DIR"
if [[ ! -f "$CF_ENV" ]]; then
  cat > "$CF_ENV" <<'EOS'
# Cấu hình Cloudflare Tunnel cho tc-tunnel.sh
DOMAIN="example.com"     # hostname mặc định = <instance>.<DOMAIN>
CF_CONFIG=""             # config.yml cloudflared đang dùng; để trống = tự tìm (~/.cloudflared, /etc/cloudflared, brew etc)
TUNNEL=""                # tên/UUID tunnel; để trống = lấy dòng "tunnel:" trong CF_CONFIG
ORIGIN_HOST="localhost"  # Tomcat chạy trên chính máy này
EOS
  echo "Đã tạo $CF_ENV — sửa TUNNEL / DOMAIN / CF_CONFIG rồi chạy lại."; [[ "$ACTION" == gen ]] || exit 1
fi
# shellcheck disable=SC1090
source "$CF_ENV"
ORIGIN_HOST="${ORIGIN_HOST:-localhost}"
if [[ -z "${CF_CONFIG:-}" || ! -f "${CF_CONFIG:-}" ]]; then
  for c in "$HOME/.cloudflared/config.yml" "$HOME/.cloudflared/config.yaml" /etc/cloudflared/config.yml \
           /usr/local/etc/cloudflared/config.yml /opt/homebrew/etc/cloudflared/config.yml; do
    [[ -f "$c" ]] && { CF_CONFIG="$c"; break; }
  done
fi
CF_CONFIG="${CF_CONFIG:-$HOME/.cloudflared/config.yml}"
[[ -n "${TUNNEL:-}" ]] || TUNNEL=$(sed -n 's/^tunnel:[[:space:]]*//p' "$CF_CONFIG" 2>/dev/null | tr -d '"' | head -1)
TUNNEL_ID="${TUNNEL_ID:-$(sed -n 's/^tunnel:[[:space:]]*//p' "$CF_CONFIG" 2>/dev/null | tr -d '"' | head -1)}"
# shellcheck disable=SC1091
source "$(dirname "$0")/cf-api.sh"

hosts_list() {   # in: "<hostname> <port> <instance>"
  local d n port host off
  for d in "$INSTANCES"/*/; do
    [[ -f "$d/instance.env" ]] || continue; n=$(basename "$d")
    port=$(sed -n 's/^HTTP_PORT=//p' "$d/instance.env" | head -1)
    off=$(sed -n 's/^CF_TUNNEL=//p' "$d/instance.env" | tr -d '"' | head -1)
    [[ "$off" == "off" ]] && continue
    host=$(sed -n 's/^CF_HOSTNAME=//p' "$d/instance.env" | tr -d '"' | head -1)
    [[ -n "$host" ]] || host="$n.$DOMAIN"
    echo "$host $port $n"
  done
}

gen_block() {    # <indent>
  local ind="$1" host port n
  echo "$ind$MARK_BEGIN"
  while read -r host port n; do
    [[ -n "$host" ]] || continue
    echo "$ind- hostname: $host          # instance $n"
    echo "$ind  service: http://$ORIGIN_HOST:$port"
  done < <(hosts_list)
  echo "$ind$MARK_END"
}

do_gen() { gen_block "  " > "$BLOCK_FILE"; echo "Đã sinh $BLOCK_FILE:"; sed 's/^/  /' "$BLOCK_FILE"; }

do_apply() {
  [[ -f "$CF_CONFIG" ]] || { echo "Không thấy config cloudflared (đặt CF_CONFIG trong $CF_ENV)"; return 1; }
  [[ -w "$CF_CONFIG" ]] || { echo "Không có quyền ghi $CF_CONFIG — chạy: sudo TC_ROOT=$TC_ROOT $0 apply"; return 1; }
  echo "Config: $CF_CONFIG  (tunnel: ${TUNNEL:-?})"
  grep -qE '^[[:space:]]*ingress:' "$CF_CONFIG" || { echo "$CF_CONFIG chưa có mục 'ingress:'"; return 1; }
  local ind tmp bak
  # Thụt lề theo rule catch-all (vd "  - service: http_status:404"), mặc định 2 dấu cách
  ind=$(grep -m1 -E '^[[:space:]]*-[[:space:]]+service:[[:space:]]*http_status:' "$CF_CONFIG" | sed -E 's/^([[:space:]]*)-.*/\1/')
  [[ -n "${ind+x}" ]] || ind="  "
  gen_block "$ind" > "$BLOCK_FILE"
  bak="$CF_CONFIG.bak.$(date +%Y%m%d%H%M%S)"; cp "$CF_CONFIG" "$bak"
  tmp="$CF_CONFIG.tmp.$$"
  BF="$BLOCK_FILE" MB="$MARK_BEGIN" ME="$MARK_END" awk '
    function block() { while ((getline l < ENVIRON["BF"]) > 0) print l; close(ENVIRON["BF"]); done = 1 }
    index($0, ENVIRON["MB"]) { if (!done) block(); skip = 1; next }
    index($0, ENVIRON["ME"]) { skip = 0; next }
    skip { next }
    /^[[:space:]]*-[[:space:]]+service:[[:space:]]*http_status:/ && !done { block() }
    { print }
    END { if (!done) exit 3 }' "$CF_CONFIG" > "$tmp"
  if [[ $? -ne 0 ]]; then
    rm -f "$tmp"; echo "Không tìm thấy rule catch-all '- service: http_status:404' trong $CF_CONFIG — thêm rule đó ở cuối ingress rồi chạy lại."; return 1
  fi
  mv -f "$tmp" "$CF_CONFIG"
  echo "Đã cập nhật $CF_CONFIG (backup: $bak)"
  sed -n "/$(printf '%s' "$MARK_BEGIN" | sed 's/[^^]/[&]/g; s/\^/\\^/g')/,/$MARK_END/p" "$CF_CONFIG" | sed 's/^/  /'
}

need_cf() { command -v cloudflared >/dev/null 2>&1 || { echo "Chưa có cloudflared (brew install cloudflared)"; return 1; }; }

do_validate() {
  need_cf || return 1
  cloudflared tunnel --config "$CF_CONFIG" ingress validate || return 1
  local host port n
  while read -r host port n; do
    [[ -n "$host" ]] || continue
    printf "  %-35s -> " "$host"; cloudflared tunnel --config "$CF_CONFIG" ingress rule "https://$host/" 2>/dev/null | grep -i 'service' | head -1
  done < <(hosts_list)
}

do_dns() {
  local host port n out
  if cf_have_token; then
    [[ -n "$TUNNEL_ID" ]] || { echo "Không thấy 'tunnel: <UUID>' trong $CF_CONFIG"; return 1; }
    cf_zone "$DOMAIN" || return 1
    while read -r host port n; do
      [[ -n "$host" ]] || continue
      [[ "$host" == *".$DOMAIN" || "$host" == "$DOMAIN" ]] || { echo "  DNS BỎ QUA $host: không thuộc zone $DOMAIN"; continue; }
      cf_dns_cname "$CF_ZONE_ID" "$host" "$TUNNEL_ID.cfargotunnel.com"
    done < <(hosts_list)
    return 0
  fi
  need_cf || return 1
  [[ -n "$TUNNEL" ]] || { echo "Chưa biết TUNNEL (đặt trong $CF_ENV)"; return 1; }
  while read -r host port n; do
    [[ -n "$host" ]] || continue
    out=$(cloudflared tunnel route dns "$TUNNEL" "$host" 2>&1)
    if [[ $? -eq 0 ]]; then echo "  DNS OK  $host"
    elif grep -qi 'already exists' <<<"$out"; then echo "  DNS có sẵn $host"
    else echo "  DNS LỖI $host: $out"; fi
  done < <(hosts_list)
}

# Tunnel remote-managed (chạy bằng --token): đọc ingress trên Cloudflare, bỏ qua hostname/port đã tồn tại,
# chỉ thêm phần còn thiếu (trước rule catch-all). `remote --dry-run` chỉ in kế hoạch, không PUT.
do_remote() {
  local dry=0 r tid="${TUNNEL_ID:-}" want new
  [[ "${1:-}" == "--dry-run" ]] && dry=1
  cf_have_token || { echo "Cần API token (tc-tunnel.sh token) — tunnel token không gọi được API"; return 1; }
  if ! cf_zone "$DOMAIN"; then
    [[ -n "${ACCOUNT_ID:-}" ]] || return 1
    echo "  (bỏ qua DNS: token chưa có Zone:Read — dùng ACCOUNT_ID trong $CF_ENV; DNS tự tạo khi thêm Public Hostname trên dashboard)"; NO_DNS=1
  fi
  CF_ACCOUNT_ID="${ACCOUNT_ID:-$CF_ACCOUNT_ID}"
  if [[ -z "$tid" ]]; then
    r=$(cf_api GET "/accounts/$CF_ACCOUNT_ID/cfd_tunnel?name=${TUNNEL:-}&is_deleted=false"); tid=$(jget result.0.id <<<"$r")
    [[ -n "$tid" ]] || { echo "Không thấy tunnel '${TUNNEL:-}' (đặt TUNNEL_ID trong $CF_ENV)"; return 1; }
  fi
  TUNNEL_ID="$tid"
  r=$(cf_api GET "/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$tid/configurations")
  [[ "$(jget success <<<"$r")" == "1" ]] || { echo "Không đọc được ingress: $(jerr <<<"$r")"; return 1; }
  want=$(hosts_list | awk -v h="$ORIGIN_HOST" '{print $1" http://"h":"$2" "$3}')
  new=$(WANT="$want" CUR="$r" perl -MJSON::PP -e '
    my $j = JSON::PP->new->canonical; my $cur = $j->decode($ENV{CUR});
    my $cfg = $cur->{result}{config} || {}; my @in = @{ $cfg->{ingress} || [] };
    my $catch = (@in && !defined $in[-1]{hostname}) ? pop @in : { service => "http_status:404" };
    my @add;
    for my $l (split /\n/, $ENV{WANT}) {
      my ($host, $svc, $name) = split / /, $l; next unless $host;
      (my $port = $svc) =~ s/.*://;
      my ($hit) = grep { ($_->{hostname} // "") eq $host or ($_->{service} // "") =~ m{^https?://(localhost|127\.0\.0\.1|\[::1\]):\Q$port\E/?$} } @in;
      if ($hit) { print STDERR "  BỎ QUA $host ($name, port $port): đã có rule ", ($hit->{hostname} // "-"), " -> ", $hit->{service}, "\n"; next }
      push @in, { hostname => $host, service => $svc }; push @add, $host; print STDERR "  THÊM   $host -> $svc ($name)\n";
    }
    $cfg->{ingress} = [ @in, $catch ];
    print $j->encode({ added => scalar(@add), body => { config => $cfg } });')
  [[ -n "$new" ]] || { echo "Không tính được ingress mới"; return 1; }
  if [[ "$(jget added <<<"$new")" == "0" ]]; then echo "Không có gì cần thêm (mọi instance đã có trong tunnel)."; (( dry )) || [[ -n "${NO_DNS:-}" ]] || do_dns; return 0; fi
  if (( dry )); then echo "(--dry-run: chưa ghi gì lên Cloudflare)"; return 0; fi
  r=$(cf_api PUT "/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$tid/configurations" "$(jget body <<<"$new")")
  [[ "$(jget success <<<"$r")" == "1" ]] && echo "Đã cập nhật ingress của tunnel ${TUNNEL:-$tid}" || { echo "PUT lỗi: $(jerr <<<"$r")"; return 1; }
  [[ -z "${NO_DNS:-}" ]] && do_dns
}

do_restart() {
  if command -v brew >/dev/null 2>&1 && brew services list 2>/dev/null | grep -q '^cloudflared'; then
    brew services restart cloudflared
  elif launchctl list 2>/dev/null | grep -q cloudflared; then
    launchctl kickstart -k "gui/$(id -u)/$(launchctl list | awk '/cloudflared/{print $3; exit}')" 2>/dev/null \
      || echo "Hãy restart cloudflared thủ công (sudo launchctl kickstart -k system/com.cloudflare.cloudflared)"
  else
    echo "Không thấy cloudflared chạy dạng service. Chạy tay: cloudflared tunnel --config \"$CF_CONFIG\" run \"$TUNNEL\""
  fi
}

case "$ACTION" in
  gen) do_gen ;;
  apply) do_apply ;;
  show) [[ -f "$BLOCK_FILE" ]] && cat "$BLOCK_FILE" || do_gen ;;
  dns) do_dns ;;
  validate) do_validate ;;
  remote) do_remote "${2:-}" ;;
  restart) do_restart ;;
  token) cf_save_token ;;
  all) do_apply && do_validate && do_dns && do_restart ;;
  *) sed -n '2,16p' "$0"; exit 1 ;;
esac
