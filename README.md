# BitVault USD (USDX) - Bitcoin-Backed Stablecoin Protocol

[![Stacks](https://img.shields.io/badge/Built%20on-Stacks-purple)](https://stacks.co)
[![Clarity](https://img.shields.io/badge/Language-Clarity-blue)](https://clarity-lang.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

## Overview

BitVault USD is a decentralized finance (DeFi) protocol that enables users to mint USDX, a USD-pegged stablecoin, by depositing STX and xBTC as collateral. The protocol implements a Collateralized Debt Position (CDP) system with automated liquidation mechanisms, real-time price oracles, and robust risk management to maintain the stability of the USDX peg while providing capital efficiency for Bitcoin ecosystem users.

## Key Features

- **Multi-Asset Collateral Support**: Accept both STX and xBTC as collateral
- **Over-Collateralized Lending**: Configurable collateral ratios for risk management
- **Automated Liquidation Engine**: Protects protocol solvency through automated liquidations
- **Decentralized Price Oracle System**: Real-time price feeds with staleness protection
- **SIP-010 Compliant Token**: USDX stablecoin follows Stacks token standards
- **Risk Management**: Health factor monitoring and minimum collateral requirements

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    BitVault USD Protocol                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐         │
│  │   Oracle    │    │    Vault    │    │ Liquidation │         │
│  │   System    │    │ Management  │    │   Engine    │         │
│  │             │    │             │    │             │         │
│  │ • STX Price │    │ • Create    │    │ • Health    │         │
│  │ • xBTC Price│    │ • Collateral│    │   Monitoring│         │
│  │ • Confidence│    │ • Mint USDX │    │ • Auto Liq. │         │
│  └─────────────┘    │ • Burn USDX │    │ • Penalties │         │
│                     └─────────────┘    └─────────────┘         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                USDX Token (SIP-010)                     │   │
│  │                                                         │   │
│  │ • Mint/Burn Mechanism                                   │   │
│  │ • Transfer Functions                                     │   │
│  │ • Balance Tracking                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Contract Architecture

### Core Components

#### 1. **Vault Management System**

- **Vault Creation**: Users can create vaults by depositing STX/xBTC collateral
- **Collateral Management**: Add/withdraw collateral while maintaining ratios
- **Debt Management**: Mint USDX against collateral and burn to reduce debt

#### 2. **Oracle Price Feed System**

- **Multi-Asset Support**: Real-time pricing for STX and xBTC
- **Staleness Protection**: Maximum price age of 1 hour
- **Confidence Intervals**: Oracle operators provide confidence levels (1-100%)

#### 3. **Liquidation Engine**

- **Health Factor Monitoring**: Continuous vault health assessment
- **Automated Liquidation**: Liquidators can close undercollateralized positions
- **Penalty Mechanism**: 10% liquidation penalty to incentivize proper collateralization

#### 4. **USDX Stablecoin Token**

- **SIP-010 Compliance**: Full compatibility with Stacks ecosystem
- **Mint/Burn Mechanics**: Controlled supply based on vault collateralization
- **Transfer Functions**: Standard token transfer capabilities

## Data Flow

```
User Journey - Creating a Vault and Minting USDX:

1. User deposits STX collateral → Vault created
2. Oracle provides STX/xBTC prices → Collateral value calculated
3. User mints USDX → Debt recorded in vault
4. Health factor monitored → Liquidation if ratio < 150%

┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│  User   │───▶│  Vault  │───▶│ Oracle  │───▶│ USDX    │
│Deposits │    │Created  │    │Pricing  │    │Minted   │
│STX      │    │         │    │         │    │         │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
     │              │              │              │
     │              ▼              │              ▼
     │         ┌─────────┐         │         ┌─────────┐
     │         │Health   │         │         │Protocol │
     │         │Monitor  │◀────────┘         │Stats    │
     │         │         │                   │Updated  │
     │         └─────────┘                   └─────────┘
     │              │
     ▼              ▼
┌─────────┐    ┌─────────┐
│Liquidate│    │Maintain │
│if Unsafe│    │if Safe  │
└─────────┘    └─────────┘
```

## Protocol Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| **Liquidation Ratio** | 150% | Threshold for liquidation eligibility |
| **Minimum Collateral Ratio** | 200% | Required ratio for new vault creation |
| **Liquidation Penalty** | 10% | Additional penalty for liquidated vaults |
| **Stability Fee Rate** | 2% | Annual fee on outstanding debt |
| **Max Price Age** | 1 hour | Maximum oracle price staleness |
| **Max Vaults Per User** | 10 | Maximum vaults per user address |

## Getting Started

### Prerequisites

- Stacks wallet (Hiro Wallet, Xverse, etc.)
- STX tokens for collateral and transaction fees
- xBTC tokens (optional, for additional collateral)

### Deployment

1. **Deploy the contract** to Stacks mainnet or testnet
2. **Initialize oracle operators** for price feeds
3. **Set up authorized liquidators** for liquidation engine
4. **Configure protocol parameters** as needed

### Usage Examples

#### Creating a Vault

```clarity
;; Create vault with 1000 STX collateral
(contract-call? .bitvault-usd create-vault u1000000000 u0)
```

#### Minting USDX

```clarity
;; Mint 100 USDX from vault ID 1
(contract-call? .bitvault-usd mint-usdx u1 u100000000)
```

#### Adding Collateral

```clarity
;; Add 500 STX to vault ID 1
(contract-call? .bitvault-usd add-collateral u1 u500000000 u0)
```

## Risk Management

### Collateralization Requirements

- **Minimum Ratio**: 200% collateralization required for new vaults
- **Liquidation Threshold**: Vaults become liquidatable below 150%
- **Safety Buffer**: Recommended 250%+ collateralization for safety

### Oracle Security

- **Multiple Operators**: Decentralized oracle network
- **Price Staleness**: Automatic rejection of stale price data
- **Confidence Scoring**: Oracle confidence levels tracked

### Liquidation Protection

- **Automated System**: No manual intervention required
- **Incentive Alignment**: Liquidators rewarded with discounted collateral
- **Penalty Mechanism**: Discourages excessive leverage

## API Reference

### Read-Only Functions

#### `get-vault (vault-id uint)`

Returns vault information including collateral, debt, and status.

#### `calculate-health-factor (vault-id uint)`

Calculates the current health factor (collateral ratio) for a vault.

#### `get-protocol-stats ()`

Returns protocol-wide statistics including total debt and collateral.

#### `is-vault-safe (vault-id uint)`

Checks if a vault is above the liquidation threshold.

### Public Functions

#### `create-vault (stx-amount uint) (xbtc-amount uint)`

Creates a new vault with specified collateral amounts.

#### `mint-usdx (vault-id uint) (amount uint)`

Mints USDX tokens against vault collateral.

#### `burn-usdx (vault-id uint) (amount uint)`

Burns USDX tokens to reduce vault debt.

#### `liquidate-vault (vault-id uint)`

Liquidates an undercollateralized vault (liquidators only).

## Security Considerations

### Smart Contract Security

- **Overflow Protection**: All arithmetic operations checked
- **Access Control**: Role-based permissions for critical functions
- **Input Validation**: Comprehensive parameter validation
- **Emergency Shutdown**: Owner can halt protocol in emergencies

### Economic Security

- **Collateral Requirements**: High collateralization ratios
- **Liquidation Incentives**: Economic incentives for liquidators
- **Oracle Dependencies**: Multiple price feed sources recommended

## Contributing

We welcome contributions to the BitVault USD protocol! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup

```bash
# Install Clarinet
npm install -g @hirosystems/clarinet-cli

# Clone repository
git clone https://github.com/vdirisu/bitcoin-backed-stablecoin.git
cd bitvault-usd

# Run tests
clarinet test
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
