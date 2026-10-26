#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
report_dir="${SUNSET_REPORT_DIR:-$PWD/out/sunset-preparation}"
mkdir -p "$report_dir"
rpc="${ETHEREUM_RPC_URL:-https://eth.drpc.org}"
block="${SUNSET_BLOCK_NUMBER:-$(cast block-number --rpc-url "$rpc")}"
SUNSET_ARTIFACT_ROOT=out/sunset-fork FOUNDRY_BUILD_INFO_PATH=out/sunset-fork/build-info FOUNDRY_PROFILE=default FOUNDRY_FFI=false \
  forge script script/sunset/PrintZKCSunset.s.sol:PrintZKCSunset --offline \
  --out out/sunset-fork --cache-path cache/sunset-fork --rpc-url "$rpc" --fork-block-number "$block" \
  2>&1 | tee "$report_dir/prepare.log"
python3 script/sunset/simulate.py extract --log "$report_dir/prepare.log" --output "$report_dir/transaction.json"
python3 script/sunset/simulate.py simulate --input "$report_dir/transaction.json" --rpc-url "$rpc" --output "$report_dir/simulation.json"
