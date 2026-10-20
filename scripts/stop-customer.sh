#!/usr/bin/env bash
exec "$(dirname "$0")/tc.sh" stop customer "$@"
