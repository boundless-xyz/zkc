#!/usr/bin/env bash
# End-to-end rehearsal of the ZKCSweep Safe transaction on a local Anvil mainnet fork:
#   1. deploy ZKCSweep with the freeze profile and check the runtime code (artifact match, no metadata)
#   2. print the Safe tx with script/SweepZKC.s.sol
#   3. run ZKCSweepForkTest against the deployed implementation
#   4. execute the printed hex through the real Safe with 3 impersonated owners and show the result
#
# MAINNET_RPC_URL=<url> ./script/rehearse-sweep.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${MAINNET_RPC_URL:?set MAINNET_RPC_URL}"
PORT=${ANVIL_PORT:-8547}
R=http://127.0.0.1:$PORT
S=0x3886eEaf95AA2bDDdf0C924925e290291f70447F
Z=0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555
MS=0x9641d764fc13c8B624c04430C7356C1C7C8102e2
ZERO=0x0000000000000000000000000000000000000000
IMPL_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
TMP=$(mktemp -d)

anvil --fork-url "$MAINNET_RPC_URL" --port "$PORT" --silent &
ANVIL_PID=$!
trap 'kill $ANVIL_PID 2>/dev/null; rm -rf "$TMP" broadcast/DeployZKCSweep.s.sol/1' EXIT
for _ in $(seq 1 60); do cast block-number -r $R >/dev/null 2>&1 && break; sleep 0.5; done

echo "== 1. Deploy ZKCSweep (freeze profile)"
# Fresh deployer: the default Anvil account carries mainnet state on a fork.
W=$(cast wallet new --json)
PK=$(echo "$W" | jq -r '.[0].private_key')
cast rpc anvil_setBalance "$(echo "$W" | jq -r '.[0].address')" 0x56BC75E2D63100000 -r $R >/dev/null
FOUNDRY_PROFILE=freeze forge script script/DeployZKCSweep.s.sol:DeployZKCSweep --rpc-url $R --private-key "$PK" \
  --broadcast >"$TMP/deploy.out" 2>&1
IMPL=$(grep -m1 "ZKCSweep impl:" "$TMP/deploy.out" | awk '{print $NF}')
echo "ZKCSweep impl: $IMPL"
diff <(cast code "$IMPL" -r $R | sed "s/${IMPL#0x}/0000000000000000000000000000000000000000/gI") \
  <(jq -r .deployedBytecode.object out-freeze/ZKCSweep.sol/ZKCSweep.json) >/dev/null && echo "bytecode matches out-freeze artifact"
[ "$(cast code "$IMPL" -r $R | grep -c a2646970667358)" = 0 ] && echo "no metadata hash in runtime code"

echo "== 2. Safe transaction"
ZKC_SWEEP_IMPL=$IMPL FOUNDRY_PROFILE=freeze forge script script/SweepZKC.s.sol:SweepZKC --rpc-url $R 2>&1 |
  sed -n '/== Logs ==/,/Expected events/p' | tee "$TMP/sweep.out"

echo "== 3. Fork tests against the deployed implementation"
ZKC_SWEEP_IMPL=$IMPL MAINNET_RPC_URL=$R FOUNDRY_PROFILE=freeze forge test --match-contract ZKCSweepForkTest

echo "== 4. Execute the printed Safe tx with 3 impersonated owners"
DATA=$(grep -A1 "  data:" "$TMP/sweep.out" | tail -1 | tr -d ' ')
H=$(grep -A1 safeTxHash "$TMP/sweep.out" | tail -1 | tr -d ' ')
F=$(cast call "$IMPL" "FROZEN()(address)" -r $R)
D=$(cast call "$IMPL" "SWEEP_RECIPIENT()(address)" -r $R)
OWNERS=($(cast call $S "getOwners()(address[])" -r $R | tr -d '[] ' | tr ',' '\n' | tr 'A-F' 'a-f' | sort | head -3))
SIGS=0x
for O in "${OWNERS[@]}"; do
  cast rpc anvil_impersonateAccount "$O" -r $R >/dev/null
  cast rpc anvil_setBalance "$O" 0x56BC75E2D63100000 -r $R >/dev/null
  cast send $S "approveHash(bytes32)" "$H" --from "$O" --unlocked -r $R >/dev/null
  SIGS=$SIGS$(cast abi-encode "f(address)" "$O" | cut -c3-)$(printf '0%.0s' {1..64})01
done
bal() { cast call $Z 'balanceOf(address)(uint256)' "$1" -r $R | awk '{print $1}'; }
echo "before: frozen=$(bal "$F") recipient=$(bal "$D")"
TX=$(cast send $S "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)" \
  $MS 0 "$DATA" 1 0 0 0 $ZERO $ZERO "$SIGS" --from "${OWNERS[0]}" --unlocked -r $R --json)
echo "tx status: $(echo "$TX" | jq -r .status)"
echo "ZKC events (topics, data):"
echo "$TX" | jq -r --arg z "$(echo $Z | tr 'A-F' 'a-f')" \
  '.logs[] | select((.address|ascii_downcase)==$z) | "  " + (.topics | join(" ")) + " " + .data'
echo "after:  frozen=$(bal "$F") recipient=$(bal "$D")"
echo "impl:   $(cast storage $Z $IMPL_SLOT -r $R)"
if cast call $Z "transfer(address,uint256)(bool)" "$D" 0 --from "$F" -r $R >/dev/null 2>&1; then
  echo "ERROR: frozen address can transfer after rollback" && exit 1
fi
echo "frozen address still frozen"
