// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IProtocol {
    struct Gmx {
        address VAULT;
        address REWARD_ROUTER;
        address REWARD_ROUTER2;
        address GLP;
        address GLP_MANAGER;
        address FEEGLP_TRACKER;
        address STAKEDGLP_TRACKER;
    }

    struct AaveV3 {
        address pool;
    }

    struct Stargate {
        address router;
        address lpStaking;
        address stargateToken;
    }
}

interface IAave {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getUserAccountData(address user)
        external
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
}

interface IStargate {
    function userInfo(uint256 poolId, address user) external returns(uint256 amount, uint256 rewardDebt);
    function addLiquidity(uint256 poolId, uint256 amount, address to) external;
    function deposit(uint256 poolId, uint256 amount) external;
    function withdraw(uint256 poolId, uint256 amount) external;
    function instantRedeemLocal(uint16 srcPoolId, uint256 amount, address to) external;
}

interface IGmx {
    function getStakingInfo(address account, address[] memory trackers) external returns (uint256[] memory);
    function stakedAmounts(address account) external returns (uint256);
    function stakeForAccount(address fundingAccount, address account, address glp, uint256 amount)
        external
        returns (uint256);
    function addLiquidity(address token, uint256 amount, uint256 minUsdg, uint256 minGlp) external returns (uint256);
    function mintAndStakeGlp(address token, uint256 amount, uint256 minUsdg, uint256 minGlp)
        external
        returns (uint256);

    function unstakeAndRedeemGlp(address tokenOut, uint256 glpAmount, uint256 minOut, address receiver)
        external
        returns (uint256);

    function claim() external;
    function claimFees() external;
    function getPrice(bool _maximise) external view returns (uint256); // glp price
}
