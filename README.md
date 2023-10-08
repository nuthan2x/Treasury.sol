## Treasury

*Treasury.sol is a contract that allows depositing stablecoins and allow the owner tofarm and harvest on GMX, AAVE and Stargate pools.*

## Deployments
- On Polygon mumbai => [Treasury.sol](https://mumbai.polygonscan.com/address/0xe5415c9f1f4e89e84e3fa5899adb6fbd72b81ea7#writeContract)
- https://mumbai.polygonscan.com/address/0xe5415c9f1f4e89e84e3fa5899adb6fbd72b81ea7#writeContract

## Working

![Alt text](https://i.imgur.com/Tzp3vV7.png) 

## Test
- fork the repo and run the below commands to test

```
npm install; forge build;
forge t -mt testAaveV3 -vvv
forge t --ffi --mt testGmx  -vvv
forge t --ffi --mt testStargate  -vvv
forge t --ffi --mt testSwap -vvv
```

### Main functions
```
deposit(address,uint256)
withdraw(address,uint256)
swap(address,address,address,bytes)
```


### Farm and harvest functions
```
farmStargate(address,uint256,uint256,address)
harvestStargate(address,uint16,uint256,address,bytes,uint256)

farmAaveV3(address,uint256)
harvestAaveV3(address,uint256,uint256)

farmGmx(address,uint256,uint256,uint256)
harvestGmx(address,address,uint256,uint256,uint256,bytes)
```

### Setter functions
```
setAaveV3(AaveV3)
setStargate(Stargate)
setGmx(Gmx)

setProtocolRatio(bytes32,uint64)
setProtocolsRatio(bytes32[],uint64[])
whitelistToken(address,bool)
whitelistTokens(address[],bool[])
```

### View functions
```
getRemainingRatio()
getBalance()
getProtocolData(bytes32,uint256)
getProtocolRatio(bytes32)
getWhitelisted(address)
```

### Internal helper functions
```
adjustedDecimals(address,uint256)
oneInchSwap(bytes)
```