// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "src/YearnV2YieldSource_2e0e49.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {Test} from "forge-std/Test.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "MockERC20: insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "MockERC20: insufficient allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        require(balanceOf[from] >= amount, "MockERC20: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockVault {
    MockERC20 public token;
    uint256 public pricePerShare;
    uint256 public vaultDecimals;
    string public apiVersion;
    uint256 public activation;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(
        MockERC20 _token,
        uint256 _pricePerShare,
        uint256 _vaultDecimals,
        string memory _apiVersion,
        uint256 _activation
    ) {
        token = _token;
        pricePerShare = _pricePerShare;
        vaultDecimals = _vaultDecimals;
        apiVersion = _apiVersion;
        activation = _activation;
    }

    function token() external view returns (address) {
        return address(token);
    }

    function decimals() external view returns (uint256) {
        return vaultDecimals;
    }

    function deposit() external returns (uint256) {
        uint256 amount = token.balanceOf(msg.sender);
        token.transferFrom(msg.sender, address(this), amount);
        uint256 shares = (amount * (10 ** vaultDecimals)) / pricePerShare;
        _mint(msg.sender, shares);
        return shares;
    }

    function withdraw(uint256 maxShares) external returns (uint256) {
        return _withdraw(maxShares, msg.sender, 0);
    }

    function withdraw(uint256 maxShares, address recipient, uint256 maxLoss) external returns (uint256) {
        return _withdraw(maxShares, recipient, maxLoss);
    }

    function _withdraw(uint256 shares, address recipient, uint256) internal returns (uint256) {
        uint256 userShares = balanceOf[msg.sender];
        if (shares > userShares) {
            shares = userShares;
        }
        uint256 tokens = (shares * pricePerShare) / (10 ** vaultDecimals);
        _burn(msg.sender, shares);
        token.transfer(recipient, tokens);
        return tokens;
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }
}

contract YearnV2YieldSourceRoundingTest is Test {
    MockERC20 token;
    MockVault vault;
    YearnV2YieldSource yieldSource;

    address alice = address(0xA11CE);

    function setUp() public {
        token = new MockERC20("USD Coin", "USDC", 18);
        vault = new MockVault(token, 483330, 0, "0.4.3", 1);
        yieldSource = new YearnV2YieldSource();
        yieldSource.initialize(IYVaultV2(address(vault)), IERC20Upgradeable(address(token)));
    }

    function test_zeroVaultSharesRoundingDoesNotBurnUserShares() public {
        uint256 depositAmount = 483330;
        uint256 redeemAmount = 483328;

        token.mint(alice, depositAmount);

        vm.startPrank(alice);
        token.approve(address(yieldSource), depositAmount);
        yieldSource.supplyTokenTo(depositAmount, alice);
        vm.stopPrank();

        uint256 sharesBefore = yieldSource.balanceOf(alice);
        assertGt(sharesBefore, 0);

        vm.prank(alice);
        try yieldSource.redeemToken(redeemAmount) returns (uint256 received) {
            if (received == 0) {
                assertEq(
                    yieldSource.balanceOf(alice),
                    sharesBefore,
                    "rounding _tokenToYShares to zero must not burn user shares"
                );
            }
        } catch {
            // Reverting on dust redemptions is an acceptable safe behavior.
        }
    }
}