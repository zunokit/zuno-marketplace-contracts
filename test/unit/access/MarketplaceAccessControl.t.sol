// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {MarketplaceAccessControl} from "src/core/access/MarketplaceAccessControl.sol";
import "src/errors/MarketplaceAccessControlErrors.sol";
import "src/events/MarketplaceAccessControlEvents.sol";

/**
 * @title MarketplaceAccessControlTest
 * @notice Basic unit tests for simplified MarketplaceAccessControl contract
 */
contract MarketplaceAccessControlTest is Test {
    MarketplaceAccessControl public accessControl;

    address public admin;
    address public user1;
    address public user2;

    // Role constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    function setUp() public {
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy contract
        vm.prank(admin);
        accessControl = new MarketplaceAccessControl();
    }

    function test_Constructor_Success() public view {
        assertTrue(accessControl.hasRole(accessControl.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(accessControl.hasRole(ADMIN_ROLE, admin));
        assertTrue(accessControl.activeRoles(ADMIN_ROLE));
    }

    function test_GrantRoleSimple_Success() public {
        vm.prank(admin);
        accessControl.grantRoleSimple(MODERATOR_ROLE, user1);

        assertTrue(accessControl.hasRole(MODERATOR_ROLE, user1));
        (uint256 current, uint256 maximum) = accessControl.getRoleMemberInfo(MODERATOR_ROLE);
        assertEq(current, 1);
        assertEq(maximum, 10);
    }

    function test_RevokeRoleSimple_Success() public {
        vm.prank(admin);
        accessControl.grantRoleSimple(MODERATOR_ROLE, user1);

        vm.prank(admin);
        accessControl.revokeRoleSimple(MODERATOR_ROLE, user1);

        assertFalse(accessControl.hasRole(MODERATOR_ROLE, user1));
        (uint256 current,) = accessControl.getRoleMemberInfo(MODERATOR_ROLE);
        assertEq(current, 0);
    }

    function test_GrantRoleSimple_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(MarketplaceAccessControl__ZeroAddress.selector);
        accessControl.grantRoleSimple(MODERATOR_ROLE, address(0));
    }

    function test_SetRoleActive() public {
        vm.prank(admin);
        accessControl.setRoleActive(MODERATOR_ROLE, false);

        assertFalse(accessControl.activeRoles(MODERATOR_ROLE));
    }

    function test_HasPermission_Success() public view {
        assertTrue(accessControl.hasPermission(admin, "EMERGENCY_ACTION"));
        assertTrue(accessControl.hasPermission(admin, "UPDATE_FEES"));
    }

    function test_GetActiveRoles() public {
        vm.prank(admin);
        accessControl.grantRoleSimple(MODERATOR_ROLE, user1);

        bytes32[] memory roles = accessControl.getActiveRoles(user1);
        assertEq(roles.length, 1);
        assertEq(roles[0], MODERATOR_ROLE);
    }

    function test_GetActiveRoles_NoRoles() public view {
        bytes32[] memory roles = accessControl.getActiveRoles(user1);
        assertEq(roles.length, 0);
    }

    function test_HasPermission_NoRole() public view {
        assertFalse(accessControl.hasPermission(user1, "EMERGENCY_ACTION"));
    }
}
