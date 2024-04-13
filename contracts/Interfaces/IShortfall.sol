pragma solidity ^0.8.25;

interface IShortfall {
    function convertibleBaseAsset() external returns (address);
}
