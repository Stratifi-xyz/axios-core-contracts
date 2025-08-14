### Borrow and Lend Isolated Market For Fixed Rate Lending over Fuel

A decentralized money market protocol that enables lending & borrowing with customizable terms and automated liquidation mechanisms.

### Dev Setup

```
forc 0.69.1
```

## Core Features

### Loan Requests

Users can create loan requests by specifying:

- **Asset Token**: The token to be borrowed
- **Collateral Token**: The token provided as security
- **Borrow Amount**: Quantity of asset tokens requested
- **Repayment Amount**: Total amount to be repaid (includes interest)
- **Collateral Amount**: Security deposit required
- **Duration**: Loan term length

### Loan Management

- **Fill Requests**: Lenders can fulfill open loan requests
- **Cancel Requests**: Borrowers can cancel unfilled requests
- **Repay Loans**: Borrowers can repay active loans
- **Auto-Expiration**: Unfilled requests automatically expire after `DURATION`

### Liquidation System

Loans are subject to liquidation under one conditions:

1. **Time-based**: Loan duration expires without repayment

### Fee Structure

- **Protocol Fee**: Applied only to interest portion (repayment amount - borrowed amount) i.e 10%
- **Liquidation Rewards**:
  - 1% of collateral amount to liquidator
  - 1% of collateral to protocol

## How It Works

1. Borrower creates a loan request with desired terms
2. Lender reviews and fills the request
3. Borrower receives the asset and repays within the specified duration
4. If conditions aren't met, the loan may be liquidated with collateral distributed to liquidator and protocol
