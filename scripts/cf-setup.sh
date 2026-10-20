#!/usr/bin/env bash
# cf-setup.sh — Cài cloudflared + tạo Cloudflare Tunnel + /etc/cloudflared/config.yml cho các Tomcat instance
# Usage: ~/tomcat/scripts/cf-setup.sh [tunnel-name]        (chạy trên Mac, user thường; script tự gọi sudo khi cần)
#   1. brew install cloudflared (nếu chưa có)
#   2-3. Xác thực + tunnel, 1 trong 2 cách:
#      a) CÓ API token (CF_API_TOKEN hoặc Keychain, lưu bằng: tc-tunnel.sh token) -> KHÔNG cần login trình duyệt:
#         tìm/tạo tunnel qua API (POST /accounts/<id>/cfd_tunnel), lấy credentials qua API (…/token)
#      b) không có token: cloudflared tunnel login (trình duyệt) + cloudflared tunnel create <name>
#   4. ghi /etc/cloudflared/config.yml (tunnel, credentials-file, ingress catch-all) + copy credentials vào /etc/cloudflared
#   5. tc-tunnel.sh apply/validate/dns  -> ingress <instance>.<DOMAIN> -> localhost:<port> + CNAME
#   6. sudo cloudflared service install (LaunchDaemon, tự chạy khi khởi động máy) hoặc restart nếu đã cài
set -euo pipefail
TC_ROOT="${TC_ROOT:-$HOME/tomcat}"
SCRIPTS="$TC_ROOT/scripts"
CF_ENV="$TC_ROOT/cloudflare/tunnel.env"
ETC=/etc/cloudflared
CONF="$ETC/config.yml"

[[ -f "$CF_ENV" ]] || "$SCRIPTS/tc-tunnel.sh" gen >/dev/null || true
# shellcheck disable=SC1090
source "$CF_ENV"
DOMAIN="${DOMAIN:?Đặt DOMAIN trong $CF_ENV}"
NAME="${1:-${TUNNEL:-tomcat-$(hostname -s | tr '[:upper:]' '[:lower:]')}}"
# shellcheck disable=SC1091
source "$SCRIPTS/cf-api.sh"
step() { printf '\n==> %s\n' "$*"; }

step "1. cloudflared"
if ! command -v cloudflared >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || { echo "Cần Homebrew (https://brew.sh) hoặc tải cloudflared từ Cloudflare"; exit 1; }
  brew install cloudflared
fi
cloudflared --version

CRED_TMP=""
if cf_have_token; then
  step "2. Xác thực bằng API token"
  cf_verify
  cf_zone "$DOMAIN"
  echo "Zone $DOMAIN: $CF_ZONE_ID  (account $CF_ACCOUNT_ID)"

  step "3. Tunnel '$NAME' (qua API)"
  R=$(cf_api GET "/accounts/$CF_ACCOUNT_ID/cfd_tunnel?name=$NAME&is_deleted=false")
  ID=$(jget result.0.id <<<"$R")
  if [[ -z "$ID" ]]; then
    SECRET=$(openssl rand -base64 32)
    R=$(cf_api POST "/accounts/$CF_ACCOUNT_ID/cfd_tunnel" "{\"name\":\"$NAME\",\"tunnel_secret\":\"$SECRET\",\"config_src\":\"local\"}")
    ID=$(jget result.id <<<"$R")
    [[ -n "$ID" ]] || { echo "Tạo tunnel lỗi (token thiếu quyền Cloudflare Tunnel:Edit?): $(jerr <<<"$R")"; exit 1; }
    echo "Đã tạo tunnel $NAME ($ID)"
  else
    echo "Dùng lại tunnel có sẵn $NAME ($ID)"
  fi
  # credentials-file từ tunnel token (base64 JSON {a: account, t: tunnel id, s: secret})
  R=$(cf_api GET "/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$ID/token")
  TOK=$(jget result <<<"$R")
  [[ -n "$TOK" ]] || { echo "Không lấy được tunnel token: $(jerr <<<"$R")"; exit 1; }
  CRED_TMP=$(mktemp); chmod 600 "$CRED_TMP"
  printf '%s' "$TOK" | base64 -D 2>/dev/null > "$CRED_TMP.raw" || printf '%s' "$TOK" | base64 -d > "$CRED_TMP.raw"
  perl -MJSON::PP -0e 'my $j=JSON::PP->new->decode(<STDIN>); print JSON::PP->new->canonical->encode({AccountTag=>$j->{a}, TunnelID=>$j->{t}, TunnelSecret=>$j->{s}})' < "$CRED_TMP.raw" > "$CRED_TMP"
  rm -f "$CRED_TMP.raw"
  CRED_SRC="$CRED_TMP"
