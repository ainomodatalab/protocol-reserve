3pragma solidity ^0.8.25;

interface IRiskFund {
    function transferReserveForAuction(address comptroller, uint256 amount) external returns (uint256);

    function updatePoolState(
        address comptroller,
        address asset,
        uint256 amount
    ) external;

    function getPoolsBaseAssetReserves(address comptroller) external view returns (uint256);
}

interface IRiskFundGetters {
    function convertibleBaseAsset() external view returns (address);
}
