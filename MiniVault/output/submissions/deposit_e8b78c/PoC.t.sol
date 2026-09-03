// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

// reasoning: The solver witness is (assets=1, totalSupply=1, totalAssets=1000).
// This property test reaches that exact state through public MiniVault calls only,
// then asserts that a positive deposit into an existing vault must not mint zero
// shares. If the deposit mints zero shares, the depositor's assets are donated to
// existing shareholders and the share accounting invariant is broken.

import "forge-std/Test.sol";
import "src/MiniVault_263b3a.sol";

contract MockERC20 {
    string public constant name = "Mock Token";
    string public constant symbol = "MOCK";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allowance exceeded");
            allowance[from][msg.sender] = allowed - amount;
        }

        require(balanceOf[from] >= amount, "insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract PropertyTest is Test {
    MiniVault internal vault;
    MockERC20 internal token;

    address internal alice;
    address internal bob;
    address internal carol;

    function setUp() public {
        token = new MockERC20();
        vault = new MiniVault(address(token));

        alice = vm.addr(0xA11CE);
        bob = vm.addr(0xB0B);
        carol = vm.addr(0xC0FFEE);

        token.mint(alice, 100_000);
        token.mint(bob, 100_000);
        token.mint(carol, 100_000);

        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);

        vm.prank(carol);
        token.approve(address(vault), type(uint256).max);

        targetContract(address(vault));
    }

    function invariant_property_verification() public {
        // Build a real, non-forced position: totalSupply = totalAssets = 1000.
        vm.startPrank(alice);
        vault.deposit(1000);
        vault.emergencyWithdraw(999);
        vm.stopPrank();

        // After the emergency withdrawal, the fixed 500-unit penalty leaves:
        // totalSupply = 1, totalAssets = 501.
        assertEq(vault.totalSupply(), 1);
        assertEq(vault.totalAssets(), 501);

        // A second user deposits just below the current 501 asset/share price.
        // The share formula rounds down to zero, yet the tokens are accepted.
        vm.prank(bob);
        vault.deposit(499);

        assertEq(vault.balances(bob), 0);
        assertEq(vault.totalSupply(), 1);
        assertEq(vault.totalAssets(), 1000);

        // This is now the exact concrete witness state from the solver:
        // assets = 1, totalSupply = 1, totalAssets = 1000.
        uint256 witnessSupply = 1;
        uint256 witnessTotalAssets = 1000;
        uint256 witnessDeposit = 1;

        assertEq(vault.totalSupply(), witnessSupply);
        assertEq(vault.totalAssets(), witnessTotalAssets);

        uint256 supplyBefore = vault.totalSupply();

        vm.prank(carol);
        vault.deposit(witnessDeposit);

        // A positive deposit must increase totalSupply. In the vulnerable
        // implementation this deposit mints zero shares and leaves totalSupply
        // at 1 while totalAssets grows to 1001.
        assertGt(
            vault.totalSupply(),
            supplyBefore,
            "positive deposit into an existing vault must mint positive shares"
        );
    }
}