//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Treasury} from "src/Treasury.sol";
import {IProtocol, IAave, IStargate, IGmx} from "src/interfaces/IProtocol.sol";

contract DeployScript is Script {
    uint64 private constant MAX_RATIO = 1e18;

    // MAINNET
    address private constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI_MAINNET = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant AAVE_V3POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address private constant STARGATE_ROUTER = 0x8731d54E9D02c286767d56ac03e8037C07e01e98;
    address private constant STARGATE_USDC_LP = 0xdf0770dF86a8034b3EFEf0A1Bb3c889B8332FF56;
    address private constant STARGATE_LP_STAKING = 0xB0D502E938ed5f4df2E681fE6E419ff29631d62b;
    address private constant STG_TOKEN = 0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6;

    // ARBITRUM
    address private constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private constant GLP = 0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE;
    address private constant VAULT = 0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE;
    address private constant REWARD_ROUTER = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    address private constant REWARD_ROUTER2 = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address private constant GLP_MANAGER = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    address private constant FEEGLP_TRACKER = 0x4e971a87900b931fF39d1Aad67697F49835400b6;
    address private constant STAKEDGLP_TRACKER = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;

    Treasury public treasury;

    function run() external {
        vm.startBroadcast();

        treasury = new Treasury();
        initSetFunctions();

        vm.stopBroadcast();
    }

    function initSetFunctions() public {
        address[] memory tokens = new address[](3);
        bool[] memory isWhitelist = new bool[](3);
        tokens[0] = USDC_MAINNET;
        tokens[1] = DAI_MAINNET;
        tokens[2] = USDT_MAINNET;
        isWhitelist[0] = isWhitelist[1] = isWhitelist[2] = true;

        treasury.whitelistTokens(tokens, isWhitelist);
        treasury.whitelistToken(USDC, true);

        bytes32[] memory protocols = new bytes32[](3);
        uint64[] memory newRatio = new uint64[](3);
        protocols[0] = bytes32("stargate");
        protocols[1] = bytes32("gmx");
        protocols[2] = bytes32("aave-v3");
        newRatio[0] = newRatio[1] = MAX_RATIO / 4;
        newRatio[2] = MAX_RATIO / 2;
        treasury.setProtocolsRatio(protocols, newRatio);

        IProtocol.Stargate memory stragate = IProtocol.Stargate(STARGATE_ROUTER, STARGATE_LP_STAKING, STG_TOKEN);
        treasury.setStargate(stragate);

        IProtocol.AaveV3 memory aaveV3 = IProtocol.AaveV3(AAVE_V3POOL);
        treasury.setAaveV3(aaveV3);

        IProtocol.Gmx memory gmx =
            IProtocol.Gmx(VAULT, REWARD_ROUTER, REWARD_ROUTER2, GLP, GLP_MANAGER, FEEGLP_TRACKER, STAKEDGLP_TRACKER);
        treasury.setGmx(gmx);
    }
}
