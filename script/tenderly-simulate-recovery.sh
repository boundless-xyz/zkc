#!/usr/bin/env bash
# Builds a Tenderly simulator link for the ZKC recovery Safe transaction. No Tenderly API key needed:
# open the link while logged in to Tenderly (free plan works), click Simulate, then share the result.
#
# The simulation is the real Safe call: execTransaction(MultiSendCallOnly, 0, multiSend(...), DELEGATECALL, ...)
# at the Safe's current nonce, sent by a real owner with its pre-validated (v = 1) signature. The only state
# override is the Safe threshold set to 1 (same approach as base/contracts Simulation.sol), which keeps the
# calldata short enough for Tenderly's URL handling. The fork test covers the full 3-of-6 threshold path.
#
# Required env: MAINNET_RPC_URL, ZKC_RECOVERY_IMPL
# Optional env: TENDERLY_ACCOUNT, TENDERLY_PROJECT (open the simulator in that project; else your default one)
set -euo pipefail

: "${MAINNET_RPC_URL:?set MAINNET_RPC_URL}"
: "${ZKC_RECOVERY_IMPL:?set ZKC_RECOVERY_IMPL to the deployed ZKCRecovery address}"
RPC="$MAINNET_RPC_URL"

ZKC=0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555
PREV_IMPL=0xe90A3bc5992d30b9909eeb6A8015A7bC402D7F98
SAFE=0x3886eEaf95AA2bDDdf0C924925e290291f70447F
MULTISEND=0x9641d764fc13c8B624c04430C7356C1C7C8102e2
ZERO=0x0000000000000000000000000000000000000000
THRESHOLD_SLOT=4 # Safe v1.4.1 OwnerManager.threshold

[ "$(cast code "$ZKC_RECOVERY_IMPL" -r "$RPC")" != "0x" ] || { echo "no code at $ZKC_RECOVERY_IMPL" >&2; exit 1; }

# --- Calldata (must match RecoverZKCCalldata in script/RecoverZKC.s.sol) ---
CALL1=$(cast calldata "upgradeToAndCall(address,bytes)" "$ZKC_RECOVERY_IMPL" "$(cast sig 'recoverSelfTransfer()')")
CALL2=$(cast calldata "upgradeToAndCall(address,bytes)" "$PREV_IMPL" 0x)
pack() { # operation(uint8=0) | to | value(uint256=0) | len(uint256) | data
  local data=$1 len=$(( (${#1} - 2) / 2 ))
  cast concat-hex 0x00 "$ZKC" "$(cast to-uint256 0)" "$(cast to-uint256 $len)" "$data"
}
TXS=$(cast concat-hex "$(pack "$CALL1")" "$(pack "$CALL2")")
DATA=$(cast calldata "multiSend(bytes)" "$TXS")

NONCE=$(cast call "$SAFE" "nonce()(uint256)" -r "$RPC")
THRESHOLD=$(cast call "$SAFE" "getThreshold()(uint256)" -r "$RPC")
SAFE_TX_HASH=$(cast call "$SAFE" \
  "getTransactionHash(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,uint256)(bytes32)" \
  "$MULTISEND" 0 "$DATA" 1 0 0 0 "$ZERO" "$ZERO" "$NONCE" -r "$RPC")

# Lowest-address owner signs (v = 1: valid because msg.sender == that owner)
FROM=$(cast call "$SAFE" "getOwners()(address[])" -r "$RPC" | tr -d '[] ' | tr ',' '\n' \
  | python3 -c 'import sys; print(sorted((l.strip() for l in sys.stdin if l.strip()), key=lambda a: int(a,16))[0])')
SIGS=$(cast concat-hex "$(cast to-uint256 "$FROM")" "$(cast to-uint256 0)" 0x01)
ONE=$(cast to-uint256 1)
THRESHOLD_KEY=$(cast to-uint256 $THRESHOLD_SLOT)
[ "$(cast storage "$SAFE" $THRESHOLD_SLOT -r "$RPC")" = "$(cast to-uint256 "$THRESHOLD")" ] \
  || { echo "threshold slot mismatch" >&2; exit 1; }

EXEC=$(cast calldata \
  "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)" \
  "$MULTISEND" 0 "$DATA" 1 0 0 0 "$ZERO" "$ZERO" "$SIGS")

echo "Safe:           $SAFE (nonce $NONCE, threshold $THRESHOLD)"
echo "to:             $MULTISEND (MultiSendCallOnly v1.4.1), operation 1, value 0"
echo "ZKCRecovery:    $ZKC_RECOVERY_IMPL"
echo "safeTxHash:     $SAFE_TX_HASH"
echo "signer (sim):   $FROM (threshold overridden $THRESHOLD -> 1)"
echo "data:           $DATA"
echo

# --- Local preflight: same call + overrides via eth_call ---
RESULT=$(cast call "$SAFE" "$EXEC" --from "$FROM" -r "$RPC" --override-state-diff "$SAFE:$THRESHOLD_KEY:$ONE")
[ "$(cast to-dec "$RESULT")" = "1" ] || { echo "preflight failed: $RESULT" >&2; exit 1; }
echo "Preflight eth_call: execTransaction returned true"

BLOCK=$(cast block-number -r "$RPC")
OVERRIDES_JSON="[{\"contractAddress\":\"$SAFE\",\"storage\":[{\"key\":\"$THRESHOLD_KEY\",\"value\":\"$ONE\"}]}]"
ENC_OVERRIDES=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$OVERRIDES_JSON")

if [ -n "${TENDERLY_ACCOUNT:-}" ] && [ -n "${TENDERLY_PROJECT:-}" ]; then
  BASE="https://dashboard.tenderly.co/$TENDERLY_ACCOUNT/$TENDERLY_PROJECT/simulator/new"
else
  BASE="https://dashboard.tenderly.co/simulator/new"
fi
URL="$BASE?network=1&block=$BLOCK&blockIndex=0&from=$FROM&contractAddress=$SAFE&value=0&gas=3000000&gasPrice=0&stateOverrides=$ENC_OVERRIDES&rawFunctionInput=$EXEC"

echo
echo "State override (Safe threshold = 1):"
echo "$OVERRIDES_JSON"
echo
echo "Raw input data (paste into Tenderly's 'Raw input data' field if the link truncates it):"
echo "$EXEC"
echo
echo "Tenderly simulator link (block $BLOCK, ${#URL} chars, raw input ${#EXEC} chars):"
echo "$URL"
