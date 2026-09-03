// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/MiniVault_c44e5a.sol";

// reasoning: emergencyWithdraw burns shares but only reduces totalAssets by the net payout,
// leaving the penalty behind. If the last shareholder emergency-withdraws all shares,
// totalSupply becomes zero while totalAssets remains positive. A brand-new depositor
// (solver counterexample: new=1) can then deposit 1 wei and withdraw the orphaned balance.
// The invariant below asserts that zero outstanding shares implies zero recorded assets.

contract MockERC20 {
    string public name = "MockERC20";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "MockERC20: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

contract VaultHandler {
    MiniVault public vault;
    MockERC20 public token;

    constructor(address _vault, address _token) {
        vault = MiniVault(_vault);
        token = MockERC20(_token);
    }

    function deposit(uint256 amount) external {
        amount = (amount % 1_000_000e18) + 1_000;
        token.mint(address(this), amount);
        token.approve(address(vault), amount);
        vault.deposit(amount);
    }

    function emergencyWithdrawAll() external {
        uint256 shares = vault.balances(address(this));
        if (shares > 0) {
            vault.emergencyWithdraw(shares);
        }
    }
}

contract PropertyTest is Test {
    MiniVault public vault;
    MockERC20 public token;
    VaultHandler public handler;

    uint256 internal constant INITIAL_BALANCE = 1_000_000e18;

    function setUp() public {
        token = new MockERC20();
        vault = new MiniVault(address(token));
        handler = new VaultHandler(address(vault), address(token));

        token.mint(address(handler), INITIAL_BALANCE);
        targetContract(address(handler));
    }

    function invariant_property_verification() public {
        if (vault.totalSupply() == 0) {
            assertEq(vault.totalAssets(), 0, "vault holds orphaned assets while no shares are outstanding");
        }
    }

    function test_new_depositor_can_claim_orphaned_penalty() public {
        address alice = address(0xA11CE);
        address bob = address(0xB0B);

        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);

        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);

        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        vault.deposit(depositAmount);

        vm.prank(alice);
        vault.emergencyWithdraw(vault.totalSupply());

        assertEq(vault.totalSupply(), 0);
        assertGt(vault.totalAssets(), 0, "emergency withdrawal left orphaned assets");

        uint256 bobBalanceBefore = token.balanceOf(bob);

        // Solver trace counterexample: a brand-new depositor uses new=1.
        vm.prank(bob);
        vault.deposit(1);

        assertEq(vault.balances(bob), 1);

        vm.prank(bob);
        vault.withdraw(vault.totalAssets());

        assertLe(
            token.balanceOf(bob) - bobBalanceBefore,
            1,
            "a 1 wei first deposit must not withdraw the orphaned penalty"
        );
    }
}