// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "src/libraries/DutchAuctionPricingLib.sol";

/**
 * @notice Thin external wrapper around the library functions. Tests need a
 *         call-depth boundary so `vm.expectRevert` sees the revert from a
 *         child call rather than the cheatcode itself.
 */
contract DutchPricingHarness {
    function linearPriceAt(DutchAuctionPricingLib.LinearCurve memory c, uint256 t)
        external
        pure
        returns (uint256)
    {
        return DutchAuctionPricingLib.linearPriceAt(c, t);
    }

    function stepPriceAt(DutchAuctionPricingLib.StepCurve memory c, uint256 t)
        external
        pure
        returns (uint256)
    {
        return DutchAuctionPricingLib.stepPriceAt(c, t);
    }
}

/**
 * @title DutchAuctionPricingLibTest
 * @notice Foundry tests for the linear and step Dutch auction pricing curves.
 */
contract DutchAuctionPricingLibTest is Test {
    using DutchAuctionPricingLib for DutchAuctionPricingLib.LinearCurve;
    using DutchAuctionPricingLib for DutchAuctionPricingLib.StepCurve;

    DutchPricingHarness internal harness;

    function setUp() public {
        harness = new DutchPricingHarness();
    }

    function _linearCurve() internal pure returns (DutchAuctionPricingLib.LinearCurve memory) {
        return DutchAuctionPricingLib.LinearCurve({
            startTime: 1_000,
            endTime: 2_000,
            startPrice: 1 ether,
            endPrice: 0.1 ether
        });
    }

    function _stepCurve() internal pure returns (DutchAuctionPricingLib.StepCurve memory) {
        return DutchAuctionPricingLib.StepCurve({
            startTime: 1_000,
            stepDuration: 100,
            startPrice: 1 ether,
            endPrice: 0.1 ether,
            stepAmount: 0.09 ether
        });
    }

    // -------------------------------------------------------------------
    // Linear curve
    // -------------------------------------------------------------------

    function test_Linear_BeforeStart_ReturnsStartPrice() public pure {
        DutchAuctionPricingLib.LinearCurve memory c = _linearCurve();
        assertEq(DutchAuctionPricingLib.linearPriceAt(c, 0), 1 ether);
        assertEq(DutchAuctionPricingLib.linearPriceAt(c, 999), 1 ether);
        assertEq(DutchAuctionPricingLib.linearPriceAt(c, 1_000), 1 ether);
    }

    function test_Linear_AfterEnd_ReturnsEndPrice() public pure {
        DutchAuctionPricingLib.LinearCurve memory c = _linearCurve();
        assertEq(DutchAuctionPricingLib.linearPriceAt(c, 2_000), 0.1 ether);
        assertEq(DutchAuctionPricingLib.linearPriceAt(c, 999_999), 0.1 ether);
    }

    function test_Linear_Midpoint_ReturnsMiddlePrice() public pure {
        DutchAuctionPricingLib.LinearCurve memory c = _linearCurve();
        // halfway through: 1 ether - 0.45 ether == 0.55 ether
        assertEq(DutchAuctionPricingLib.linearPriceAt(c, 1_500), 0.55 ether);
    }

    function test_Linear_QuarterAndThreeQuarter() public pure {
        DutchAuctionPricingLib.LinearCurve memory c = _linearCurve();
        // 1/4 elapsed -> dropped 0.225 ether
        assertEq(DutchAuctionPricingLib.linearPriceAt(c, 1_250), 0.775 ether);
        // 3/4 elapsed -> dropped 0.675 ether
        assertEq(DutchAuctionPricingLib.linearPriceAt(c, 1_750), 0.325 ether);
    }

    function test_Linear_Monotonic_NonIncreasing() public pure {
        DutchAuctionPricingLib.LinearCurve memory c = _linearCurve();
        uint256 prev = c.startPrice;
        for (uint256 t = c.startTime; t <= c.endTime + 5; t += 73) {
            uint256 px = DutchAuctionPricingLib.linearPriceAt(c, t);
            assertLe(px, prev);
            prev = px;
        }
    }

    function test_Linear_RevertOnInvalidTimeWindow() public {
        DutchAuctionPricingLib.LinearCurve memory c = _linearCurve();
        c.endTime = c.startTime; // zero-duration
        vm.expectRevert(DutchAuctionPricingLib.DutchAuctionPricing__InvalidTimeWindow.selector);
        harness.linearPriceAt(c, 1_500);
    }

    function test_Linear_RevertOnInvalidPriceRange() public {
        DutchAuctionPricingLib.LinearCurve memory c = _linearCurve();
        c.endPrice = c.startPrice + 1; // inverted
        vm.expectRevert(DutchAuctionPricingLib.DutchAuctionPricing__InvalidPriceRange.selector);
        harness.linearPriceAt(c, 1_500);
    }

    function test_Linear_CurrentLinearPrice_UsesBlockTimestamp() public {
        DutchAuctionPricingLib.LinearCurve memory c = _linearCurve();
        vm.warp(1_500);
        assertEq(DutchAuctionPricingLib.currentLinearPrice(c), 0.55 ether);
    }

    function test_Linear_SecondsRemaining() public pure {
        DutchAuctionPricingLib.LinearCurve memory c = _linearCurve();
        assertEq(DutchAuctionPricingLib.linearSecondsRemaining(c, 1_200), 800);
        assertEq(DutchAuctionPricingLib.linearSecondsRemaining(c, 2_500), 0);
    }

    // -------------------------------------------------------------------
    // Step curve
    // -------------------------------------------------------------------

    function test_Step_BeforeStart_ReturnsStartPrice() public pure {
        DutchAuctionPricingLib.StepCurve memory c = _stepCurve();
        assertEq(DutchAuctionPricingLib.stepPriceAt(c, 999), 1 ether);
        assertEq(DutchAuctionPricingLib.stepPriceAt(c, 1_000), 1 ether);
    }

    function test_Step_FirstStep_DropsByOneStepAmount() public pure {
        DutchAuctionPricingLib.StepCurve memory c = _stepCurve();
        // At t = startTime + stepDuration, one step has elapsed
        assertEq(DutchAuctionPricingLib.stepPriceAt(c, 1_100), 0.91 ether);
        // Mid-step (no further drop)
        assertEq(DutchAuctionPricingLib.stepPriceAt(c, 1_199), 0.91 ether);
    }

    function test_Step_MultipleSteps() public pure {
        DutchAuctionPricingLib.StepCurve memory c = _stepCurve();
        // 5 full steps -> 0.45 ether dropped -> 0.55 ether
        assertEq(DutchAuctionPricingLib.stepPriceAt(c, 1_500), 0.55 ether);
        // 9 full steps -> 0.81 ether dropped -> 0.19 ether
        assertEq(DutchAuctionPricingLib.stepPriceAt(c, 1_900), 0.19 ether);
    }

    function test_Step_FloorsAtEndPrice() public pure {
        DutchAuctionPricingLib.StepCurve memory c = _stepCurve();
        // 10 steps would drop 0.9 ether, hitting the floor exactly
        assertEq(DutchAuctionPricingLib.stepPriceAt(c, 2_000), 0.1 ether);
        // After that we stay at the floor
        assertEq(DutchAuctionPricingLib.stepPriceAt(c, 999_999), 0.1 ether);
    }

    function test_Step_RevertOnZeroStep() public {
        DutchAuctionPricingLib.StepCurve memory c = _stepCurve();
        c.stepDuration = 0;
        vm.expectRevert(DutchAuctionPricingLib.DutchAuctionPricing__InvalidStep.selector);
        harness.stepPriceAt(c, 1_500);

        c = _stepCurve();
        c.stepAmount = 0;
        vm.expectRevert(DutchAuctionPricingLib.DutchAuctionPricing__InvalidStep.selector);
        harness.stepPriceAt(c, 1_500);
    }

    function test_Step_RevertOnInvalidPriceRange() public {
        DutchAuctionPricingLib.StepCurve memory c = _stepCurve();
        c.endPrice = c.startPrice + 1;
        vm.expectRevert(DutchAuctionPricingLib.DutchAuctionPricing__InvalidPriceRange.selector);
        harness.stepPriceAt(c, 1_500);
    }

    function test_Step_CurrentStepPrice_UsesBlockTimestamp() public {
        DutchAuctionPricingLib.StepCurve memory c = _stepCurve();
        vm.warp(1_500);
        assertEq(DutchAuctionPricingLib.currentStepPrice(c), 0.55 ether);
    }

    function test_Step_SecondsRemaining() public pure {
        DutchAuctionPricingLib.StepCurve memory c = _stepCurve();
        // 10 steps to floor, each 100 sec -> floor reached at 2000
        assertEq(DutchAuctionPricingLib.stepSecondsRemaining(c, 1_000), 1_000);
        assertEq(DutchAuctionPricingLib.stepSecondsRemaining(c, 1_500), 500);
        assertEq(DutchAuctionPricingLib.stepSecondsRemaining(c, 5_000), 0);
    }

    // -------------------------------------------------------------------
    // Fuzz tests
    // -------------------------------------------------------------------

    function testFuzz_Linear_AlwaysInRange(uint256 timeOffset) public pure {
        timeOffset = bound(timeOffset, 0, 10_000);
        DutchAuctionPricingLib.LinearCurve memory c = _linearCurve();
        uint256 px = DutchAuctionPricingLib.linearPriceAt(c, c.startTime + timeOffset);
        assertGe(px, c.endPrice);
        assertLe(px, c.startPrice);
    }

    function testFuzz_Step_AlwaysInRange(uint256 timeOffset) public pure {
        timeOffset = bound(timeOffset, 0, 10_000);
        DutchAuctionPricingLib.StepCurve memory c = _stepCurve();
        uint256 px = DutchAuctionPricingLib.stepPriceAt(c, c.startTime + timeOffset);
        assertGe(px, c.endPrice);
        assertLe(px, c.startPrice);
    }
}
