// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IERC20
 * @notice Standard minimal ERC20 interface required for the pool.
 */
interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title DiscountLiquidityPool
 * @notice A simple constant-product-style liquidity pool that offers dynamic 
 * withdrawal fee discounts for larger liquidity removals. 
 * @dev Designed specifically for formal verification benchmarking. 
 * All cross-contract calls and reentrancy are out of scope.
 */
contract DiscountLiquidityPool {
    IERC20 public immutable tokenA;
    IERC20 public immutable tokenB;

    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public totalLpSupply;

    mapping(address => uint256) public lpBalances;

    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB, uint256 lpMinted);
    event LiquidityRemoved(address indexed provider, uint256 lpAmount, uint256 amountA, uint256 amountB, uint256 feeA);

    /**
     * @notice Initializes the liquidity pool with two tokens.
     */
    constructor(address _tokenA, address _tokenB) {
        require(_tokenA != address(0) && _tokenB != address(0), "Invalid tokens");
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    /**
     * @notice Adds liquidity to the pool.
     * @param amountA The amount of Token A to add.
     * @param amountB The amount of Token B to add.
     */
    function addLiquidity(uint256 amountA, uint256 amountB) external {
        require(amountA > 0 && amountB > 0, "Zero amounts not allowed");
        
        // Cap inputs to prevent runaway scaling in the pool 
        require(amountA <= type(uint128).max, "Amount A exceeds bounds");
        require(amountB <= type(uint128).max, "Amount B exceeds bounds");

        uint256 lpToMint;

        unchecked {
            // Calculate LP tokens to mint based on a simple additive formula for this benchmark pool
            uint256 total = amountA + amountB; 
            lpToMint = total / 2;
        }

        require(lpToMint > 0, "Zero LP minted");

        lpBalances[msg.sender] += lpToMint;
        totalLpSupply += lpToMint;
        
        reserveA += amountA;
        reserveB += amountB;

        require(tokenA.transferFrom(msg.sender, address(this), amountA), "Transfer A failed");
        require(tokenB.transferFrom(msg.sender, address(this), amountB), "Transfer B failed");

        emit LiquidityAdded(msg.sender, amountA, amountB, lpToMint);
    }

    /**
     * @notice Removes liquidity from the pool and applies a dynamic withdrawal fee on Token A.
     * @param lpAmount The amount of LP tokens to burn.
     */
    function removeLiquidity(uint256 lpAmount) external returns (uint256 finalAmountA, uint256 amountB) {
        require(lpAmount > 0, "Zero LP amount");
        require(lpBalances[msg.sender] >= lpAmount, "Insufficient LP balance");
        require(totalLpSupply > 0, "No liquidity in pool");

        // Calculate proportional amounts of Token A and Token B
        uint256 baseAmountA = (reserveA / totalLpSupply) * lpAmount;
        amountB = (reserveB / totalLpSupply) * lpAmount;

        // Calculate dynamic withdrawal fee based on the size of the Token A withdrawal
        uint256 feeA = calculateWithdrawalFee(baseAmountA);
        finalAmountA = baseAmountA - feeA;

        lpBalances[msg.sender] -= lpAmount;
        totalLpSupply -= lpAmount;
        
        // Fee remains in the pool's reserve
        reserveA -= finalAmountA;
        reserveB -= amountB;

        require(tokenA.transfer(msg.sender, finalAmountA), "Transfer A failed");
        require(tokenB.transfer(msg.sender, amountB), "Transfer B failed");

        emit LiquidityRemoved(msg.sender, lpAmount, finalAmountA, amountB, feeA);
        return (finalAmountA, amountB);
    }

    /**
     * @notice Calculates the withdrawal fee for Token A based on withdrawal size.
     * @dev Base fee is 500 bps (5%). The fee decreases by 100 bps for every 1000 tokens withdrawn.
     * The maximum discount is 400 bps, ensuring a minimum fee of 100 bps (1%).
     * @param withdrawAmount The base amount of Token A being withdrawn.
     * @return The absolute fee amount deducted from the withdrawal.
     */
    function calculateWithdrawalFee(uint256 withdrawAmount) public pure returns (uint256) {
        if (withdrawAmount == 0) return 0;

        uint256 feeBps = 500; 
        
        uint256 discountUnits = withdrawAmount / 1000;
        uint256 discountBps = discountUnits * 100;
        
        if (discountBps > 400) {
            discountBps = 400; 
        }
        
        feeBps -= discountBps;
        
        return (withdrawAmount * feeBps) / 10000;
    }
}