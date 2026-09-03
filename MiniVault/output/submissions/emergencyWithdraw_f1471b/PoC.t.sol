// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MiniVault} from "src/MiniVault_8a81ce.sol";

// reasoning: MiniVault.emergencyWithdraw charges a flat 500 wei penalty under the name penaltyBps.
// With a normal 1:1 deposit, withdrawing 501 shares entitles the caller to 501 assets, but the
// vault sends only 1 asset. The invariant below requires the emergency-withdraw payout to retain
// at least 95% of the entitled assets. The traced l_assets=501 is reached by a real deposit and
// a real emergencyWithdraw(501) call; the trace's a_shares=0 is unmachable because shares must be > 0.

contract MockERC20 {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        _balances[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        require(allowed >= amount, "ERC20: allowance");
        _allowances[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(_balances[from] >= amount, "ERC20: balance");
        _balances[from] -= amount;
        _balances[to] += amount;
    }
}

contract VaultHandler {
    MiniVault public immutable vault;
    MockERC20 public immutable token;

    uint256 public lastAssets;
    uint256 public lastNetAssets;
    bool public triggered;

    constructor(address vault_, address token_) {
        vault = MiniVault(vault_);
        token = MockERC20(token_);
    }

    function emergencyWithdrawPenalty() external {
        if (triggered) return;

        uint256 shares = 501;

        // With 10,000 deposited the share price is 1:1, so 501 shares are entitled to 501 assets.
        uint256 entitledAssets = (shares * vault.totalAssets()) / vault.totalSupply();

        uint256 balanceBefore = token.balanceOf(address(this));
        vault.emergencyWithdraw(shares);
        uint256 receivedAssets = token.balanceOf(address(this)) - balanceBefore;

        lastAssets = entitledAssets;
        lastNetAssets = receivedAssets;
        triggered = true;
    }
}

contract PropertyTest is Test {
    MiniVault private vault;
    MockERC20 private token;
    VaultHandler private handler;

    function setUp() public {
        token = new MockERC20();
        vault = new MiniVault(address(token));
        handler = new VaultHandler(address(vault), address(token));

        token.mint(address(handler), 10000);

        vm.prank(address(handler));
        token.approve(address(vault), type(uint256).max);

        vm.prank(address(handler));
        vault.deposit(10000);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = VaultHandler.emergencyWithdrawPenalty.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_property_verification() public view {
        if (handler.triggered()) {
            uint256 entitledAssets = handler.lastAssets();
            uint256 receivedAssets = handler.lastNetAssets();
            uint256 minReceived = (entitledAssets * 9500) / 10000;

            require(receivedAssets >= minReceived, "emergencyWithdraw flat 500 wei penalty exceeds 5%");
        }
    }
}