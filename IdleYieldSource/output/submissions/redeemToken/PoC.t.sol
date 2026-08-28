// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "src/IdleYieldSource_a6f558.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "MockERC20: allowance exceeded");
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        require(balanceOf[from] >= amount, "MockERC20: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        require(balanceOf[from] >= amount, "MockERC20: burn exceeds balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}

contract MockIdleToken is MockERC20 {
    address public immutable underlying;
    uint256 public mintPrice;
    uint256 public feePrice;

    constructor(address _underlying) MockERC20("Mock Idle Token", "idleMOCK") {
        underlying = _underlying;
    }

    function token() external view returns (address) {
        return underlying;
    }

    function tokenPriceWithFee(address) external view returns (uint256) {
        return feePrice;
    }

    function setPrices(uint256 _mintPrice, uint256 _feePrice) external {
        mintPrice = _mintPrice;
        feePrice = _feePrice;
    }

    function mintIdleToken(
        uint256 amount,
        bool,
        address
    ) external returns (uint256 minted) {
        MockERC20(underlying).transferFrom(msg.sender, address(this), amount);
        minted = (amount * 1e18) / mintPrice;
        _mint(msg.sender, minted);
    }

    function redeemIdleToken(uint256 amount) external returns (uint256 redeemed) {
        _burn(msg.sender, amount);
        redeemed = (amount * feePrice) / 1e18;
        MockERC20(underlying).transfer(msg.sender, redeemed);
    }
}

contract IdleYieldSourceTest is Test {
    MockERC20 underlying;
    MockIdleToken idleToken;
    IdleYieldSource yieldSource;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        underlying = new MockERC20("Underlying", "UND");
        idleToken = new MockIdleToken(address(underlying));
        idleToken.setPrices(1_000_000, 1_000_000);

        yieldSource = new IdleYieldSource();
        yieldSource.initialize(address(idleToken));

        underlying.mint(alice, 100);
        underlying.mint(bob, 100);

        // Alice deposits before yield accrues.
        vm.startPrank(alice);
        underlying.approve(address(yieldSource), type(uint256).max);
        yieldSource.supplyTokenTo(1, alice);
        vm.stopPrank();

        // Yield accrues: IdleToken price doubles, but the fee-adjusted price stays the same.
        idleToken.setPrices(2_000_000, 1_000_000);

        // Bob deposits after yield accrual.
        vm.startPrank(bob);
        underlying.approve(address(yieldSource), type(uint256).max);
        yieldSource.supplyTokenTo(1, bob);
        vm.stopPrank();
    }

    function test_redeemToken_shouldNotLockExistingUserAfterFeeAccrualAndLaterDeposit() public {
        // Bob withdraws his own 1 wei deposit first.
        vm.prank(bob);
        yieldSource.redeemToken(1);

        uint256 aliceBalanceBefore = underlying.balanceOf(alice);

        // Safe invariant: Alice, who deposited before Bob, must still be able to
        // redeem her 1 wei deposit after Bob has redeemed his own 1 wei deposit.
        vm.prank(alice);
        (bool success, ) = address(yieldSource).call(
            abi.encodeWithSelector(IdleYieldSource.redeemToken.selector, uint256(1))
        );

        assertTrue(success, "Alice's withdrawal reverted after a later depositor withdrew");
        assertEq(
            underlying.balanceOf(alice),
            aliceBalanceBefore + 1,
            "Alice should receive her 1 wei deposit back"
        );
    }
}