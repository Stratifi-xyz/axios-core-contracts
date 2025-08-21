### Borrow and Lend Isolated Market For Fixed Rate Lending over Fuel

A decentralized money market protocol that enables lending & borrowing with customizable terms and automated liquidation mechanisms.

### Dev Setup

```
forc 0.69.1
```

## Core Features

### Loan Requests

Borrower can create loan requests by specifying:

- **Asset Token**: The token to be borrowed
- **Asset Amount**: Amount it want to borrow
- **Collateral Token**: The token provided as security
- **Repayment Amount**: Total amount to be repaid (includes interest)
- **Collateral Amount**: Security deposit required
- **Duration**: Loan term length
- **Liquidation(optional)**: Borrowers can enable automatic liquidation of their loans when collateral ratios fall below specified thresholds.

### Loan Offers

Lender can create lending offer by specifying:

- **Asset Token**: The token to be borrowed
- **Asset Amount**: Amount borrower can borrow
- **Collateral Token**: The token provided as security
- **Repayment Amount**: Total amount to be repaid (includes interest)
- **Collateral Amount**: Security deposit required
- **Duration**: Loan term length
- **Liquidation(optional)**: Lenders can enable automatic liquidation of their loans when collateral ratios fall below specified thresholds. Price feeds are sourced from Pyth Network oracles.

### Loan Management

- **Fill Requests**: Lenders can fulfill open loan requests and borrower can fulfill open loan offers
- **Cancel Requests**: Borrowers and lenders can cancel unfilled requests
- **Repay Loans**: Borrowers can repay active loans
- **Auto-Expiration**: Unfilled requests automatically expire after `DURATION`

### Liquidation System

Loans are subject to liquidation under following conditions:

1. **Time-based**: Loan duration expires without repayment
2. **Liquidation Threshold**: When value of asset borrowed is higher than the value of collateral and liquidation threshold

### Fee Structure

- **Protocol Fee**: Applied only to interest portion (repayment amount - borrowed amount) i.e 10%
- **Liquidation Rewards**:
  - 1% of collateral amount to liquidator
  - 1% of collateral to protocol

## How It Works

For Borrower:

1. Borrower creates a loan request with desired terms
2. Lender reviews and fills the request
3. Borrower receives the asset and repays within the specified duration
4. In case of liquidation, collateral is sent to lender with some parts to protocol and liquidator

For Lender:

1. Lender creates a loan offer with desired terms
2. Borrower reviews and fills the request
3. Borrower receives the asset and repays within the specified duration
4. In case of liquidation, collateral is sent to lender with some parts to protocol and liquidator