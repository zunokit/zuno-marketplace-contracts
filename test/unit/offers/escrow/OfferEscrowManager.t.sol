// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/core/offers/escrow/OfferEscrowManager.sol";
import "test/mocks/MockERC20.sol";

/**
 * @title OfferEscrowManagerTest
 * @notice Comprehensive tests for OfferEscrowManager
 */
contract OfferEscrowManagerTest is Test {
    OfferEscrowManager public escrowManager;
    MockERC20 public paymentToken;

    address public owner = address(0x1);
    address public authorizedCaller = address(0x2);
    address public offerer = address(0x3);
    address public recipient = address(0x4);
    address public unauthorized = address(0x5);

    bytes32 public constant OFFER_ID = keccak256("offer1");

    function setUp() public {
        vm.prank(owner);
        escrowManager = new OfferEscrowManager();

        paymentToken = new MockERC20("Payment Token", "PAY", 18);

        // Authorize caller
        vm.prank(owner);
        escrowManager.authorizeCaller(authorizedCaller);

        // Setup balances
        vm.deal(offerer, 100 ether);
        vm.deal(authorizedCaller, 100 ether);
        vm.deal(unauthorized, 100 ether);
        paymentToken.mint(offerer, 1000 ether);
    }

    // ============================================================================
    // AUTHORIZATION TESTS
    // ============================================================================

    function testAuthorizeCaller_Success() public {
        vm.prank(owner);
        escrowManager.authorizeCaller(unauthorized);

        assertTrue(escrowManager.authorizedCallers(unauthorized));
    }

    function testAuthorizeCaller_RevertNotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        escrowManager.authorizeCaller(unauthorized);
    }

    function testRevokeCaller_Success() public {
        vm.prank(owner);
        escrowManager.revokeCaller(authorizedCaller);

        assertFalse(escrowManager.authorizedCallers(authorizedCaller));
    }

    // ============================================================================
    // ETH ESCROW TESTS
    // ============================================================================

    function testLockETH_Success() public {
        uint256 amount = 1 ether;

        vm.prank(authorizedCaller);
        escrowManager.lockETH{value: amount}(OFFER_ID, offerer);

        assertEq(escrowManager.getEscrowedETH(OFFER_ID), amount);
        assertEq(escrowManager.getOfferOwner(OFFER_ID), offerer);
    }

    function testLockETH_RevertUnauthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert(OfferEscrowManager.Escrow__Unauthorized.selector);
        escrowManager.lockETH{value: 1 ether}(OFFER_ID, offerer);
    }

    function testLockETH_RevertZeroAmount() public {
        vm.prank(authorizedCaller);
        vm.expectRevert(OfferEscrowManager.Escrow__InvalidAmount.selector);
        escrowManager.lockETH{value: 0}(OFFER_ID, offerer);
    }

    function testReleaseETH_Success() public {
        // Lock first
        uint256 amount = 1 ether;
        vm.prank(authorizedCaller);
        escrowManager.lockETH{value: amount}(OFFER_ID, offerer);

        uint256 recipientBalanceBefore = recipient.balance;

        // Release
        vm.prank(authorizedCaller);
        escrowManager.releaseETH(OFFER_ID, recipient, amount);

        assertEq(escrowManager.getEscrowedETH(OFFER_ID), 0);
        assertEq(recipient.balance, recipientBalanceBefore + amount);
    }

    function testReleaseETH_RevertInsufficientBalance() public {
        vm.prank(authorizedCaller);
        vm.expectRevert(OfferEscrowManager.Escrow__InsufficientBalance.selector);
        escrowManager.releaseETH(OFFER_ID, recipient, 1 ether);
    }

    function testRefundETH_Success() public {
        // Lock first
        uint256 amount = 1 ether;
        vm.prank(authorizedCaller);
        escrowManager.lockETH{value: amount}(OFFER_ID, offerer);

        uint256 offererBalanceBefore = offerer.balance;

        // Refund
        vm.prank(authorizedCaller);
        escrowManager.refundETH(OFFER_ID, amount);

        assertEq(escrowManager.getEscrowedETH(OFFER_ID), 0);
        assertEq(offerer.balance, offererBalanceBefore + amount);
    }

    function testRefundETH_RevertInvalidOfferId() public {
        bytes32 invalidOfferId = keccak256("invalid");

        vm.prank(authorizedCaller);
        vm.expectRevert(OfferEscrowManager.Escrow__InvalidOfferId.selector);
        escrowManager.refundETH(invalidOfferId, 1 ether);
    }

    // ============================================================================
    // ERC20 ESCROW TESTS
    // ============================================================================

    function testLockERC20_Success() public {
        uint256 amount = 100 ether;

        // Approve escrow manager
        vm.prank(offerer);
        paymentToken.approve(address(escrowManager), amount);

        // Lock
        vm.prank(authorizedCaller);
        escrowManager.lockERC20(OFFER_ID, offerer, address(paymentToken), amount);

        assertEq(escrowManager.getEscrowedERC20(OFFER_ID, address(paymentToken)), amount);
        assertEq(paymentToken.balanceOf(address(escrowManager)), amount);
    }

    function testLockERC20_RevertUnauthorized() public {
        vm.prank(offerer);
        paymentToken.approve(address(escrowManager), 100 ether);

        vm.prank(unauthorized);
        vm.expectRevert(OfferEscrowManager.Escrow__Unauthorized.selector);
        escrowManager.lockERC20(OFFER_ID, offerer, address(paymentToken), 100 ether);
    }

    function testLockERC20_RevertZeroAmount() public {
        vm.prank(authorizedCaller);
        vm.expectRevert(OfferEscrowManager.Escrow__InvalidAmount.selector);
        escrowManager.lockERC20(OFFER_ID, offerer, address(paymentToken), 0);
    }

    function testReleaseERC20_Success() public {
        uint256 amount = 100 ether;

        // Lock first
        vm.prank(offerer);
        paymentToken.approve(address(escrowManager), amount);
        vm.prank(authorizedCaller);
        escrowManager.lockERC20(OFFER_ID, offerer, address(paymentToken), amount);

        // Release
        vm.prank(authorizedCaller);
        escrowManager.releaseERC20(OFFER_ID, recipient, address(paymentToken), amount);

        assertEq(escrowManager.getEscrowedERC20(OFFER_ID, address(paymentToken)), 0);
        assertEq(paymentToken.balanceOf(recipient), amount);
    }

    function testReleaseERC20_RevertInsufficientBalance() public {
        vm.prank(authorizedCaller);
        vm.expectRevert(OfferEscrowManager.Escrow__InsufficientBalance.selector);
        escrowManager.releaseERC20(OFFER_ID, recipient, address(paymentToken), 100 ether);
    }

    function testRefundERC20_Success() public {
        uint256 amount = 100 ether;

        // Lock first
        vm.prank(offerer);
        paymentToken.approve(address(escrowManager), amount);
        vm.prank(authorizedCaller);
        escrowManager.lockERC20(OFFER_ID, offerer, address(paymentToken), amount);

        uint256 offererBalanceBefore = paymentToken.balanceOf(offerer);

        // Refund
        vm.prank(authorizedCaller);
        escrowManager.refundERC20(OFFER_ID, address(paymentToken), amount);

        assertEq(escrowManager.getEscrowedERC20(OFFER_ID, address(paymentToken)), 0);
        assertEq(paymentToken.balanceOf(offerer), offererBalanceBefore + amount);
    }

    function testRefundERC20_RevertInvalidOfferId() public {
        bytes32 invalidOfferId = keccak256("invalid");

        vm.prank(authorizedCaller);
        vm.expectRevert(OfferEscrowManager.Escrow__InvalidOfferId.selector);
        escrowManager.refundERC20(invalidOfferId, address(paymentToken), 100 ether);
    }

    // ============================================================================
    // MULTIPLE OFFERS TESTS
    // ============================================================================

    function testMultipleOffers_ETH() public {
        bytes32 offer1 = keccak256("offer1");
        bytes32 offer2 = keccak256("offer2");

        vm.startPrank(authorizedCaller);
        escrowManager.lockETH{value: 1 ether}(offer1, offerer);
        escrowManager.lockETH{value: 2 ether}(offer2, offerer);
        vm.stopPrank();

        assertEq(escrowManager.getEscrowedETH(offer1), 1 ether);
        assertEq(escrowManager.getEscrowedETH(offer2), 2 ether);
    }

    function testMultipleOffers_ERC20() public {
        bytes32 offer1 = keccak256("offer1");
        bytes32 offer2 = keccak256("offer2");

        vm.prank(offerer);
        paymentToken.approve(address(escrowManager), 300 ether);

        vm.startPrank(authorizedCaller);
        escrowManager.lockERC20(offer1, offerer, address(paymentToken), 100 ether);
        escrowManager.lockERC20(offer2, offerer, address(paymentToken), 200 ether);
        vm.stopPrank();

        assertEq(escrowManager.getEscrowedERC20(offer1, address(paymentToken)), 100 ether);
        assertEq(escrowManager.getEscrowedERC20(offer2, address(paymentToken)), 200 ether);
    }
}
