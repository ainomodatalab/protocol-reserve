pragma solidity ^0.8.25;

interface IRiskFundConverter {
    function updateAssetsState(address comptroller, address asset) external;

    function getPools(address asset) external view returns (address[] memory);
}
