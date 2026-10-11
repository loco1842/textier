#!/usr/bin/env bash
# Runs `swift test` with the toolchain, timeout and cleanup this repo needs, and
# prints only failures, compile errors and the run summaries. Arguments go to
# `swift test`: `scripts/test.sh --skip TextierAppTests`, `--filter SettingsTests`.
# The full output is kept in .build/test.log.
set -uo pipefail

cd "$(dirname "$0")/.."
source scripts/xcode-env.sh

root="$(pwd -P)"

# A run killed by the timeout can leave the test helper hanging, and the next run
# then waits on it. Only such orphans of this checkout are killed: their
# `swift test` is gone, so launchd (pid 1) is their parent, and they run a test
# bundle from this checkout's .build. Live runs, here, in other worktrees or in
# other projects, still have their parent and are left alone.
kill_orphaned_helpers() {
    local pid
    for pid in $(pgrep -f swiftpm-testing-helper); do
        [[ "$(ps -o ppid= -p "$pid" | tr -d ' ')" == 1 ]] || continue
        if ps -ww -o command= -p "$pid" | grep -qF "$root/.build/"; then
            kill "$pid" 2>/dev/null
        fi
    done
}

kill_orphaned_helpers

timeout="${TEXTIER_TEST_TIMEOUT:-600}"
log=.build/test.log
mkdir -p .build

perl -e 'alarm shift; exec @ARGV' "$timeout" swift test "$@" > "$log" 2>&1 &
wait $! 2>/dev/null
status=$?

# Compiler diagnostics come colored, even into a file. Read as bytes: a crash can
# leave bytes in the log that aren't UTF-8.
LC_ALL=C sed $'s/\x1b\\[[0-9;]*m//g' "$log" |
    LC_ALL=C grep -aE '\.swift:[0-9]+:[0-9]+: error:|✘|Test run with|Fatal error|unexpected signal'

if [[ $status -eq 142 ]]; then
    echo "test.sh: timed out after ${timeout}s (TEXTIER_TEST_TIMEOUT); full output in $log"
    # The alarm ended this run's `swift test`, which orphaned its helper.
    kill_orphaned_helpers
elif [[ $status -eq 0 ]] && ! grep -q 'Test run with' "$log"; then
    # An AppKit event outside `NSApp.run()` ends Swift Testing's main silently.
    echo "test.sh: exited 0 without a test summary; see docs/agents/testing.md and $log"
    status=1
elif [[ $status -ne 0 ]]; then
    echo "test.sh: failed (exit $status); full output in $log"
fi
exit $status
