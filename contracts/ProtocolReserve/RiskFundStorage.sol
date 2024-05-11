4444444pragma solidity 0.8.25;

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract ReserveHelpersStorage is Ownable2StepUpgradeable {
    bytes32 private __deprecatedSlot1;

    mapping(address => mapping(address => uint256)) public poolAssetsFunds;

    bytes32 private __deprecatedSlot2;
    bytes32 private __deprecatedSlot3;

    uint256[46] private __gap;
}

contract MaxLoopsLimitHelpersStorage {
    uint256 public maxLoopsLimit;

    uint256[49] private __gap;
}

contract RiskFundV1Storage is ReserveHelpersStorage, MaxLoopsLimitHelpersStorage {
    address public convertibleBaseAsset;
    address public shortfall;

    address private pancakeSwapRouter;
    uint256 private minAmountToConvert;
}

contract RiskFundV2Storage is RiskFundV1Storage, ReentrancyGuardUpgradeable {
    address public riskFundConverter;
}
