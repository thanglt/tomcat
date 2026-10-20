#!/usr/bin/env bash
# Chuẩn bị trước khi start các instance: local-overrides + bucket localstack (lỗi bucket không chặn start)
cp "$HOME/etc/env/local-overrides-me.properties" "$HOME/etc/local-overrides.properties" || exit 1
for b in sunnypoint-media-dev sunnypoint-export-dev; do
  aws s3 mb "s3://$b" --endpoint-url=http://localhost.localstack.cloud:4566 --no-sign-request >/dev/null 2>&1 || true
done
echo "prestart OK (local-overrides-me.properties -> ~/etc/local-overrides.properties)"
