// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IProtocol, IGmx} from "src/interfaces/IProtocol.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import "forge-std/Test.sol";

contract Treasury is Ownable, IProtocol {
    using SafeERC20 for IERC20;

    error ZeroAmount();
    error ZeroAddress();
    error LengthMismatch();
    error NonWhitelistedToken();
    error MaxRatioExceeded();
    error ExchangeDataMismatch();
    error BalanceLessThanAmount();
    error SwapFailed();

    // TODO : emit events
    // TODO : natspec comments
    // TODO : move events, and errors to separate libraries

    event Deposit(address depositor, address token, uint256 amount);

    struct ProtocolData {
        uint96 investedBalance;
        uint96 harvestedBalance;
        int96 yield;
        address tokenUsed;
    }

    uint256 private constant DEFAULT_DECIMALS = 18;
    uint64 private constant MAX_RATIO = 1e18;
    address private constant oneInchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    uint96 private balance;
    uint64 private remainingRatio;
    mapping(bytes32 protocol => mapping(uint256 timestamp => ProtocolData)) private protocolData;
    mapping(bytes32 protocol => uint64 ratio) private protocolRatio;
    mapping(address token => bool) private isWhitelisted;

    Gmx public gmx;

    constructor() {
        remainingRatio = MAX_RATIO;
    }

    function deposit(address token, uint256 amount) external returns (bool) {
        if (!isWhitelisted[token]) revert NonWhitelistedToken();
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        balance += adjustedDecimals(token, amount);

        return true;
    }

    function withdraw(address token, uint256 amount) external onlyOwner returns (bool) {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransfer(msg.sender, amount);
        balance -= adjustedDecimals(token, amount);
        return true;
    }

    function swap(address tokenIn, address tokenOut, address receiver, bytes memory exchangeData)
        external
        returns (uint96)
    {
        if (!isWhitelisted[tokenOut]) revert NonWhitelistedToken();
        if (exchangeData.length == 0) revert ExchangeDataMismatch();
        uint256 tokenInBalanceBefore = IERC20(tokenIn).balanceOf(receiver);
        uint256 tokenOutBalanceBefore = IERC20(tokenOut).balanceOf(receiver);

        IERC20(tokenIn).approve(oneInchRouter, IERC20(tokenIn).balanceOf(address(this)));
        (bool success, bytes memory returnData) = oneInchRouter.call(exchangeData);
        uint256 returnAmount;
        if (success) {
            (returnAmount) = abi.decode(returnData, (uint256));
            uint256 tokenInBalanceAfter = IERC20(tokenIn).balanceOf(receiver);
            uint256 tokenOutBalanceAfter = IERC20(tokenOut).balanceOf(receiver);
            if (tokenInBalanceAfter >= tokenInBalanceBefore) revert BalanceLessThanAmount();
            if (tokenOutBalanceAfter <= tokenOutBalanceBefore) revert BalanceLessThanAmount();

            balance -= adjustedDecimals(tokenIn, tokenInBalanceBefore - tokenInBalanceAfter);
            balance += adjustedDecimals(tokenIn, tokenOutBalanceAfter - tokenOutBalanceBefore);
        } else {
            revert SwapFailed();
        }
        return uint96(returnAmount);
    }

    /////////////////// setter Functions ////////////////////
    //////////////////////////////////////////////////////////

    function setProtocolRatio(bytes32 protocol, uint64 newRatio) public onlyOwner {
        uint64 _prevRatio = protocolRatio[protocol];
        if (newRatio > remainingRatio + _prevRatio) revert MaxRatioExceeded();
        if (newRatio <= remainingRatio) {
            remainingRatio -= newRatio;
            protocolRatio[protocol] = newRatio;
        }
    }

    function setProtocolsRatio(bytes32[] memory protocols, uint64[] memory newRatio) public onlyOwner {
        if (protocols.length != newRatio.length) revert LengthMismatch();
        uint256 i = 0;
        for (; i < protocols.length;) {
            setProtocolRatio(protocols[i], newRatio[i]);

            unchecked {
                ++i;
            }
        }
    }

    function whitelistToken(address token, bool isWhitelist) public onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        isWhitelisted[token] = isWhitelist;
    }

    function whitelistTokens(address[] memory tokens, bool[] memory isWhitelist) public onlyOwner {
        if (tokens.length != isWhitelist.length) revert LengthMismatch();
        uint256 i = 0;
        for (; i < tokens.length;) {
            whitelistToken(tokens[i], isWhitelist[i]);

            unchecked {
                ++i;
            }
        }
    }


    function setGmx(Gmx memory _gmx) external onlyOwner {
        gmx = _gmx;
    }

    /////////////////// protocol Functions ////////////////////
    //////////////////////////////////////////////////////////

    function farmInGmx(address token, uint256 amount, uint256 minUsdg, uint256 minGlp) external onlyOwner {
        IERC20(token).approve(gmx.GLP_MANAGER, amount);
        uint256 glpAmount = IGmx(gmx.REWARD_ROUTER2).mintAndStakeGlp(token, amount, minUsdg, minGlp);
        if(adjustedDecimals(token, amount) > balance * protocolRatio[bytes32("gmx")] / MAX_RATIO) {
            revert MaxRatioExceeded();
        }
        ProtocolData storage _protocolData = protocolData[bytes32("gmx")][block.timestamp];

        _protocolData.investedBalance += uint96(amount);
        _protocolData.tokenUsed = token;
    }

    function farmOutGmx(
        address tokenIn,
        address tokenOut,
        uint256 glpAmount,
        uint256 minOut,
        uint256 timestamp,
        bytes memory exchangeData
    ) external onlyOwner {
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));
        ProtocolData storage _protocolData = protocolData[bytes32("gmx")][timestamp];

        if (exchangeData.length > 0) {
            IERC20(tokenIn).approve(oneInchRouter, IERC20(tokenIn).balanceOf(address(this)));
            oneInchSwap(exchangeData);

            uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
            if (balanceAfter != balanceBefore) {
                uint256 difference = adjustedDecimals(tokenOut, balanceAfter - balanceBefore);
                _protocolData.yield = int96(uint96(difference));
            }
        } else {
            IGmx(gmx.REWARD_ROUTER).claim();
            uint256 amountOut = IGmx(gmx.REWARD_ROUTER2).unstakeAndRedeemGlp(tokenOut, glpAmount, minOut, address(this));

            uint256 difference = adjustedDecimals(tokenOut, amountOut);
            _protocolData.harvestedBalance = uint96(difference);
        }
    }

    /////////////////// get Functions ////////////////////////
    //////////////////////////////////////////////////////////

    function getRemainingRatio() external view returns (uint64) {
        return remainingRatio;
    }

    function getBalance() external view returns (uint96) {
        return balance;
    }

    function getProtocolData(bytes32 protocol, uint256 timestamp) external view returns (ProtocolData memory) {
        return protocolData[protocol][timestamp];
    }

    function getProtocolRatio(bytes32 protocol) external view returns (uint64) {
        return protocolRatio[protocol];
    }

    function getWhitelisted(address token) external view returns (bool) {
        return isWhitelisted[token];
    }

    /////////////////// Internal Functions ////////////////////
    //////////////////////////////////////////////////////////

    function adjustedDecimals(address token, uint256 amount) internal view returns (uint64) {
        uint256 adjustedAmount = amount * (10 ** DEFAULT_DECIMALS) / (10 ** IERC20(token).decimals());
        return uint64(adjustedAmount);
    }

    function oneInchSwap(bytes memory exchangeData) internal returns (uint96) {
        if (exchangeData.length == 0) revert ExchangeDataMismatch();

        (bool success, bytes memory returnData) = oneInchRouter.call(exchangeData);
        uint256 returnAmount;
        if (success) {
            (returnAmount) = abi.decode(returnData, (uint256));
        } else {
            revert SwapFailed();
        }
        return uint96(returnAmount);
    }
}
