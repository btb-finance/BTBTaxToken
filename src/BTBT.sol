// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.27;

import {ERC1363} from "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BTBTaxToken
 * @notice A bonding curve wrapped token for BTB Finance with 1% tax on transfers
 * @dev Users deposit BTB tokens to mint BTBT tokens (bonding curve price)
 *      Users can redeem BTBT tokens back to BTB tokens (bonding curve price)
 *      ALL BTBT transfers incur 1% tax (50% burned, 50% to collector)
 *      Burning BTBT increases the backing ratio, making price go up over time
 */
contract BTBTaxToken is ERC20, ERC20Burnable, Ownable, ERC1363, ERC20Permit, ReentrancyGuard {
    
    // BTB token address on mainnet
    IERC20 public immutable BTB_TOKEN;
    
    // Tax rate in basis points (100 = 1%)
    uint256 public constant TAX_RATE = 100;
    uint256 public constant BASIS_POINTS = 10000;
    
    // Tax collector address
    address public taxCollector;

    // Whitelist for tax-free transfers
    mapping(address => bool) public isExcludedFromTax;

    // Initialization flag - one time use only
    bool public initialized;

    // Initial liquidity amounts
    uint256 public constant INITIAL_BTB_AMOUNT = 1_000_000 * 1e18;
    uint256 public constant INITIAL_BTBT_AMOUNT = 1_000_000 * 1e18;

    // Events
    event Initialized(address indexed initializer, uint256 btbAmount, uint256 btbtAmount);
    event Minted(address indexed user, uint256 btbAmount, uint256 btbtAmount, uint256 price);
    event Redeemed(address indexed user, uint256 btbtAmount, uint256 btbAmount, uint256 price);
    event TaxCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event TaxCollected(address indexed from, address indexed to, uint256 amount, uint256 taxAmount, uint256 burnedAmount);
    event ExclusionUpdated(address indexed account, bool excluded);
    
    /**
     * @notice Constructor
     * @param initialOwner The initial owner of the contract
     * @param _btbToken The address of the BTB token contract
     * @param _taxCollector The address that will receive tax fees
     */
    constructor(
        address initialOwner,
        address _btbToken,
        address _taxCollector
    )
        ERC20("BTBT", "BTBT")
        Ownable(initialOwner)
        ERC20Permit("BTBT")
    {
        require(_btbToken != address(0), "Invalid BTB token address");
        require(_taxCollector != address(0), "Invalid tax collector address");

        BTB_TOKEN = IERC20(_btbToken);
        taxCollector = _taxCollector;
        
        // Exclude contract itself and tax collector from transfer tax
        isExcludedFromTax[address(this)] = true;
        isExcludedFromTax[_taxCollector] = true;
    }
    
    /**
     * @notice Initialize the contract with initial liquidity (ONE TIME ONLY)
     * @dev Seeds 1M BTB and mints 1M BTBT at 1:1 ratio to owner
     *      This saves gas on all future price calculations by removing the supply == 0 check
     */
    function initialize() external onlyOwner nonReentrant {
        require(!initialized, "Already initialized");
        require(totalSupply() == 0, "Supply must be zero");

        initialized = true;

        // Transfer initial BTB from owner to contract
        require(
            BTB_TOKEN.transferFrom(msg.sender, address(this), INITIAL_BTB_AMOUNT),
            "Initial BTB transfer failed"
        );

        // Mint initial BTBT to owner at 1:1 ratio
        _mint(msg.sender, INITIAL_BTBT_AMOUNT);

        emit Initialized(msg.sender, INITIAL_BTB_AMOUNT, INITIAL_BTBT_AMOUNT);
    }

    /**
     * @notice Get current price of BTBT in BTB (how much BTB per 1 BTBT)
     * @dev Price = BTB balance / BTBT supply
     *      GAS OPTIMIZED: No conditional checks - supply will never be zero after initialization
     * @return price Current price (with 18 decimals precision)
     */
    function getCurrentPrice() public view returns (uint256 price) {
        uint256 supply = totalSupply();
        uint256 btbBalance = BTB_TOKEN.balanceOf(address(this));

        // Price = BTB balance / BTBT supply (with 18 decimals)
        price = (btbBalance * 1e18) / supply;
    }
    
    /**
     * @notice Mint BTBT tokens by depositing BTB tokens
     * @dev BTBT amount depends on current bonding curve price
     * @param btbAmount Amount of BTB tokens to deposit
     * @return btbtAmount Amount of BTBT tokens minted
     */
    function mint(uint256 btbAmount) external nonReentrant returns (uint256 btbtAmount) {
        require(initialized, "Contract not initialized");
        require(btbAmount > 0, "Amount must be greater than 0");

        // Calculate how much BTBT to mint based on CURRENT price (before deposit)
        uint256 currentPrice = getCurrentPrice();
        btbtAmount = (btbAmount * 1e18) / currentPrice;

        require(btbtAmount > 0, "BTBT amount too small");

        // Transfer BTB tokens from user
        require(
            BTB_TOKEN.transferFrom(msg.sender, address(this), btbAmount),
            "BTB transfer failed"
        );

        // Mint BTBT tokens to user
        _mint(msg.sender, btbtAmount);

        emit Minted(msg.sender, btbAmount, btbtAmount, currentPrice);
    }
    
    /**
     * @notice Redeem BTBT tokens for BTB tokens
     * @dev BTB amount depends on current bonding curve price
     * @param btbtAmount Amount of BTBT tokens to redeem
     * @return btbAmount Amount of BTB tokens received
     */
    function redeem(uint256 btbtAmount) external nonReentrant returns (uint256 btbAmount) {
        require(initialized, "Contract not initialized");
        require(btbtAmount > 0, "Amount must be greater than 0");  // Fixed: check input parameter, not return variable
        require(balanceOf(msg.sender) >= btbtAmount, "Insufficient BTBT balance");
        
        // Calculate how much BTB to return based on current price
        uint256 currentPrice = getCurrentPrice();
        btbAmount = (btbtAmount * currentPrice) / 1e18;
        
        require(btbAmount > 0, "BTB amount too small");
        require(BTB_TOKEN.balanceOf(address(this)) >= btbAmount, "Insufficient BTB in contract");

        // Burn BTBT tokens from user
        _burn(msg.sender, btbtAmount);

        // Transfer BTB tokens to user
        require(
            BTB_TOKEN.transfer(msg.sender, btbAmount),
            "BTB transfer failed"
        );
        
        emit Redeemed(msg.sender, btbtAmount, btbAmount, currentPrice);
    }
    
    /**
     * @notice Override transfer to apply 1% tax (50% burned, 50% to collector)
     * @dev Recipient receives 99% of amount, 0.5% burned, 0.5% to collector
     */
    function transfer(address to, uint256 amount) public virtual override(ERC20, IERC20) returns (bool) {
        address owner = _msgSender();
        
        // If sender or recipient is excluded from tax, transfer normally
        if (isExcludedFromTax[owner] || isExcludedFromTax[to]) {
            _transfer(owner, to, amount);
            return true;
        }
        
        // Calculate tax (1% total)
        uint256 taxAmount = (amount * TAX_RATE) / BASIS_POINTS;
        
        // Split tax: 50% burned, 50% to collector
        uint256 burnAmount = taxAmount / 2;
        uint256 collectorAmount = taxAmount - burnAmount;
        
        // Calculate net amount to recipient
        uint256 netAmount = amount - taxAmount;
        
        // Burn 50% of tax
        if (burnAmount > 0) {
            _burn(owner, burnAmount);
        }
        
        // Transfer 50% of tax to collector
        if (collectorAmount > 0) {
            _transfer(owner, taxCollector, collectorAmount);
        }
        
        // Transfer net amount to recipient
        _transfer(owner, to, netAmount);
        
        emit TaxCollected(owner, to, amount, taxAmount, burnAmount);
        
        return true;
    }
    
    /**
     * @notice Override transferFrom to apply 1% tax (50% burned, 50% to collector)
     * @dev Recipient receives 99% of amount, 0.5% burned, 0.5% to collector
     */
    function transferFrom(address from, address to, uint256 amount) public virtual override(ERC20, IERC20) returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        
        // If sender or recipient is excluded from tax, transfer normally
        if (isExcludedFromTax[from] || isExcludedFromTax[to]) {
            _transfer(from, to, amount);
            return true;
        }
        
        // Calculate tax (1% total)
        uint256 taxAmount = (amount * TAX_RATE) / BASIS_POINTS;
        
        // Split tax: 50% burned, 50% to collector
        uint256 burnAmount = taxAmount / 2;
        uint256 collectorAmount = taxAmount - burnAmount;
        
        // Calculate net amount to recipient
        uint256 netAmount = amount - taxAmount;
        
        // Burn 50% of tax
        if (burnAmount > 0) {
            _burn(from, burnAmount);
        }
        
        // Transfer 50% of tax to collector
        if (collectorAmount > 0) {
            _transfer(from, taxCollector, collectorAmount);
        }
        
        // Transfer net amount to recipient
        _transfer(from, to, netAmount);
        
        emit TaxCollected(from, to, amount, taxAmount, burnAmount);
        
        return true;
    }
    
    /**
     * @notice Update the tax collector address
     * @param newTaxCollector New tax collector address
     */
    function updateTaxCollector(address newTaxCollector) external onlyOwner {
        require(newTaxCollector != address(0), "Invalid tax collector address");
        
        // Remove old tax collector from exclusion list
        isExcludedFromTax[taxCollector] = false;
        
        address oldCollector = taxCollector;
        taxCollector = newTaxCollector;
        
        // Add new tax collector to exclusion list
        isExcludedFromTax[newTaxCollector] = true;
        
        emit TaxCollectorUpdated(oldCollector, newTaxCollector);
    }
    
    /**
     * @notice Exclude or include an address from transfer tax
     * @param account Address to update
     * @param excluded True to exclude from tax, false to include
     */
    function setExcludedFromTax(address account, bool excluded) external onlyOwner {
        require(account != address(0), "Invalid address");
        isExcludedFromTax[account] = excluded;
        emit ExclusionUpdated(account, excluded);
    }
    
    /**
     * @notice Get the amount of BTBT tokens that will be minted for a given BTB amount
     * @param btbAmount Amount of BTB tokens to deposit
     * @return btbtAmount Amount of BTBT tokens to be received
     * @return price Current price
     */
    function previewMint(uint256 btbAmount) external view returns (uint256 btbtAmount, uint256 price) {
        price = getCurrentPrice();
        btbtAmount = (btbAmount * 1e18) / price;
    }
    
    /**
     * @notice Get the amount of BTB tokens that will be received for redeeming BTBT
     * @param btbtAmount Amount of BTBT tokens to redeem
     * @return btbAmount Amount of BTB tokens to be received
     * @return price Current price
     */
    function previewRedeem(uint256 btbtAmount) external view returns (uint256 btbAmount, uint256 price) {
        price = getCurrentPrice();
        btbAmount = (btbtAmount * price) / 1e18;
    }
    
    /**
     * @notice Preview transfer to see how much recipient will receive after tax
     * @param amount Amount to transfer
     * @return netAmount Amount recipient will receive (after tax)
     * @return taxAmount Amount of tax (total)
     * @return burnAmount Amount that will be burned
     * @return collectorAmount Amount that goes to collector
     */
    function previewTransfer(uint256 amount) external pure returns (
        uint256 netAmount,
        uint256 taxAmount,
        uint256 burnAmount,
        uint256 collectorAmount
    ) {
        taxAmount = (amount * TAX_RATE) / BASIS_POINTS;
        burnAmount = taxAmount / 2;
        collectorAmount = taxAmount - burnAmount;
        netAmount = amount - taxAmount;
    }
    
    /**
     * @notice Get contract stats
     * @return btbBalance Total BTB backing in contract
     * @return btbtSupply Total BTBT supply
     * @return currentPrice Current price of BTBT in BTB
     */
    function getStats() external view returns (
        uint256 btbBalance,
        uint256 btbtSupply,
        uint256 currentPrice
    ) {
        btbBalance = BTB_TOKEN.balanceOf(address(this));
        btbtSupply = totalSupply();
        currentPrice = getCurrentPrice();
    }
    
    /**
     * @notice Emergency function to recover stuck tokens (only owner)
     * @param token Token address to recover
     * @param amount Amount to recover
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        require(token != address(BTB_TOKEN), "Cannot withdraw BTB tokens");
        require(IERC20(token).transfer(owner(), amount), "Token transfer failed");
    }
}