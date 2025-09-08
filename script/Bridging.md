# Bridging the canonical ZKC to OP Stack chains
This is the process that was used to bridge ZKC to OP stack chains.

## 1. Deploy the canonical bridged token on the L2
```
cast send 0x4200000000000000000000000000000000000012 \
  "createOptimismMintableERC20WithDecimals(address,string,string,uint8)" \
  <L1_TOKEN_ADDRESS> "ZK Coin" "ZKC" 18 \
  --private-key $PRIVATE_KEY \
  --rpc-url  https://base-sepolia.g.alchemy.com/v2/<API_KEY>
```

## 2. Inspect events to get the canonical token address on the L2
On L2 etherscan.

## 3. Approve the bridge on the L1
```
cast send 0x99a52662b576f4b2d4ffbc4504331a624a7b2846 \
  "approve(address,uint256)" \
  <L1_STANDARD_BRIDGE_ADDRESS> \
  10000000000000000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/<API_KEY>
```

## 4. Bridge the tokens
| The 400000 is gas limit for the L2 execution.

```
cast send <L1_STANDARD_BRIDGE_ADDRESS> \
  "bridgeERC20(address,address,uint256,uint32,bytes)" \
  <L1_TOKEN_ADDRESS> \
  <L2_TOKEN_ADDRESS> \
  10000000000000000000000 \
  400000 \
  0x \
  --private-key $PRIVATE_KEY \
  --rpc-url https://eth-sepolia.g.alchemy.com/v2/<API_KEY> 
```

## 5. Wait, then check balance on L2
```
cast call <L2_TOKEN_ADDRESS> "balanceOf(address)" <WALLET_ADDRESS> --rpc-url https://base-sepolia.g.alchemy.com/v2/<API_KEY>
```
