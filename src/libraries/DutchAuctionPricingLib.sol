// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title DutchAuctionPricingLib
 * @notice Pure pricing math for time-weighted Dutch auctions (mints / drops).
 * @dev Solidity 0.8.30 — all math uses checked arithmetic. No storage, no
 *      external calls; safe to embed in mint contracts or exchanges that
 *      need to expose a `currentPrice(...)` view alongside the listing.
 *
 *      The two curves implemented here are:
 *
 *        1. Linear price drop          — straightforward,
 *           current = startPrice - (startPrice-endPrice) * elapsed / duration
 *
 *        2. Step-wise drop on intervals — drops by a fixed amount every
 *           `stepDuration` seconds; useful for "drop 0.01 ETH every minute"
 *           UX, where users see discrete tick marks.
 */
library DutchAuctionPricingLib {
    // ============================================================================
    // ERRORS
    // ============================================================================

    error DutchAuctionPricing__InvalidTimeWindow();
    error DutchAuctionPricing__InvalidPriceRange();
    error DutchAuctionPricing__InvalidStep();

    // ============================================================================
    // STRUCTS
    // ============================================================================

    struct LinearCurve {
        uint256 startTime;   // unix seconds — auction opens
        uint256 endTime;     // unix seconds — price reaches endPrice
        uint256 startPrice;  // wei (must be >= endPrice)
        uint256 endPrice;    // wei
    }

    struct StepCurve {
        uint256 startTime;     // unix seconds
        uint256 stepDuration;  // seconds between price drops (> 0)
        uint256 startPrice;    // wei (>= endPrice)
        uint256 endPrice;      // wei (floor — auction never drops below)
        uint256 stepAmount;    // wei to subtract per step (> 0)
    }

    // ============================================================================
    // LINEAR CURVE
    // ============================================================================

    /**
     * @notice Computes the current price along a linear Dutch curve.
     * @dev Returns `startPrice` before `startTime`, `endPrice` after `endTime`,
     *      and a linear interpolation in between. Reverts on a malformed curve.
     *
     *      Math: floor((startPrice - endPrice) * elapsed / duration).
     *      Result is monotonically non-increasing as `currentTime` advances.
     */
    function linearPriceAt(LinearCurve memory curve, uint256 currentTime)
        internal
        pure
        returns (uint256)
    {
        if (curve.endTime <= curve.startTime) revert DutchAuctionPricing__InvalidTimeWindow();
        if (curve.endPrice > curve.startPrice) revert DutchAuctionPricing__InvalidPriceRange();

        if (currentTime <= curve.startTime) return curve.startPrice;
        if (currentTime >= curve.endTime) return curve.endPrice;

        uint256 elapsed = currentTime - curve.startTime;
        uint256 duration = curve.endTime - curve.startTime;
        uint256 priceDelta = curve.startPrice - curve.endPrice;
        uint256 dropped = (priceDelta * elapsed) / duration;
        return curve.startPrice - dropped;
    }

    /**
     * @notice Returns the linear price at the current block timestamp.
     */
    function currentLinearPrice(LinearCurve memory curve) internal view returns (uint256) {
        return linearPriceAt(curve, block.timestamp);
    }

    // ============================================================================
    // STEP CURVE
    // ============================================================================

    /**
     * @notice Computes the current price along a step Dutch curve.
     * @dev Drops by `stepAmount` every `stepDuration` seconds, floored at
     *      `endPrice`. Reverts on a malformed curve.
     */
    function stepPriceAt(StepCurve memory curve, uint256 currentTime)
        internal
        pure
        returns (uint256)
    {
        if (curve.stepDuration == 0 || curve.stepAmount == 0) revert DutchAuctionPricing__InvalidStep();
        if (curve.endPrice > curve.startPrice) revert DutchAuctionPricing__InvalidPriceRange();

        if (currentTime <= curve.startTime) return curve.startPrice;

        uint256 elapsed = currentTime - curve.startTime;
        uint256 steps = elapsed / curve.stepDuration;
        uint256 dropped = steps * curve.stepAmount;

        // Saturate at floor (endPrice) — never go below.
        if (dropped >= curve.startPrice - curve.endPrice) {
            return curve.endPrice;
        }
        return curve.startPrice - dropped;
    }

    /**
     * @notice Returns the step price at the current block timestamp.
     */
    function currentStepPrice(StepCurve memory curve) internal view returns (uint256) {
        return stepPriceAt(curve, block.timestamp);
    }

    // ============================================================================
    // HELPERS
    // ============================================================================

    /**
     * @notice Returns the number of seconds remaining until the curve reaches its floor.
     *         For linear curves: endTime - currentTime (clamped at zero).
     *         For step curves:   computed from remaining steps.
     */
    function linearSecondsRemaining(LinearCurve memory curve, uint256 currentTime)
        internal
        pure
        returns (uint256)
    {
        if (currentTime >= curve.endTime) return 0;
        return curve.endTime - currentTime;
    }

    function stepSecondsRemaining(StepCurve memory curve, uint256 currentTime)
        internal
        pure
        returns (uint256)
    {
        if (curve.stepDuration == 0 || curve.stepAmount == 0) revert DutchAuctionPricing__InvalidStep();

        uint256 priceRange = curve.startPrice - curve.endPrice;
        // Total steps needed to hit floor, rounded up.
        uint256 stepsToFloor = (priceRange + curve.stepAmount - 1) / curve.stepAmount;
        uint256 floorAt = curve.startTime + stepsToFloor * curve.stepDuration;
        if (currentTime >= floorAt) return 0;
        return floorAt - currentTime;
    }
}
