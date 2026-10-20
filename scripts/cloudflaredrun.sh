#!/bin/bash
# Chạy Cloudflare Tunnel "tomcat-les-macbook-pro" (remote-managed, chạy bằng token).
# Ingress/hostname quản lý trên Zero Trust dashboard hoặc: ~/tomcat/scripts/tc-tunnel.sh remote
# KHÔNG commit file này (chứa token).
TOKEN="eyJhIjoiNWQ0MmU1YjczNDMzZTZiZDM1MGRlNWVkOTIwZDIyOGYiLCJ0IjoiOWUzOGY4MzgtZDFjZi00MTZmLTg2ZjEtYTY4ZmU2MDQ2MTE0IiwicyI6IkdoUklUeHZPYnJSZnZJOGtTaUhrYkJZWWVDQnNSdDBCUHlDa09TT1lIZXM9In0="
CLOUDFLARED="$(command -v cloudflared || echo /opt/homebrew/bin/cloudflared)"
if pgrep -f "cloudflared tunnel run" >/dev/null 2>&1; then
  echo "cloudflared đang chạy, bỏ qua (pkill -f 'cloudflared tunnel run' để chạy lại)"; exit 0
fi
exec "$CLOUDFLARED" tunnel run --token "$TOKEN"
