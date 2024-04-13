pragma solidity ^0.8.25;

import { IAbstractTokenConverter } from "../TokenConverter/IAbstractTokenConverter.sol";

interface IConverterNetwork {
    function addTokenConverter(IAbstractTokenConverter _tokenConverter) external;

    function removeTokenConverter(IAbstractTokenConverter _tokenConverter) external;

    function findTokenConverters(address _tokenAddressIn, address _tokenAddressOut)
        external
        returns (address[] memory converters, uint256[] memory convertersBalance);

    function findTokenConvertersForConverters(address _tokenAddressIn, address _tokenAddressOut)
        external
        returns (address[] memory converters, uint256[] memory convertersBalance);

    function getAllConverters() external view returns (IAbstractTokenConverter[] memory);

    function isTokenConverter(address _tokenConverter) external view returns (bool);
}
