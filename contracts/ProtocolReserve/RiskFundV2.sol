pragma solidity 0.8.25;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { AccessControlledV8 } from "@ainomodatalab/governance-contracts/contracts/Governance/AccessControlledV8.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ensureNonzeroAddress, ensureNonzeroValue } from "@ainomodatalab/solidity-utilities/contracts/validators.sol";

import { IRiskFund } from "../Interfaces/IRiskFund.sol";
import { IRiskFundConverter } from "../Interfaces/IRiskFundConverter.sol";
import { RiskFundV2Storage } from "./RiskFundStorage.sol";

contract RiskFundV2 is AccessControlledV8, RiskFundV2Storage, IRiskFund {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event ConvertibleBaseAssetUpdated(address indexed oldConvertibleBaseAsset, address indexed newConvertibleBaseAsset);

    event RiskFundConverterUpdated(address indexed oldRiskFundConverter, address indexed newRiskFundConverter);

    event ShortfallContractUpdated(address indexed oldShortfallContract, address indexed newShortfallContract);

    event TransferredReserveForAuction(address indexed comptroller, uint256 amount);

    event PoolAssetsIncreased(address indexed comptroller, address indexed asset, uint256 amount);

    event PoolAssetsDecreased(address indexed comptroller, address indexed asset, uint256 amount);

    event SweepToken(address indexed token, address indexed to, uint256 amount);

    event SweepTokenFromPool(address indexed token, address indexed comptroller, uint256 amount);

    error InvalidRiskFundConverter();

    error InvalidShortfallAddress();

    error InsufficientBalance();

    error InsufficientPoolReserve(address comptroller, uint256 amount, uint256 poolReserve);

    function setConvertibleBaseAsset(address convertibleBaseAsset_) external onlyOwner {
        ensureNonzeroAddress(convertibleBaseAsset_);
        emit ConvertibleBaseAssetUpdated(convertibleBaseAsset, convertibleBaseAsset_);
        convertibleBaseAsset = convertibleBaseAsset_;
    }

    function setRiskFundConverter(address riskFundConverter_) external onlyOwner {
        ensureNonzeroAddress(riskFundConverter_);
        emit RiskFundConverterUpdated(riskFundConverter, riskFundConverter_);
        riskFundConverter = riskFundConverter_;
    }

    function setShortfallContractAddress(address shortfallContractAddress_) external onlyOwner {
        ensureNonzeroAddress(shortfallContractAddress_);
        emit ShortfallContractUpdated(shortfall, shortfallContractAddress_);
        shortfall = shortfallContractAddress_;
    }

    function transferReserveForAuction(address comptroller, uint256 amount)
        external
        override
        nonReentrant
        returns (uint256)
    {
        uint256 poolReserve = poolAssetsFunds[comptroller][convertibleBaseAsset];

        if (msg.sender != shortfall) {
            revert InvalidShortfallAddress();
        }
        if (amount > poolReserve) {
            revert InsufficientPoolReserve(comptroller, amount, poolReserve);
        }

        unchecked {
            poolAssetsFunds[comptroller][convertibleBaseAsset] = poolReserve - amount;
        }

        IERC20Upgradeable(convertibleBaseAsset).safeTransfer(shortfall, amount);
        emit TransferredReserveForAuction(comptroller, amount);

        return amount;
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

    function sweepTokenFromPool(
        address tokenAddress,
        address comptroller,
        uint256 amount
    ) external onlyOwner nonReentrant {
        ensureNonzeroAddress(tokenAddress);
        ensureNonzeroAddress(comptroller);
        ensureNonzeroValue(amount);

        uint256 poolReserve = poolAssetsFunds[comptroller][tokenAddress];

        if (amount > poolReserve) {
            revert InsufficientPoolReserve(comptroller, amount, poolReserve);
        }

        unchecked {
            poolAssetsFunds[comptroller][tokenAddress] = poolReserve - amount;
        }

        IERC20Upgradeable(tokenAddress).safeTransfer(comptroller, amount);

        emit SweepTokenFromPool(tokenAddress, comptroller, amount);
    }

    function getPoolsBaseAssetReserves(address comptroller) external view returns (uint256) {
        return poolAssetsFunds[comptroller][convertibleBaseAsset];
    }

    function updatePoolState(
        address comptroller,
        address asset,
        uint256 amount
    ) public {
        if (msg.sender != riskFundConverter) {
            revert InvalidRiskFundConverter();
        }

        poolAssetsFunds[comptroller][asset] += amount;
        emit PoolAssetsIncreased(comptroller, asset, amount);
    }

    function preSweepToken(address tokenAddress, uint256 amount) internal {
        uint256 balance = IERC20Upgradeable(tokenAddress).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance();

        address[] memory pools = IRiskFundConverter(riskFundConverter).getPools(tokenAddress);

        uint256 assetReserves;
        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ) {
            assetReserves += poolAssetsFunds[pools[i]][tokenAddress];
            unchecked {
                ++i;
            }
        }

        uint256 balanceDiff = balance - assetReserves;

        if (balanceDiff < amount) {
            uint256 amountDiff;
            unchecked {
                amountDiff = amount - balanceDiff;
            }
            uint256 distributedShare;
            for (uint256 i; i < poolsLength; ) {
                if (poolAssetsFunds[pools[i]][tokenAddress] != 0) {
                    uint256 poolAmountShare;
                    if (i < (poolsLength - 1)) {
                        poolAmountShare = (poolAssetsFunds[pools[i]][tokenAddress] * amount) / assetReserves;
                        distributedShare += poolAmountShare;
                    } else {
                        poolAmountShare = amountDiff - distributedShare;
                    }
                    poolAssetsFunds[pools[i]][tokenAddress] -= poolAmountShare;
                    emit PoolAssetsDecreased(pools[i], tokenAddress, poolAmountShare);
                }
                unchecked {
                    ++i;
                }
            }
        }
    }
}
