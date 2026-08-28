// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "src/YearnV2YieldSource_06f971.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract MockToken {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 6;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allowance");
            _allowances[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(_balances[from] >= amount, "balance");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract MockYearnVault {
    address private _token;
    uint256 private _pricePerShare;
    uint256 private _decimals;
    string private _apiVersion;
    uint256 private _activation;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        address token_,
        string memory apiVersion_,
        uint256 activation_,
        uint256 decimals_,
        uint256 pricePerShare_
    ) {
        _token = token_;
        _apiVersion = apiVersion_;
        _activation = activation_;
        _decimals = decimals_;
        _pricePerShare = pricePerShare_;
    }

    function token() external view returns (address) {
        return _token;
    }

    function pricePerShare() external view returns (uint256) {
        return _pricePerShare;
    }

    function decimals() external view returns (uint256) {
        return _decimals;
    }

    function apiVersion() external view returns (string memory) {
        return _apiVersion;
    }

    function activation() external view returns (uint256) {
        return _activation;
    }

    function setPricePerShare(uint256 newPrice) external {
        _pricePerShare = newPrice;
    }

    function deposit() external returns (uint256) {
        uint256 amount = IERC20Upgradeable(_token).balanceOf(msg.sender);
        IERC20Upgradeable(_token).transferFrom(msg.sender, address(this), amount);
        uint256 shares = (amount * (10 ** _decimals)) / _pricePerShare;
        _mint(msg.sender, shares);
        return shares;
    }

    function withdraw(uint256 maxShares) external returns (uint256) {
        return _withdraw(msg.sender, maxShares, msg.sender);
    }

    function withdraw(uint256 maxShares, address recipient, uint256) external returns (uint256) {
        return _withdraw(msg.sender, maxShares, recipient);
    }

    function _withdraw(address account, uint256 shares, address recipient) internal returns (uint256) {
        require(_balances[account] >= shares, "shares");
        _balances[account] -= shares;
        _totalSupply -= shares;
        uint256 amount = (shares * _pricePerShare) / (10 ** _decimals);
        IERC20Upgradeable(_token).transfer(recipient, amount);
        emit Transfer(account, address(0), shares);
        return amount;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = _allowances[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allowance");
            _allowances[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(_balances[from] >= amount, "balance");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}

contract YearnV2YieldSource_ZeroSharesTest is Test {
    MockToken internal token;
    MockYearnVault internal vault;
    YearnV2YieldSource internal yieldSource;

    address internal alice = address(0xA11CE);
    address internal attacker = address(0xA77A);
    address internal donor = address(0xD0D0);

    function setUp() public {
        token = new MockToken();
        vault = new MockYearnVault(address(token), "0.4.3", 1, 6, 1e6);
        yieldSource = new YearnV2YieldSource();
        yieldSource.initialize(IYVaultV2(address(vault)), IERC20Upgradeable(address(token)));

        token.mint(alice, 262144);
        token.mint(attacker, 3);
        token.mint(donor, 1);

        vm.startPrank(alice);
        token.approve(address(yieldSource), type(uint256).max);
        yieldSource.supplyTokenTo(262144, alice);
        vm.stopPrank();

        vault.setPricePerShare(3500000);

        vm.prank(donor);
        token.transfer(address(yieldSource), 1);
    }

    function test_supplyTokenTo_smallDepositShouldNotMintZeroShares() public {
        uint256 vaultShares = vault.balanceOf(address(yieldSource));
        uint256 tokenBalance = token.balanceOf(address(yieldSource));
        uint256 totalTokens = tokenBalance + (vaultShares * vault.pricePerShare()) / (10 ** vault.decimals());

        assertEq(yieldSource.totalSupply(), 262144);
        assertEq(totalTokens, 917505);

        vm.startPrank(attacker);
        token.approve(address(yieldSource), 3);
        yieldSource.supplyTokenTo(3, attacker);
        vm.stopPrank();

        uint256 attackerAssets = yieldSource.balanceOfToken(attacker);
        assertGe(attackerAssets, 3, "depositor should retain at least the supplied token balance");
    }
}