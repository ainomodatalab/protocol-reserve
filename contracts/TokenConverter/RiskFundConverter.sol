pragma solidity 0.8.25;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ResilientNomo } from "@ainomodatalab/ainomoprotocol/contracts/ResilientNomo.sol";
import { ensureNonzeroAddress, ensureNonzeroValue } from "@ainomodatalab/solidity-utilities/contracts/validators.sol";

import { AbstractTokenConverter } from "./AbstractTokenConverter.sol";
import { IPoolRegistry } from "../Interfaces/IPoolRegistry.sol";
import { IComptroller } from "../Interfaces/IComptroller.sol";
import { IRiskFund, IRiskFundGetters } from "../Interfaces/IRiskFund.sol";
import { IVToken } from "../Interfaces/IVToken.sol";

contract RiskFundConverter is AbstractTokenConverter {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public immutable CORE_POOL_COMPTROLLER;

    address public immutable VBNB;

    address public immutable NATIVE_WRAPPED;

    mapping(address => uint256) internal assetsReserves;

    mapping(address => mapping(address => uint256)) internal poolsAssetsReserves;

    address public poolRegistry;

    mapping(address => mapping(address => bool)) public poolsAssetsDirectTransfer;

    event PoolRegistryUpdated(address indexed oldPoolRegistry, address indexed newPoolRegistry);

    event AssetsReservesUpdated(address indexed comptroller, address indexed asset, uint256 amount);

    event AssetTransferredToDestination(
        address indexed receiver,
        address indexed comptroller,
        address indexed asset,
        uint256 amount
    );

    event PoolAssetsDirectTransferUpdated(address indexed comptroller, address indexed asset, bool value);

    error InvalidArguments();

    error InsufficientBalance();

    error MarketNotExistInPool(address comptroller, address asset);

    error ReentrancyGuardError();

    constructor(
        address corePoolComptroller_,
        address vBNB_,
        address nativeWrapped_
    ) {
        ensureNonzeroAddress(corePoolComptroller_);
        ensureNonzeroAddress(vBNB_);
        ensureNonzeroAddress(nativeWrapped_);

        CORE_POOL_COMPTROLLER = corePoolComptroller_;
        VBNB = vBNB_;
        NATIVE_WRAPPED = nativeWrapped_;

        _disableInitializers();
    }

    function initialize(
        address accessControlManager_,
        ResilientNomo price,
        address destinationAddress_,
        address poolRegistry_,
        uint256 minAmountToConvert_,
        address[] calldata comptrollers,
        address[][] calldata assets,
        bool[][] calldata values
    ) public initializer {
        __AbstractTokenConverter_init(accessControlManager_, price_, destinationAddress_, minAmountToConvert_);
        ensureNonzeroAddress(poolRegistry_);
        poolRegistry = poolRegistry_;
        _setPoolsAssetsDirectTransfer(comptrollers, assets, values);
    }

    function setPoolRegistry(address poolRegistry_) external onlyOwner {
        ensureNonzeroAddress(poolRegistry_);
        emit PoolRegistryUpdated(poolRegistry, poolRegistry_);
        poolRegistry = poolRegistry_;
    }

    function setPoolsAssetsDirectTransfer(
        address[] calldata comptrollers,
        address[][] calldata assets,
        bool[][] calldata values
    ) external {
        _checkAccessAllowed("setPoolsAssetsDirectTransfer(address[],address[][],bool[][])");
        _setPoolsAssetsDirectTransfer(comptrollers, assets, values);
    }

    function getPoolAssetReserve(address comptroller, address asset) external view returns (uint256 reserves) {
        if (_reentrancyGuardEntered()) revert ReentrancyGuardError();
        if (!ensureAssetListed(comptroller, asset)) revert MarketNotExistInPool(comptroller, asset);

        reserves = poolsAssetsReserves[comptroller][asset];
    }

    function balanceOf(address tokenAddress) public view override returns (uint256 tokenBalance) {
        tokenBalance = assetsReserves[tokenAddress];
    }

    function getPools(address tokenAddress) public view returns (address[] memory poolsWithCore) {
        poolsWithCore = IPoolRegistry(poolRegistry).getPoolsSupportedByAsset(tokenAddress);

        if (isAssetListedInCore(tokenAddress)) {
            uint256 poolsLength = poolsWithCore.length;
            address[] memory extendedPools = new address[](poolsLength + 1);

            for (uint256 i; i < poolsLength; ) {
                extendedPools[i] = poolsWithCore[i];
                unchecked {
                    ++i;
                }
            }

            extendedPools[poolsLength] = CORE_POOL_COMPTROLLER;
            poolsWithCore = extendedPools;
        }
    }

    function _preTransferHook(address tokenOutAddress, uint256 amountOut) internal override {
        assetsReserves[tokenOutAddress] -= amountOut;
    }

    function _postConversionHook(
        address tokenInAddress,
        address tokenOutAddress,
        uint256 amountIn,
        uint256 amountOut
    ) internal override {
        address[] memory pools = getPools(tokenOutAddress);
        uint256 assetReserve = assetsReserves[tokenOutAddress] + amountOut;
        ensureNonzeroValue(assetReserve);

        uint256 poolsLength = pools.length;
        uint256 distributedOutShare;
        uint256 poolAmountInShare;
        uint256 distributedInShare;

        for (uint256 i; i < poolsLength; ) {
            uint256 currentPoolsAssetsReserves = poolsAssetsReserves[pools[i]][tokenOutAddress];
            if (currentPoolsAssetsReserves != 0) {
                if (i < (poolsLength - 1)) {
                    distributedOutShare += updatePoolAssetsReserve(pools[i], tokenOutAddress, amountOut, assetReserve);
                    poolAmountInShare = (amountIn * currentPoolsAssetsReserves) / assetReserve;
                    distributedInShare += poolAmountInShare;
                } else {
                    uint256 distributedDiff = amountOut - distributedOutShare;
                    poolsAssetsReserves[pools[i]][tokenOutAddress] -= distributedDiff;
                    emit AssetsReservesUpdated(pools[i], tokenOutAddress, distributedDiff);
                    poolAmountInShare = amountIn - distributedInShare;
                }
                emit AssetTransferredToDestination(destinationAddress, pools[i], tokenInAddress, poolAmountInShare);
                IRiskFund(destinationAddress).updatePoolState(pools[i], tokenInAddress, poolAmountInShare);
            }
            unchecked {
                ++i;
            }
        }
    }

    function preSweepToken(address tokenAddress, uint256 amount) internal override {
        uint256 balance = IERC20Upgradeable(tokenAddress).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance();
        uint256 balanceDiff = balance - assetsReserves[tokenAddress];

        if (balanceDiff < amount) {
            uint256 amountDiff;
            unchecked {
                amountDiff = amount - balanceDiff;
            }

            address[] memory pools = getPools(tokenAddress);
            uint256 assetReserve = assetsReserves[tokenAddress];
            uint256 poolsLength = pools.length;
            uint256 distributedShare;

            for (uint256 i; i < poolsLength; ) {
                if (poolsAssetsReserves[pools[i]][tokenAddress] != 0) {
                    if (i < (poolsLength - 1)) {
                        distributedShare += updatePoolAssetsReserve(pools[i], tokenAddress, amountDiff, assetReserve);
                    } else {
                        uint256 distributedDiff = amountDiff - distributedShare;
                        poolsAssetsReserves[pools[i]][tokenAddress] -= distributedDiff;
                        emit AssetsReservesUpdated(pools[i], tokenAddress, distributedDiff);
                    }
                }
                unchecked {
                    ++i;
                }
            }
            assetsReserves[tokenAddress] -= amountDiff;
        }
    }

    function updatePoolAssetsReserve(
        address pool,
        address tokenAddress,
        uint256 amount,
        uint256 assetReserve
    ) internal returns (uint256 poolAmountShare) {
        poolAmountShare = (poolsAssetsReserves[pool][tokenAddress] * amount) / assetReserve;
        poolsAssetsReserves[pool][tokenAddress] -= poolAmountShare;
        emit AssetsReservesUpdated(pool, tokenAddress, poolAmountShare);
    }

    function _setPoolsAssetsDirectTransfer(
        address[] calldata comptrollers,
        address[][] calldata assets,
        bool[][] calldata values
    ) internal {
        uint256 comptrollersLength = comptrollers.length;

        if ((comptrollersLength != assets.length) || (comptrollersLength != values.length)) {
            revert InvalidArguments();
        }

        for (uint256 i; i < comptrollersLength; ) {
            address[] memory poolAssets = assets[i];
            bool[] memory assetsValues = values[i];
            uint256 poolAssetsLength = poolAssets.length;

            if (poolAssetsLength != assetsValues.length) {
                revert InvalidArguments();
            }

            for (uint256 j; j < poolAssetsLength; ) {
                poolsAssetsDirectTransfer[comptrollers[i]][poolAssets[j]] = assetsValues[j];
                emit PoolAssetsDirectTransferUpdated(comptrollers[i], poolAssets[j], assetsValues[j]);
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    function _updateAssetsState(address comptroller, address asset)
        internal
        override
        returns (uint256 balanceDifference)
    {
        if (!ensureAssetListed(comptroller, asset)) revert MarketNotExistInPool(comptroller, asset);

        IERC20Upgradeable token = IERC20Upgradeable(asset);
        uint256 currentBalance = token.balanceOf(address(this));
        uint256 assetReserve = assetsReserves[asset];
        if (currentBalance > assetReserve) {
            unchecked {
                balanceDifference = currentBalance - assetReserve;
            }
            if (poolsAssetsDirectTransfer[comptroller][asset]) {
                uint256 previousDestinationBalance = token.balanceOf(destinationAddress);
                token.safeTransfer(destinationAddress, balanceDifference);
                uint256 newDestinationBalance = token.balanceOf(destinationAddress);

                emit AssetTransferredToDestination(destinationAddress, comptroller, asset, balanceDifference);
                IRiskFund(destinationAddress).updatePoolState(
                    comptroller,
                    asset,
                    newDestinationBalance - previousDestinationBalance
                );
                balanceDifference = 0;
            }
        }
    }

    function _postPrivateConversionHook(
        address comptroller,
        address tokenAddressIn,
        uint256 convertedTokenInBalance,
        address tokenAddressOut,
        uint256 convertedTokenOutBalance
    ) internal override {
        if (convertedTokenInBalance > 0) {
            emit AssetTransferredToDestination(
                destinationAddress,
                comptroller,
                tokenAddressIn,
                convertedTokenInBalance
            );
            IRiskFund(destinationAddress).updatePoolState(comptroller, tokenAddressIn, convertedTokenInBalance);
        }
        if (convertedTokenOutBalance > 0) {
            assetsReserves[tokenAddressOut] += convertedTokenOutBalance;
            poolsAssetsReserves[comptroller][tokenAddressOut] += convertedTokenOutBalance;
            emit AssetsReservesUpdated(comptroller, tokenAddressOut, convertedTokenOutBalance);
        }
    }

    function isAssetListedInCore(address tokenAddress) internal view returns (bool isAssetListed) {
        address[] memory coreMarkets = IComptroller(CORE_POOL_COMPTROLLER).getAllMarkets();

        uint256 coreMarketsLength = coreMarkets.length;
        for (uint256 i; i < coreMarketsLength; ) {
            isAssetListed = (VBNB == coreMarkets[i])
                ? (tokenAddress == NATIVE_WRAPPED)
                : (IVToken(coreMarkets[i]).underlying() == tokenAddress);

            if (isAssetListed) {
                break;
            }

            unchecked {
                ++i;
            }
        }
    }

    function ensureAssetListed(address comptroller, address asset) internal view returns (bool isListed) {
        if (comptroller == CORE_POOL_COMPTROLLER) {
            isListed = isAssetListedInCore(asset);
        } else {
            isListed = IPoolRegistry(poolRegistry).getVTokenForAsset(comptroller, asset) != address(0);
        }
    }

    function _getDestinationBaseAsset() internal view override returns (address destinationBaseAsset) {
        destinationBaseAsset = IRiskFundGetters(destinationAddress).convertibleBaseAsset();
    }
}
