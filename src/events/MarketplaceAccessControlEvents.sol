// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title MarketplaceAccessControlEvents
 * @notice Events for MarketplaceAccessControl contract
 * @dev Comprehensive events for role management and access control
 */

// ============================================================================
// ROLE MANAGEMENT EVENTS
// ============================================================================

/**
 * @notice Emitted when a role is granted with reason
 * @param role Role that was granted
 * @param account Account that received the role
 * @param sender Account that granted the role
 * @param reason Reason for granting the role
 * @param timestamp When the role was granted
 */
event RoleGrantedWithReason(
    bytes32 indexed role, address indexed account, address indexed sender, string reason, uint256 timestamp
);

/**
 * @notice Emitted when a role is revoked with reason
 * @param role Role that was revoked
 * @param account Account that lost the role
 * @param sender Account that revoked the role
 * @param reason Reason for revoking the role
 * @param timestamp When the role was revoked
 */
event RoleRevokedWithReason(
    bytes32 indexed role, address indexed account, address indexed sender, string reason, uint256 timestamp
);

/**
 * @notice Emitted when a role is granted (simple version)
 */
event RoleGrantedSimple(bytes32 indexed role, address indexed account, address indexed sender, uint256 timestamp);

/**
 * @notice Emitted when a role is revoked (simple version)
 */
event RoleRevokedSimple(bytes32 indexed role, address indexed account, address indexed sender, uint256 timestamp);

/**
 * @notice Emitted when a role's active status changes
 * @param role Role whose status changed
 * @param wasActive Previous active status
 * @param isActive New active status
 * @param changedBy Account that changed the status
 * @param timestamp When the status was changed
 */
event RoleStatusChanged(
    bytes32 indexed role, bool wasActive, bool isActive, address indexed changedBy, uint256 timestamp
);

/**
 * @notice Emitted when role member limit is updated
 * @param role Role whose limit was updated
 * @param oldLimit Previous member limit
 * @param newLimit New member limit
 * @param updatedBy Account that updated the limit
 */
event RoleMemberLimitUpdated(bytes32 indexed role, uint256 oldLimit, uint256 newLimit, address indexed updatedBy);

// ============================================================================
// PERMISSION EVENTS
// ============================================================================

/**
 * @notice Emitted when role permissions are updated
 * @param role Role whose permissions were updated
 * @param oldPermissions Previous permissions
 * @param newPermissions New permissions
 * @param updatedBy Account that updated the permissions
 */
event RolePermissionsUpdated(
    bytes32 indexed role, RolePermissions oldPermissions, RolePermissions newPermissions, address indexed updatedBy
);

/**
 * @notice Emitted when permission check is performed
 * @param account Account being checked
 * @param permission Permission being checked
 * @param hasPermission Whether account has the permission
 * @param checkedBy Account that performed the check
 * @param timestamp When the check was performed
 */
event PermissionChecked(
    address indexed account, string permission, bool hasPermission, address indexed checkedBy, uint256 timestamp
);

// ============================================================================
// BATCH OPERATION EVENTS
// ============================================================================

/**
 * @notice Emitted when batch role operation is completed
 * @param operationType Type of operation (GRANT/REVOKE)
 * @param count Number of operations performed
 * @param performedBy Account that performed the batch operation
 * @param timestamp When the operation was completed
 */
event BatchRoleOperationCompleted(string operationType, uint256 count, address indexed performedBy, uint256 timestamp);

/**
 * @notice Emitted when batch operation partially fails
 * @param operationType Type of operation
 * @param totalCount Total number of operations attempted
 * @param successCount Number of successful operations
 * @param failureCount Number of failed operations
 * @param performedBy Account that performed the operation
 */
event BatchOperationPartialFailure(
    string operationType, uint256 totalCount, uint256 successCount, uint256 failureCount, address indexed performedBy
);

// ============================================================================
// EMERGENCY EVENTS
// ============================================================================

/**
 * @notice Emitted when emergency role action is performed
 * @param role Role used for emergency action
 * @param account Account that performed the action
 * @param action Description of the emergency action
 * @param target Target of the emergency action
 * @param timestamp When the action was performed
 */
event EmergencyRoleActionPerformed(
    bytes32 indexed role, address indexed account, string action, address indexed target, uint256 timestamp
);

