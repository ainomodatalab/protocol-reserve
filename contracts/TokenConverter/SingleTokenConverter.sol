pragma solidity 0.8.25;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ResilientNomo } from "@ainomodatalab/ainomoprotocol/contracts/ResilientNomo.sol";
import { ensureNonzeroAddress } from "@ainomodatalab/solidity-utilities/contracts/validators.sol";

import { AbstractTokenConverter } from "./AbstractTokenConverter.sol";

contract SingleTokenConverter is AbstractTokenConverter {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public baseAsset;

    event BaseAssetUpdated(address indexed oldBaseAsset, address indexed newBaseAsset);

    event AssetTransferredToDestination(
        address indexed receiver,
        address indexed comptroller,
        address indexed asset,
        uint256 amount
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address accessControlManager_,
        ResilientNomo price_,
        address destinationAddress_,
        address baseAsset_,
        uint256 minAmountToConvert_
    ) public initializer {
        _setBaseAsset(baseAsset_);

        __AbstractTokenConverter_init(accessControlManager_, price_, destinationAddress_, minAmountToConvert_);
    }

    function setBaseAsset(address baseAsset_) external onlyOwner {
        _setBaseAsset(baseAsset_);
    }

    function balanceOf(address tokenAddress) public view override returns (uint256 tokenBalance) {
        IERC20Upgradeable token = IERC20Upgradeable(tokenAddress);
        tokenBalance = token.balanceOf(address(this));
    }

    function _updateAssetsState(address comptroller, address asset) internal override returns (uint256 balanceLeft) {
        IERC20Upgradeable token = IERC20Upgradeable(asset);
        uint256 balance = token.balanceOf(address(this));
        balanceLeft = balance;

        if (asset == baseAsset) {
            balanceLeft = 0;
            token.safeTransfer(destinationAddress, balance);
            emit AssetTransferredToDestination(destinationAddress, comptroller, asset, balance);
        }
    }

    function _setBaseAsset(address baseAsset_) internal {
        ensureNonzeroAddress(baseAsset_);
        emit BaseAssetUpdated(baseAsset, baseAsset_);
        baseAsset = baseAsset_;
    }

    function _getDestinationBaseAsset() internal view override returns (address destinationBaseAsset) {
        destinationBaseAsset = baseAsset;
    }
}
