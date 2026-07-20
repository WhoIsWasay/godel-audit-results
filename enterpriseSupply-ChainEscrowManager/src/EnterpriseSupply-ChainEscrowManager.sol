// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title SupplyChainEscrowManager
 * @notice Enterprise-grade escrow protocol for supply chain milestone tracking, 
 * dynamic quality-based payouts, and automated dispute resolution.
 * @dev Designed specifically for formal verification benchmarking. 
 * Cross-contract calls, reentrancy, and access-control bypasses are out of scope.
 */
contract SupplyChainEscrowManager {

    enum EscrowStatus { PENDING, FUNDED, ACTIVE, IN_DISPUTE, COMPLETED, CANCELLED }
    enum MilestoneStatus { PENDING, DELIVERED, APPROVED, DISPUTED, CANCELLED }

    struct Milestone {
        uint256 id;
        uint256 weight;      // Basis points (10000 = 100%)
        uint256 amount;      // Fiat/Token base amount
        uint64 dueDate;      // Timestamp deadline
        uint64 deliveredAt;  // Timestamp of submission
        uint256 qualityScore;// Score out of 100
        uint256 payout;      // Final adjusted payout amount
        MilestoneStatus status;
    }

    struct Escrow {
        uint256 id;
        address buyer;
        address supplier;
        address arbitrator;
        uint256 totalDeposit;
        uint256 balance;
        uint256 totalReleased;
        uint256 arbitratorFeeBps;
        uint256 milestoneCount;
        uint256 highQualityCount;
        EscrowStatus status;
        mapping(uint256 => Milestone) milestones;
    }

    struct SupplierMetrics {
        uint256 totalDeliveries;
        uint256 totalApprovals;
        uint256 totalPenalties;
        uint256 cumulativeQualityScore;
    }

    // --- State Variables ---
    address public protocolAdmin;
    uint256 public escrowCounter;
    
    mapping(uint256 => Escrow) public escrows;
    mapping(address => SupplierMetrics) public supplierProfiles;
    mapping(address => uint256) public arbitratorBalances;

    // --- Events ---
    event EscrowCreated(uint256 indexed id, address indexed buyer, address indexed supplier);
    event EscrowFunded(uint256 indexed id, uint256 amount);
    event MilestoneAdded(uint256 indexed escrowId, uint256 milestoneId, uint256 weight);
    event DeliverySubmitted(uint256 indexed escrowId, uint256 milestoneId);
    event DeliveryApproved(uint256 indexed escrowId, uint256 milestoneId, uint256 payout);
    event DisputeRaised(uint256 indexed escrowId, uint256 milestoneId);
    event DisputeResolved(uint256 indexed escrowId, uint256 milestoneId, bool favorSupplier);
    event MetricsUpdated(address indexed supplier, uint256 newTotal);

    // --- Modifiers ---
    modifier onlyBuyer(uint256 escrowId) {
        require(msg.sender == escrows[escrowId].buyer, "Not buyer");
        _;
    }

    modifier onlySupplier(uint256 escrowId) {
        require(msg.sender == escrows[escrowId].supplier, "Not supplier");
        _;
    }

    modifier onlyArbitrator(uint256 escrowId) {
        require(msg.sender == escrows[escrowId].arbitrator, "Not arbitrator");
        _;
    }

    modifier validEscrow(uint256 escrowId) {
        require(escrows[escrowId].buyer != address(0), "Escrow does not exist");
        _;
    }

    constructor() {
        protocolAdmin = msg.sender;
    }

    /**
     * @notice Creates a new supply chain escrow agreement.
     * @param supplier The entity providing the goods/services.
     * @param arbitrator The trusted third party for disputes.
     * @param feeBps The percentage fee for the arbitrator if disputes arise.
     */
    function createEscrow(address supplier, address arbitrator, uint256 feeBps) external returns (uint256) {
        require(supplier != address(0) && arbitrator != address(0), "Invalid addresses");
        require(feeBps <= 1000, "Arbitrator fee exceeds 10%");

        escrowCounter++;
        uint256 newId = escrowCounter;

        Escrow storage e = escrows[newId];
        e.id = newId;
        e.buyer = msg.sender;
        e.supplier = supplier;
        e.arbitrator = arbitrator;
        e.arbitratorFeeBps = feeBps;
        e.status = EscrowStatus.PENDING;

        emit EscrowCreated(newId, msg.sender, supplier);
        return newId;
    }

    /**
     * @notice Adds multiple delivery milestones to a pending escrow.
     * @param escrowId The target escrow ID.
     * @param weights Array of basis point weights (must sum to 10000 across all).
     * @param amounts Array of fiat/token base amounts.
     * @param dueDates Array of timestamps.
     */
    function addMilestones(
        uint256 escrowId, 
        uint256[] calldata weights, 
        uint256[] calldata amounts, 
        uint64[] calldata dueDates
    ) external onlyBuyer(escrowId) validEscrow(escrowId) {
        Escrow storage e = escrows[escrowId];
        require(e.status == EscrowStatus.PENDING, "Escrow no longer pending");
        require(weights.length == amounts.length && amounts.length == dueDates.length, "Array length mismatch");
        require(weights.length > 0 && weights.length <= 50, "Batch size out of bounds");

        for (uint256 i = 0; i < weights.length; i++) {
            require(weights[i] > 0, "Weight cannot be zero");
            require(amounts[i] > 0, "Amount cannot be zero");
            
            uint256 mId = e.milestoneCount;
            
            e.milestones[mId] = Milestone({
                id: mId,
                weight: weights[i],
                amount: amounts[i],
                dueDate: dueDates[i],
                deliveredAt: 0,
                qualityScore: 0,
                payout: 0,
                status: MilestoneStatus.PENDING
            });
            
            e.totalDeposit += amounts[i];
            e.milestoneCount++;
            
            emit MilestoneAdded(escrowId, mId, weights[i]);
        }
    }

    /**
     * @notice Simulates funding the escrow (locking the deposit).
     */
    function fundEscrow(uint256 escrowId) external onlyBuyer(escrowId) validEscrow(escrowId) {
        Escrow storage e = escrows[escrowId];
        require(e.status == EscrowStatus.PENDING, "Cannot fund now");
        require(e.totalDeposit <= 1e24, "Deposit exceeds protocol max limit");

        e.balance = e.totalDeposit;
        e.status = EscrowStatus.ACTIVE;

        emit EscrowFunded(escrowId, e.totalDeposit);
    }

    /**
     * @notice Supplier submits a milestone delivery for review.
     * @param escrowId The escrow ID.
     * @param milestoneId The ID of the specific milestone.
     */
    function submitDelivery(uint256 escrowId, uint256 milestoneId) external onlySupplier(escrowId) validEscrow(escrowId) {
        Escrow storage e = escrows[escrowId];
        require(e.status == EscrowStatus.ACTIVE, "Escrow not active");
        
        // BUG 2: Off-by-one array/mapping length bound.
        // It uses `<=` instead of `<`. Because it's a mapping, accessing `e.milestoneCount` 
        // does not revert. It returns an uninitialized Milestone struct (status=PENDING, weight=0).
        // The supplier can submit a phantom delivery.
        require(milestoneId <= e.milestoneCount, "Invalid milestone ID");

        Milestone storage m = e.milestones[milestoneId];
        require(m.status == MilestoneStatus.PENDING, "Milestone not pending");

        m.status = MilestoneStatus.DELIVERED;
        m.deliveredAt = uint64(block.timestamp);

        SupplierMetrics storage metrics = supplierProfiles[e.supplier];
        metrics.totalDeliveries++;

        emit DeliverySubmitted(escrowId, milestoneId);
    }

    /**
     * @notice Approves a delivery, applies penalties, and releases funds.
     * @dev Demonstrates internal helper call chaining and deep state updates.
     */
    function approveDelivery(uint256 escrowId, uint256 milestoneId, uint256 qualityScore) external onlyBuyer(escrowId) validEscrow(escrowId) {
        require(qualityScore <= 100, "Max score is 100");
        Escrow storage e = escrows[escrowId];
        Milestone storage m = e.milestones[milestoneId];
        
        require(m.status == MilestoneStatus.DELIVERED, "Not delivered");

        // RED HERRING 2: Inclusive Threshold per Documented Spec
        // The spec states: "Scores of exactly 80 or above are considered high quality".
        // Naive tools flag this exact equality boundary `>=` as an off-by-one error.
        if (qualityScore >= 80) {
            e.highQualityCount++;
        }

        m.qualityScore = qualityScore;
        m.status = MilestoneStatus.APPROVED;

        // Internal call 1: Calculate exact payout
        uint256 payout = _calculateMilestonePayout(m.amount, m.dueDate, m.deliveredAt, qualityScore);
        m.payout = payout;

        // State update 1: Add to released total
        e.totalReleased += payout;

        // BUG 4: Unscaled/Base subtraction desync breaking running totals.
        // The balance must track the remaining actual funds. By subtracting `m.amount` (the base)
        // instead of the `payout` (which is often smaller due to penalties), the remaining balance
        // mathematically desyncs from `totalDeposit - totalReleased`. The difference is permanently trapped.
        e.balance -= m.amount;

        // Internal call 2: Update global profiles
        _updateGlobalSupplierMetrics(e.supplier, qualityScore, (m.amount - payout));

        emit DeliveryApproved(escrowId, milestoneId, payout);
    }

    /**
     * @notice Internal helper to sequentially apply multi-variable penalties.
     */
    function _calculateMilestonePayout(
        uint256 basePayout, 
        uint64 dueDate, 
        uint64 deliveredAt, 
        uint256 qualityScore
    ) internal pure returns (uint256) {
        uint256 adjustedPayout = basePayout;

        // Penalty 1: Quality drop
        if (qualityScore < 50) {
            uint256 qualityPenalty = (basePayout * 20) / 100; // 20% penalty
            adjustedPayout = basePayout - qualityPenalty;
        }

        // Penalty 2: Late delivery
        if (deliveredAt > dueDate) {
            uint256 delayPenalty = (basePayout * 10) / 100; // 10% penalty
            
            // BUG 1: Stale local variable. 
            // Assigns `basePayout - delayPenalty` instead of `adjustedPayout - delayPenalty`.
            // If the delivery is both late AND poor quality, the quality penalty is entirely erased.
            adjustedPayout = basePayout - delayPenalty;
        }

        return adjustedPayout;
    }

    /**
     * @notice Internal helper to update global metrics mapping.
     */
    function _updateGlobalSupplierMetrics(address supplier, uint256 qualityScore, uint256 penaltyAmount) internal {
        SupplierMetrics storage metrics = supplierProfiles[supplier];
        metrics.totalApprovals++;
        metrics.totalPenalties += penaltyAmount;
        metrics.cumulativeQualityScore += qualityScore;
        
        emit MetricsUpdated(supplier, metrics.totalApprovals);
    }

    /**
     * @notice Computes a time-and-weight complexity bound for analytical purposes.
     */
    function getMilestoneComplexityBound(uint256 escrowId, uint256 milestoneId) external view validEscrow(escrowId) returns (uint256) {
        Escrow storage e = escrows[escrowId];
        Milestone storage m = e.milestones[milestoneId];
        
        // RED HERRING 1: Safe Multi-Variable Unchecked Math
        // Naive tools flag this as a critical multiplication overflow because 3 variables are multiplied.
        // However, prior boundaries mathematically bound this: totalDeposit <= 1e24, weight <= 10000.
        // 1e24 * 10000 * 100 = 1e30, which effortlessly fits inside a 256-bit uint.
        unchecked {
            uint256 maxPotentialImpact = e.totalDeposit * m.weight * 100;
            return maxPotentialImpact;
        }
    }

    /**
     * @notice Evaluates the overall performance rating of the supplier for an escrow.
     * @return weightedAverage The average quality score normalized across active weights.
     */
    function calculateTotalWeightedProgress(uint256 escrowId) external view validEscrow(escrowId) returns (uint256) {
        Escrow storage e = escrows[escrowId];
        
        uint256 totalWeightedScore = 0;
        uint256 activeMilestonesCount = 0;

        for (uint256 i = 0; i < e.milestoneCount; i++) {
            if (e.milestones[i].status == MilestoneStatus.APPROVED) {
                totalWeightedScore += e.milestones[i].qualityScore * e.milestones[i].weight;
                activeMilestonesCount++;
            }
        }

        if (activeMilestonesCount == 0) return 0;

        // BUG 3: Incorrect Weighted-Average Denominator
        // The totalWeightedScore is accumulated using basis point weights (e.g., score * 10000).
        // To get the true average, it must be divided by the sum of those weights (or 10000).
        // Dividing by the raw `activeMilestonesCount` (e.g., 1 or 2) leaves the value inflated 
        // by a factor of 10,000, drastically blowing past the 100-point maximum.
        return totalWeightedScore / activeMilestonesCount;
    }

    /**
     * @notice Distributes owed fees to the arbitrator for disputed milestones.
     * @dev Loops through milestones and applies sequential deductions.
     */
    function distributeArbitratorFees(uint256 escrowId) external onlyArbitrator(escrowId) validEscrow(escrowId) {
        Escrow storage e = escrows[escrowId];
        require(e.status == EscrowStatus.IN_DISPUTE || e.status == EscrowStatus.ACTIVE, "Invalid state");

        uint256 totalFeePaid = 0;

        // RED HERRING 3: Storage Pointer Loop Mutation
        // Naive tools flag `e.balance -= fee` inside a loop as operating on a stale cache or missing 
        // a storage re-write. Because `e` is a storage pointer, the mutation happens atomically in state.
        for (uint256 i = 0; i < e.milestoneCount; i++) {
            Milestone storage m = e.milestones[i];
            
            if (m.status == MilestoneStatus.DISPUTED) {
                uint256 fee = (m.amount * e.arbitratorFeeBps) / 10000;
                require(e.balance >= fee, "Insufficient balance for fees");
                
                e.balance -= fee;
                totalFeePaid += fee;
                
                // Reset status to prevent double-charging
                m.status = MilestoneStatus.CANCELLED;
            }
        }

        arbitratorBalances[e.arbitrator] += totalFeePaid;
    }

    /**
     * @notice Refunds remaining escrow balance to the buyer if conditions are unmet.
     */
    function refundRemainingToBuyer(uint256 escrowId) external onlyBuyer(escrowId) validEscrow(escrowId) {
        Escrow storage e = escrows[escrowId];
        require(e.status == EscrowStatus.ACTIVE || e.status == EscrowStatus.IN_DISPUTE, "Cannot refund");
        
        uint256 remaining = e.balance;
        require(remaining > 0, "No balance to refund");

        e.balance = 0;
        e.status = EscrowStatus.CANCELLED;
        
        // Simulated refund execution
    }

    /**
     * @notice Arbitrator steps in to freeze a milestone.
     */
    function raiseDispute(uint256 escrowId, uint256 milestoneId) external onlyArbitrator(escrowId) validEscrow(escrowId) {
        Escrow storage e = escrows[escrowId];
        require(milestoneId < e.milestoneCount, "Invalid milestone");
        
        Milestone storage m = e.milestones[milestoneId];
        require(m.status == MilestoneStatus.DELIVERED, "Can only dispute delivered");
        
        m.status = MilestoneStatus.DISPUTED;
        e.status = EscrowStatus.IN_DISPUTE;
        
        emit DisputeRaised(escrowId, milestoneId);
    }
}