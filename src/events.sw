library;

pub struct LoanCancelledEvent {
    pub loan_id: u64,
    pub borrower: Address,
    pub collateral: b256,
    pub amount: u64,
}
pub struct LoanFilledEvent {
    pub loan_id: u64,
    pub borrower: Address,
    pub lender: Address,
    pub asset: b256,
    pub amount: u64,
    pub liquidation: bool,
}
pub struct LoanRepaidEvent {
    pub loan_id: u64,
    pub borrower: Address,
    pub lender: Address,
    pub asset: b256,
    pub repayment_amount: u64,
}
pub struct LoanLiquidatedEvent {
    pub loan_id: u64,
    pub borrower: Address,
    pub lender: Address,
    pub collateral_amount: u64,
}
pub struct ClaimExpiredLoanReqEvent {
    pub loan_id: u64,
    pub borrower: Address,
    pub collateral: b256,
    pub amount: u64,
}
pub struct LoanRequestedEvent {
    pub loan_id: u64,
    pub borrower: Address,
    pub asset: b256,
    pub asset_amount: u64,
    pub collateral: b256,
    pub collateral_amount: u64,
    pub duration: u64,
    pub liquidation: bool,
}
pub struct LoanOfferedEvent {
    pub loan_id: u64,
    pub lender: Address,
    pub asset: b256,
    pub asset_amount: u64,
    pub collateral: b256,
    pub collateral_amount: u64,
    pub duration: u64,
    pub liquidation: bool,
}

pub struct LoanOfferFilledEvent {
    pub loan_id: u64,
    pub borrower: Address,
    pub lender: Address,
    pub asset: b256,
    pub amount: u64,
    pub duration: u64,
    pub liquidation: bool,
}

pub struct LoanOfferedCancelledEvent {
    pub loan_id: u64,
    pub lender: Address,
    pub asset: b256,
    pub amount: u64,
}
pub struct ClaimExpiredLoanOfferEvent {
    pub loan_id: u64,
    pub lender: Address,
    pub asset: b256,
    pub amount: u64,
}
