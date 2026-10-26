#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
report_dir="${SUNSET_REPORT_DIR:-$PWD/out/sunset-fork-reports}"
mkdir -p "$report_dir"
FOUNDRY_FFI=false FOUNDRY_TEST=fork-test forge test --offline \
  --out out/sunset-fork --cache-path cache/sunset-fork \
  --fork-url "${ETHEREUM_RPC_URL:-https://ethereum-rpc.publicnode.com}" \
  --fork-block-number 26276732 --match-contract ZKCForkTest -vv \
  2>&1 | tee "$report_dir/zkc.log"
