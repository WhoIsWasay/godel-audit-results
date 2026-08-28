// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "src/YearnV2YieldSource_bf165d.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
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
        require(allowed >= amount, "MockERC20: insufficient allowance");
        if (allowed != type(uint256).max) {
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
        uint256 fromBalance = balanceOf[from];
        require(fromBalance >= amount, "MockERC20: insufficient balance");
        balanceOf[from] = fromBalance - amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract MockYearnVault {
    MockERC20 private _token;
    uint256 private _pricePerShare = 1e18;
    uint256 private _activation = 1;
    string private _apiVersion = "0.4.3";
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(MockERC20 token_) {
        _token = token_;
    }

    function token() external view returns (address) {
        return address(_token);
    }

    function pricePerShare() external view returns (uint256) {
        return _pricePerShare;
    }

    function decimals() external pure returns (uint256) {
        return 18;
    }

    function apiVersion() external view returns (string memory) {
        return _apiVersion;
    }

    function activation() external view returns (uint256) {
        return _activation;
    }

    function deposit() external returns (uint256) {
        uint256 amount = _token.balanceOf(msg.sender);
        require(amount > 0, "MockYearnVault: zero deposit");
        _token.transferFrom(msg.sender, address(this), amount);
        uint256 shares = (amount * 1e18) / _pricePerShare;
        _mint(msg.sender, shares);
        return shares;
    }

    function withdraw(uint256 maxShares) external returns (uint256) {
        uint256 amount = (maxShares * _pricePerShare) / 1e18;
        _burn(msg.sender, maxShares);
        _token.transfer(msg.sender, amount);
        return amount;
    }

    function withdraw(
        uint256 maxShares,
        address recipient,
        uint256
    ) external returns (uint256) {
        uint256 amount = (maxShares * _pricePerShare) / 1e18;
        _burn(msg.sender, maxShares);
        _token.transfer(recipient, amount);
        return amount;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "MockYearnVault: insufficient allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        require(balanceOf[from] >= value, "MockYearnVault: insufficient share balance");
        balanceOf[from] -= value;
        totalSupply -= value;
        emit Transfer(from, address(0), value);
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal {
        require(balanceOf[from] >= value, "MockYearnVault: insufficient share balance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}

contract YearnV2YieldSourceTest is Test {
    MockERC20 private token;
    MockYearnVault private vault;
    YearnV2YieldSource private yieldSource;

    address private user = address(0xA11CE);
    address private donor = address(0xB0B);

    function setUp() public {
        token = new MockERC20();
        vault = new MockYearnVault(token);
        yieldSource = new YearnV2YieldSource();

        yieldSource.initialize(
            IYVaultV2(address(vault)),
            IERC20Upgradeable(address(token))
        );

        token.mint(user, 1_000_000 ether);
        token.mint(donor, 1_000_000 ether);

        vm.startPrank(user);
        token.approve(address(yieldSource), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(donor);
        token.approve(address(yieldSource), type(uint256).max);
        vm.stopPrank();
    }

    function test_withdrawFromVault_balanceDifferenceUnderflow() external {
        uint256 depositAmount = 655359;
        uint256 donationAmount = 999934;
        uint256 withdrawAmount = 655359; // receivedAmount from the trace

        vm.prank(user);
        yieldSource.supplyTokenTo(depositAmount, user);

        // Creates previousBalance = 999934 before the vault withdrawal.
        vm.prank(donor);
        token.transfer(address(yieldSource), donationAmount);

        uint256 userBalanceBefore = token.balanceOf(user);

        vm.prank(user);
        try yieldSource.redeemToken(withdrawAmount) returns (uint256 received) {
            assertEq(
                received,
                withdrawAmount,
                "redeemToken should return the requested token amount"
            );
            assertEq(
                token.balanceOf(user),
                userBalanceBefore + withdrawAmount,
                "user token balance should increase by the redeemed amount"
            );
        } catch {
            assertTrue(false, "safe invariant violated: redeemToken must not revert");
        }
    }
}