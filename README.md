# BTB Tax Token (BTBT)

A deflationary bonding curve wrapped token for BTB Finance with a 1% transfer tax that drives price appreciation over time.

[![Tests](https://img.shields.io/badge/tests-81%2F81%20passing-brightgreen)]()
[![Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen)]()
[![Solidity](https://img.shields.io/badge/solidity-0.8.27-blue)]()
[![License](https://img.shields.io/badge/license-MIT-blue)]()

## 🎯 Overview

BTBT is a sophisticated ERC20 token that wraps BTB tokens using a dynamic bonding curve pricing mechanism. The contract features a 1% transfer tax that is split 50/50 between burning and a tax collector, creating a **deflationary token** where the price **always increases or stays the same, never decreases**.

### Key Features

- 🔥 **Deflationary Mechanics**: 0.5% of every transfer is burned, reducing supply and increasing price
- 💰 **Bonding Curve**: Dynamic pricing based on backing ratio (BTB balance / BTBT supply)
- 📈 **Price Appreciation**: Price increases with every transfer due to burns
- ⚡ **Gas Optimized**: Removed conditional checks from hot path (saves ~200-500 gas per operation)
- 🔒 **Battle Tested**: 81 comprehensive tests (unit, fuzz, invariant) all passing
- 🛡️ **Security First**: ReentrancyGuard, access control, audit-ready code
- 💎 **ERC1363 & ERC20Permit**: Advanced token standards support

## 📊 How It Works

### Bonding Curve Pricing

The token uses a simple yet powerful bonding curve formula:

```solidity
Price = (BTB balance in contract) / (BTBT total supply)
```

**Price starts at 1:1** (1 BTB = 1 BTBT) and increases over time as tokens are burned.

### Operations

#### 1. **Mint** (Buy BTBT with BTB)
```solidity
// Deposit BTB to get BTBT at current price
btbt.mint(btbAmount);

// Example: If price = 1.0
// Deposit 100 BTB → Get 100 BTBT
// Contract now has more BTB backing
```

**Effect on price:** ⚖️ Neutral (proportional increase in both backing and supply)

#### 2. **Redeem** (Sell BTBT for BTB)
```solidity
// Burn BTBT to get BTB back at current price
btbt.redeem(btbtAmount);

// Example: If price = 1.1
// Redeem 100 BTBT → Get 110 BTB
// You made 10% profit!
```

**Effect on price:** ⚖️ Neutral (proportional decrease in both backing and supply)

#### 3. **Transfer** (Pay 1% tax)
```solidity
// Every transfer has 1% tax
btbt.transfer(recipient, 1000);

// Tax breakdown:
// - Recipient receives: 990 BTBT (99%)
// - Burned: 5 BTBT (0.5%)
// - Tax collector: 5 BTBT (0.5%)
```

**Effect on price:** 📈 INCREASES (backing unchanged, supply decreased by burns)

#### 4. **Burn** (Direct burn)
```solidity
// Voluntarily burn tokens to increase price for all holders
btbt.burn(amount);
```

**Effect on price:** 📈 INCREASES (backing unchanged, supply decreased)

### Why Price Always Goes Up

Every transfer burns 0.5% of tokens:
- ✅ **Backing stays the same** (BTB remains in contract)
- ✅ **Supply decreases** (tokens burned)
- ✅ **Price = Backing ÷ Supply** → **Price goes up!**

**Example:**
```
Initial State:
- BTB backing: 1,000,000
- BTBT supply: 1,000,000
- Price: 1.0

After 100,000 BTBT burned from transfers:
- BTB backing: 1,000,000 (unchanged)
- BTBT supply: 900,000 (100k burned)
- Price: 1.111... (11% increase!)
```

All holders benefit from every transfer! 🚀

## ⚡ Gas Optimization

The contract uses a one-time initialization pattern to remove conditional checks from the price calculation hot path:

### Before Optimization
```solidity
function getCurrentPrice() public view returns (uint256) {
    if (totalSupply() == 0) {  // Checked on EVERY call ❌
        return 1e18;
    }
    return (btbBalance * 1e18) / totalSupply();
}
```

### After Optimization
```solidity
function initialize() external onlyOwner {
    // Seeds 1M BTB/BTBT at 1:1 ratio (ONE TIME ONLY)
    BTB_TOKEN.transferFrom(msg.sender, address(this), 1_000_000e18);
    _mint(msg.sender, 1_000_000e18);
}

function getCurrentPrice() public view returns (uint256) {
    // NO conditional checks - pure calculation ✅
    return (btbBalance * 1e18) / totalSupply();
}
```

**Gas Saved:** ~200-500 gas per mint/redeem operation

## 🚀 Deployment

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone repository
git clone <your-repo>
cd "BTB TAX token"

# Install dependencies
forge install
```

### Deploy Contract

```solidity
// 1. Deploy contract
BTBTaxToken btbt = new BTBTaxToken(
    owner,           // Owner address
    btbTokenAddress, // BTB token address
    taxCollector     // Tax collector address
);

// 2. Approve 1M BTB tokens for initialization
btb.approve(address(btbt), 1_000_000 * 1e18);

// 3. Initialize contract (one-time only, seeds liquidity)
btbt.initialize();

// 4. Contract is ready to use!
```

### Initial State After Initialization

- **BTB Backing**: 1,000,000 BTB
- **BTBT Supply**: 1,000,000 BTBT (owned by deployer)
- **Initial Price**: 1e18 (1:1 ratio)
- **Status**: Ready for users to mint/redeem

## 🧪 Testing

The contract has **81 comprehensive tests** covering every edge case and failure point.

### Run Tests

```bash
# Run all tests
forge test

# Run with gas report
forge test --gas-report

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test test_Mint_Success
```

### Test Suite

| Test Suite | Tests | Description |
|------------|-------|-------------|
| **Unit Tests** | 47 | Core functionality, access control, edge cases |
| **Fuzz Tests** | 18 | 1,000 runs each (18,036 total test cases) |
| **Invariant Tests** | 16 | 256 runs × 15 depth (61,440 random sequences) |
| **Total** | **81** | **100% passing ✅** |

### Test Coverage

```
✅ Constructor validation
✅ Initialization (one-time only)
✅ Mint/Redeem functionality
✅ Transfer tax mechanics
✅ Tax exclusions
✅ Price calculations
✅ Bonding curve accuracy
✅ Reentrancy protection
✅ Access control
✅ Emergency functions
✅ Precision and rounding
✅ Edge cases (small/large amounts)
✅ Invariant protection (16 invariants)
```

### Key Invariants Protected

1. BTB backing always sufficient for redemptions
2. Price never decreases
3. Total supply equals sum of all balances
4. BTB balance consistency
5. No excess BTB in contract
6. Tax collector only receives from transfers
7. Constants remain unchanged
8. No balance exceeds total supply

## 📖 Contract Functions

### User Functions

```solidity
// Mint BTBT by depositing BTB
function mint(uint256 btbAmount) external returns (uint256 btbtAmount)

// Redeem BTBT for BTB
function redeem(uint256 btbtAmount) external returns (uint256 btbAmount)

// Transfer with 1% tax (0.5% burn, 0.5% to collector)
function transfer(address to, uint256 amount) public returns (bool)

// TransferFrom with 1% tax
function transferFrom(address from, address to, uint256 amount) public returns (bool)

// Burn tokens to increase price for all holders
function burn(uint256 amount) public
```

### View Functions

```solidity
// Get current price (BTB per BTBT)
function getCurrentPrice() public view returns (uint256 price)

// Preview mint result
function previewMint(uint256 btbAmount) external view returns (uint256 btbtAmount, uint256 price)

// Preview redeem result
function previewRedeem(uint256 btbtAmount) external view returns (uint256 btbAmount, uint256 price)

// Preview transfer with tax breakdown
function previewTransfer(uint256 amount) external pure returns (
    uint256 netAmount,
    uint256 taxAmount,
    uint256 burnAmount,
    uint256 collectorAmount
)

// Get contract statistics
function getStats() external view returns (
    uint256 btbBalance,
    uint256 btbtSupply,
    uint256 currentPrice
)
```

### Owner Functions

```solidity
// Initialize contract with 1M BTB/BTBT (one-time only)
function initialize() external onlyOwner

// Update tax collector address
function updateTaxCollector(address newTaxCollector) external onlyOwner

// Exclude/include address from transfer tax
function setExcludedFromTax(address account, bool excluded) external onlyOwner

// Emergency withdraw (cannot withdraw BTB backing)
function emergencyWithdraw(address token, uint256 amount) external onlyOwner
```

## 🔐 Security Features

- ✅ **ReentrancyGuard**: All state-changing functions protected
- ✅ **Access Control**: Ownable pattern for admin functions
- ✅ **Input Validation**: All inputs validated
- ✅ **Safe Math**: Solidity 0.8+ built-in overflow protection
- ✅ **Immutable State**: BTB token address cannot be changed
- ✅ **One-Time Init**: Initialization can only happen once
- ✅ **Emergency Withdraw**: Cannot withdraw BTB backing (only accidentally sent tokens)
- ✅ **Audit-Ready**: Clean code, comprehensive tests, detailed documentation

## 🏗️ Architecture

```
BTBTaxToken.sol (Main Contract)
├── ERC20 (OpenZeppelin)
├── ERC20Burnable (OpenZeppelin)
├── ERC1363 (OpenZeppelin) - Payable token
├── ERC20Permit (OpenZeppelin) - Gasless approvals
├── Ownable (OpenZeppelin)
└── ReentrancyGuard (OpenZeppelin)

Key State Variables:
├── BTB_TOKEN (immutable) - BTB token reference
├── taxCollector - Receives 50% of transfer tax
├── isExcludedFromTax - Whitelist for tax-free transfers
├── initialized - One-time initialization flag
└── Constants: TAX_RATE, BASIS_POINTS, INITIAL_AMOUNTS
```

## 📈 Tokenomics

| Parameter | Value |
|-----------|-------|
| **Transfer Tax** | 1% (100 basis points) |
| **Burn Rate** | 0.5% per transfer |
| **Collector Rate** | 0.5% per transfer |
| **Initial Supply** | 1,000,000 BTBT |
| **Initial Backing** | 1,000,000 BTB |
| **Initial Price** | 1:1 ratio |
| **Min Price** | 1:1 (cannot go below) |
| **Max Price** | Unlimited (increases with burns) |

### Tax Exclusions

By default, these addresses are excluded from transfer tax:
- Contract itself
- Tax collector

Owner can add more exclusions (e.g., DEX pools, staking contracts).

## 🔧 Configuration

### Foundry Configuration

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
remappings = [
    "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/"
]

fuzz = { runs = 1000 }
invariant = { runs = 256, depth = 15, fail_on_revert = true }
```

### Adjust Initial Liquidity

For different tokenomics, modify the constants in `BTBT.sol`:

```solidity
uint256 public constant INITIAL_BTB_AMOUNT = 1_000_000 * 1e18;
uint256 public constant INITIAL_BTBT_AMOUNT = 1_000_000 * 1e18;
```

## 📝 License

This project is licensed under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please ensure all tests pass before submitting PRs.

```bash
# Run tests
forge test

# Check coverage
forge coverage

# Format code
forge fmt
```

## 📚 Additional Documentation

- [Initialization Optimization](./INITIALIZATION_OPTIMIZATION.md) - Details on gas optimization strategy
- [Test Summary](./TEST_SUMMARY.md) - Comprehensive test results
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/) - Base contract documentation

## ⚠️ Disclaimer

This is experimental software. Use at your own risk. Always conduct thorough testing and auditing before deploying to mainnet.

## 📞 Contact

For questions or support, please open an issue on GitHub.

---

**Built with ❤️ using Foundry and OpenZeppelin**

*Creating sustainable deflationary tokenomics through bonding curves and strategic burns* 🔥📈
