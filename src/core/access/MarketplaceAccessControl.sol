// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "src/errors/MarketplaceAccessControlErrors.sol";
import "src/events/MarketplaceAccessControlEvents.sol";

/**
 * @title MarketplaceAccessControl
 * @notice Manages role-based access control for the marketplace ecosystem
 * @dev Extends OpenZeppelin's AccessControl with marketplace-specific roles and functions
 * @author NFT Marketplace Team
 */
contract MarketplaceAccessControl is AccessControl, Ownable, ReentrancyGuard {
    // ============================================================================
    // ROLES
    // ============================================================================

    /// @notice Admin role - can manage all other roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Moderator role - can perform emergency actions and moderate content
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    /// @notice Operator role - can update fees and manage operational parameters
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Verifier role - can verify collections and manage verification status
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    /// @notice Emergency role - can perform emergency functions during incidents
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /// @notice Pauser role - can pause/unpause contracts
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ============================================================================
    // STATE VARIABLES
    // ============================================================================

    /// @notice Mapping to track if a role is currently active
    mapping(bytes32 => bool) public activeRoles;

    /// @notice Maximum number of addresses that can have a role simultaneously
    mapping(bytes32 => uint256) public maxRoleMembers;

    /// @notice Current number of members for each role
    mapping(bytes32 => uint256) public currentRoleMembers;

    // ============================================================================
    // MODIFIERS
    // ============================================================================

    /**
     * @notice Ensures role is active
     */
    modifier onlyActiveRole(bytes32 role) {
        if (!activeRoles[role]) {
            revert MarketplaceAccessControl__RoleNotActive();
        }
        _;
    }

    /**
     * @notice Ensures caller has specific role and role is active
     */
    modifier onlyActiveRoleHolder(bytes32 role) {
        if (!activeRoles[role]) {
            revert MarketplaceAccessControl__RoleNotActive();
        }
        if (!hasRole(role, msg.sender)) {
            revert MarketplaceAccessControl__InsufficientPermissions();
        }
        _;
    }

    /**
     * @notice Ensures role member limit is not exceeded
     */
    modifier withinRoleLimit(bytes32 role) {
        if (currentRoleMembers[role] >= maxRoleMembers[role]) {
            revert MarketplaceAccessControl__RoleMemberLimitExceeded();
        }
        _;
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    /**
     * @notice Initializes the access control system
     */
    constructor() Ownable(msg.sender) {
        // Grant admin role to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        // Initialize role settings
        _initializeRoles();
    }

    // ============================================================================
    // ROLE MANAGEMENT FUNCTIONS
    // ============================================================================

    /**
     * @notice Grants a role to an account
     * @param role Role to grant
     * @param account Account to grant role to
     */
    function grantRoleSimple(bytes32 role, address account)
        external
        onlyRole(ADMIN_ROLE)
        onlyActiveRole(role)
        withinRoleLimit(role)
        nonReentrant
    {
        if (account == address(0)) {
            revert MarketplaceAccessControl__ZeroAddress();
        }

        if (hasRole(role, account)) {
            revert MarketplaceAccessControl__RoleAlreadyGranted();
        }

        _grantRole(role, account);
        currentRoleMembers[role]++;

        emit RoleGrantedSimple(role, account, msg.sender, block.timestamp);
    }

    /**
     * @notice Revokes a role from an account
     * @param role Role to revoke
     * @param account Account to revoke role from
     */
    function revokeRoleSimple(bytes32 role, address account) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (!hasRole(role, account)) {
            revert MarketplaceAccessControl__RoleNotGranted();
        }

        _revokeRole(role, account);
        if (currentRoleMembers[role] > 0) {
            currentRoleMembers[role]--;
        }

        emit RoleRevokedSimple(role, account, msg.sender, block.timestamp);
    }

    /**
     * @notice Activates or deactivates a role
     * @param role Role to activate/deactivate
     * @param isActive Whether to activate or deactivate
     */
    function setRoleActive(bytes32 role, bool isActive) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (!isActive && (role == DEFAULT_ADMIN_ROLE || role == ADMIN_ROLE)) {
            revert MarketplaceAccessControl__CannotDeactivateAdminRole();
        }

        bool wasActive = activeRoles[role];
        activeRoles[role] = isActive;

        emit RoleStatusChanged(role, wasActive, isActive, msg.sender, block.timestamp);
    }

    /**
     * @notice Sets maximum number of members for a role
     * @param role Role to set limit for
     * @param maxMembers Maximum number of members
     */
    function setRoleMemberLimit(bytes32 role, uint256 maxMembers) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (maxMembers == 0) {
            revert MarketplaceAccessControl__InvalidMemberLimit();
        }

        if (maxMembers < currentRoleMembers[role]) {
            revert MarketplaceAccessControl__MemberLimitBelowCurrent();
        }

        uint256 oldLimit = maxRoleMembers[role];
        maxRoleMembers[role] = maxMembers;

        emit RoleMemberLimitUpdated(role, oldLimit, maxMembers, msg.sender);
    }

    /**
     * @notice Checks if an account has specific permission
     * @param account Account to check
     * @param permission Permission to check
     * @return hasPermission Whether account has the permission
     */
    function hasPermission(address account, string calldata permission) external view returns (bool) {
        // Check admin roles first
        if (hasRole(ADMIN_ROLE, account) || hasRole(DEFAULT_ADMIN_ROLE, account)) {
            return true;
        }

        // Check specific permissions based on roles
        bytes32 permissionHash = keccak256(abi.encodePacked(permission));

        if (permissionHash == keccak256("EMERGENCY_ACTION")) {
            return hasRole(EMERGENCY_ROLE, account) || hasRole(MODERATOR_ROLE, account);
        } else if (permissionHash == keccak256("UPDATE_FEES")) {
            return hasRole(OPERATOR_ROLE, account);
        } else if (permissionHash == keccak256("VERIFY_COLLECTIONS")) {
            return hasRole(VERIFIER_ROLE, account);
        } else if (permissionHash == keccak256("PAUSE_CONTRACTS")) {
            return hasRole(PAUSER_ROLE, account);
        } else if (permissionHash == keccak256("MODERATE_CONTENT")) {
            return hasRole(MODERATOR_ROLE, account);
        }

        return false;
    }

    // ============================================================================
    // VIEW FUNCTIONS
    // ============================================================================

    /**
     * @notice Gets all active roles for an account
     * @param account Account to check
     * @return activeUserRoles Array of active roles
     */
    function getActiveRoles(address account) external view returns (bytes32[] memory activeUserRoles) {
        bytes32[] memory allRoles = new bytes32[](6);
        allRoles[0] = ADMIN_ROLE;
        allRoles[1] = MODERATOR_ROLE;
        allRoles[2] = OPERATOR_ROLE;
        allRoles[3] = VERIFIER_ROLE;
        allRoles[4] = EMERGENCY_ROLE;
        allRoles[5] = PAUSER_ROLE;

        uint256 activeCount = 0;
        for (uint256 i = 0; i < allRoles.length; i++) {
            if (hasRole(allRoles[i], account)) {
                activeCount++;
            }
        }

        activeUserRoles = new bytes32[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allRoles.length; i++) {
            if (hasRole(allRoles[i], account)) {
                activeUserRoles[index] = allRoles[i];
                index++;
            }
        }

        return activeUserRoles;
    }

    /**
     * @notice Gets role member count and limit
     * @param role Role to check
     * @return current Current number of members
     * @return maximum Maximum allowed members
     */
    function getRoleMemberInfo(bytes32 role) external view returns (uint256 current, uint256 maximum) {
        return (currentRoleMembers[role], maxRoleMembers[role]);
    }

    // ============================================================================
    // INTERNAL FUNCTIONS
    // ============================================================================

    /**
     * @notice Initializes default role settings
     */
    function _initializeRoles() internal {
        // Set all roles as active by default
        activeRoles[DEFAULT_ADMIN_ROLE] = true;
        activeRoles[ADMIN_ROLE] = true;
        activeRoles[MODERATOR_ROLE] = true;
        activeRoles[OPERATOR_ROLE] = true;
        activeRoles[VERIFIER_ROLE] = true;
        activeRoles[EMERGENCY_ROLE] = true;
        activeRoles[PAUSER_ROLE] = true;

        // Set default member limits
        maxRoleMembers[DEFAULT_ADMIN_ROLE] = 3;
        maxRoleMembers[ADMIN_ROLE] = 5;
        maxRoleMembers[MODERATOR_ROLE] = 10;
        maxRoleMembers[OPERATOR_ROLE] = 15;
        maxRoleMembers[VERIFIER_ROLE] = 20;
        maxRoleMembers[EMERGENCY_ROLE] = 3;
        maxRoleMembers[PAUSER_ROLE] = 5;

        // Initialize current member counts
        currentRoleMembers[DEFAULT_ADMIN_ROLE] = 1;
        currentRoleMembers[ADMIN_ROLE] = 1;
    }
}
