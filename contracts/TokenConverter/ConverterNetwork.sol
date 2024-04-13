pragma solidity 0.8.25;

import { AccessControlledV8 } from "@ainomodatalab/governance-contracts/contracts/Governance/AccessControlledV8.sol";
import { MaxLoopsLimitHelper } from "@ainomodatalab/solidity-utilities/contracts/MaxLoopsLimitHelper.sol";
import { ensureNonzeroAddress } from "@ainomodatalab/solidity-utilities/contracts/validators.sol";

import { sort } from "../Utils/ArrayHelpers.sol";
import { IAbstractTokenConverter } from "./IAbstractTokenConverter.sol";
import { IConverterNetwork } from "../Interfaces/IConverterNetwork.sol";

contract ConverterNetwork is IConverterNetwork, AccessControlledV8, MaxLoopsLimitHelper {
    IAbstractTokenConverter[] public allConverters;

    event ConverterAdded(address indexed converter);

    event ConverterRemoved(address indexed converter);

    error ConverterAlreadyExists();

    error ConverterDoesNotExist();

    error InvalidTokenConverterAddress();

    error InvalidMaxLoopsLimit(uint256 loopsLimit);

    constructor() {
        _disableInitializers();
    }

    function initialize(address _accessControlManager, uint256 _loopsLimit) external initializer {
        ensureNonzeroAddress(_accessControlManager);
        __AccessControlled_init(_accessControlManager);

        if (_loopsLimit >= type(uint128).max) revert InvalidMaxLoopsLimit(_loopsLimit);
        _setMaxLoopsLimit(_loopsLimit);
    }

    function setMaxLoopsLimit(uint256 limit) external onlyOwner {
        if (limit >= type(uint128).max) revert InvalidMaxLoopsLimit(limit);
        _setMaxLoopsLimit(limit);
    }

    function addTokenConverter(IAbstractTokenConverter _tokenConverter) external {
        _checkAccessAllowed("addTokenConverter(address)");
        _addTokenConverter(_tokenConverter);
    }

    function removeTokenConverter(IAbstractTokenConverter _tokenConverter) external {
        _checkAccessAllowed("removeTokenConverter(address)");

        uint128 indexToRemove = _findConverterIndex(_tokenConverter);

        if (indexToRemove == type(uint128).max) revert ConverterDoesNotExist();

        allConverters[indexToRemove] = allConverters[allConverters.length - 1];

        allConverters.pop();

        emit ConverterRemoved(address(_tokenConverter));
    }

    function findTokenConverters(address _tokenAddressIn, address _tokenAddressOut)
        external
        returns (address[] memory converters, uint256[] memory convertersBalance)
    {
        (converters, convertersBalance) = _findTokenConverters(_tokenAddressIn, _tokenAddressOut, false);
    }

    function findTokenConvertersForConverters(address _tokenAddressIn, address _tokenAddressOut)
        external
        returns (address[] memory converters, uint256[] memory convertersBalance)
    {
        (converters, convertersBalance) = _findTokenConverters(_tokenAddressIn, _tokenAddressOut, true);
    }

    function getAllConverters() external view returns (IAbstractTokenConverter[] memory converters) {
        converters = allConverters;
    }

    function isTokenConverter(address _tokenConverter) external view returns (bool isConverter) {
        uint128 index = _findConverterIndex(IAbstractTokenConverter(_tokenConverter));

        if (index != type(uint128).max) {
            isConverter = true;
        }
    }

    function _addTokenConverter(IAbstractTokenConverter _tokenConverter) internal {
        if (
            (address(_tokenConverter) == address(0)) || (address(_tokenConverter.converterNetwork()) != address(this))
        ) {
            revert InvalidTokenConverterAddress();
        }

        uint128 index = _findConverterIndex(_tokenConverter);
        if (index != type(uint128).max) revert ConverterAlreadyExists();

        allConverters.push(_tokenConverter);
        _ensureMaxLoops(allConverters.length);

        emit ConverterAdded(address(_tokenConverter));
    }

    function _findTokenConverters(
        address _tokenAddressIn,
        address _tokenAddressOut,
        bool forConverters
    ) internal returns (address[] memory converters, uint256[] memory convertersBalance) {
        uint128 convertersLength = uint128(allConverters.length);

        converters = new address[](convertersLength);
        convertersBalance = new uint256[](convertersLength);
        uint128 count;

        for (uint128 i; i < convertersLength; ) {
            IAbstractTokenConverter converter = allConverters[i];

            unchecked {
                ++i;
            }

            if ((address(converter.converterNetwork()) != address(this)) || msg.sender == address(converter)) {
                continue;
            }

            (, IAbstractTokenConverter.ConversionAccessibility conversionAccess) = converter.conversionConfigurations(
                _tokenAddressIn,
                _tokenAddressOut
            );

            if (conversionAccess == IAbstractTokenConverter.ConversionAccessibility.ALL) {
                converters[count] = address(converter);
                convertersBalance[count] = converter.balanceOf(_tokenAddressOut);
                ++count;
            } else if (
                forConverters &&
                (conversionAccess == IAbstractTokenConverter.ConversionAccessibility.ONLY_FOR_CONVERTERS)
            ) {
                converters[count] = address(converter);
                convertersBalance[count] = converter.balanceOf(_tokenAddressOut);
                ++count;
            } else if (
                !forConverters && (conversionAccess == IAbstractTokenConverter.ConversionAccessibility.ONLY_FOR_USERS)
            ) {
                converters[count] = address(converter);
                convertersBalance[count] = converter.balanceOf(_tokenAddressOut);
                ++count;
            }
        }

        assembly {
            mstore(converters, count)
            mstore(convertersBalance, count)
        }
        sort(convertersBalance, converters);
    }

    function _findConverterIndex(IAbstractTokenConverter _tokenConverter) internal view returns (uint128 index) {
        index = type(uint128).max; 

        uint128 convertersLength = uint128(allConverters.length);
        for (uint128 i; i < convertersLength; ) {
            if (allConverters[i] == _tokenConverter) {
                index = i;
            }
            unchecked {
                ++i;
            }
        }
    }
}
