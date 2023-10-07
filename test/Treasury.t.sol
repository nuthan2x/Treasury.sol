// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Treasury} from "src/Treasury.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IProtocol, IGmx} from "src/interfaces/IProtocol.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract TreasuryTest is Test {
    uint256 private constant DEFAULT_DECIMALS = 18;
    uint64 private constant MAX_RATIO = 1e18;
    // TODO : change local rpc
    string private constant MAINNET_RPC = "http://127.0.0.1:8547";
    string private constant ARB_RPC = "http://127.0.0.1:8545";
    // string private constant ARB_RPC = "https://rpc.ankr.com/arbitrum";
    // string private constant MAINNET_RPC = "https://rpc.ankr.com/eth";
    uint256 private arbForkId;
    uint256 private mainnetForkId;

    // MAINNET
    address private constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant DAI_MAINNET = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

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

    function setUp() public {
        // TODO : vm label as much
        vm.label(address(treasury), "TREASURY");
    }

    function testGmx() external {
        setUpArbFork();

        bytes32[] memory protocols = new bytes32[](1);
        uint64[] memory newRatio = new uint64[](1);
        protocols[0] = bytes32("gmx");
        newRatio[0] = MAX_RATIO;
        treasury.setProtocolsRatio(protocols, newRatio);

        IProtocol.Gmx memory gmx =
            IProtocol.Gmx(VAULT, REWARD_ROUTER, REWARD_ROUTER2, GLP, GLP_MANAGER, FEEGLP_TRACKER, STAKEDGLP_TRACKER);
        treasury.setGmx(gmx);

        assertEq(treasury.getRemainingRatio(), 0);
        assertEq(treasury.getProtocolRatio(bytes32("gmx")), MAX_RATIO);
        assertEq(treasury.getBalance(), 0);
                 
        uint256 timestampFarmedIn = block.timestamp;

        // faarming In
        {
            uint256 balanceBefore = 1000e6;
            deal(USDC, address(this), balanceBefore); // 1000 USDC
            assertEq(IERC20(USDC).balanceOf(address(this)), balanceBefore);

            IERC20(USDC).approve(address(treasury), balanceBefore);
            treasury.deposit(USDC, balanceBefore);
            assertEq(treasury.getBalance(), adjustedDecimals(USDC, balanceBefore));

            uint256 glpPrice = IGmx(GLP_MANAGER).getPrice(true);
            uint256 minGlp = (glpPrice * 9500 / 1000) * balanceBefore / 1e30; // with slippage
            treasury.farmInGmx(USDC, balanceBefore, 0, minGlp);
            assertEq(treasury.getProtocolData(bytes32("gmx"), timestampFarmedIn).investedBalance, balanceBefore);
        }

        // farming Out
        {
            vm.rollFork(137961220); // oct 6 2023
            uint256 stakedAmount = IGmx(STAKEDGLP_TRACKER).stakedAmounts(address(treasury));
            treasury.farmOutGmx(WETH, USDC, stakedAmount, 0, timestampFarmedIn, "");

            uint256 rewardAmount = IERC20(WETH).balanceOf(address(treasury));
            string[] memory res = new string[](8);
            res[0] = "node";
            res[1] = "test/1inch.js";
            res[2] = "42161"; // chainId
            res[3] = Strings.toHexString(address(WETH));
            res[4] = Strings.toHexString(address(USDC));
            res[5] = Strings.toString(uint256(rewardAmount));
            res[6] = res[7] = Strings.toHexString(address(treasury));

            bytes memory exchangeData = vm.ffi(res);
            treasury.farmOutGmx(WETH, USDC, stakedAmount, 0, timestampFarmedIn, exchangeData);

            assertGt(treasury.getProtocolData(bytes32("gmx"), timestampFarmedIn).yield, 0);
            assertGt(treasury.getProtocolData(bytes32("gmx"), timestampFarmedIn).harvestedBalance, 0);
        }

        // address[] memory trackers = new address[](2);
        // trackers[0] = FEEGLP_TRACKER;
        // trackers[1] = STAKEDGLP_TRACKER;
        // uint[] memory info =  IGmx(0x8BFb8e82Ee4569aee78D03235ff465Bd436D40E0).getStakingInfo(
        //         address(treasury), trackers);
    }

    function testSwap() external {
        setUpMainnetFork();
        bytes32[] memory protocols = new bytes32[](1);
        uint64[] memory newRatio = new uint64[](1);
        protocols[0] = bytes32("gmx");
        newRatio[0] = MAX_RATIO;
        treasury.setProtocolsRatio(protocols, newRatio);

        uint256 balanceBefore = 1000e6;
        deal(USDC_MAINNET, address(this), balanceBefore); // 1000 USDC
        IERC20(USDC_MAINNET).approve(address(treasury), balanceBefore);
        treasury.deposit(USDC_MAINNET, balanceBefore);

        string[] memory res = new string[](8);
        res[0] = "node";
        res[1] = "test/1inch.js";
        res[2] = "1"; // chainId
        res[3] = Strings.toHexString(address(USDC_MAINNET));
        res[4] = Strings.toHexString(address(DAI_MAINNET));
        res[5] = Strings.toString(uint256(balanceBefore));
        res[6] = res[7] = Strings.toHexString(address(treasury));

        bytes memory exchangeData = vm.ffi(res);
        treasury.swap(USDC_MAINNET, DAI_MAINNET, address(treasury), exchangeData);
    }

    /////////////// helpers /////////////////
    function adjustedDecimals(address token, uint256 amount) internal view returns (uint64) {
        uint256 adjustedAmount = amount * (10 ** DEFAULT_DECIMALS) / (10 ** IERC20(token).decimals());
        return uint64(adjustedAmount);
    }

    function setUpArbFork() internal {
        arbForkId = vm.createSelectFork(ARB_RPC, 120709407); //  12 Aug 2023
        treasury = new Treasury();
        treasury.whitelistToken(USDC, true);
    }

    function setUpMainnetFork() internal {
        mainnetForkId = vm.createSelectFork(MAINNET_RPC, 17802698); //  30 Jul 2023
        treasury = new Treasury();

        address[] memory tokens = new address[](2);
        bool[] memory isWhitelist = new bool[](2);
        tokens[0] = USDC_MAINNET;
        tokens[1] = DAI_MAINNET;
        isWhitelist[0] = isWhitelist[1] = true;

        treasury.whitelistTokens(tokens, isWhitelist);
    }
}
