// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RoleManager
 * @notice Centralized role management for the entire marketplace system
 * @dev Designed for easy expansion of roles and permissions
 */
contract RoleManager is AccessControl {
    // Core roles
    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    // Feature-specific roles (easily expandable)
    bytes32 public constant AUCTION_MANAGER_ROLE = keccak256("AUCTION_MANAGER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant COLLECTION_MANAGER_ROLE = keccak256("COLLECTION_MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Future expansion roles (add as needed)
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    // Events for role management
    event RoleManagerInitialized(address indexed superAdmin);
    event BulkRolesGranted(address indexed account, bytes32[] roles);
    event BulkRolesRevoked(address indexed account, bytes32[] roles);
    event RoleHierarchyUpdated(bytes32 indexed parentRole, bytes32 indexed childRole);

    // Role hierarchy mapping (parent role → child roles)
    mapping(bytes32 => bytes32[]) public roleHierarchy;

    // Quick role checks
    mapping(address => mapping(bytes32 => bool)) public hasRoleCache;

    constructor(address superAdmin) {
        require(superAdmin != address(0), "RoleManager: Super admin cannot be zero address");

        // Grant super admin role
        _grantRole(DEFAULT_ADMIN_ROLE, superAdmin);
        _grantRole(SUPER_ADMIN_ROLE, superAdmin);

        // Set up role hierarchy
        _setupRoleHierarchy();

        emit RoleManagerInitialized(superAdmin);
    }

    /**
     * @notice Grant multiple roles to an account at once
     * @param account Address to grant roles to
     * @param roles Array of role identifiers
     */
    function grantRoles(address account, bytes32[] calldata roles) external onlyRole(SUPER_ADMIN_ROLE) {
        for (uint256 i = 0; i < roles.length; i++) {
            _grantRole(roles[i], account);
            hasRoleCache[account][roles[i]] = true;
        }
        emit BulkRolesGranted(account, roles);
    }

    /**
     * @notice Revoke multiple roles from an account at once
     * @param account Address to revoke roles from
     * @param roles Array of role identifiers
     */
    function revokeRoles(address account, bytes32[] calldata roles) external onlyRole(SUPER_ADMIN_ROLE) {
        for (uint256 i = 0; i < roles.length; i++) {
            _revokeRole(roles[i], account);
            hasRoleCache[account][roles[i]] = false;
        }
        emit BulkRolesRevoked(account, roles);
    }

    /**
     * @notice Add a new role to the system (for future expansion)
     * @param newRole New role identifier
     * @param adminRole Role that can manage this new role
     */
    function addNewRole(bytes32 newRole, bytes32 adminRole) external onlyRole(SUPER_ADMIN_ROLE) {
        _setRoleAdmin(newRole, adminRole);
        emit RoleHierarchyUpdated(adminRole, newRole);
    }

    /**
     * @notice Check if an account has any of the specified roles
     * @param account Address to check
     * @param roles Array of roles to check against
     * @return hasAnyRole True if account has at least one of the roles
     */
    function hasAnyRole(address account, bytes32[] calldata roles) external view returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (hasRole(roles[i], account)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Check if an account has all specified roles
     * @param account Address to check
     * @param roles Array of roles to check against
     * @return hasAllRoles True if account has all roles
     */
    function hasAllRoles(address account, bytes32[] calldata roles) external view returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (!hasRole(roles[i], account)) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Get all roles for an account
     * @param account Address to get roles for
     * @return activeRoles Array of active role identifiers
     */
    function getAccountRoles(address account) external view returns (bytes32[] memory activeRoles) {
        bytes32[] memory allRoles = _getAllRoles();
        uint256 activeCount = 0;

        // Count active roles
        for (uint256 i = 0; i < allRoles.length; i++) {
            if (hasRole(allRoles[i], account)) {
                activeCount++;
            }
        }

        // Build active roles array
        activeRoles = new bytes32[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allRoles.length; i++) {
            if (hasRole(allRoles[i], account)) {
                activeRoles[index] = allRoles[i];
                index++;
            }
        }

        return activeRoles;
    }

    /**
     * @notice Setup initial role hierarchy
     * @dev Internal function to establish role relationships
     */
    function _setupRoleHierarchy() internal {
        // SUPER_ADMIN can manage everything
        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MODERATOR_ROLE, ADMIN_ROLE);

        // Feature-specific role admins
        _setRoleAdmin(AUCTION_MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(FEE_MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(COLLECTION_MANAGER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(EMERGENCY_ROLE, SUPER_ADMIN_ROLE);

        // Future roles
        _setRoleAdmin(GOVERNANCE_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(DAO_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(VALIDATOR_ROLE, ADMIN_ROLE);
    }

    /**
     * @notice Get all defined roles in the system
     * @return roles Array of all role identifiers
     */
    function _getAllRoles() internal pure returns (bytes32[] memory roles) {
        roles = new bytes32[](11);
        roles[0] = SUPER_ADMIN_ROLE;
        roles[1] = ADMIN_ROLE;
        roles[2] = OPERATOR_ROLE;
        roles[3] = MODERATOR_ROLE;
        roles[4] = AUCTION_MANAGER_ROLE;
        roles[5] = FEE_MANAGER_ROLE;
        roles[6] = COLLECTION_MANAGER_ROLE;
        roles[7] = EMERGENCY_ROLE;
        roles[8] = GOVERNANCE_ROLE;
        roles[9] = DAO_ROLE;
        roles[10] = VALIDATOR_ROLE;
        return roles;
    }

    /**
     * @notice Override to update cache when roles are granted
     */
    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        bool result = super._grantRole(role, account);
        hasRoleCache[account][role] = true;
        return result;
    }

    /**
     * @notice Override to update cache when roles are revoked
     */
    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        bool result = super._revokeRole(role, account);
        hasRoleCache[account][role] = false;
        return result;
    }
}
