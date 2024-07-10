pragma solidity ^0.8.25;

interface IIncomeDestination {
    function updateAssetsState(address comptroller, address asset) external;
}
