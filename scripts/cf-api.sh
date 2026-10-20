#!/usr/bin/env bash
# cf-api.sh — helper gọi Cloudflare API bằng API token (được source bởi tc-tunnel.sh / cf-setup.sh)
# Token lấy theo thứ tự: biến môi trường CF_API_TOKEN -> macOS Keychain (service "cloudflare-api-token").
# Lưu token vào Keychain:  ~/tomcat/scripts/tc-tunnel.sh token
# Quyền cần cho token: Account › Cloudflare Tunnel › Edit;  Zone › Zone › Read;  Zone › DNS › Edit  (zone = DOMAIN)
CF_API="https://api.cloudflare.com/client/v4"
CF_KEYCHAIN_SERVICE="cloudflare-api-token"

cf_token() {
  if [[ -n "${CF_API_TOKEN:-}" ]]; then printf '%s' "$CF_API_TOKEN"; return 0; fi
  command -v security >/dev/null 2>&1 && security find-generic-password -s "$CF_KEYCHAIN_SERVICE" -w 2>/dev/null
}
cf_have_token() { [[ -n "$(cf_token)" ]]; }

cf_save_token() {   # hỏi token (không hiện ra màn hình) và lưu vào Keychain
  command -v security >/dev/null 2>&1 || { echo "Không có Keychain; hãy export CF_API_TOKEN=..."; return 1; }
  local t; read -r -s -p "Dán Cloudflare API token: " t; echo
  [[ -n "$t" ]] || { echo "Token rỗng"; return 1; }
  security add-generic-password -U -s "$CF_KEYCHAIN_SERVICE" -a "$USER" -w "$t" && echo "Đã lưu token vào Keychain ($CF_KEYCHAIN_SERVICE)"
  CF_API_TOKEN="$t" cf_verify
}

cf_api() {          # <METHOD> <path> [json-body]  -> in JSON response
  local m="$1" p="$2" b="${3:-}" t; t=$(cf_token)
  [[ -n "$t" ]] || { echo '{"success":false,"errors":[{"message":"no API token"}]}'; return 1; }
  if [[ -n "$b" ]]; then
    curl -sS -X "$m" "$CF_API$p" -H "Authorization: Bearer $t" -H "Content-Type: application/json" --data "$b"
  else
    curl -sS -X "$m" "$CF_API$p" -H "Authorization: Bearer $t"
  fi
}

jget() {            # <path> : đọc JSON từ stdin, path dạng result.0.id ; in rỗng nếu không có
  JP="$1" perl -MJSON::PP -0e '
    my $d = eval { JSON::PP->new->decode(<STDIN>) } or exit 0;
    for my $k (split /\./, $ENV{JP}) { $d = (ref $d eq "ARRAY") ? $d->[$k] : (ref $d eq "HASH" ? $d->{$k} : undef); last unless defined $d }
    if (JSON::PP::is_bool($d)) { print $d ? 1 : 0 }
    elsif (ref $d) { print JSON::PP->new->canonical->encode($d) }
    else { print $d // "" }'
}
jerr() { perl -MJSON::PP -0e 'my $d=eval{JSON::PP->new->decode(<STDIN>)}; print join("; ", map {"$_->{code}: $_->{message}"} @{$d->{errors}||[]}) if $d'; }

cf_verify() {
  local r; r=$(cf_api GET /user/tokens/verify)
  if [[ "$(jget success <<<"$r")" == "1" ]]; then echo "Token hợp lệ (status: $(jget result.status <<<"$r"))"
  else echo "Token không hợp lệ: $(jerr <<<"$r")"; return 1; fi
}

cf_zone() {         # <domain> -> set CF_ZONE_ID, CF_ACCOUNT_ID
  local r; r=$(cf_api GET "/zones?name=$1")
  CF_ZONE_ID=$(jget result.0.id <<<"$r"); CF_ACCOUNT_ID=$(jget result.0.account.id <<<"$r")
  [[ -n "$CF_ZONE_ID" && -n "$CF_ACCOUNT_ID" ]] || { echo "Không lấy được zone $1 (token thiếu quyền Zone:Read?): $(jerr <<<"$r")"; return 1; }
}

cf_dns_cname() {    # <zone_id> <hostname> <target> : tạo CNAME proxied; không ghi đè record khác
  local z="$1" h="$2" target="$3" r cnt typ content
  r=$(cf_api GET "/zones/$z/dns_records?name=$h")
  cnt=$(jget result_info.count <<<"$r")
  if [[ "${cnt:-0}" != "0" ]]; then
    typ=$(jget result.0.type <<<"$r"); content=$(jget result.0.content <<<"$r")
    if [[ "$typ" == "CNAME" && "$content" == "$target" ]]; then echo "  DNS có sẵn $h"
    else echo "  DNS BỎ QUA $h: đã có record $typ -> $content (không ghi đè; đổi CF_HOSTNAME hoặc xoá record trên dashboard)"; fi
    return 0
  fi
  r=$(cf_api POST "/zones/$z/dns_records" "{\"type\":\"CNAME\",\"name\":\"$h\",\"content\":\"$target\",\"proxied\":true,\"comment\":\"tomcat instance (tc-tunnel.sh)\"}")
  if [[ "$(jget success <<<"$r")" == "1" ]]; then echo "  DNS OK  $h -> $target"; else echo "  DNS LỖI $h: $(jerr <<<"$r")"; fi
}
