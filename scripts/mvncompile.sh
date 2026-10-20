#!/usr/bin/env bash
# Build v3 bằng Maven tại sunnypoint-parent rồi copy env-overrides.properties vào ~/etc
set -e
cd "${V3_PARENT:-$HOME/working/sunnypoint-v3/src/sunnypoint-parent}"
mvn clean -DmyVariable=redis compile package install -DskipTests
cp "$HOME/working/sunnypoint-v3/src/sunnypoint-config/src/profiles/dev/env-overrides.properties" "$HOME/etc/env-overrides.properties"
