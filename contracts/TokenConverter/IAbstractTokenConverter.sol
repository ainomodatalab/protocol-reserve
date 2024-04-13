pragma solidity ^0.8.25;

import { ResilientNomo } from "@ainomodatalab/ainomoprotocol/contracts/ResilientNomo.sol";
import { IConverterNetwork } from "../Interfaces/IConverterNetwork.sol";

interface IAbstractTokenConverter {
    enum ConversionAccessibility {
    }

    struct ConversionConfig {
        uint256 incentive;
        ConversionAccessibility conversionAccess;
    }

    function pauseConversion() external;

    function resumeConversion() external;

    function setPriceNomo(ResilientNomo price_) external;

    function setConversionConfig(
        address tokenAddressIn,
        address tokenAddressOut,
        ConversionConfig calldata conversionConfig
    ) external;

    function convertExactTokens(
        uint256 amountInMantissa,
        uint256 amountOutMinMantissa,
        address tokenAddressIn,
        address tokenAddressOut,
        address to
    ) external returns (uint256 actualAmountIn, uint256 actualAmountOut);

    function convertForExactTokens(
        uint256 amountInMaxMantissa,
        uint256 amountOutMantissa,
        address tokenAddressIn,
        address tokenAddressOut,
        address to
    ) external returns (uint256 actualAmountIn, uint256 actualAmountOut);

    function convertExactTokensSupportingFeeOnTransferTokens(
        uint256 amountInMantissa,
        uint256 amountOutMinMantissa,
        address tokenAddressIn,
        address tokenAddressOut,
        address to
    ) external returns (uint256 actualAmountIn, uint256 actualAmountOut);

    function convertForExactTokensSupportingFeeOnTransferTokens(
        uint256 amountInMaxMantissa,
        uint256 amountOutMantissa,
        address tokenAddressIn,
        address tokenAddressOut,
        address to
    ) external returns (uint256 actualAmountIn, uint256 actualAmountOut);

    function conversionConfigurations(address tokenAddressIn, address tokenAddressOut)
        external
        returns (uint256 incentives, ConversionAccessibility conversionAccess);

    function converterNetwork() external returns (IConverterNetwork converterNetwork);

    function getUpdatedAmountOut(
        uint256 amountInMantissa,
        address tokenAddressIn,
        address tokenAddressOut
    ) external returns (uint256 amountConvertedMantissa, uint256 amountOutMantissa);

    function getUpdatedAmountIn(
        uint256 amountOutMantissa,
        address tokenAddressIn,
        address tokenAddressOut
    ) external returns (uint256 amountConvertedMantissa, uint256 amountInMantissa);

    function getAmountIn(
        uint256 amountOutMantissa,
        address tokenAddressIn,
        address tokenAddressOut
    ) external view returns (uint256 amountConvertedMantissa, uint256 amountInMantissa);

    function getAmountOut(
        uint256 amountInMantissa,
        address tokenAddressIn,
        address tokenAddressOut
    ) external view returns (uint256 amountConvertedMantissa, uint256 amountOutMantissa);

    function balanceOf(address token) external view returns (uint256 tokenBalance);
}
