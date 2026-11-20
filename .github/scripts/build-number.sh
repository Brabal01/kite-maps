#!/usr/bin/env bash
# A build number that grows with the source history rather than with a single
# workflow's run counter. Two workflows (custom iPhone and main release) used
# to stamp unrelated counters, so an update could install as a downgrade.
#
# 1000 + commit count keeps the number above every v28 build (1051) and makes
# it increase with every commit on any branch that contains the previous work.
set -euo pipefail
echo $(( 1000 + $(git rev-list --count HEAD) ))