/**
 * @notice Emitted when emergency access is granted temporarily
 * @param account Account receiving emergency access
 * @param role Role granted for emergency
 * @param duration Duration of emergency access
 * @param grantedBy Account that granted emergency access
 * @param reason Reason for emergency access
 */
event EmergencyAccessGranted(
    address indexed account, bytes32 indexed role, uint256 duration, address indexed grantedBy, string reason
);

/**
 * @notice Emitted when emergency access expires or is revoked
 * @param account Account losing emergency access
 * @param role Role that was revoked
 * @param revokedBy Account that revoked access (or zero for expiration)
 * @param reason Reason for revocation
 */
event EmergencyAccessRevoked(address indexed account, bytes32 indexed role, address indexed revokedBy, string reason);

// ============================================================================
// AUDIT EVENTS
// ============================================================================

/**
 * @notice Emitted when role assignment history is queried
 * @param role Role being queried
 * @param account Account being queried
 * @param queriedBy Account that performed the query
 * @param timestamp When the query was performed
 */
event RoleHistoryQueried(bytes32 indexed role, address indexed account, address indexed queriedBy, uint256 timestamp);

/**
 * @notice Emitted when access control audit is performed
 * @param auditType Type of audit performed
 * @param scope Scope of the audit
 * @param performedBy Account that performed the audit
 * @param findings Summary of audit findings
 * @param timestamp When the audit was performed
 */
event AccessControlAuditPerformed(
    string auditType, string scope, address indexed performedBy, string findings, uint256 timestamp
);

// ============================================================================
// CONFIGURATION EVENTS
// ============================================================================

/**
 * @notice Emitted when access control configuration is updated
 * @param parameter Parameter that was updated
 * @param oldValue Previous value (encoded)
 * @param newValue New value (encoded)
 * @param updatedBy Account that made the update
 * @param timestamp When the update was made
 */
event AccessControlConfigUpdated(
    string parameter, bytes oldValue, bytes newValue, address indexed updatedBy, uint256 timestamp
);

/**
 * @notice Emitted when role hierarchy is modified
 * @param parentRole Parent role in hierarchy
 * @param childRole Child role in hierarchy
 * @param isAdded Whether relationship was added or removed
 * @param modifiedBy Account that modified the hierarchy
 */
event RoleHierarchyModified(
    bytes32 indexed parentRole, bytes32 indexed childRole, bool isAdded, address indexed modifiedBy
);

// ============================================================================
// DELEGATION EVENTS
// ============================================================================

/**
 * @notice Emitted when role is delegated
 * @param role Role being delegated
 * @param delegator Account delegating the role
 * @param delegate Account receiving the delegation
 * @param duration Duration of delegation
 * @param permissions Specific permissions delegated
 */
event RoleDelegated(
    bytes32 indexed role, address indexed delegator, address indexed delegate, uint256 duration, string permissions
);

/**
 * @notice Emitted when role delegation is revoked
 * @param role Role delegation being revoked
 * @param delegator Original delegator
 * @param delegate Account losing delegation
 * @param revokedBy Account that revoked delegation
 * @param reason Reason for revocation
 */
event RoleDelegationRevoked(
    bytes32 indexed role, address indexed delegator, address indexed delegate, address revokedBy, string reason
);

// ============================================================================
// SUSPENSION EVENTS
// ============================================================================

/**
 * @notice Emitted when role is suspended
 * @param role Role being suspended
 * @param account Account whose role is suspended
 * @param duration Duration of suspension
 * @param suspendedBy Account that suspended the role
 * @param reason Reason for suspension
 */
event RoleSuspended(
    bytes32 indexed role, address indexed account, uint256 duration, address indexed suspendedBy, string reason
);

/**
 * @notice Emitted when role suspension is lifted
 * @param role Role suspension being lifted
 * @param account Account whose suspension is lifted
 * @param liftedBy Account that lifted the suspension
 * @param reason Reason for lifting suspension
 */
event RoleSuspensionLifted(bytes32 indexed role, address indexed account, address indexed liftedBy, string reason);

// ============================================================================
// STRUCT DEFINITIONS FOR EVENTS
// ============================================================================

/**
 * @notice Structure for role permissions (used in events)
 */
struct RolePermissions {
    bool canManageRoles;
    bool canEmergencyAction;
    bool canUpdateFees;
    bool canVerifyCollections;
    bool canPauseContracts;
    bool canModerateContent;
    bool canAccessAnalytics;
    uint256 maxActions;
    uint256 cooldownPeriod;
}
