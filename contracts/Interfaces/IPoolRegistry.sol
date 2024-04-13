pragma solidity ^0.8.25;

interface IPoolRegistry {
    function getVTokenForAsset(address comptroller, address asset) external view returns (address);

    function getPoolsSupportedByAsset(address asset) external view returns (address[] memory);
}
