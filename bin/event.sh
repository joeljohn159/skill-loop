#!/usr/bin/env bash
# Append one clean line to the activity log. Used by commands (promote/bootstrap)
# and available for manual/CI use:  event.sh PROMOTE "sl-error-handling <- rule"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/../lib/common.sh" 2>/dev/null || exit 0
[ -n "$1" ] || exit 0
type="$1"; shift
sl_event "$type" "$*"
exit 0
