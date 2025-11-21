// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC1363} from "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BTBTaxToken
 * @notice A 1:1 wrapped token for BTB Finance with 1% tax on transfers
 * @dev Users deposit BTB tokens to mint BTBT tokens (1:1 ratio)
 *      Users can redeem BTBT tokens back to BTB tokens (1:1 ratio)
 *      ALL BTBT transfers incur 1% tax (100% to admin)
 *      Fully decentralized - no owner functions
 */
contract BTBTaxToken is ERC20, ERC20Burnable, ERC1363, ERC20Permit, Ownable, ReentrancyGuard {
    IERC20 public immutable BTB_TOKEN;

    uint256 public constant TAX_RATE = 100; // 1%
    uint256 public constant BASIS_POINTS = 10000;

    address public taxCollector;

    event Minted(address indexed user, uint256 btbAmount, uint256 btbtAmount);
    event Redeemed(address indexed user, uint256 btbtAmount, uint256 btbAmount);
    event TaxCollected(address indexed from, address indexed to, uint256 amount, uint256 taxAmount);
    event TaxCollectorUpdated(address indexed oldCollector, address indexed newCollector);

    constructor(address btbToken, address _taxCollector, address initialOwner)
        ERC20("BTBT", "BTBT")
        ERC20Permit("BTBT")
        Ownable(initialOwner)
    {
        require(btbToken != address(0), "Invalid BTB token");
        require(_taxCollector != address(0), "Invalid tax collector");

        BTB_TOKEN = IERC20(btbToken);
        taxCollector = _taxCollector;
    }

    /**
     * @notice Update the tax collector address (only owner)
     */
    function setTaxCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "Invalid address");
        address oldCollector = taxCollector;
        taxCollector = newCollector;
        emit TaxCollectorUpdated(oldCollector, newCollector);
    }

    /**
     * @notice Mint BTBT tokens by depositing BTB tokens (1:1 ratio)
     */
    function mint(uint256 btbAmount) external nonReentrant returns (uint256 btbtAmount) {
        require(btbAmount > 0, "Amount must be > 0");

        btbtAmount = btbAmount;

        require(BTB_TOKEN.transferFrom(msg.sender, address(this), btbAmount), "BTB transfer failed");
        _mint(msg.sender, btbtAmount);

        emit Minted(msg.sender, btbAmount, btbtAmount);
    }

    /**
     * @notice Redeem BTBT tokens for BTB tokens (1:1 ratio)
     */
    function redeem(uint256 btbtAmount) external nonReentrant returns (uint256 btbAmount) {
        require(btbtAmount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= btbtAmount, "Insufficient BTBT");

        btbAmount = btbtAmount;

        require(BTB_TOKEN.balanceOf(address(this)) >= btbAmount, "Insufficient BTB");

        _burn(msg.sender, btbtAmount);
        require(BTB_TOKEN.transfer(msg.sender, btbAmount), "BTB transfer failed");

        emit Redeemed(msg.sender, btbtAmount, btbAmount);
    }

    /**
     * @notice Override transfer to apply 1% tax (100% to admin)
     */
    function transfer(address to, uint256 amount) public virtual override(ERC20, IERC20) returns (bool) {
        address sender = _msgSender();

        uint256 taxAmount = (amount * TAX_RATE) / BASIS_POINTS;
        uint256 netAmount = amount - taxAmount;

        if (taxAmount > 0) {
            _transfer(sender, taxCollector, taxAmount);
        }
        _transfer(sender, to, netAmount);

        emit TaxCollected(sender, to, amount, taxAmount);
        return true;
    }

    /**
     * @notice Override transferFrom to apply 1% tax (100% to admin)
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override(ERC20, IERC20)
        returns (bool)
    {
        _spendAllowance(from, _msgSender(), amount);

        uint256 taxAmount = (amount * TAX_RATE) / BASIS_POINTS;
        uint256 netAmount = amount - taxAmount;

        if (taxAmount > 0) {
            _transfer(from, taxCollector, taxAmount);
        }
        _transfer(from, to, netAmount);

        emit TaxCollected(from, to, amount, taxAmount);
        return true;
    }

    /**
     * @notice Preview transfer tax
     */
    function previewTransfer(uint256 amount) external pure returns (uint256 netAmount, uint256 taxAmount) {
        taxAmount = (amount * TAX_RATE) / BASIS_POINTS;
        netAmount = amount - taxAmount;
    }

    /**
     * @notice Get contract stats
     */
    function getStats() external view returns (uint256 btbBalance, uint256 btbtSupply) {
        btbBalance = BTB_TOKEN.balanceOf(address(this));
        btbtSupply = totalSupply();
    }
}
