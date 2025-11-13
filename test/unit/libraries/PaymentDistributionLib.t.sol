// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/libraries/PaymentDistributionLib.sol";

/**
 * @title PaymentDistributionLibTest
 * @notice Comprehensive test suite for PaymentDistributionLib library
 * @dev Tests all functions, edge cases, and error conditions to achieve >90% coverage
 */
contract PaymentDistributionLibTest is Test {
    using PaymentDistributionLib for PaymentDistributionLib.PaymentData;

    // Test addresses
    address public constant SELLER = address(0x1);
    address public constant BUYER = address(0x2);
    address public constant ROYALTY_RECEIVER = address(0x3);
    address public constant MARKETPLACE_WALLET = address(0x4);
    address public constant ZERO_ADDRESS = address(0);

    // Test constants
    uint256 public constant SALE_PRICE = 1 ether;
    uint256 public constant MARKETPLACE_FEE_RATE = 250; // 2.5%
    uint256 public constant ROYALTY_RATE = 500; // 5%
    uint256 public constant BPS_DENOMINATOR = 10000;

    // Test contract to expose internal functions
    TestablePaymentDistribution public testContract;

    function setUp() public {
        testContract = new TestablePaymentDistribution();

        // Fund test contract for payment distribution tests
        vm.deal(address(testContract), 100 ether);

        // Fund test addresses
        vm.deal(SELLER, 10 ether);
        vm.deal(BUYER, 10 ether);
        vm.deal(ROYALTY_RECEIVER, 1 ether);
        vm.deal(MARKETPLACE_WALLET, 1 ether);
    }

    // ============================================================================
    // PAYMENT CALCULATION TESTS
    // ============================================================================

    function test_CalculatePaymentDistribution_Success() public {
        PaymentDistributionLib.FeeParams memory params = PaymentDistributionLib.FeeParams({
            salePrice: SALE_PRICE,
            marketplaceFeeRate: MARKETPLACE_FEE_RATE,
            royaltyRate: ROYALTY_RATE,
            bpsDenominator: BPS_DENOMINATOR
        });

        PaymentDistributionLib.PaymentData memory data =
            PaymentDistributionLib.calculatePaymentDistribution(params, SELLER, ROYALTY_RECEIVER, MARKETPLACE_WALLET);

        uint256 expectedMarketplaceFee = (SALE_PRICE * MARKETPLACE_FEE_RATE) / BPS_DENOMINATOR;
        uint256 expectedRoyalty = (SALE_PRICE * ROYALTY_RATE) / BPS_DENOMINATOR;
        uint256 expectedSellerAmount = SALE_PRICE - expectedMarketplaceFee - expectedRoyalty;

        assertEq(data.seller, SELLER);
        assertEq(data.royaltyReceiver, ROYALTY_RECEIVER);
        assertEq(data.marketplaceWallet, MARKETPLACE_WALLET);
        assertEq(data.totalAmount, SALE_PRICE);
        assertEq(data.sellerAmount, expectedSellerAmount);
        assertEq(data.marketplaceFee, expectedMarketplaceFee);
        assertEq(data.royaltyAmount, expectedRoyalty);
    }

    function test_CalculatePaymentDistribution_ZeroFees() public {
        PaymentDistributionLib.FeeParams memory params = PaymentDistributionLib.FeeParams({
            salePrice: SALE_PRICE, marketplaceFeeRate: 0, royaltyRate: 0, bpsDenominator: BPS_DENOMINATOR
        });

        PaymentDistributionLib.PaymentData memory data =
            PaymentDistributionLib.calculatePaymentDistribution(params, SELLER, ROYALTY_RECEIVER, MARKETPLACE_WALLET);

        assertEq(data.sellerAmount, SALE_PRICE);
        assertEq(data.marketplaceFee, 0);
        assertEq(data.royaltyAmount, 0);
    }

    function test_CalculatePaymentDistribution_MaxFees() public {
        PaymentDistributionLib.FeeParams memory params = PaymentDistributionLib.FeeParams({
            salePrice: SALE_PRICE,
            marketplaceFeeRate: 5000, // 50%
            royaltyRate: 5000, // 50%
            bpsDenominator: BPS_DENOMINATOR
        });

        PaymentDistributionLib.PaymentData memory data =
            PaymentDistributionLib.calculatePaymentDistribution(params, SELLER, ROYALTY_RECEIVER, MARKETPLACE_WALLET);

        assertEq(data.sellerAmount, 0); // All goes to fees
        assertEq(data.marketplaceFee, SALE_PRICE / 2);
        assertEq(data.royaltyAmount, SALE_PRICE / 2);
    }

    function test_CalculateBuyerPrice_Success() public {
        uint256 totalPrice =
            PaymentDistributionLib.calculateBuyerPrice(SALE_PRICE, MARKETPLACE_FEE_RATE, ROYALTY_RATE, BPS_DENOMINATOR);

        uint256 expectedTakerFee = (SALE_PRICE * MARKETPLACE_FEE_RATE) / BPS_DENOMINATOR;
        uint256 expectedRoyalty = (SALE_PRICE * ROYALTY_RATE) / BPS_DENOMINATOR;
        uint256 expectedTotal = SALE_PRICE + expectedTakerFee + expectedRoyalty;

        assertEq(totalPrice, expectedTotal);
    }

    function test_CalculateBuyerPrice_ZeroFees() public {
        uint256 totalPrice = PaymentDistributionLib.calculateBuyerPrice(SALE_PRICE, 0, 0, BPS_DENOMINATOR);

        assertEq(totalPrice, SALE_PRICE);
    }

    // ============================================================================
    // PAYMENT DISTRIBUTION TESTS
    // ============================================================================

    function test_DistributePayment_Success() public {
        uint256 marketplaceFee = (SALE_PRICE * MARKETPLACE_FEE_RATE) / BPS_DENOMINATOR;
        uint256 royaltyAmount = (SALE_PRICE * ROYALTY_RATE) / BPS_DENOMINATOR;
        uint256 sellerAmount = SALE_PRICE - marketplaceFee - royaltyAmount;

        PaymentDistributionLib.PaymentData memory data = PaymentDistributionLib.PaymentData({
            seller: SELLER,
            royaltyReceiver: ROYALTY_RECEIVER,
            marketplaceWallet: MARKETPLACE_WALLET,
            totalAmount: SALE_PRICE,
            sellerAmount: sellerAmount,
            marketplaceFee: marketplaceFee,
            royaltyAmount: royaltyAmount
        });

        // Record initial balances
        uint256 sellerBalanceBefore = SELLER.balance;
        uint256 royaltyBalanceBefore = ROYALTY_RECEIVER.balance;
        uint256 marketplaceBalanceBefore = MARKETPLACE_WALLET.balance;

        // Distribute payment
        testContract.distributePayment(data);

        // Verify balances
        assertEq(SELLER.balance, sellerBalanceBefore + sellerAmount);
        assertEq(ROYALTY_RECEIVER.balance, royaltyBalanceBefore + royaltyAmount);
        assertEq(MARKETPLACE_WALLET.balance, marketplaceBalanceBefore + marketplaceFee);
    }

    function test_DistributePayment_ZeroRoyalty() public {
        PaymentDistributionLib.PaymentData memory data = PaymentDistributionLib.PaymentData({
            seller: SELLER,
            royaltyReceiver: ZERO_ADDRESS,
            marketplaceWallet: MARKETPLACE_WALLET,
            totalAmount: SALE_PRICE,
            sellerAmount: SALE_PRICE - 25000, // 0.25 ETH marketplace fee
            marketplaceFee: 25000,
            royaltyAmount: 0
        });

        uint256 royaltyBalanceBefore = ROYALTY_RECEIVER.balance;

        testContract.distributePayment(data);

        // Royalty receiver balance should not change
        assertEq(ROYALTY_RECEIVER.balance, royaltyBalanceBefore);
    }

    function test_DistributePayment_ZeroMarketplaceFee() public {
        PaymentDistributionLib.PaymentData memory data = PaymentDistributionLib.PaymentData({
            seller: SELLER,
            royaltyReceiver: ROYALTY_RECEIVER,
            marketplaceWallet: MARKETPLACE_WALLET,
            totalAmount: SALE_PRICE,
            sellerAmount: SALE_PRICE - 50000, // 0.05 ETH royalty
            marketplaceFee: 0,
            royaltyAmount: 50000
        });

        uint256 marketplaceBalanceBefore = MARKETPLACE_WALLET.balance;

        testContract.distributePayment(data);

        // Marketplace balance should not change
        assertEq(MARKETPLACE_WALLET.balance, marketplaceBalanceBefore);
    }

    // ============================================================================
    // ERROR CONDITION TESTS
    // ============================================================================

    function test_DistributePayment_ZeroSellerAddress_Reverts() public {
        PaymentDistributionLib.PaymentData memory data = PaymentDistributionLib.PaymentData({
            seller: ZERO_ADDRESS,
            royaltyReceiver: ROYALTY_RECEIVER,
            marketplaceWallet: MARKETPLACE_WALLET,
            totalAmount: SALE_PRICE,
            sellerAmount: SALE_PRICE,
            marketplaceFee: 0,
            royaltyAmount: 0
        });

        vm.expectRevert(PaymentDistributionLib.PaymentDistribution__ZeroAddress.selector);
        testContract.distributePayment(data);
    }

    function test_DistributePayment_ZeroMarketplaceAddress_Reverts() public {
        PaymentDistributionLib.PaymentData memory data = PaymentDistributionLib.PaymentData({
            seller: SELLER,
            royaltyReceiver: ROYALTY_RECEIVER,
            marketplaceWallet: ZERO_ADDRESS,
            totalAmount: SALE_PRICE,
            sellerAmount: SALE_PRICE,
            marketplaceFee: 0,
            royaltyAmount: 0
        });

        vm.expectRevert(PaymentDistributionLib.PaymentDistribution__ZeroAddress.selector);
        testContract.distributePayment(data);
    }

    function test_DistributePayment_ZeroTotalAmount_Reverts() public {
        PaymentDistributionLib.PaymentData memory data = PaymentDistributionLib.PaymentData({
            seller: SELLER,
            royaltyReceiver: ROYALTY_RECEIVER,
            marketplaceWallet: MARKETPLACE_WALLET,
            totalAmount: 0,
            sellerAmount: 0,
            marketplaceFee: 0,
            royaltyAmount: 0
        });

        vm.expectRevert(PaymentDistributionLib.PaymentDistribution__InvalidAmount.selector);
        testContract.distributePayment(data);
    }

    function test_DistributePayment_InvalidAmountSum_Reverts() public {
        PaymentDistributionLib.PaymentData memory data = PaymentDistributionLib.PaymentData({
            seller: SELLER,
            royaltyReceiver: ROYALTY_RECEIVER,
            marketplaceWallet: MARKETPLACE_WALLET,
            totalAmount: SALE_PRICE,
            sellerAmount: SALE_PRICE, // Wrong: should be less due to fees
            marketplaceFee: 25000,
            royaltyAmount: 50000
        });

        vm.expectRevert(PaymentDistributionLib.PaymentDistribution__InvalidAmount.selector);
        testContract.distributePayment(data);
    }

    function test_DistributePayment_InsufficientBalance_Reverts() public {
        // Create contract with insufficient balance
        TestablePaymentDistribution poorContract = new TestablePaymentDistribution();
        vm.deal(address(poorContract), 0.1 ether); // Less than required

        PaymentDistributionLib.PaymentData memory data = PaymentDistributionLib.PaymentData({
            seller: SELLER,
            royaltyReceiver: ROYALTY_RECEIVER,
            marketplaceWallet: MARKETPLACE_WALLET,
            totalAmount: SALE_PRICE,
            sellerAmount: SALE_PRICE,
            marketplaceFee: 0,
            royaltyAmount: 0
        });

        vm.expectRevert(PaymentDistributionLib.PaymentDistribution__InsufficientBalance.selector);
        poorContract.distributePayment(data);
    }

    // ============================================================================
    // UTILITY FUNCTION TESTS
    // ============================================================================

    function test_CalculatePercentage_Success() public {
        uint256 result = PaymentDistributionLib.calculatePercentage(SALE_PRICE, MARKETPLACE_FEE_RATE, BPS_DENOMINATOR);

        uint256 expected = (SALE_PRICE * MARKETPLACE_FEE_RATE) / BPS_DENOMINATOR;
        assertEq(result, expected);
    }

    function test_CalculatePercentage_ZeroAmount() public {
        uint256 result = PaymentDistributionLib.calculatePercentage(0, MARKETPLACE_FEE_RATE, BPS_DENOMINATOR);

        assertEq(result, 0);
    }

    function test_CalculatePercentage_ZeroPercentage() public {
        uint256 result = PaymentDistributionLib.calculatePercentage(SALE_PRICE, 0, BPS_DENOMINATOR);

        assertEq(result, 0);
    }

    function test_CalculatePercentage_FullPercentage() public {
        uint256 result = PaymentDistributionLib.calculatePercentage(
            SALE_PRICE,
            BPS_DENOMINATOR, // 100%
            BPS_DENOMINATOR
        );

        assertEq(result, SALE_PRICE);
    }

    // ============================================================================
    // FUZZ TESTS
    // ============================================================================

    function testFuzz_CalculatePaymentDistribution(uint256 salePrice, uint256 marketplaceFeeRate, uint256 royaltyRate)
        public
    {
        // Bound inputs to reasonable ranges
        salePrice = bound(salePrice, 1, type(uint128).max);
        marketplaceFeeRate = bound(marketplaceFeeRate, 0, 5000); // 0-50%
        royaltyRate = bound(royaltyRate, 0, 5000); // 0-50%

        // Ensure total fees don't exceed 100%
        vm.assume(marketplaceFeeRate + royaltyRate <= BPS_DENOMINATOR);

        PaymentDistributionLib.FeeParams memory params = PaymentDistributionLib.FeeParams({
            salePrice: salePrice,
            marketplaceFeeRate: marketplaceFeeRate,
            royaltyRate: royaltyRate,
            bpsDenominator: BPS_DENOMINATOR
        });

        PaymentDistributionLib.PaymentData memory data =
            PaymentDistributionLib.calculatePaymentDistribution(params, SELLER, ROYALTY_RECEIVER, MARKETPLACE_WALLET);

        // Verify amounts add up correctly
        assertEq(data.totalAmount, salePrice);
        assertEq(data.sellerAmount + data.marketplaceFee + data.royaltyAmount, salePrice);

        // Verify individual calculations
        assertEq(data.marketplaceFee, (salePrice * marketplaceFeeRate) / BPS_DENOMINATOR);
        assertEq(data.royaltyAmount, (salePrice * royaltyRate) / BPS_DENOMINATOR);
    }

    function testFuzz_CalculateBuyerPrice(uint256 basePrice, uint256 takerFeeRate, uint256 royaltyRate) public {
        // Bound inputs
        basePrice = bound(basePrice, 1, type(uint128).max);
        takerFeeRate = bound(takerFeeRate, 0, 2500); // 0-25%
        royaltyRate = bound(royaltyRate, 0, 2500); // 0-25%

        uint256 totalPrice =
            PaymentDistributionLib.calculateBuyerPrice(basePrice, takerFeeRate, royaltyRate, BPS_DENOMINATOR);

        uint256 expectedTakerFee = (basePrice * takerFeeRate) / BPS_DENOMINATOR;
        uint256 expectedRoyalty = (basePrice * royaltyRate) / BPS_DENOMINATOR;
        uint256 expectedTotal = basePrice + expectedTakerFee + expectedRoyalty;

        assertEq(totalPrice, expectedTotal);
        assertGe(totalPrice, basePrice); // Total should always be >= base price
    }
}

// ============================================================================
// TEST CONTRACT TO EXPOSE INTERNAL FUNCTIONS
// ============================================================================

/**
 * @title TestablePaymentDistribution
 * @notice Test contract that exposes PaymentDistributionLib internal functions
 */
contract TestablePaymentDistribution {
    using PaymentDistributionLib for PaymentDistributionLib.PaymentData;

    function distributePayment(PaymentDistributionLib.PaymentData memory data) external {
        PaymentDistributionLib.distributePayment(data);
    }

    // Allow contract to receive ETH
    receive() external payable {}
}
