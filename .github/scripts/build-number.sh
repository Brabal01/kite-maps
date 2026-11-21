#!/usr/bin/env bash
# A build number that grows with the source history rather than with a single
# workflow's run counter. Two workflows (custom iPhone and main release) used
# to stamp unrelated counters, so an update could install as a downgrade.
#
# 1000 + commit count keeps the number above every v28 build (1051) and makes
# it increase with every commit on any branch that contains the previous work.
set -euo pipefail
COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
# actions/checkout is shallow unless fetch-depth: 0; never stamp build 1001
# again just because the history was cut off.
if [ "$COUNT" -le 1 ] && [ -n "${GITHUB_RUN_NUMBER:-}" ]; then
  COUNT="$((GITHUB_RUN_NUMBER))"
fi
echo $(( 1000 + COUNT ))
