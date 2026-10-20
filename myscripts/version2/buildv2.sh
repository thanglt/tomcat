#!/bin/bash
# Build sunnypoint-version2-core, sunnypoint-version2-server and sunnypoint-version2-admin
# (-> <module>/target/webapp-current, linked as webapps/v2server and webapps/v2admin).
# Extra Maven arguments are passed through, e.g. ./buildv2.sh -o
set -e
cd ~/working/sunnypoint-v3/src/sunnypoint-parent
mvn clean install -DskipTests -pl ../sunnypoint-version2-core,../sunnypoint-version2-server,../sunnypoint-version2-admin "$@"
