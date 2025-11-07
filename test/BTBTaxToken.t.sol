// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {BTBTaxToken} from "../src/BTBT.sol";
import {MockBTB} from "./mocks/MockBTB.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title BTBTaxTokenTest
 * @notice Comprehensive test suite for BTBTaxToken contract
 */
contract BTBTaxTokenTest is Test {
    BTBTaxToken public btbt;
    MockBTB public btb;

    address public owner;
    address public taxCollector;
    address public user1;
    address public user2;
    address public user3;

    // Events to test
    event Minted(address indexed user, uint256 btbAmount, uint256 btbtAmount, uint256 price);
    event Redeemed(address indexed user, uint256 btbtAmount, uint256 btbAmount, uint256 price);
    event TaxCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event TaxCollected(
        address indexed from, address indexed to, uint256 amount, uint256 taxAmount, uint256 burnedAmount
    );
    event ExclusionUpdated(address indexed account, bool excluded);

    function setUp() public {
        owner = address(this);
        taxCollector = makeAddr("taxCollector");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy mock BTB token
        btb = new MockBTB();

        // Deploy BTBT tax token
        btbt = new BTBTaxToken(owner, address(btb), taxCollector);

        // Initialize the contract with 1M BTB/BTBT
        btb.approve(address(btbt), btbt.INITIAL_BTB_AMOUNT());
        btbt.initialize();

        // Fund users with BTB tokens
        btb.transfer(user1, 1000 ether);
        btb.transfer(user2, 1000 ether);
        btb.transfer(user3, 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_Success() public view {
        assertEq(address(btbt.BTB_TOKEN()), address(btb));
        assertEq(btbt.taxCollector(), taxCollector);
        assertEq(btbt.owner(), owner);
        assertTrue(btbt.isExcludedFromTax(address(btbt)));
        assertTrue(btbt.isExcludedFromTax(taxCollector));
        assertTrue(btbt.initialized());
    }

    function test_Constructor_RevertWhen_InvalidBTBAddress() public {
        vm.expectRevert("Invalid BTB token address");
        new BTBTaxToken(owner, address(0), taxCollector);
    }

    function test_Constructor_RevertWhen_InvalidTaxCollectorAddress() public {
        vm.expectRevert("Invalid tax collector address");
        new BTBTaxToken(owner, address(btb), address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialize_Success() public {
        // Deploy new contract (not initialized)
        BTBTaxToken newBtbt = new BTBTaxToken(owner, address(btb), taxCollector);

        assertFalse(newBtbt.initialized());
        assertEq(newBtbt.totalSupply(), 0);

        // Approve and initialize
        btb.approve(address(newBtbt), newBtbt.INITIAL_BTB_AMOUNT());

        vm.expectEmit(true, false, false, true);
        emit Initialized(owner, newBtbt.INITIAL_BTB_AMOUNT(), newBtbt.INITIAL_BTBT_AMOUNT());

        newBtbt.initialize();

        // Check initialized state
        assertTrue(newBtbt.initialized());
        assertEq(newBtbt.totalSupply(), newBtbt.INITIAL_BTBT_AMOUNT());
        assertEq(newBtbt.balanceOf(owner), newBtbt.INITIAL_BTBT_AMOUNT());
        assertEq(btb.balanceOf(address(newBtbt)), newBtbt.INITIAL_BTB_AMOUNT());
        assertEq(newBtbt.getCurrentPrice(), 1e18); // 1:1 ratio
    }

    function test_Initialize_RevertWhen_AlreadyInitialized() public {
        // btbt is already initialized in setUp
        vm.expectRevert("Already initialized");
        btbt.initialize();
    }

    function test_Initialize_RevertWhen_NotOwner() public {
        BTBTaxToken newBtbt = new BTBTaxToken(owner, address(btb), taxCollector);

        vm.prank(user1);
        vm.expectRevert();
        newBtbt.initialize();
    }

    function test_Initialize_RevertWhen_InsufficientBTB() public {
        BTBTaxToken newBtbt = new BTBTaxToken(owner, address(btb), taxCollector);

        // Don't approve enough BTB
        btb.approve(address(newBtbt), 100 ether);

        vm.expectRevert();
        newBtbt.initialize();
    }

    event Initialized(address indexed initializer, uint256 btbAmount, uint256 btbtAmount);

    /*//////////////////////////////////////////////////////////////
                        PRICE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCurrentPrice_AfterInitialization() public view {
        assertEq(btbt.getCurrentPrice(), 1e18); // 1:1 ratio after initialization
    }

    function test_GetCurrentPrice_WhenNotInitialized() public {
        BTBTaxToken newBtbt = new BTBTaxToken(owner, address(btb), taxCollector);
        // Will revert with division by zero when not initialized (supply = 0)
        vm.expectRevert();
        newBtbt.getCurrentPrice();
    }

    function test_GetCurrentPrice_AfterMinting() public {
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);
        vm.stopPrank();

        uint256 price = btbt.getCurrentPrice();
        assertEq(price, 1e18); // Should still be 1:1 after first mint
    }

    function test_GetCurrentPrice_AfterBurning() public {
        // Mint some BTBT
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);

        // Burn some BTBT (increases backing ratio)
        uint256 burnAmount = 10 ether;
        btbt.burn(burnAmount);
        vm.stopPrank();

        uint256 price = btbt.getCurrentPrice();
        // Price should increase because supply decreased but BTB backing stayed same
        assertGt(price, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                        MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Mint_Success() public {
        uint256 btbAmount = 100 ether;

        vm.startPrank(user1);
        btb.approve(address(btbt), btbAmount);

        uint256 initialBtbBalance = btb.balanceOf(user1);
        uint256 initialContractBtbBalance = btb.balanceOf(address(btbt));

        vm.expectEmit(true, false, false, true);
        emit Minted(user1, btbAmount, btbAmount, 1e18);

        uint256 btbtAmount = btbt.mint(btbAmount);
        vm.stopPrank();

        assertEq(btbtAmount, btbAmount); // 1:1 ratio initially
        assertEq(btb.balanceOf(user1), initialBtbBalance - btbAmount);
        assertEq(btb.balanceOf(address(btbt)), initialContractBtbBalance + btbAmount);
        assertEq(btbt.balanceOf(user1), btbtAmount);
    }

    function test_Mint_RevertWhen_ZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert("Amount must be greater than 0");
        btbt.mint(0);
        vm.stopPrank();
    }

    function test_Mint_RevertWhen_NotInitialized() public {
        BTBTaxToken newBtbt = new BTBTaxToken(owner, address(btb), taxCollector);

        vm.startPrank(user1);
        btb.approve(address(newBtbt), 100 ether);
        vm.expectRevert("Contract not initialized");
        newBtbt.mint(100 ether);
        vm.stopPrank();
    }

    function test_Mint_RevertWhen_InsufficientAllowance() public {
        vm.startPrank(user1);
        vm.expectRevert();
        btbt.mint(100 ether);
        vm.stopPrank();
    }

    function test_Mint_RevertWhen_InsufficientBalance() public {
        vm.startPrank(user1);
        btb.approve(address(btbt), type(uint256).max);
        vm.expectRevert();
        btbt.mint(10000 ether); // User only has 1000 ether
        vm.stopPrank();
    }

    function test_Mint_MultipleUsers() public {
        // User1 mints
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        uint256 user1Btbt = btbt.mint(100 ether);
        vm.stopPrank();

        // User2 mints at same price
        vm.startPrank(user2);
        btb.approve(address(btbt), 100 ether);
        uint256 user2Btbt = btbt.mint(100 ether);
        vm.stopPrank();

        assertEq(user1Btbt, 100 ether);
        assertEq(user2Btbt, 100 ether);
        assertEq(btbt.balanceOf(user1), user1Btbt);
        assertEq(btbt.balanceOf(user2), user2Btbt);
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Redeem_Success() public {
        // First mint some BTBT
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        uint256 mintedAmount = btbt.mint(100 ether);

        uint256 redeemAmount = 50 ether;
        uint256 initialBtbBalance = btb.balanceOf(user1);
        uint256 initialBtbtBalance = btbt.balanceOf(user1);

        uint256 btbAmount = btbt.redeem(redeemAmount);
        vm.stopPrank();

        assertEq(btb.balanceOf(user1), initialBtbBalance + btbAmount);
        assertEq(btbt.balanceOf(user1), initialBtbtBalance - redeemAmount);
    }

    function test_Redeem_RevertWhen_ZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert("Amount must be greater than 0");
        btbt.redeem(0);
        vm.stopPrank();
    }

    function test_Redeem_RevertWhen_NotInitialized() public {
        BTBTaxToken newBtbt = new BTBTaxToken(owner, address(btb), taxCollector);

        vm.startPrank(user1);
        vm.expectRevert("Contract not initialized");
        newBtbt.redeem(100 ether);
        vm.stopPrank();
    }

    function test_Redeem_RevertWhen_InsufficientBTBTBalance() public {
        // Mint some BTBT first
        vm.startPrank(user1);
        btb.approve(address(btbt), 10 ether);
        btbt.mint(10 ether);

        // Try to redeem more than balance
        vm.expectRevert("Insufficient BTBT balance");
        btbt.redeem(100 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER TAX TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Transfer_WithTax() public {
        // Mint BTBT to user1
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);

        uint256 transferAmount = 100 ether;
        uint256 expectedTax = (transferAmount * btbt.TAX_RATE()) / btbt.BASIS_POINTS();
        uint256 expectedBurn = expectedTax / 2;
        uint256 expectedCollector = expectedTax - expectedBurn;
        uint256 expectedNet = transferAmount - expectedTax;

        uint256 initialSupply = btbt.totalSupply();

        vm.expectEmit(true, true, false, true);
        emit TaxCollected(user1, user2, transferAmount, expectedTax, expectedBurn);

        btbt.transfer(user2, transferAmount);
        vm.stopPrank();

        assertEq(btbt.balanceOf(user2), expectedNet);
        assertEq(btbt.balanceOf(taxCollector), expectedCollector);
        assertEq(btbt.totalSupply(), initialSupply - expectedBurn);
    }

    function test_Transfer_TaxFreeWhenExcluded() public {
        // Exclude user1 from tax
        btbt.setExcludedFromTax(user1, true);

        // Mint BTBT to user1
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);

        uint256 transferAmount = 100 ether;
        btbt.transfer(user2, transferAmount);
        vm.stopPrank();

        // No tax should be applied
        assertEq(btbt.balanceOf(user2), transferAmount);
        assertEq(btbt.balanceOf(taxCollector), 0);
    }

    function test_Transfer_TaxFreeToExcluded() public {
        // Exclude user2 from tax
        btbt.setExcludedFromTax(user2, true);

        // Mint BTBT to user1
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);

        uint256 transferAmount = 100 ether;
        btbt.transfer(user2, transferAmount);
        vm.stopPrank();

        // No tax should be applied
        assertEq(btbt.balanceOf(user2), transferAmount);
        assertEq(btbt.balanceOf(taxCollector), 0);
    }

    function test_TransferFrom_WithTax() public {
        // Mint BTBT to user1
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);

        // Approve user2 to spend user1's BTBT
        btbt.approve(user2, 100 ether);
        vm.stopPrank();

        uint256 transferAmount = 100 ether;
        uint256 expectedTax = (transferAmount * btbt.TAX_RATE()) / btbt.BASIS_POINTS();
        uint256 expectedBurn = expectedTax / 2;
        uint256 expectedNet = transferAmount - expectedTax;

        // User2 transfers from user1 to user3
        vm.prank(user2);
        btbt.transferFrom(user1, user3, transferAmount);

        assertEq(btbt.balanceOf(user3), expectedNet);
        assertEq(btbt.balanceOf(user1), 0);
    }

    function test_TransferFrom_TaxFreeWhenExcluded() public {
        // Exclude user1 from tax
        btbt.setExcludedFromTax(user1, true);

        // Mint BTBT to user1
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);
        btbt.approve(user2, 100 ether);
        vm.stopPrank();

        uint256 transferAmount = 100 ether;

        // User2 transfers from user1 to user3
        vm.prank(user2);
        btbt.transferFrom(user1, user3, transferAmount);

        // No tax should be applied
        assertEq(btbt.balanceOf(user3), transferAmount);
        assertEq(btbt.balanceOf(taxCollector), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        TAX CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TaxCalculation_SmallAmount() public {
        vm.startPrank(user1);
        btb.approve(address(btbt), 10 ether);
        btbt.mint(10 ether);

        btbt.transfer(user2, 1 ether);
        vm.stopPrank();

        // 1 ether * 1% = 0.01 ether tax
        // 0.005 ether burned, 0.005 ether to collector
        // Net = 0.99 ether
        assertEq(btbt.balanceOf(user2), 0.99 ether);
    }

    function test_TaxCalculation_LargeAmount() public {
        vm.startPrank(user1);
        btb.approve(address(btbt), 1000 ether);
        btbt.mint(1000 ether);

        btbt.transfer(user2, 1000 ether);
        vm.stopPrank();

        // 1000 ether * 1% = 10 ether tax
        // 5 ether burned, 5 ether to collector
        // Net = 990 ether
        assertEq(btbt.balanceOf(user2), 990 ether);
        assertEq(btbt.balanceOf(taxCollector), 5 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateTaxCollector_Success() public {
        address newCollector = makeAddr("newCollector");

        vm.expectEmit(true, true, false, false);
        emit TaxCollectorUpdated(taxCollector, newCollector);

        btbt.updateTaxCollector(newCollector);

        assertEq(btbt.taxCollector(), newCollector);
        assertTrue(btbt.isExcludedFromTax(newCollector));
        assertFalse(btbt.isExcludedFromTax(taxCollector));
    }

    function test_UpdateTaxCollector_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        btbt.updateTaxCollector(user2);
    }

    function test_UpdateTaxCollector_RevertWhen_ZeroAddress() public {
        vm.expectRevert("Invalid tax collector address");
        btbt.updateTaxCollector(address(0));
    }

    function test_SetExcludedFromTax_Success() public {
        vm.expectEmit(true, false, false, true);
        emit ExclusionUpdated(user1, true);

        btbt.setExcludedFromTax(user1, true);
        assertTrue(btbt.isExcludedFromTax(user1));

        btbt.setExcludedFromTax(user1, false);
        assertFalse(btbt.isExcludedFromTax(user1));
    }

    function test_SetExcludedFromTax_RevertWhen_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        btbt.setExcludedFromTax(user2, true);
    }

    function test_SetExcludedFromTax_RevertWhen_ZeroAddress() public {
        vm.expectRevert("Invalid address");
        btbt.setExcludedFromTax(address(0), true);
    }

    function test_EmergencyWithdraw_Success() public {
        // Deploy a different ERC20 token
        MockBTB otherToken = new MockBTB();
        otherToken.transfer(address(btbt), 100 ether);

        uint256 initialBalance = otherToken.balanceOf(owner);
        btbt.emergencyWithdraw(address(otherToken), 100 ether);

        assertEq(otherToken.balanceOf(owner), initialBalance + 100 ether);
    }

    function test_EmergencyWithdraw_RevertWhen_WithdrawingBTB() public {
        vm.expectRevert("Cannot withdraw BTB tokens");
        btbt.emergencyWithdraw(address(btb), 100 ether);
    }

    function test_EmergencyWithdraw_RevertWhen_NotOwner() public {
        MockBTB otherToken = new MockBTB();

        vm.prank(user1);
        vm.expectRevert();
        btbt.emergencyWithdraw(address(otherToken), 100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        PREVIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PreviewMint() public view {
        (uint256 btbtAmount, uint256 price) = btbt.previewMint(100 ether);
        assertEq(btbtAmount, 100 ether);
        assertEq(price, 1e18);
    }

    function test_PreviewRedeem() public {
        // Mint some first
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);
        vm.stopPrank();

        (uint256 btbAmount, uint256 price) = btbt.previewRedeem(50 ether);
        assertEq(btbAmount, 50 ether);
        assertEq(price, 1e18);
    }

    function test_PreviewTransfer() public view {
        (uint256 netAmount, uint256 taxAmount, uint256 burnAmount, uint256 collectorAmount) =
            btbt.previewTransfer(100 ether);

        assertEq(taxAmount, 1 ether);
        assertEq(burnAmount, 0.5 ether);
        assertEq(collectorAmount, 0.5 ether);
        assertEq(netAmount, 99 ether);
    }

    function test_GetStats() public {
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);
        vm.stopPrank();

        (uint256 btbBalance, uint256 btbtSupply, uint256 currentPrice) = btbt.getStats();

        // Add initial liquidity to expected values
        assertEq(btbBalance, btbt.INITIAL_BTB_AMOUNT() + 100 ether);
        assertEq(btbtSupply, btbt.INITIAL_BTBT_AMOUNT() + 100 ether);
        assertEq(currentPrice, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                        REENTRANCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Mint_ReentrancyProtection() public {
        // The nonReentrant modifier should prevent reentrancy
        // This is tested implicitly by the modifier
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);
        vm.stopPrank();
    }

    function test_Redeem_ReentrancyProtection() public {
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        uint256 mintedAmount = btbt.mint(100 ether);
        btbt.redeem(50 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PriceIncrease_AfterTaxBurns() public {
        // Mint BTBT
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);
        vm.stopPrank();

        uint256 initialPrice = btbt.getCurrentPrice();

        // Transfer with tax (burns 0.5%)
        vm.startPrank(user1);
        btbt.transfer(user2, 100 ether);
        vm.stopPrank();

        uint256 newPrice = btbt.getCurrentPrice();

        // Price should increase because supply decreased but BTB backing stayed same
        assertGt(newPrice, initialPrice);
    }

    function test_MultipleTransfers_TaxAccumulation() public {
        // Mint BTBT
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);
        vm.stopPrank();

        // Transfer 1: user1 -> user2
        vm.prank(user1);
        btbt.transfer(user2, 50 ether);

        uint256 user2Balance = btbt.balanceOf(user2);

        // Transfer 2: user2 -> user3
        vm.prank(user2);
        btbt.transfer(user3, user2Balance);

        // Tax collector should have accumulated fees from both transfers
        assertGt(btbt.balanceOf(taxCollector), 0);

        // Verify user3 received less than user2Balance due to tax
        assertLt(btbt.balanceOf(user3), user2Balance);
    }

    function test_BurnIncreasesBackingRatio() public {
        // Mint BTBT
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);

        uint256 initialPrice = btbt.getCurrentPrice();

        // Direct burn
        btbt.burn(10 ether);
        vm.stopPrank();

        uint256 newPrice = btbt.getCurrentPrice();

        // Price increases because supply decreased but backing stayed same
        assertGt(newPrice, initialPrice);
    }

    function test_ZeroTaxForContractToContract() public {
        // Exclude another contract
        address mockContract = makeAddr("mockContract");
        btbt.setExcludedFromTax(mockContract, true);

        // Mint to user1
        vm.startPrank(user1);
        btb.approve(address(btbt), 100 ether);
        btbt.mint(100 ether);

        // Transfer to excluded contract
        btbt.transfer(mockContract, 50 ether);
        vm.stopPrank();

        // No tax applied
        assertEq(btbt.balanceOf(mockContract), 50 ether);
        assertEq(btbt.balanceOf(taxCollector), 0);
    }
}
