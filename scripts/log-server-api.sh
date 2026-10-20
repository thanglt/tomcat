#!/usr/bin/env bash
exec "$(dirname "$0")/tc.sh" log server-api "$@"
