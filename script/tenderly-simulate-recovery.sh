#!/usr/bin/env bash
# Simulates the ZKC recovery Safe transaction on Tenderly and prints a public share link.
#
# The simulation is the real Safe call: execTransaction(MultiSendCallOnly, 0, multiSend(...), DELEGATECALL, ...)
# at the Safe's current nonce. Signatures are "pre-approved hash" (v = 1) signatures from `threshold` real owners,
# made valid with a state override on the Safe's approvedHashes mapping. Nothing else is overridden.
#
# Required env: MAINNET_RPC_URL, ZKC_RECOVERY_IMPL
# For Tenderly:  TENDERLY_ACCESS_KEY, TENDERLY_ACCOUNT, TENDERLY_PROJECT
# DRY_RUN=1 runs only the local preflight eth_call and prints the Tenderly payload.
set -euo pipefail

: "${MAINNET_RPC_URL:?set MAINNET_RPC_URL}"
: "${ZKC_RECOVERY_IMPL:?set ZKC_RECOVERY_IMPL to the deployed ZKCRecovery address}"
RPC="$MAINNET_RPC_URL"

ZKC=0x000006c2A22ff4A44ff1f5d0F2ed65F781F55555
PREV_IMPL=0xe90A3bc5992d30b9909eeb6A8015A7bC402D7F98
SAFE=0x3886eEaf95AA2bDDdf0C924925e290291f70447F
MULTISEND=0x9641d764fc13c8B624c04430C7356C1C7C8102e2
ZERO=0x0000000000000000000000000000000000000000
APPROVED_HASHES_SLOT=8 # Safe v1.4.1: mapping(address => mapping(bytes32 => uint256)) approvedHashes

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

# First `threshold` owners in ascending order (Safe requires sorted signers)
SIGNERS=$(cast call "$SAFE" "getOwners()(address[])" -r "$RPC" | tr -d '[] ' | tr ',' '\n' \
  | python3 -c 'import sys; print("\n".join(sorted((l.strip() for l in sys.stdin if l.strip()), key=lambda a: int(a,16))))' \
  | head -n "$THRESHOLD")

SIGS=0x
OVERRIDES=()
SLOTS=()
for s in $SIGNERS; do
  SIGS=$(cast concat-hex "$SIGS" "$(cast to-uint256 "$s")" "$(cast to-uint256 0)" 0x01)
  SLOT=$(cast index bytes32 "$SAFE_TX_HASH" "$(cast index address "$s" $APPROVED_HASHES_SLOT)")
  SLOTS+=("$SLOT")
  OVERRIDES+=("$SAFE:$SLOT:$(cast to-uint256 1)")
done
FROM=$(echo "$SIGNERS" | head -n1)

EXEC=$(cast calldata \
  "execTransaction(address,uint256,bytes,uint8,uint256,uint256,uint256,address,address,bytes)" \
  "$MULTISEND" 0 "$DATA" 1 0 0 0 "$ZERO" "$ZERO" "$SIGS")

echo "Safe:           $SAFE (nonce $NONCE, threshold $THRESHOLD)"
echo "to:             $MULTISEND (MultiSendCallOnly v1.4.1), operation 1, value 0"
echo "ZKCRecovery:    $ZKC_RECOVERY_IMPL"
echo "safeTxHash:     $SAFE_TX_HASH"
echo "signers (sim):  $(echo $SIGNERS)"
echo "data:           $DATA"
echo

# --- Local preflight: same call + overrides via eth_call ---
RESULT=$(cast call "$SAFE" "$EXEC" --from "$FROM" -r "$RPC" --override-state-diff "$(IFS=,; echo "${OVERRIDES[*]}")")
[ "$(cast to-dec "$RESULT")" = "1" ] || { echo "preflight failed: $RESULT" >&2; exit 1; }
echo "Preflight eth_call: execTransaction returned true"

BLOCK=$(cast block-number -r "$RPC")
STORAGE_JSON=$(for sl in "${SLOTS[@]}"; do printf '"%s":"%s",' "$sl" "$(cast to-uint256 1)"; done | sed 's/,$//')
PAYLOAD=$(cat <<JSON
{
  "network_id": "1",
  "block_number": $BLOCK,
  "from": "$FROM",
  "to": "$SAFE",
  "input": "$EXEC",
  "value": "0",
  "gas": 3000000,
  "gas_price": "0",
  "save": true,
  "save_if_fails": true,
  "simulation_type": "full",
  "state_objects": { "$SAFE": { "storage": { $STORAGE_JSON } } }
}
JSON
)

if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "$PAYLOAD"
  exit 0
fi

: "${TENDERLY_ACCESS_KEY:?set TENDERLY_ACCESS_KEY}"
: "${TENDERLY_ACCOUNT:?set TENDERLY_ACCOUNT}"
: "${TENDERLY_PROJECT:?set TENDERLY_PROJECT}"
API="https://api.tenderly.co/api/v1/account/$TENDERLY_ACCOUNT/project/$TENDERLY_PROJECT"

RESP=$(curl -sS -X POST "$API/simulate" -H "X-Access-Key: $TENDERLY_ACCESS_KEY" -H "Content-Type: application/json" -d "$PAYLOAD")
SIM_ID=$(echo "$RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin)["simulation"]["id"])') \
  || { echo "Tenderly error: $RESP" >&2; exit 1; }
STATUS=$(echo "$RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin)["simulation"]["status"])')
echo "Tenderly simulation status: $STATUS"

curl -sS -X POST "$API/simulations/$SIM_ID/share" -H "X-Access-Key: $TENDERLY_ACCESS_KEY" -o /dev/null
echo "Dashboard: https://dashboard.tenderly.co/$TENDERLY_ACCOUNT/$TENDERLY_PROJECT/simulator/$SIM_ID"
echo "Public:    https://dashboard.tenderly.co/shared/simulation/$SIM_ID"
[ "$STATUS" = "True" ] || exit 1
