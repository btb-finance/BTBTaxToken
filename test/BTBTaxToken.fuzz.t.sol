
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {BTBTaxToken} from "../src/BTBT.sol";
import {MockBTB} from "./mocks/MockBTB.sol";

/**
 * @title BTBTaxTokenFuzzTest
 * @notice Fuzz testing for BTBTaxToken contract
 */
contract BTBTaxTokenFuzzTest is Test {
    BTBTaxToken public btbt;
    MockBTB public btb;

    address public owner;
    address public taxCollector;

    function setUp() public {
        owner = address(this);
        taxCollector = makeAddr("taxCollector");

        btb = new MockBTB();
        btbt = new BTBTaxToken(owner, address(btb), taxCollector);
    }

    /*//////////////////////////////////////////////////////////////
                        MINT FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Mint_ValidAmounts(uint256 amount) public {
        // Bound to reasonable values
        amount = bound(amount, 1, 1_000_000 ether);

        address user = makeAddr("user");
        btb.mint(user, amount);

        vm.startPrank(user);
        btb.approve(address(btbt), amount);

        uint256 initialPrice = btbt.getCurrentPrice();
        uint256 btbtAmount = btbt.mint(amount);
        vm.stopPrank();

        // Verify BTBT amount is correct based on price
        assertEq(btbtAmount, (amount * 1e18) / initialPrice);
        assertEq(btbt.balanceOf(user), btbtAmount);
        assertEq(btb.balanceOf(address(btbt)), amount);
    }

    function testFuzz_Mint_MultipleMints(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 1_000_000 ether);
        amount2 = bound(amount2, 1, 1_000_000 ether);

        address user = makeAddr("user");
        btb.mint(user, amount1 + amount2);

        vm.startPrank(user);
        btb.approve(address(btbt), amount1 + amount2);

        uint256 btbt1 = btbt.mint(amount1);
        uint256 btbt2 = btbt.mint(amount2);
        vm.stopPrank();

        assertEq(btbt.balanceOf(user), btbt1 + btbt2);
    }

    function testFuzz_Mint_PriceConsistency(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);

        address user = makeAddr("user");
        btb.mint(user, amount);

        uint256 priceBefore = btbt.getCurrentPrice();

        vm.startPrank(user);
        btb.approve(address(btbt), amount);
        btbt.mint(amount);
        vm.stopPrank();

        uint256 priceAfter = btbt.getCurrentPrice();

        // Price should remain 1:1 after minting (no price impact)
        assertEq(priceAfter, priceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        REDEEM FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Redeem_ValidAmounts(uint256 mintAmount, uint256 redeemAmount) public {
        mintAmount = bound(mintAmount, 100, 1_000_000 ether);
        redeemAmount = bound(redeemAmount, 1, mintAmount);

        address user = makeAddr("user");
        btb.mint(user, mintAmount);

        vm.startPrank(user);
        btb.approve(address(btbt), mintAmount);
        btbt.mint(mintAmount);

        uint256 btbBalanceBefore = btb.balanceOf(user);
        uint256 btbRedeemed = btbt.redeem(redeemAmount);
        vm.stopPrank();

        assertEq(btb.balanceOf(user), btbBalanceBefore + btbRedeemed);
        assertGt(btbRedeemed, 0);
    }

    function testFuzz_Redeem_RoundTrip(uint256 amount) public {
        amount = bound(amount, 1000, 1_000_000 ether);

        address user = makeAddr("user");
        btb.mint(user, amount);

        vm.startPrank(user);
        btb.approve(address(btbt), amount);

        uint256 btbtMinted = btbt.mint(amount);
        uint256 btbRedeemed = btbt.redeem(btbtMinted);
        vm.stopPrank();

        // Should get back approximately same amount (minus rounding)
        assertApproxEqAbs(btbRedeemed, amount, 1);
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER TAX FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Transfer_TaxCalculation(uint256 amount) public {
        amount = bound(amount, 1000, 1_000_000 ether);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        btb.mint(user1, amount);

        vm.startPrank(user1);
        btb.approve(address(btbt), amount);
        btbt.mint(amount);

        uint256 transferAmount = btbt.balanceOf(user1);
        uint256 expectedTax = (transferAmount * btbt.TAX_RATE()) / btbt.BASIS_POINTS();
        uint256 expectedNet = transferAmount - expectedTax;

        btbt.transfer(user2, transferAmount);
        vm.stopPrank();

        assertEq(btbt.balanceOf(user2), expectedNet);
    }

    function testFuzz_Transfer_TaxBurnAndCollectorSplit(uint256 amount) public {
        amount = bound(amount, 1000, 1_000_000 ether);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        btb.mint(user1, amount);

        vm.startPrank(user1);
        btb.approve(address(btbt), amount);
        btbt.mint(amount);

        uint256 transferAmount = btbt.balanceOf(user1);
        uint256 supplyBefore = btbt.totalSupply();

        btbt.transfer(user2, transferAmount);
        vm.stopPrank();

        uint256 supplyAfter = btbt.totalSupply();
        uint256 burned = supplyBefore - supplyAfter;
        uint256 toCollector = btbt.balanceOf(taxCollector);

        // Burned and collector amounts should be approximately equal (50/50 split)
        // Allow for 1 wei difference due to integer division
        assertApproxEqAbs(burned, toCollector, 1);
    }

    function testFuzz_TransferFrom_TaxCalculation(uint256 amount) public {
        amount = bound(amount, 1000, 1_000_000 ether);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        btb.mint(user1, amount);

        vm.startPrank(user1);
        btb.approve(address(btbt), amount);
        btbt.mint(amount);

        uint256 transferAmount = btbt.balanceOf(user1);
        btbt.approve(user2, transferAmount);
        vm.stopPrank();

        uint256 expectedTax = (transferAmount * btbt.TAX_RATE()) / btbt.BASIS_POINTS();
        uint256 expectedNet = transferAmount - expectedTax;

        vm.prank(user2);
        btbt.transferFrom(user1, user3, transferAmount);

        assertEq(btbt.balanceOf(user3), expectedNet);
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE MANIPULATION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_PriceIncrease_AfterBurn(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1000, 1_000_000 ether);
        burnAmount = bound(burnAmount, 1, mintAmount / 2);

        address user = makeAddr("user");
        btb.mint(user, mintAmount);

        vm.startPrank(user);
        btb.approve(address(btbt), mintAmount);
        btbt.mint(mintAmount);

        uint256 priceBefore = btbt.getCurrentPrice();
        btbt.burn(burnAmount);
        uint256 priceAfter = btbt.getCurrentPrice();
        vm.stopPrank();

        // Price should increase after burning
        assertGt(priceAfter, priceBefore);
    }

    function testFuzz_PriceIncrease_AfterTaxTransfer(uint256 amount) public {
        amount = bound(amount, 1000, 1_000_000 ether);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        btb.mint(user1, amount);

        vm.startPrank(user1);
        btb.approve(address(btbt), amount);
        btbt.mint(amount);

        uint256 priceBefore = btbt.getCurrentPrice();
        btbt.transfer(user2, btbt.balanceOf(user1));
        vm.stopPrank();

        uint256 priceAfter = btbt.getCurrentPrice();

        // Price should increase after transfer (due to burn)
        assertGe(priceAfter, priceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        INVARIANT HELPER FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_BackingRatio_NeverDecreases(uint256 seed) public {
        seed = bound(seed, 0, 10);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        btb.mint(user1, 1_000_000 ether);

        vm.startPrank(user1);
        btb.approve(address(btbt), type(uint256).max);
        btbt.mint(100_000 ether);

        uint256 initialPrice = btbt.getCurrentPrice();

        // Perform random operations
        for (uint256 i = 0; i < seed; i++) {
            uint256 transferAmount = 1000 ether;
            if (btbt.balanceOf(user1) >= transferAmount) {
                btbt.transfer(user2, transferAmount);
            }
        }
        vm.stopPrank();

        uint256 finalPrice = btbt.getCurrentPrice();

        // Price (backing ratio) should never decrease
        assertGe(finalPrice, initialPrice);
    }

    function testFuzz_TotalSupply_ConsistentWithBalances(uint256 numUsers, uint256 amountPerUser) public {
        numUsers = bound(numUsers, 1, 10);
        amountPerUser = bound(amountPerUser, 1000, 100_000 ether);

        uint256 totalMinted = 0;

        for (uint256 i = 0; i < numUsers; i++) {
            address user = address(uint160(i + 1000));
            btb.mint(user, amountPerUser);

            vm.startPrank(user);
            btb.approve(address(btbt), amountPerUser);
            btbt.mint(amountPerUser);
            totalMinted += btbt.balanceOf(user);
            vm.stopPrank();
        }

        // Total supply should equal sum of all balances (plus tax collector)
        uint256 totalBalances = totalMinted + btbt.balanceOf(taxCollector);
        assertEq(btbt.totalSupply(), totalBalances);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SmallAmounts_NoZeroResults(uint256 amount) public {
        amount = bound(amount, 1, 1000);

        address user = makeAddr("user");
        btb.mint(user, amount);

        vm.startPrank(user);
        btb.approve(address(btbt), amount);

        // Should revert if BTBT amount would be 0
        if ((amount * 1e18) / btbt.getCurrentPrice() == 0) {
            vm.expectRevert("BTBT amount too small");
            btbt.mint(amount);
        } else {
            uint256 btbtAmount = btbt.mint(amount);
            assertGt(btbtAmount, 0);
        }
        vm.stopPrank();
    }

    function testFuzz_LargeAmounts_NoOverflow(uint256 amount) public {
        // Test with very large amounts (but not overflow)
        amount = bound(amount, 1_000_000 ether, 1_000_000_000 ether);

        address user = makeAddr("user");
        btb.mint(user, amount);

        vm.startPrank(user);
        btb.approve(address(btbt), amount);
        uint256 btbtAmount = btbt.mint(amount);
        vm.stopPrank();

        assertGt(btbtAmount, 0);
        assertEq(btbt.balanceOf(user), btbtAmount);
    }

    function testFuzz_MultipleRedeems_ConsistentPricing(uint256 mintAmount, uint8 numRedeems) public {
        mintAmount = bound(mintAmount, 10_000 ether, 1_000_000 ether);
        numRedeems = uint8(bound(numRedeems, 2, 10));

        address user = makeAddr("user");
        btb.mint(user, mintAmount);

        vm.startPrank(user);
        btb.approve(address(btbt), mintAmount);
        uint256 btbtMinted = btbt.mint(mintAmount);

        uint256 redeemAmount = btbtMinted / numRedeems;
        uint256 totalRedeemed = 0;

        for (uint256 i = 0; i < numRedeems - 1; i++) {
            if (btbt.balanceOf(user) >= redeemAmount) {
                uint256 btbReceived = btbt.redeem(redeemAmount);
                totalRedeemed += btbReceived;
            }
        }

        // Redeem remaining
        if (btbt.balanceOf(user) > 0) {
            totalRedeemed += btbt.redeem(btbt.balanceOf(user));
        }
        vm.stopPrank();

        // Should get back approximately the same amount (minus rounding)
        assertApproxEqAbs(totalRedeemed, mintAmount, numRedeems);
    }

    /*//////////////////////////////////////////////////////////////
                        EXCLUSION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ExclusionFromTax_Works(uint256 amount, bool excludeSender, bool excludeRecipient) public {
        amount = bound(amount, 1000, 1_000_000 ether);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        btb.mint(user1, amount);

        if (excludeSender) {
            btbt.setExcludedFromTax(user1, true);
        }
        if (excludeRecipient) {
            btbt.setExcludedFromTax(user2, true);
        }

        vm.startPrank(user1);
        btb.approve(address(btbt), amount);
        btbt.mint(amount);

        uint256 transferAmount = btbt.balanceOf(user1);
        btbt.transfer(user2, transferAmount);
        vm.stopPrank();

        if (excludeSender || excludeRecipient) {
            // No tax applied
            assertEq(btbt.balanceOf(user2), transferAmount);
            assertEq(btbt.balanceOf(taxCollector), 0);
        } else {
            // Tax applied
            uint256 expectedTax = (transferAmount * btbt.TAX_RATE()) / btbt.BASIS_POINTS();
            assertEq(btbt.balanceOf(user2), transferAmount - expectedTax);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        PRECISION FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_PricePrecision_Maintained(uint256 amount) public {
        amount = bound(amount, 1000, 1_000_000 ether);

        address user = makeAddr("user");
        btb.mint(user, amount);

        vm.startPrank(user);
        btb.approve(address(btbt), amount);
        uint256 btbtAmount = btbt.mint(amount);

        // Preview should match actual
        (uint256 previewBtb,) = btbt.previewRedeem(btbtAmount);
        uint256 actualBtb = btbt.redeem(btbtAmount);
        vm.stopPrank();

        assertEq(previewBtb, actualBtb);
    }

    function testFuzz_TaxPrecision_NoRoundingErrors(uint256 amount) public {
        amount = bound(amount, 10_000, 1_000_000 ether);

        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        btb.mint(user1, amount);

        vm.startPrank(user1);
        btb.approve(address(btbt), amount);
        btbt.mint(amount);

        uint256 transferAmount = btbt.balanceOf(user1);
        uint256 supplyBefore = btbt.totalSupply();

        (uint256 previewNet, uint256 previewTax, uint256 previewBurn, uint256 previewCollector)
            = btbt.previewTransfer(transferAmount);

        btbt.transfer(user2, transferAmount);
        vm.stopPrank();

        uint256 supplyAfter = btbt.totalSupply();

        // Verify preview matches actual
        assertEq(btbt.balanceOf(user2), previewNet);
        assertApproxEqAbs(supplyBefore - supplyAfter, previewBurn, 1);
        assertApproxEqAbs(btbt.balanceOf(taxCollector), previewCollector, 1);
    }
}
