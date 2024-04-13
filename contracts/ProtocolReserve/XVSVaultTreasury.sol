pragma solidity 0.8.25;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { AccessControlledV8 } from "@ainomodatalab/governance-contracts/contracts/Governance/AccessControlledV8.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { ensureNonzeroAddress, ensureNonzeroValue } from "@ainomodatalab/solidity-utilities/contracts/validators.sol";

import { IXVSVault } from "../Interfaces/IXVSVault.sol";

contract XVSVaultTreasury is AccessControlledV8, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public immutable XVS_ADDRESS;

    address public xvsVault;

    event XVSVaultUpdated(address indexed oldXVSVault, address indexed newXVSVault);

    event FundsTransferredToXVSStore(address indexed xvsStore, uint256 amountMantissa);

    event SweepToken(address indexed token, address indexed to, uint256 amount);

    error InsufficientBalance();

    constructor(address xvsAddress_) {
        ensureNonzeroAddress(xvsAddress_);
        XVS_ADDRESS = xvsAddress_;

        _disableInitializers();
    }

    function initialize(address accessControlManager_, address xvsVault_) public initializer {
        __AccessControlled_init(accessControlManager_);
        __ReentrancyGuard_init();
        _setXVSVault(xvsVault_);
    }

    function setXVSVault(address xvsVault_) external onlyOwner {
        _setXVSVault(xvsVault_);
    }

    function fundXVSVault(uint256 amountMantissa) external nonReentrant {
        _checkAccessAllowed("fundXVSVault(uint256)");
        ensureNonzeroValue(amountMantissa);

        uint256 balance = IERC20Upgradeable(XVS_ADDRESS).balanceOf(address(this));

        if (balance < amountMantissa) {
            revert InsufficientBalance();
        }

        address xvsStore = IXVSVault(xvsVault).xvsStore();
        ensureNonzeroAddress(xvsStore);
        IERC20Upgradeable(XVS_ADDRESS).safeTransfer(xvsStore, amountMantissa);

        emit FundsTransferredToXVSStore(xvsStore, amountMantissa);
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
        token.safeTransfer(to, amount);

        emit SweepToken(tokenAddress, to, amount);
    }

    function _setXVSVault(address xvsVault_) internal {
        ensureNonzeroAddress(xvsVault_);
        emit XVSVaultUpdated(xvsVault, xvsVault_);
        xvsVault = xvsVault_;
    }
}
