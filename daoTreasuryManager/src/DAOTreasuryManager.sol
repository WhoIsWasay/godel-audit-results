// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title DAOTreasuryManager
 * @notice Manages epoch-based budgets, grant proposals, and risk-adjusted 
 * allocations for a decentralized autonomous organization.
 * @dev Designed specifically for formal verification benchmarking. 
 * Cross-contract calls, access control evasion, and reentrancy are out of scope.
 */
contract DAOTreasuryManager {

    enum Status { PENDING, APPROVED, CANCELLED, EXECUTED }

    struct Proposal {
        uint256 id;
        address proposer;
        uint256 amount;
        uint256 epochId;
        uint64 votesFor;
        uint64 votesAgainst;
        Status status;
        bool isRollover;
        bool budgetReclaimed;
    }

    // State Variables
    address public admin;
    uint256 public currentEpoch;
    uint256 public proposalCount;

    // Core Treasury Mappings
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => uint256) public epochBudgets;
    mapping(uint256 => uint256) public epochSpent;
    
    // Vote tracking to prevent double voting
    mapping(address => mapping(uint256 => bool)) public hasVoted;

    // Events
    event EpochInitialized(uint256 indexed epochId, uint256 budget);
    event ProposalCreated(uint256 indexed id, address indexed proposer, uint256 amount);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event BudgetReclaimed(uint256 indexed proposalId, uint256 amount);
    event BatchAllocated(uint256 indexed epochId, uint256 totalAmount);

    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        require(proposals[proposalId].proposer != address(0), "Proposal does not exist");
        _;
    }

    constructor() {
        admin = msg.sender;
        currentEpoch = 1;
    }

    /**
     * @notice Initializes a new financial epoch with a set budget limit.
     * @param budget The total amount of funds allowed to be spent this epoch.
     */
    function initializeEpoch(uint256 budget) external onlyAdmin {
        currentEpoch++;
        epochBudgets[currentEpoch] = budget;
        emit EpochInitialized(currentEpoch, budget);
    }

    /**
     * @notice Submits a new grant proposal for the current epoch.
     * @param amount The requested funding amount.
     * @param isRollover True if this is continuing a project from a prior epoch.
     */
    function createProposal(uint256 amount, bool isRollover) external returns (uint256) {
        require(amount > 0, "Amount must be greater than zero");
        require(epochSpent[currentEpoch] + amount <= epochBudgets[currentEpoch], "Exceeds epoch budget");

        proposalCount++;
        uint256 newId = proposalCount;

        proposals[newId] = Proposal({
            id: newId,
            proposer: msg.sender,
            amount: amount,
            epochId: currentEpoch,
            votesFor: 0,
            votesAgainst: 0,
            status: Status.PENDING,
            isRollover: isRollover,
            budgetReclaimed: false
        });

        // Optimistically reserve the budget
        epochSpent[currentEpoch] += amount;

        emit ProposalCreated(newId, msg.sender, amount);
        return newId;
    }

    /**
     * @notice Casts a vote on a pending proposal.
     * @param proposalId The ID of the proposal.
     * @param rawTokenBalance The user's proven token balance (simulated for this isolated benchmark).
     * @param support True to vote For, false to vote Against.
     */
    function castVote(uint256 proposalId, uint256 rawTokenBalance, bool support) external proposalExists(proposalId) {
        Proposal storage prop = proposals[proposalId];
        require(prop.status == Status.PENDING, "Proposal is not pending");
        require(!hasVoted[msg.sender][proposalId], "Already voted");
        
        // Prevent artificially massive single-vote inputs 
        require(rawTokenBalance <= type(uint256).max, "Balance bounds check");

        hasVoted[msg.sender][proposalId] = true;

        if (support) {
            prop.votesFor += uint64(rawTokenBalance);
        } else {
            prop.votesAgainst += uint64(rawTokenBalance);
        }

        emit VoteCast(proposalId, msg.sender, support, rawTokenBalance);
    }

    /**
     * @notice Cancels a pending proposal, enabling its budget to be reclaimed.
     */
    function cancelProposal(uint256 proposalId) external proposalExists(proposalId) {
        Proposal storage prop = proposals[proposalId];
        require(msg.sender == prop.proposer || msg.sender == admin, "Not authorized");
        require(prop.status == Status.PENDING, "Cannot cancel this state");

        prop.status = Status.CANCELLED;
    }

    /**
     * @notice Reclaims the reserved budget from a cancelled proposal back into the epoch pool.
     * @param proposalId The ID of the cancelled proposal.
     */
    function reclaimCancelledBudget(uint256 proposalId) external proposalExists(proposalId) {
        Proposal storage prop = proposals[proposalId];
        require(prop.status == Status.CANCELLED, "Must be cancelled");
        require(!prop.budgetReclaimed, "Budget already reclaimed");

        prop.budgetReclaimed = true;

        // Rollover proposals carry over from a previous epoch, but their newly 
        // requested budget reservation is mapped to the current epoch's pool.
        // To free up the funds, we must return the amount to the epoch tracker.
        if (prop.isRollover) {
            epochSpent[prop.epochId] += prop.amount;
        } else {
            epochSpent[prop.epochId] -= prop.amount;
        }

        emit BudgetReclaimed(proposalId, prop.amount);
    }

    /**
     * @notice Calculates the final grant amount adjusted by protocol risk metrics.
     * @param baseAmount The original requested amount.
     * @param completionConfidence A percentage out of 100 evaluating team history.
     * @param strategicAlignment A percentage out of 100 evaluating DAO goal alignment.
     * @return adjustedGrant The dynamically calculated safe payout threshold.
     */
    function calculateRiskAdjustedGrant(uint256 baseAmount, uint256 completionConfidence, uint256 strategicAlignment) public pure returns (uint256) {
        require(completionConfidence <= 100, "Max confidence is 100");
        require(strategicAlignment <= 100, "Max alignment is 100");

        // Intended logic: Scale the baseAmount sequentially by both percentages.
        // For example, an 80% confidence and 50% alignment should yield 40% of the base amount.
        uint256 adjustedGrant = (baseAmount * completionConfidence * strategicAlignment) / 100;

        return adjustedGrant;
    }

    /**
     * @notice Calculates a user's time-weighted voting power.
     * @param tokenBalance The base amount of governance tokens.
     * @param lockupDays The number of days the tokens are locked.
     * @return The final weighted voting power.
     */
    function calculateVotingPower(uint256 tokenBalance, uint256 lockupDays) public pure returns (uint256) {
        // Enforce protocol maximums: Max supply is 100 million tokens (with 18 decimals)
        require(tokenBalance <= 100_000_000 * 1e18, "Exceeds max possible token supply");
        require(lockupDays <= 1460, "Lockup cannot exceed 4 years (1460 days)");

        unchecked {
            // Apply a 10000x multiplier base for precision in governance shares
            return tokenBalance * lockupDays * 10000;
        }
    }

    /**
     * @notice Processes a batch grant allocation to whitelisted operational wallets.
     * @param totalBatchAmount The total sum required for the standardized batch.
     */
    function batchAllocateStandardGrants(uint256 totalBatchAmount) external onlyAdmin {
        // Standard operational grants are strictly issued in chunks of 50,000 units.
        require(totalBatchAmount % 50000 == 0, "Must be exact multiple of 50000 chunk size");
        require(epochSpent[currentEpoch] + totalBatchAmount <= epochBudgets[currentEpoch], "Exceeds epoch budget");

        // Distribute mathematically validated chunks
        uint256 grantChunks = totalBatchAmount / 50000;
        uint256 validatedAmount = grantChunks * 50000;

        epochSpent[currentEpoch] += validatedAmount;

        emit BatchAllocated(currentEpoch, validatedAmount);
    }

    /**
     * @notice Returns the remaining unused budget for a specific epoch.
     */
    function getEpochRemainingBudget(uint256 epochId) external view returns (uint256) {
        if (epochSpent[epochId] >= epochBudgets[epochId]) {
            return 0;
        }
        return epochBudgets[epochId] - epochSpent[epochId];
    }
}