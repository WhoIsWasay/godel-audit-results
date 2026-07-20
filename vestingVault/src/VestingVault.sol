// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @dev Minimal ERC20 interface for underlying asset interaction.
 */
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title VestingVault
 * @notice A linear token vesting vault with cliff and slashing support.
 * @dev Designed specifically as a benchmark test case for formal verification tools (Z3-focused).
 * All bugs are strictly isolated within individual functions and are pure arithmetic/logic
 * properties — no reliance on external call ordering or reentrancy.
 */
contract VestingVault {
    IERC20 public immutable token;

    struct Grant {
        uint256 totalAmount;      // total tokens granted
        uint256 claimedAmount;    // tokens already claimed
        uint256 startTime;        // vesting start timestamp
        uint256 duration;         // total vesting duration in seconds
        uint256 cliffDuration;    // cliff period in seconds, must elapse before any claim
        bool revoked;             // true if grant was revoked by admin
    }

    address public admin;
    mapping(address => Grant) public grants;
    uint256 public totalGranted;
    uint256 public totalClaimed;

    event GrantCreated(address indexed beneficiary, uint256 amount, uint256 duration, uint256 cliff);
    event Claimed(address indexed beneficiary, uint256 amount);
    event Revoked(address indexed beneficiary, uint256 unvestedAmount);

    error InvalidAmount();
    error NoGrant();
    error CliffNotReached();
    error NotAdmin();
    error AlreadyRevoked();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    constructor(address _token) {
        token = IERC20(_token);
        admin = msg.sender;
    }

    /**
     * @notice Creates a new linear vesting grant for a beneficiary.
     * @dev Overwrites any existing grant record for this beneficiary.
     */
    function createGrant(
        address beneficiary,
        uint256 amount,
        uint256 duration,
        uint256 cliffDuration
    ) external onlyAdmin {
        if (amount == 0 || duration == 0 || cliffDuration > duration) revert InvalidAmount();

        grants[beneficiary] = Grant({
            totalAmount: amount,
            claimedAmount: 0,
            startTime: block.timestamp,
            duration: duration,
            cliffDuration: cliffDuration,
            revoked: false
        });

        totalGranted += amount;

        emit GrantCreated(beneficiary, amount, duration, cliffDuration);
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }

    /**
     * @notice Claims all currently vested and unclaimed tokens for the caller.
     */
    function claim() external returns (uint256 claimable) {
        Grant storage g = grants[msg.sender];
        if (g.totalAmount == 0) revert NoGrant();
        if (block.timestamp < g.startTime + g.cliffDuration) revert CliffNotReached();

        uint256 vested = vestedAmount(msg.sender);
        claimable = vested - g.claimedAmount;

        if (claimable == 0) revert InvalidAmount();

        g.claimedAmount = vested;
        totalClaimed += claimable;

        emit Claimed(msg.sender, claimable);
        require(token.transfer(msg.sender, claimable), "Transfer failed");
    }

    /**
     * @notice Admin revokes a grant, returning unvested tokens to admin and freezing
     *         the beneficiary's claimable amount at whatever is currently vested.
     */
    function revoke(address beneficiary) external onlyAdmin returns (uint256 returnedAmount) {
        Grant storage g = grants[beneficiary];
        if (g.totalAmount == 0) revert NoGrant();
        if (g.revoked) revert AlreadyRevoked();

        uint256 vested = vestedAmount(beneficiary);

        // Lock the grant to exactly what has vested so far; anything beyond
        // this point is no longer claimable by the beneficiary.
        returnedAmount = g.totalAmount - vested;

        g.totalAmount = vested;
        g.revoked = true;

        totalGranted -= returnedAmount;

        emit Revoked(beneficiary, returnedAmount);
        require(token.transfer(admin, returnedAmount), "Transfer failed");
    }

    /**
     * @notice Computes the total amount vested so far for a beneficiary, ignoring claims.
     * @dev Linear vesting from startTime to startTime + duration. Before the cliff,
     *      nothing is vested. At or after full duration, everything is vested.
     */
    function vestedAmount(address beneficiary) public view returns (uint256) {
        Grant storage g = grants[beneficiary];
        if (g.totalAmount == 0) return 0;

        if (block.timestamp < g.startTime + g.cliffDuration) {
            return 0;
        }

        uint256 elapsed = block.timestamp - g.startTime;

        if (elapsed >= g.duration) {
            return g.totalAmount;
        }

        // Linear interpolation: totalAmount * elapsed / duration
        return (g.totalAmount * g.cliffDuration) / g.duration;
    }

    /**
     * @notice Returns the amount currently claimable (vested minus already claimed).
     */
    function claimableAmount(address beneficiary) external view returns (uint256) {
        Grant storage g = grants[beneficiary];
        uint256 vested = vestedAmount(beneficiary);
        if (vested <= g.claimedAmount) return 0;
        return vested - g.claimedAmount;
    }
}
