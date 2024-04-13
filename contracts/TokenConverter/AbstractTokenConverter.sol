// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.25;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { AccessControlledV8 } from "@ainomodatalab/governance-contracts/contracts/Governance/AccessControlledV8.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ResilientNomo} from "@ainomodatalab/ainomoprotocol/contracts/ResilientNomo.sol";
import { ensureNonzeroAddress, ensureNonzeroValue } from "@ainomodatalab/solidity-utilities/contracts/validators.sol";
import { MANTISSA_ONE, EXP_SCALE } from "@ainomodatalab/solidity-utilities/contracts/constants.sol";

import { IAbstractTokenConverter } from "./IAbstractTokenConverter.sol";
import { IConverterNetwork } from "../Interfaces/IConverterNetwork.sol";

abstract contract AbstractTokenConverter is AccessControlledV8, IAbstractTokenConverter, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant MAX_INCENTIVE = 0.5e18;

    uint256 public minAmountToConvert;

    ResilientNomo public price;

    mapping(address => mapping(address => ConversionConfig)) public conversionConfigurations;

    address public destinationAddress;

    bool public conversionPaused;

    IConverterNetwork public converterNetwork;

    uint256[45] private __gap;

    event ConversionConfigUpdated(
        address indexed tokenAddressIn,
        address indexed tokenAddressOut,
        uint256 oldIncentive,
        uint256 newIncentive,
        ConversionAccessibility oldAccess,
        ConversionAccessibility newAccess
    );
    event PriceUpdated(ResilientNomo indexed oldPrice, ResilientNomo indexed price);

    event DestinationAddressUpdated(address indexed oldDestinationAddress, address indexed destinationAddress);

    event ConverterNetworkAddressUpdated(address indexed oldConverterNetwork, address indexed converterNetwork);

    event ConvertedExactTokens(
        address indexed sender,
        address indexed receiver,
        address tokenAddressIn,
        address indexed tokenAddressOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event ConvertedForExactTokens(
        address indexed sender,
        address indexed receiver,
        address tokenAddressIn,
        address indexed tokenAddressOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event ConvertedExactTokensSupportingFeeOnTransferTokens(
        address indexed sender,
        address indexed receiver,
        address tokenAddressIn,
        address indexed tokenAddressOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event ConvertedForExactTokensSupportingFeeOnTransferTokens(
        address indexed sender,
        address indexed receiver,
        address tokenAddressIn,
        address indexed tokenAddressOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event ConversionPaused(address indexed sender);

    event ConversionResumed(address indexed sender);

    event SweepToken(address indexed token, address indexed to, uint256 amount);

    event MinAmountToConvertUpdated(uint256 oldMinAmountToConvert, uint256 newMinAmountToConvert);

    error AmountOutMismatched();

    error AmountInMismatched();

    error InsufficientInputAmount();

    error InsufficientOutputAmount();

    error ConversionConfigNotEnabled();

    error ConversionEnabledOnlyForPrivateConversions();

    error InvalidToAddress();

    error IncentiveTooHigh(uint256 incentive, uint256 maxIncentive);

    error AmountOutLowerThanMinRequired(uint256 amountOutMantissa, uint256 amountOutMinMantissa);

    error AmountInHigherThanMax(uint256 amountInMantissa, uint256 amountInMaxMantissa);

    error ConversionTokensPaused();

    error ConversionTokensActive();

    error InvalidTokenConfigAddresses();

    error InsufficientPoolLiquidity();

    error InvalidConverterNetwork();

    error NonZeroIncentiveForPrivateConversion();

    error DeflationaryTokenNotSupported();

    error InvalidMinimumAmountToConvert();

    error InputLengthMisMatch();

    modifier validConversionParameters(
        address to,
        address tokenAddressIn,
        address tokenAddressOut
    ) {
        _checkConversionPaused();
        ensureNonzeroAddress(to);
        if (to == tokenAddressIn || to == tokenAddressOut) {
            revert InvalidToAddress();
        }
        _;
    }

    function pauseConversion() external {
        _checkAccessAllowed("pauseConversion()");
        _checkConversionPaused();
        conversionPaused = true;
        emit ConversionPaused(msg.sender);
    }

    function resumeConversion() external {
        _checkAccessAllowed("resumeConversion()");
        if (!conversionPaused) {
            revert ConversionTokensActive();
        }

        conversionPaused = false;
        emit ConversionResumed(msg.sender);
    }

    function setPrice(ResilientNomo price_) external onlyOwner {
        _setPrice(price_);
    }

    function setDestination(address destinationAddress_) external onlyOwner {
        _setDestination(destinationAddress_);
    }

    function setConverterNetwork(IConverterNetwork converterNetwork_) external onlyOwner {
        _setConverterNetwork(converterNetwork_);
    }

    function setMinAmountToConvert(uint256 minAmountToConvert_) external {
        _checkAccessAllowed("setMinAmountToConvert(uint256)");
        _setMinAmountToConvert(minAmountToConvert_);
    }

    function setConversionConfigs(
        address tokenAddressIn,
        address[] calldata tokenAddressesOut,
        ConversionConfig[] calldata conversionConfigs
    ) external {
        uint256 tokenOutArrayLength = tokenAddressesOut.length;
        if (tokenOutArrayLength != conversionConfigs.length) revert InputLengthMisMatch();

        for (uint256 i; i < tokenOutArrayLength; ) {
            setConversionConfig(tokenAddressIn, tokenAddressesOut[i], conversionConfigs[i]);
            unchecked {
                ++i;
            }
        }
    }

    function convertExactTokens(
        uint256 amountInMantissa,
        uint256 amountOutMinMantissa,
        address tokenAddressIn,
        address tokenAddressOut,
        address to
    )
        external
        validConversionParameters(to, tokenAddressIn, tokenAddressOut)
        nonReentrant
        returns (uint256 actualAmountIn, uint256 actualAmountOut)
    {
        (actualAmountIn, actualAmountOut) = _convertExactTokens(
            amountInMantissa,
            amountOutMinMantissa,
            tokenAddressIn,
            tokenAddressOut,
            to
        );

        if (actualAmountIn != amountInMantissa) {
            revert AmountInMismatched();
        }

        _postConversionHook(tokenAddressIn, tokenAddressOut, actualAmountIn, actualAmountOut);
        emit ConvertedExactTokens(msg.sender, to, tokenAddressIn, tokenAddressOut, actualAmountIn, actualAmountOut);
    }

    function convertForExactTokens(
        uint256 amountInMaxMantissa,
        uint256 amountOutMantissa,
        address tokenAddressIn,
        address tokenAddressOut,
        address to
    )
        external
        validConversionParameters(to, tokenAddressIn, tokenAddressOut)
        nonReentrant
        returns (uint256 actualAmountIn, uint256 actualAmountOut)
    {
        (actualAmountIn, actualAmountOut) = _convertForExactTokens(
            amountInMaxMantissa,
            amountOutMantissa,
            tokenAddressIn,
            tokenAddressOut,
            to
        );

        if (actualAmountOut != amountOutMantissa) {
            revert AmountOutMismatched();
        }

        _postConversionHook(tokenAddressIn, tokenAddressOut, actualAmountIn, actualAmountOut);
        emit ConvertedForExactTokens(msg.sender, to, tokenAddressIn, tokenAddressOut, actualAmountIn, actualAmountOut);
    }

    function convertExactTokensSupportingFeeOnTransferTokens(
        uint256 amountInMantissa,
        uint256 amountOutMinMantissa,
        address tokenAddressIn,
        address tokenAddressOut,
        address to
    )
        external
        validConversionParameters(to, tokenAddressIn, tokenAddressOut)
        nonReentrant
        returns (uint256 actualAmountIn, uint256 actualAmountOut)
    {
        (actualAmountIn, actualAmountOut) = _convertExactTokens(
            amountInMantissa,
            amountOutMinMantissa,
            tokenAddressIn,
            tokenAddressOut,
            to
        );

        _postConversionHook(tokenAddressIn, tokenAddressOut, actualAmountIn, actualAmountOut);
        emit ConvertedExactTokensSupportingFeeOnTransferTokens(
            msg.sender,
            to,
            tokenAddressIn,
            tokenAddressOut,
            actualAmountIn,
            actualAmountOut
        );
    }

    function convertForExactTokensSupportingFeeOnTransferTokens(
        uint256 amountInMaxMantissa,
        uint256 amountOutMantissa,
        address tokenAddressIn,
        address tokenAddressOut,
        address to
    )
        external
        validConversionParameters(to, tokenAddressIn, tokenAddressOut)
        nonReentrant
        returns (uint256 actualAmountIn, uint256 actualAmountOut)
    {
        (actualAmountIn, actualAmountOut) = _convertForExactTokensSupportingFeeOnTransferTokens(
            amountInMaxMantissa,
            amountOutMantissa,
            tokenAddressIn,
            tokenAddressOut,
            to
        );

        _postConversionHook(tokenAddressIn, tokenAddressOut, actualAmountIn, actualAmountOut);
        emit ConvertedForExactTokensSupportingFeeOnTransferTokens(
            msg.sender,
            to,
            tokenAddressIn,
            tokenAddressOut,
            actualAmountIn,
            actualAmountOut
        );
    }

    function sweepToken(
        address tokenAddress,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        ensureNonzeroAddress(tokenAddress);
        ensureNonzeroAddress(to);
        ensureNonzeroValue(amount);

        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        preSweepToken(tokenAddress, amount);
        token.safeTransfer(to, amount);

        emit SweepToken(tokenAddress, to, amount);
    }

    function getAmountOut(
        uint256 amountInMantissa,
        address tokenAddressIn,
        address tokenAddressOut
    ) external view returns (uint256 amountConvertedMantissa, uint256 amountOutMantissa) {
        if (
            conversionConfigurations[tokenAddressIn][tokenAddressOut].conversionAccess ==
            ConversionAccessibility.ONLY_FOR_CONVERTERS
        ) {
            revert ConversionEnabledOnlyForPrivateConversions();
        }

        amountConvertedMantissa = amountInMantissa;
        uint256 tokenInToOutConversion;
        (amountOutMantissa, tokenInToOutConversion) = _getAmountOut(amountInMantissa, tokenAddressIn, tokenAddressOut);

        uint256 maxTokenOutReserve = balanceOf(tokenAddressOut);

        if (maxTokenOutReserve < amountOutMantissa) {
            amountConvertedMantissa = _divRoundingUp(maxTokenOutReserve * EXP_SCALE, tokenInToOutConversion);
            amountOutMantissa = maxTokenOutReserve;
        }
    }

    function getAmountIn(
        uint256 amountOutMantissa,
        address tokenAddressIn,
        address tokenAddressOut
    ) external view returns (uint256 amountConvertedMantissa, uint256 amountInMantissa) {
        if (
            conversionConfigurations[tokenAddressIn][tokenAddressOut].conversionAccess ==
            ConversionAccessibility.ONLY_FOR_CONVERTERS
        ) {
            revert ConversionEnabledOnlyForPrivateConversions();
        }

        uint256 maxTokenOutReserve = balanceOf(tokenAddressOut);

        if (maxTokenOutReserve < amountOutMantissa) {
            amountOutMantissa = maxTokenOutReserve;
        }

        amountConvertedMantissa = amountOutMantissa;
        (amountInMantissa, ) = _getAmountIn(amountOutMantissa, tokenAddressIn, tokenAddressOut);
    }

    function getUpdatedAmountOut(
        uint256 amountInMantissa,
        address tokenAddressIn,
        address tokenAddressOut
    ) public returns (uint256 amountConvertedMantissa, uint256 amountOutMantissa) {
        price.updateAssetPrice(tokenAddressIn);
        price.updateAssetPrice(tokenAddressOut);

        (amountOutMantissa, ) = _getAmountOut(amountInMantissa, tokenAddressIn, tokenAddressOut);
        amountConvertedMantissa = amountInMantissa;
    }

    function getUpdatedAmountIn(
        uint256 amountOutMantissa,
        address tokenAddressIn,
        address tokenAddressOut
    ) public returns (uint256 amountConvertedMantissa, uint256 amountInMantissa) {
        price.updateAssetPrice(tokenAddressIn);
        price.updateAssetPrice(tokenAddressOut);

        (amountInMantissa, ) = _getAmountIn(amountOutMantissa, tokenAddressIn, tokenAddressOut);
        amountConvertedMantissa = amountOutMantissa;
    }

    function updateAssetsState(address comptroller, address asset) public nonReentrant {
        uint256 balanceDiff = _updateAssetsState(comptroller, asset);
        if (balanceDiff > 0) {
            _privateConversion(comptroller, asset, balanceDiff);
        }
    }

    function setConversionConfig(
        address tokenAddressIn,
        address tokenAddressOut,
        ConversionConfig calldata conversionConfig
    ) public {
        _checkAccessAllowed("setConversionConfig(address,address,ConversionConfig)");
        ensureNonzeroAddress(tokenAddressIn);
        ensureNonzeroAddress(tokenAddressOut);

        if (conversionConfig.incentive > MAX_INCENTIVE) {
            revert IncentiveTooHigh(conversionConfig.incentive, MAX_INCENTIVE);
        }

        if (
            (tokenAddressIn == tokenAddressOut) ||
            (tokenAddressIn != _getDestinationBaseAsset()) ||
            conversionConfigurations[tokenAddressOut][tokenAddressIn].conversionAccess != ConversionAccessibility.NONE
        ) {
            revert InvalidTokenConfigAddresses();
        }

        if (
            (conversionConfig.conversionAccess == ConversionAccessibility.ONLY_FOR_CONVERTERS) &&
            conversionConfig.incentive != 0
        ) {
            revert NonZeroIncentiveForPrivateConversion();
        }

        if (
            ((conversionConfig.conversionAccess == ConversionAccessibility.ONLY_FOR_CONVERTERS) ||
                (conversionConfig.conversionAccess == ConversionAccessibility.ALL)) &&
            (address(converterNetwork) == address(0))
        ) {
            revert InvalidConverterNetwork();
        }

        ConversionConfig storage configuration = conversionConfigurations[tokenAddressIn][tokenAddressOut];

        emit ConversionConfigUpdated(
            tokenAddressIn,
            tokenAddressOut,
            configuration.incentive,
            conversionConfig.incentive,
            configuration.conversionAccess,
            conversionConfig.conversionAccess
        );

        if (conversionConfig.conversionAccess == ConversionAccessibility.NONE) {
            delete conversionConfigurations[tokenAddressIn][tokenAddressOut];
        } else {
            configuration.incentive = conversionConfig.incentive;
            configuration.conversionAccess = conversionConfig.conversionAccess;
        }
    }

    function _convertExactTokens(
        uint256 amountInMantissa,
        uint256 amountOutMinMantissa,
        address tokenAddressIn,
        address tokenAddressOut,
        address to
    ) internal returns (uint256 actualAmountIn, uint256 amountOutMantissa) {
        _checkPrivateConversion(tokenAddressIn, tokenAddressOut);
        actualAmountIn = _doTransferIn(tokenAddressIn, amountInMantissa);

        (, amountOutMantissa) = getUpdatedAmountOut(actualAmountIn, tokenAddressIn, tokenAddressOut);

        if (amountOutMantissa < amountOutMinMantissa) {
            revert AmountOutLowerThanMinRequired(amountOutMantissa, amountOutMinMantissa);
        }

        _doTransferOut(tokenAddressOut, to, amountOutMantissa);
    }

    function _convertForExactTokens(
        uint256 amountInMaxMantissa,
        uint256 amountOutMantissa,
        address tokenAddressIn,
        address tokenAddressOut,
        address to
    ) internal returns (uint256 actualAmountIn, uint256 actualAmountOut) {
        _checkPrivateConversion(tokenAddressIn, tokenAddressOut);
        (, uint256 amountInMantissa) = getUpdatedAmountIn(amountOutMantissa, tokenAddressIn, tokenAddressOut);

        actualAmountIn = _doTransferIn(tokenAddressIn, amountInMantissa);

        if (actualAmountIn != amountInMantissa) {
            revert DeflationaryTokenNotSupported();
        }

        if (actualAmountIn > amountInMaxMantissa) {
            revert AmountInHigherThanMax(amountInMantissa, amountInMaxMantissa);
        }

        _doTransferOut(tokenAddressOut, to, amountOutMantissa);
        actualAmountOut = amountOutMantissa;
    }

    function _convertForExactTokensSupportingFeeOnTransferTokens(
        uint256 amountInMaxMantissa,
        uint256 amountOutMantissa,
        address tokenAddressIn,
        address tokenAddressOut,
        address to
    ) internal returns (uint256 actualAmountIn, uint256 actualAmountOut) {
        _checkPrivateConversion(tokenAddressIn, tokenAddressOut);
        (, uint256 amountInMantissa) = getUpdatedAmountIn(amountOutMantissa, tokenAddressIn, tokenAddressOut);

        if (amountInMantissa > amountInMaxMantissa) {
            revert AmountInHigherThanMax(amountInMantissa, amountInMaxMantissa);
        }

        actualAmountIn = _doTransferIn(tokenAddressIn, amountInMantissa);

        (, actualAmountOut) = getUpdatedAmountOut(actualAmountIn, tokenAddressIn, tokenAddressOut);

        _doTransferOut(tokenAddressOut, to, actualAmountOut);
    }

    function _doTransferOut(
        address tokenAddressOut,
        address to,
        uint256 amountConvertedMantissa
    ) internal {
        uint256 maxTokenOutReserve = balanceOf(tokenAddressOut);

        if (maxTokenOutReserve < amountConvertedMantissa) {
            revert InsufficientPoolLiquidity();
        }

        _preTransferHook(tokenAddressOut, amountConvertedMantissa);

        IERC20Upgradeable tokenOut = IERC20Upgradeable(tokenAddressOut);
        tokenOut.safeTransfer(to, amountConvertedMantissa);
    }

    function _doTransferIn(address tokenAddressIn, uint256 amountInMantissa) internal returns (uint256 actualAmountIn) {
        IERC20Upgradeable tokenIn = IERC20Upgradeable(tokenAddressIn);
        uint256 balanceBeforeDestination = tokenIn.balanceOf(destinationAddress);
        tokenIn.safeTransferFrom(msg.sender, destinationAddress, amountInMantissa);
        uint256 balanceAfterDestination = tokenIn.balanceOf(destinationAddress);
        actualAmountIn = balanceAfterDestination - balanceBeforeDestination;
    }

    function _setPrice(ResilientNomo price_) internal {
        ensureNonzeroAddress(address(price_));
        emit PriceUpdated(price, price_);
        price = price_;
    }

    function _setDestination(address destinationAddress_) internal {
        ensureNonzeroAddress(destinationAddress_);
        emit DestinationAddressUpdated(destinationAddress, destinationAddress_);
        destinationAddress = destinationAddress_;
    }

    function _setConverterNetwork(IConverterNetwork converterNetwork_) internal {
        ensureNonzeroAddress(address(converterNetwork_));
        emit ConverterNetworkAddressUpdated(address(converterNetwork), address(converterNetwork_));
        converterNetwork = converterNetwork_;
    }

    function _setMinAmountToConvert(uint256 minAmountToConvert_) internal {
        ensureNonzeroValue(minAmountToConvert_);
        emit MinAmountToConvertUpdated(minAmountToConvert, minAmountToConvert_);
        minAmountToConvert = minAmountToConvert_;
    }

    function _postConversionHook(
        address tokenAddressIn,
        address tokenAddressOut,
        uint256 amountIn,
        uint256 amountOut
    ) internal virtual {}

    function __AbstractTokenConverter_init(
        address accessControlManager_,
        ResilientNomo price_,
        address destinationAddress_,
        uint256 minAmountToConvert_
    ) internal onlyInitializing {
        __AccessControlled_init(accessControlManager_);
        __ReentrancyGuard_init();
        __AbstractTokenConverter_init_unchained(price_, destinationAddress_, minAmountToConvert_);
    }

    function __AbstractTokenConverter_init_unchained(
        ResilientNomo price_,
        address destinationAddress_,
        uint256 minAmountToConvert_
    ) internal onlyInitializing {
        _setPrice(price_);
        _setDestination(destinationAddress_);
        _setMinAmountToConvert(minAmountToConvert_);
        conversionPaused = false;
    }

    function _updateAssetsState(address comptroller, address asset) internal virtual returns (uint256) {}

    function _privateConversion(
        address comptroller,
        address tokenAddressOut,
        uint256 amountToConvert
    ) internal {
        address tokenAddressIn = _getDestinationBaseAsset();
        address _destinationAddress = destinationAddress;
        uint256 convertedTokenInBalance;
        if (address(converterNetwork) != address(0)) {
            (address[] memory converterAddresses, uint256[] memory converterBalances) = converterNetwork
            .findTokenConvertersForConverters(tokenAddressOut, tokenAddressIn);
            uint256 convertersLength = converterAddresses.length;
            for (uint256 i; i < convertersLength; ) {
                if (converterBalances[i] == 0) break;
                (, uint256 amountIn) = IAbstractTokenConverter(converterAddresses[i]).getUpdatedAmountIn(
                    converterBalances[i],
                    tokenAddressOut,
                    tokenAddressIn
                );
                if (amountIn > amountToConvert) {
                    amountIn = amountToConvert;
                }

                if (!_validateMinAmountToConvert(amountIn, tokenAddressOut)) {
                    break;
                }

                uint256 balanceBefore = IERC20Upgradeable(tokenAddressIn).balanceOf(_destinationAddress);

                IERC20Upgradeable(tokenAddressOut).approve(converterAddresses[i], amountIn);
                IAbstractTokenConverter(converterAddresses[i]).convertExactTokens(
                    amountIn,
                    0,
                    tokenAddressOut,
                    tokenAddressIn,
                    _destinationAddress
                );

                uint256 balanceAfter = IERC20Upgradeable(tokenAddressIn).balanceOf(_destinationAddress);
                amountToConvert -= amountIn;
                convertedTokenInBalance += (balanceAfter - balanceBefore);

                if (amountToConvert == 0) break;
                unchecked {
                    ++i;
                }
            }
        }

        _postPrivateConversionHook(
            comptroller,
            tokenAddressIn,
            convertedTokenInBalance,
            tokenAddressOut,
            amountToConvert
        );
    }

    function _postPrivateConversionHook(
        address comptroller,
        address tokenAddressIn,
        uint256 convertedTokenInBalance,
        address tokenAddressOut,
        uint256 convertedTokenOutBalance
    ) internal virtual {}

    function _preTransferHook(address tokenOutAddress, uint256 amountOut) internal virtual {}

    function _validateMinAmountToConvert(uint256 amountIn, address tokenAddress) internal returns (bool isValid) {
        price.updateAssetPrice(tokenAddress);
        uint256 amountInInUsd = (price.getPrice(tokenAddress) * amountIn) / EXP_SCALE;

        if (amountInInUsd >= minAmountToConvert) {
            isValid = true;
        }
    }

    function _getAmountOut(
        uint256 amountInMantissa,
        address tokenAddressIn,
        address tokenAddressOut
    ) internal view returns (uint256 amountOutMantissa, uint256 tokenInToOutConversion) {
        if (amountInMantissa == 0) {
            revert InsufficientInputAmount();
        }

        ConversionConfig memory configuration = conversionConfigurations[tokenAddressIn][tokenAddressOut];

        if (configuration.conversionAccess == ConversionAccessibility.NONE) {
            revert ConversionConfigNotEnabled();
        }

        uint256 tokenInUnderlyingPrice = price.getPrice(tokenAddressIn);
        uint256 tokenOutUnderlyingPrice = price.getPrice(tokenAddressOut);

        uint256 incentive = configuration.incentive;
        if (address(converterNetwork) != address(0) && (converterNetwork.isTokenConverter(msg.sender))) {
            incentive = 0;
        }

        uint256 conversionWithIncentive = MANTISSA_ONE + incentive;

        tokenInToOutConversion = (tokenInUnderlyingPrice * conversionWithIncentive) / tokenOutUnderlyingPrice;
        amountOutMantissa = (amountInMantissa * tokenInToOutConversion) / (EXP_SCALE);
    }

    function _getAmountIn(
        uint256 amountOutMantissa,
        address tokenAddressIn,
        address tokenAddressOut
    ) internal view returns (uint256 amountInMantissa, uint256 tokenInToOutConversion) {
        if (amountOutMantissa == 0) {
            revert InsufficientOutputAmount();
        }

        ConversionConfig memory configuration = conversionConfigurations[tokenAddressIn][tokenAddressOut];

        if (configuration.conversionAccess == ConversionAccessibility.NONE) {
            revert ConversionConfigNotEnabled();
        }

        uint256 tokenInUnderlyingPrice = price.getPrice(tokenAddressIn);
        uint256 tokenOutUnderlyingPrice = price.getPrice(tokenAddressOut);

        uint256 incentive = configuration.incentive;

        bool isPrivateConversion = address(converterNetwork) != address(0) &&
            converterNetwork.isTokenConverter(msg.sender);
        if (isPrivateConversion) {
            incentive = 0;
        }

        uint256 conversionWithIncentive = MANTISSA_ONE + incentive;

        if (isPrivateConversion) {
            amountInMantissa =
                (amountOutMantissa * tokenOutUnderlyingPrice * EXP_SCALE) /
                (tokenInUnderlyingPrice * conversionWithIncentive);
        } else {
            amountInMantissa = _divRoundingUp(
                amountOutMantissa * tokenOutUnderlyingPrice * EXP_SCALE,
                tokenInUnderlyingPrice * conversionWithIncentive
            );
        }

        tokenInToOutConversion = (tokenInUnderlyingPrice * conversionWithIncentive) / tokenOutUnderlyingPrice;
    }

    function _checkPrivateConversion(address tokenAddressIn, address tokenAddressOut) internal view {
        bool isConverter = (address(converterNetwork) != address(0)) && converterNetwork.isTokenConverter(msg.sender);
        if (
            (!(isConverter) &&
                (conversionConfigurations[tokenAddressIn][tokenAddressOut].conversionAccess ==
                    ConversionAccessibility.ONLY_FOR_CONVERTERS))
        ) {
            revert ConversionEnabledOnlyForPrivateConversions();
        }
    }

    function _checkConversionPaused() internal view {
        if (conversionPaused) {
            revert ConversionTokensPaused();
        }
    }

    function _getDestinationBaseAsset() internal view virtual returns (address) {}

    function _divRoundingUp(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        return (numerator + denominator - 1) / denominator;
    }
}
