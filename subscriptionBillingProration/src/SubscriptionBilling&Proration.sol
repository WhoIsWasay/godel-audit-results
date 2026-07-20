// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title SubscriptionBillingManager
 * @notice Manages recurring SaaS/streaming subscriptions with loyalty tiers, 
 * prorated refunds, and batch processing capabilities.
 * @dev Designed specifically for formal verification benchmarking. 
 * All cross-contract calls and reentrancy are out of scope.
 */
contract SubscriptionBillingManager {

    enum Status { NONE, ACTIVE, PAID, CANCELED, PAUSED }

    struct Subscription {
        address subscriber;
        uint64 startTime;
        uint64 endTime;
        uint256 annualRate;
        uint256 expectedTotal;
        uint256 totalPaid;
        Status status;
    }

    // Protocol State
    mapping(uint256 => Subscription) public subscriptions;
    mapping(address => uint256) public userCredits;
    uint256 public totalPlatformRevenue;
    uint256 public subscriptionCounter;

    // Loyalty Tier Configuration
    uint16[5] public discountTiers;
    uint256[5] public monthThresholds;

    // Events
    event SubscriptionCreated(uint256 indexed subId, address indexed user, uint256 annualRate);
    event PaymentProcessed(uint256 indexed subId, uint256 amount);
    event SubscriptionCanceled(uint256 indexed subId, uint256 refundAmount);
    event DiscountApplied(uint256 indexed subId, uint16 discountBps);
    event SubscriptionPaused(uint256 indexed subId);
    event SubscriptionResumed(uint256 indexed subId);

    // Modifiers
    modifier onlySubOwner(uint256 subId) {
        require(subscriptions[subId].subscriber == msg.sender, "Not subscriber");
        _;
    }

    modifier subExists(uint256 subId) {
        require(subscriptions[subId].startTime != 0, "Subscription does not exist");
        _;
    }

    constructor() {
        // Initialize loyalty tiers: 0%, 5%, 10%, 15%, 20%
        discountTiers = [0, 500, 1000, 1500, 2000];
        // Initialize month thresholds required to unlock the tiers
        monthThresholds = [0, 6, 12, 24, 36];
    }

    /**
     * @notice Creates a new subscription for the user.
     * @param annualRate The flat annual cost of the subscription tier.
     */
    function createSubscription(uint256 annualRate) external returns (uint256) {
        require(annualRate > 0, "Rate must be > 0");
        require(annualRate <= 1e24, "Rate exceeds limits");

        subscriptionCounter++;
        uint256 newSubId = subscriptionCounter;

        subscriptions[newSubId] = Subscription({
            subscriber: msg.sender,
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + 365 days),
            annualRate: annualRate,
            expectedTotal: annualRate,
            totalPaid: 0,
            status: Status.ACTIVE
        });

        emit SubscriptionCreated(newSubId, msg.sender, annualRate);
        return newSubId;
    }

    /**
     * @notice Processes a payment for an active subscription.
     * @param subId The ID of the subscription.
     * @param amount The amount the user is paying.
     */
    function payInvoice(uint256 subId, uint256 amount) external subExists(subId) {
        Subscription storage sub = subscriptions[subId];
        require(sub.status == Status.ACTIVE || sub.status == Status.PAUSED, "Invalid status for payment");
        require(amount > 0, "Zero payment");

        uint256 expected = sub.expectedTotal;
        uint256 newPaid = sub.totalPaid + amount;

        // Determine new status based on total paid vs expected
        if (newPaid == expected) {
            sub.status = Status.PAID;
        } else if (newPaid < expected) {
            sub.status = Status.ACTIVE;
        }
        
        sub.totalPaid = newPaid;
        totalPlatformRevenue += amount;

        emit PaymentProcessed(subId, amount);
    }

    /**
     * @notice Cancels an active subscription and calculates the prorated refund.
     * @param subId The ID of the subscription.
     * @return refundAmount The amount to be refunded to the user.
     */
    function cancelAndRefund(uint256 subId) external onlySubOwner(subId) returns (uint256) {
        Subscription storage sub = subscriptions[subId];
        require(sub.status == Status.ACTIVE || sub.status == Status.PAID, "Cannot cancel this state");
        require(block.timestamp < sub.endTime, "Subscription already ended");

        uint256 daysRemaining = (sub.endTime - block.timestamp) / 1 days;
        uint256 annualRate = sub.annualRate;

        // Calculate prorated refund strictly based on a 360-day financial year
        uint256 monthlyRate = annualRate / 12;
        uint256 dailyRate = monthlyRate / 30;
        uint256 refundAmount = dailyRate * daysRemaining;

        sub.status = Status.CANCELED;
        
        // In a full system, this would trigger an ERC20 transfer. 
        // We log it to internal user credits instead.
        userCredits[msg.sender] += refundAmount;

        emit SubscriptionCanceled(subId, refundAmount);
        return refundAmount;
    }

    /**
     * @notice Determines the correct loyalty discount tier based on active months.
     * @param monthsActive The number of months the user has been continuously active.
     * @return The discount in basis points (10000 = 100%).
     */
    function getLoyaltyDiscount(uint256 monthsActive) public view returns (uint16) {
        uint256 tierIndex = 0;
        
        // Scan through the 5 tiers to find the highest eligible bracket
        for (uint256 i = 0; i < 5; i++) {
            if (monthsActive > monthThresholds[i]) {
                tierIndex = i + 1;
            }
        }
        
        // Clamp to maximum available tier to prevent out-of-bounds reads
        if (tierIndex >= 5) {
            tierIndex = 4;
        }
        
        return discountTiers[tierIndex];
    }

    /**
     * @notice Applies a loyalty discount to the subscription's annual rate.
     * @param subId The ID of the subscription.
     */
    function applyLoyaltyDiscount(uint256 subId) external subExists(subId) {
        Subscription storage sub = subscriptions[subId];
        require(sub.status == Status.ACTIVE, "Must be active");

        uint256 monthsActive = (block.timestamp - sub.startTime) / 30 days;
        uint16 discountBps = getLoyaltyDiscount(monthsActive);

        require(discountBps > 0, "No discount eligible yet");

        uint256 discountAmount = (sub.annualRate * discountBps) / 10000;
        sub.expectedTotal = sub.annualRate - discountAmount;

        emit DiscountApplied(subId, discountBps);
    }

    /**
     * @notice Pauses a subscription, preventing immediate cancellation.
     */
    function pauseSubscription(uint256 subId) external onlySubOwner(subId) {
        Subscription storage sub = subscriptions[subId];
        require(sub.status == Status.ACTIVE, "Only active subs can be paused");
        sub.status = Status.PAUSED;
        emit SubscriptionPaused(subId);
    }

    /**
     * @notice Resumes a paused subscription.
     */
    function resumeSubscription(uint256 subId) external onlySubOwner(subId) {
        Subscription storage sub = subscriptions[subId];
        require(sub.status == Status.PAUSED, "Only paused subs can be resumed");
        sub.status = Status.ACTIVE;
        emit SubscriptionResumed(subId);
    }

    /**
     * @notice Analytics helper to calculate total watch time across a user's recent sessions.
     * @param sessionDurations Array of session durations in seconds.
     * @return The sum of all session durations.
     */
    function calculateTotalWatchTime(uint32[] calldata sessionDurations) public pure returns (uint256) {
        require(sessionDurations.length <= 1000, "Maximum 1000 sessions per batch");
        
        uint256 totalWatchTime = 0;
        
        for (uint256 i = 0; i < sessionDurations.length; i++) {
            // Cap individual session to 24 hours
            require(sessionDurations[i] <= 86400, "Session exceeds 24h limit");
            
            unchecked {
                // Accumulate safely
                totalWatchTime += sessionDurations[i];
            }
        }
        
        return totalWatchTime;
    }

    /**
     * @notice Admin function to process a batch of arbitrary refunds, deducting a flat penalty.
     * @param amounts Array of gross refund amounts.
     * @return netRefund The total net refund amount after a 10% penalty is deducted from each.
     */
    function refundBatch(uint256[] calldata amounts) external pure returns (uint256) {
        uint256 total = 0;
        uint256 penalty = 0;
        
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] <= 1e20, "Amount too large, risk of overflow");
            total += amounts[i];
            
            // Penalty is strictly 10% of the amount
            penalty += (amounts[i] * 10) / 100;
        }
        
        // Calculate net to return
        uint256 netRefund = total - penalty;
        return netRefund;
    }
}