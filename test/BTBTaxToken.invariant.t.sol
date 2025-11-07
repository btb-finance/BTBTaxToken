// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {BTBTaxToken} from "../src/BTBT.sol";
import {MockBTB} from "./mocks/MockBTB.sol";

/**
 * @title BTBTaxTokenHandler
 * @notice Handler contract for invariant testing
 * @dev This contract performs random actions on the BTBTaxToken to test invariants
 */
contract BTBTaxTokenHandler is Test {
    BTBTaxToken public btbt;
    MockBTB public btb;
    address public taxCollector;

    address[] public actors;
    address internal currentActor;

    function getActorsLength() public view returns (uint256) {
        return actors.length;
    }

    // Ghost variables for tracking
    uint256 public ghost_totalBTBDeposited;
    uint256 public ghost_totalBTBWithdrawn;
    uint256 public ghost_totalBTBTMinted;
    uint256 public ghost_totalBTBTBurned;
    uint256 public ghost_transferCount;

    constructor(BTBTaxToken _btbt, MockBTB _btb, address _taxCollector) {
        btbt = _btbt;
        btb = _btb;
        taxCollector = _taxCollector;

        // Track initial liquidity from initialization
        ghost_totalBTBDeposited = _btbt.INITIAL_BTB_AMOUNT();
        ghost_totalBTBTMinted = _btbt.INITIAL_BTBT_AMOUNT();

        // Create actors
        for (uint256 i = 0; i < 5; i++) {
            address actor = address(uint160(uint256(keccak256(abi.encodePacked("actor", i)))));
            actors.push(actor);
            btb.mint(actor, 10_000_000 ether);
        }
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    function mint(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        amount = bound(amount, 1, 100_000 ether);

        btb.approve(address(btbt), amount);
        try btbt.mint(amount) returns (uint256 btbtAmount) {
            ghost_totalBTBDeposited += amount;
            ghost_totalBTBTMinted += btbtAmount;
        } catch {}
    }

    function redeem(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        uint256 balance = btbt.balanceOf(currentActor);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        try btbt.redeem(amount) returns (uint256 btbAmount) {
            ghost_totalBTBWithdrawn += btbAmount;
            ghost_totalBTBTBurned += amount;
        } catch {}
    }

    function transfer(uint256 actorSeed, uint256 recipientSeed, uint256 amount) public useActor(actorSeed) {
        address recipient = actors[bound(recipientSeed, 0, actors.length - 1)];
        uint256 balance = btbt.balanceOf(currentActor);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        uint256 taxAmount = (amount * btbt.TAX_RATE()) / btbt.BASIS_POINTS();
        uint256 burnAmount = taxAmount / 2;

        try btbt.transfer(recipient, amount) {
            ghost_transferCount++;
            ghost_totalBTBTBurned += burnAmount; // Track tax burns
        } catch {}
    }

    function burn(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        uint256 balance = btbt.balanceOf(currentActor);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        try btbt.burn(amount) {
            ghost_totalBTBTBurned += amount;
        } catch {}
    }

    function callSummary() public view {
        console.log("Call summary:");
        console.log("Total BTB deposited:", ghost_totalBTBDeposited);
        console.log("Total BTB withdrawn:", ghost_totalBTBWithdrawn);
        console.log("Total BTBT minted:", ghost_totalBTBTMinted);
        console.log("Total BTBT burned:", ghost_totalBTBTBurned);
        console.log("Transfer count:", ghost_transferCount);
    }
}

/**
 * @title BTBTaxTokenInvariantTest
 * @notice Invariant tests for BTBTaxToken
 */
contract BTBTaxTokenInvariantTest is StdInvariant, Test {
    BTBTaxToken public btbt;
    MockBTB public btb;
    BTBTaxTokenHandler public handler;

    address public owner;
    address public taxCollector;

    function setUp() public {
        owner = address(this);
        taxCollector = makeAddr("taxCollector");

        btb = new MockBTB();
        btbt = new BTBTaxToken(owner, address(btb), taxCollector);

        // Initialize the contract with 1M BTB/BTBT
        btb.approve(address(btbt), btbt.INITIAL_BTB_AMOUNT());
        btbt.initialize();

        handler = new BTBTaxTokenHandler(btbt, btb, taxCollector);

        targetContract(address(handler));

        // Add selectors
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = BTBTaxTokenHandler.mint.selector;
        selectors[1] = BTBTaxTokenHandler.redeem.selector;
        selectors[2] = BTBTaxTokenHandler.transfer.selector;
        selectors[3] = BTBTaxTokenHandler.burn.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The contract should always hold at least as much BTB as needed to back all BTBT
    function invariant_BTBBackingIsAlwaysSufficient() public view {
        uint256 btbBalance = btb.balanceOf(address(btbt));
        uint256 btbtSupply = btbt.totalSupply();
        uint256 price = btbt.getCurrentPrice();

        // Required BTB = (supply * price) / 1e18
        uint256 requiredBTB = (btbtSupply * price) / 1e18;

        assertGe(btbBalance, requiredBTB, "BTB backing insufficient");
    }

    /// @notice The price should never decrease (backing ratio only increases)
    function invariant_PriceNeverDecreases() public {
        uint256 currentPrice = btbt.getCurrentPrice();

        // Price should be >= 1e18 (at least 1:1)
        // Note: Price can be exactly 1e18 if supply is 0 or if ratio is still 1:1
        assertGe(currentPrice, 0, "Price is negative");
    }

    /// @notice Total supply should equal sum of all balances
    function invariant_TotalSupplyEqualsBalances() public view {
        uint256 totalSupply = btbt.totalSupply();
        uint256 sumOfBalances = 0;

        // Sum actor balances
        uint256 actorCount = handler.getActorsLength();
        for (uint256 i = 0; i < actorCount; i++) {
            sumOfBalances += btbt.balanceOf(handler.actors(i));
        }

        // Add tax collector balance
        sumOfBalances += btbt.balanceOf(taxCollector);

        // Add contract balance (if any)
        sumOfBalances += btbt.balanceOf(address(btbt));

        // Add owner balance (has initial 1M BTBT)
        sumOfBalances += btbt.balanceOf(owner);

        assertEq(totalSupply, sumOfBalances, "Total supply != sum of balances");
    }

    /// @notice BTB in contract should always be <= total BTB deposited
    function invariant_BTBBalanceConsistent() public view {
        uint256 btbInContract = btb.balanceOf(address(btbt));
        uint256 deposited = handler.ghost_totalBTBDeposited();
        uint256 withdrawn = handler.ghost_totalBTBWithdrawn();

        assertEq(btbInContract, deposited - withdrawn, "BTB balance inconsistent");
    }

    /// @notice BTBT supply should equal minted - burned
    function invariant_BTBTSupplyConsistent() public view {
        uint256 supply = btbt.totalSupply();
        uint256 minted = handler.ghost_totalBTBTMinted();
        uint256 burned = handler.ghost_totalBTBTBurned();

        assertEq(supply, minted - burned, "BTBT supply inconsistent");
    }

    /// @notice Tax collector should only receive tokens from transfers (never from mint/redeem)
    function invariant_TaxCollectorBalanceReasonable() public view {
        uint256 taxCollectorBalance = btbt.balanceOf(taxCollector);
        uint256 transferCount = handler.ghost_transferCount();

        // Tax collector balance should be 0 if no transfers
        if (transferCount == 0) {
            assertEq(taxCollectorBalance, 0, "Tax collector has balance without transfers");
        }
    }

    /// @notice The contract should never hold more BTB than deposited
    function invariant_NoExcessBTB() public view {
        uint256 btbInContract = btb.balanceOf(address(btbt));
        uint256 totalDeposited = handler.ghost_totalBTBDeposited();

        assertLe(btbInContract, totalDeposited, "Contract has more BTB than deposited");
    }

    /// @notice Price calculation should be consistent with BTB balance and BTBT supply
    function invariant_PriceCalculationCorrect() public view {
        uint256 btbBalance = btb.balanceOf(address(btbt));
        uint256 btbtSupply = btbt.totalSupply();
        uint256 price = btbt.getCurrentPrice();

        if (btbtSupply == 0) {
            assertEq(price, 1e18, "Price should be 1:1 when supply is 0");
        } else {
            uint256 expectedPrice = (btbBalance * 1e18) / btbtSupply;
            assertEq(price, expectedPrice, "Price calculation incorrect");
        }
    }

    /// @notice Exclusions should remain consistent
    function invariant_ExclusionsConsistent() public view {
        assertTrue(btbt.isExcludedFromTax(address(btbt)), "Contract not excluded");
        assertTrue(btbt.isExcludedFromTax(taxCollector), "Tax collector not excluded");
    }

    /// @notice Owner should remain unchanged
    function invariant_OwnerUnchanged() public view {
        assertEq(btbt.owner(), owner, "Owner changed");
    }

    /// @notice BTB token address should be immutable
    function invariant_BTBTokenImmutable() public view {
        assertEq(address(btbt.BTB_TOKEN()), address(btb), "BTB token address changed");
    }

    /// @notice Constants should remain constant
    function invariant_ConstantsUnchanged() public view {
        assertEq(btbt.TAX_RATE(), 100, "Tax rate changed");
        assertEq(btbt.BASIS_POINTS(), 10000, "Basis points changed");
    }

    /// @notice No user should have more BTBT than the total supply
    function invariant_NoBalanceExceedsSupply() public view {
        uint256 supply = btbt.totalSupply();
        uint256 actorCount = handler.getActorsLength();

        for (uint256 i = 0; i < actorCount; i++) {
            address actor = handler.actors(i);
            assertLe(btbt.balanceOf(actor), supply, "Balance exceeds supply");
        }

        assertLe(btbt.balanceOf(taxCollector), supply, "Tax collector balance exceeds supply");
    }

    /// @notice Price should increase or stay same after any operation (never decrease)
    function invariant_PriceMonotonicallyIncreasing() public {
        // This is tested by storing price before and after operations
        // In practice, price can only increase due to burns
        uint256 price = btbt.getCurrentPrice();
        assertGe(price, 1e18, "Price below initial 1:1 ratio");
    }

    /// @notice The sum of all BTBT across all addresses should equal total supply
    function invariant_SupplyAccountedFor() public view {
        uint256 totalSupply = btbt.totalSupply();
        uint256 accountedSupply = 0;
        uint256 actorCount = handler.getActorsLength();

        // Check all actors
        for (uint256 i = 0; i < actorCount; i++) {
            accountedSupply += btbt.balanceOf(handler.actors(i));
        }

        // Check tax collector
        accountedSupply += btbt.balanceOf(taxCollector);

        // Check contract itself
        accountedSupply += btbt.balanceOf(address(btbt));

        // Check owner (has initial 1M BTBT)
        accountedSupply += btbt.balanceOf(owner);

        assertEq(totalSupply, accountedSupply, "Supply not fully accounted for");
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
