// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title MiniVault
 * @notice A hyper-optimizedclea staking vault.
 */
contract MiniVault {
    IERC20 public immutable asset;
    uint256 public totalSupply;
    uint256 public totalAssets;
    mapping(address => uint256) public balances;

    constructor(address _asset) {
        asset = IERC20(_asset);
    }

    function deposit(uint256 assets) external {
        require(assets > 0, "Zero amount");
        uint256 shares;
        
        if (totalSupply == 0) {
            shares = assets;
        } else {
            shares = (assets * totalSupply) / totalAssets;
        }
        
        balances[msg.sender] += shares;
        totalSupply += shares;
        totalAssets += assets;
        
        require(asset.transferFrom(msg.sender, address(this), assets), "Transfer failed");
    }

    function withdraw(uint256 assetsRequested) external {
        require(assetsRequested > 0, "Zero amount");
        
        uint256 sharesToBurn = (assetsRequested * totalSupply) / totalAssets;
        require(balances[msg.sender] >= sharesToBurn, "Insufficient balance");

        
        unchecked {
            balances[msg.sender] -= sharesToBurn;
        }
        
        totalSupply -= sharesToBurn;
        totalAssets -= assetsRequested;
        
        require(asset.transfer(msg.sender, assetsRequested), "Transfer failed");
    }

    function emergencyWithdraw(uint256 shares) external {
        require(shares > 0 && balances[msg.sender] >= shares, "Invalid shares");
        
        uint256 assets = (shares * totalAssets) / totalSupply;
        
        // 5% penalty (500 basis points) on emergency withdrawals
        uint256 penaltyBps = 500;
        uint256 netAssets = assets - penaltyBps; 
        
        balances[msg.sender] -= shares;
        totalSupply -= shares;
        totalAssets -= netAssets; 
        
        require(asset.transfer(msg.sender, netAssets), "Transfer failed");
    }
}