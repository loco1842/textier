#!/usr/bin/env bash
# Times textier on large logs: the core (`inspect`) and the Panel, in a release
# build. Arguments are log sizes in lines (default 10000 100000). The logs are
# synthetic: about 100 bytes a line, one line in ten an ERROR with a JSON payload,
# one a WARNING with a URL, one a DEBUG with a file path, the rest INFO.
# The Panel's part shows its window for a moment. Results: the BENCH lines.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/xcode-env.sh

sizes=("${@:-10000 100000}")
read -r -a sizes <<< "${sizes[*]}"
logs="$(mktemp -d)"
trap 'rm -rf "$logs"' EXIT

files=()
for lines in "${sizes[@]}"; do
    file="$logs/$lines.log"
    awk -v n="$lines" 'BEGIN {
        for (i = 0; i < n; i++) {
            ts = sprintf("2026-10-11 09:%02d:%02d.%d", int(i / 60) % 60, i % 60, i % 1000)
            k = i % 10
            if (k == 0) printf "%s ERROR checkout.payment: charge failed {\"order\":\"ORD-%d\",\"amount\":42.5,\"gateway\":{\"name\":\"stripe\",\"status\":502},\"items\":[{\"sku\":\"TEE-M\",\"qty\":2}],\"file\":\"/srv/app/src/Pay.php\",\"line\":%d}\n", ts, i, i % 500
            else if (k == 3) printf "%s WARNING retrying https://api.example.com/v1/payments/ORD-%d?attempt=2 after 30s\n", ts, i
            else if (k == 6) printf "%s DEBUG handler at /srv/shop/app/Payments/Gateway.php:%d took %dms\n", ts, i % 900, i % 97
            else printf "%s INFO request id=%d user=%d GET /v1/orders/%d 200 in %dms\n", ts, i, i % 1234, i, i % 50
        }
    }' > "$file"
    files+=("$file")
done
list="$(IFS=,; echo "${files[*]}")"

log=.build/bench.log
mkdir -p .build
TEXTIER_BENCH="$list" perl -e 'alarm 3600; exec @ARGV' \
    swift test -c release -Xswiftc -enable-testing --filter "LargeLogBenchmark" > "$log" 2>&1 || true
LC_ALL=C grep -a -E "^BENCH|error:|✘" "$log" || echo "No results; see $log"