else
  step "2. Đăng nhập Cloudflare (chọn zone $DOMAIN trên trình duyệt) — hoặc dùng API token: tc-tunnel.sh token"
  if [[ -f "$HOME/.cloudflared/cert.pem" ]]; then echo "Đã có ~/.cloudflared/cert.pem — bỏ qua login"
  else cloudflared tunnel login; fi

  step "3. Tunnel '$NAME'"
  ID=$(cloudflared tunnel list -o json 2>/dev/null | NAME="$NAME" perl -0ne 'while(/"id"\s*:\s*"([^"]+)"\s*,\s*"name"\s*:\s*"([^"]+)"/g){ if($2 eq $ENV{NAME}){print $1; last} }')
  if [[ -z "$ID" ]]; then
    cloudflared tunnel create "$NAME"
    ID=$(cloudflared tunnel list -o json | NAME="$NAME" perl -0ne 'while(/"id"\s*:\s*"([^"]+)"\s*,\s*"name"\s*:\s*"([^"]+)"/g){ if($2 eq $ENV{NAME}){print $1; last} }')
  fi
  [[ -n "$ID" ]] || { echo "Không lấy được UUID của tunnel $NAME"; exit 1; }
  CRED_SRC="$HOME/.cloudflared/$ID.json"
  [[ -f "$CRED_SRC" ]] || { echo "Thiếu $CRED_SRC (tunnel tạo ở máy khác?). Lấy lại bằng: cloudflared tunnel token --cred-file $CRED_SRC $NAME"; exit 1; }
fi
echo "Tunnel: $NAME ($ID)"

step "4. $CONF"
sudo mkdir -p "$ETC"
sudo cp "$CRED_SRC" "$ETC/$ID.json"; sudo chmod 600 "$ETC/$ID.json"
[[ -n "$CRED_TMP" ]] && rm -f "$CRED_TMP"
if sudo test -f "$CONF"; then
  sudo cp "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
  echo "Đã có $CONF — giữ nguyên, chỉ cập nhật khối ingress Tomcat (backup đã tạo)"
  sudo grep -q '^tunnel:' "$CONF" || echo "CẢNH BÁO: $CONF không có dòng 'tunnel:'"
else
  sudo tee "$CONF" >/dev/null <<EOC
# Cloudflare Tunnel — tạo bởi ~/tomcat/scripts/cf-setup.sh
tunnel: $ID
credentials-file: $ETC/$ID.json
# Tomcat chạy HTTP thuần trên localhost; Cloudflare lo HTTPS phía ngoài
originRequest:
  connectTimeout: 30s
  noTLSVerify: false
ingress:
  - service: http_status:404
EOC
  echo "Đã tạo $CONF"
fi

step "5. Ingress + DNS cho các instance"
# cập nhật tunnel.env để các lần sau tc-tunnel.sh dùng đúng file / tunnel
perl -pi -e "s#^CF_CONFIG=.*#CF_CONFIG=\"$CONF\"#; s#^TUNNEL=.*#TUNNEL=\"$NAME\"#" "$CF_ENV"
sudo TC_ROOT="$TC_ROOT" "$SCRIPTS/tc-tunnel.sh" apply
sudo chown "$(id -u):$(id -g)" "$TC_ROOT/cloudflare"/* 2>/dev/null || true   # file do sudo tạo trả lại cho user
sudo cloudflared tunnel --config "$CONF" ingress validate
TC_ROOT="$TC_ROOT" "$SCRIPTS/tc-tunnel.sh" dns

step "6. Chạy cloudflared dạng service"
if sudo launchctl list 2>/dev/null | grep -q com.cloudflare.cloudflared; then
  sudo launchctl kickstart -k system/com.cloudflare.cloudflared && echo "Đã restart service"
else
  sudo cloudflared service install && echo "Đã cài service (LaunchDaemon com.cloudflare.cloudflared, đọc $CONF)"
fi
sleep 3
cloudflared tunnel info "$NAME" 2>/dev/null | head -15 || true

step "Xong"
sed -n 's/^ *- hostname: \([^ ]*\).*/  https:\/\/\1/p' "$CONF"
echo "Log service: sudo tail -f /Library/Logs/com.cloudflare.cloudflared.err.log"
