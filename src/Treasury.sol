// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IProtocol, IAave, IStargate, IGmx} from "src/interfaces/IProtocol.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

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

    event Deposit(address depositor, address token, uint256 amount);
    event Withdraw(address token, uint256 amount);
    event FarmAaveV3(address token, uint256 amount);
    event HarvestAaveV3(address token, uint256 amount, uint256 timestamp, int96 yield);
    event FarmStargate(address token, uint256 amount, uint256 poolId);
    event HarvestStargate(address token, uint256 amount, uint256 timestamp, uint16 poolId, int96 yield);
    event FarmGmx(address token, uint256 amount);
    event HarvestGmx(address token, uint256 amount, uint256 timestamp, int96 yield);

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
    AaveV3 public aaveV3;
    Stargate public stargate;

    constructor() {
        remainingRatio = MAX_RATIO;
    }

    function deposit(address token, uint256 amount) external returns (bool) {
        if (!isWhitelisted[token]) revert NonWhitelistedToken();
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        balance += adjustedDecimals(token, amount);

        emit Deposit(msg.sender, token, amount);
        return true;
    }

    function withdraw(address token, uint256 amount) external onlyOwner returns (bool) {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransfer(msg.sender, amount);
        balance -= adjustedDecimals(token, amount);

        emit Withdraw(token, amount);
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

    function setAaveV3(AaveV3 memory _aaveV3) external onlyOwner {
        aaveV3 = _aaveV3;
    }

    function setStargate(Stargate memory _stargate) external onlyOwner {
        stargate = _stargate;
    }

    function setGmx(Gmx memory _gmx) external onlyOwner {
        gmx = _gmx;
    }

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

    /////////////////// protocol Functions ////////////////////
    //////////////////////////////////////////////////////////

    function farmStargate(address token, uint256 poolId, uint256 amount, address lpToken) external onlyOwner {
        address STARGATE_ROUTER = stargate.router;
        IERC20(token).approve(STARGATE_ROUTER, IERC20(token).balanceOf(address(this)));
        IStargate(STARGATE_ROUTER).addLiquidity(poolId, amount, address(this));

        address STARGATE_LP_STAKING = stargate.lpStaking;
        uint256 lpBalance = IERC20(lpToken).balanceOf(address(this));
        IERC20(lpToken).approve(STARGATE_LP_STAKING, lpBalance);
        IStargate(STARGATE_LP_STAKING).deposit(poolId - 1, lpBalance);

        amount = adjustedDecimals(token, amount);
        uint256 maxFarmable = (balance / 10 ** DEFAULT_DECIMALS) * protocolRatio[bytes32("stargate")] / MAX_RATIO;
        if (amount / 10 ** DEFAULT_DECIMALS > maxFarmable) revert MaxRatioExceeded();

        ProtocolData storage _protocolData = protocolData[bytes32("stargate")][block.timestamp];

        _protocolData.investedBalance += uint96(amount);
        _protocolData.tokenUsed = token;
        balance -= uint96(amount);

        emit FarmStargate(token, amount, poolId);
    }

    function harvestStargate(
        address token,
        uint16 poolId,
        uint256 amount,
        address lpToken,
        bytes memory exchangeData,
        uint256 timestamp
    ) external onlyOwner {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        ProtocolData storage _protocolData = protocolData[bytes32("stargate")][timestamp];

        if (exchangeData.length > 0) {
            IERC20(stargate.stargateToken).approve(
                oneInchRouter, IERC20(stargate.stargateToken).balanceOf(address(this))
            );
            oneInchSwap(exchangeData);

            uint256 balanceAfter = IERC20(token).balanceOf(address(this));
            if (balanceAfter != balanceBefore) {
                uint256 difference = adjustedDecimals(token, balanceAfter - balanceBefore);
                _protocolData.yield = int96(uint96(difference));
                if (int96(uint96(difference)) > 0) balance += uint96(difference);
            }
        } else {
            address STARGATE_LP_STAKING = stargate.lpStaking;
            IStargate(STARGATE_LP_STAKING).withdraw(poolId - 1, amount);

            address STARGATE_ROUTER = stargate.router;
            IStargate(STARGATE_ROUTER).instantRedeemLocal(poolId, amount, address(this));

            uint256 balanceAfter = IERC20(token).balanceOf(address(this));
            uint256 difference = adjustedDecimals(token, balanceAfter - balanceBefore);
            _protocolData.harvestedBalance = uint96(difference);

            balanceAfter = adjustedDecimals(token, balanceAfter);
            _protocolData.yield = int96(uint96(balanceAfter - _protocolData.investedBalance));
            if (_protocolData.yield > 0) balance += uint96(_protocolData.yield);
        }

        emit HarvestStargate(token, amount, timestamp, poolId, _protocolData.yield);
    }

    function farmAaveV3(address token, uint256 amount) external onlyOwner {
        address AAVE_V3POOL = aaveV3.pool;
        IERC20(token).approve(AAVE_V3POOL, IERC20(token).balanceOf(address(this)));
        IAave(AAVE_V3POOL).supply(token, amount, address(this), uint16(0));

        amount = adjustedDecimals(token, amount);
        uint256 maxFarmable = (balance / 10 ** DEFAULT_DECIMALS) * protocolRatio[bytes32("aave-v3")] / MAX_RATIO;
        if (amount / 10 ** DEFAULT_DECIMALS > maxFarmable) revert MaxRatioExceeded();

        ProtocolData storage _protocolData = protocolData[bytes32("aave-v3")][block.timestamp];

        _protocolData.investedBalance += uint96(amount);
        _protocolData.tokenUsed = token;
        balance -= uint96(amount);

        emit FarmAaveV3(token, amount);
    }

    function harvestAaveV3(address token, uint256 amount, uint256 timestamp) external onlyOwner {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        ProtocolData storage _protocolData = protocolData[bytes32("aave-v3")][timestamp];

        address AAVE_V3POOL = aaveV3.pool;
        IAave(AAVE_V3POOL).withdraw(token, amount, address(this));

        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 difference = adjustedDecimals(token, balanceAfter - balanceBefore);
        _protocolData.harvestedBalance = uint96(difference);

        balanceAfter = adjustedDecimals(token, balanceAfter);
        _protocolData.yield = int96(uint96(balanceAfter - _protocolData.investedBalance));
        if (_protocolData.yield > 0) balance += uint96(_protocolData.yield);

        emit HarvestAaveV3(token, amount, timestamp, _protocolData.yield);
    }

    function farmGmx(address token, uint256 amount, uint256 minUsdg, uint256 minGlp) external onlyOwner {
        IERC20(token).approve(gmx.GLP_MANAGER, amount);
        IGmx(gmx.REWARD_ROUTER2).mintAndStakeGlp(token, amount, minUsdg, minGlp);

        amount = adjustedDecimals(token, amount);
        ProtocolData storage _protocolData = protocolData[bytes32("gmx")][block.timestamp];

        _protocolData.investedBalance += uint96(amount);
        _protocolData.tokenUsed = token;
        balance -= uint96(amount);

        emit FarmGmx(token, amount);
    }

    function harvestGmx(
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
                if (int96(uint96(difference)) > 0) balance += uint96(difference);
            }
        } else {
            IGmx(gmx.REWARD_ROUTER).claim();
            uint256 amountOut = IGmx(gmx.REWARD_ROUTER2).unstakeAndRedeemGlp(tokenOut, glpAmount, minOut, address(this));

            uint256 difference = adjustedDecimals(tokenOut, amountOut);
            _protocolData.harvestedBalance = uint96(difference);
            balance += uint96(difference);
        }

        emit HarvestGmx(tokenOut, glpAmount, timestamp, _protocolData.yield);
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

    function adjustedDecimals(address token, uint256 amount) internal view returns (uint96) {
        uint256 adjustedAmount = amount * (10 ** DEFAULT_DECIMALS) / (10 ** IERC20(token).decimals());
        return uint96(adjustedAmount);
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
