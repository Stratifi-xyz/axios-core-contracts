library;

pub enum Status {
    Pending: u8, // 0
    Canceled: u8, // 1
    Active: u8, // 2
    Repaid: u8, // 3
    Liquidated: u8, //4
}

pub struct Liquidation {
    pub is_liquidatable: bool,
    pub liquidation_threshold: u64,
    pub asset_oracle: Address,
    pub collateral_oracle: Address,
}

pub struct Loan {
    pub borrower: Address,
    pub lender: Address,
    pub asset: b256,
    pub collateral: b256,
    pub asset_amount: u64,
    pub repayment_amount: u64,
    pub collateral_amount: u64,
    pub created_timestamp: u64,
    pub start_timestamp: u64,
    pub duration: u64,
    pub status: u64,
    pub liquidation: Liquidation,
}

pub enum Error {
    EMsgSenderAndBorrowerNotSame: (),
    EAmountLessThanOrEqualToRepaymentAmount: (),
    ESameAssetSameCollateral: (),
    EInvalidLiqThreshold: (),
    EInvalidDecimal: (),
    EInvalidStatus: (),
    EAlreadyExpired: (),
    EInvalidCollateral: (),
    EInvalidCollateralAmount: (),
    EInvalidAsset: (),
    EInvalidAssetAmount: (),
    EDurationNotFinished: (),
}

pub struct LoanRequestedEvent {
    pub borrower: Address,
    pub loan_id: u64,
}

pub struct LoanCancelledEvent {
    pub borrower: Address,
    pub loan_id: u64,
}

pub struct LoanFilledEvent {
    pub loan_id: u64,
    pub borrower: Address,
    pub lender: Address,
}

pub struct LoanRepaidEvent {
    pub loan_id: u64,
    pub borrower: Address,
    pub lender: Address,
}

pub struct LoanLiquidatedEvent {
    pub loan_id: u64,
    pub borrower: Address,
    pub lender: Address,
    pub collateral_amount: u64,
}

abi P2PMarket {
    #[storage(read, write)]
    fn request_loan(loan_info: Loan);
    #[storage(read, write)]
    fn cancel_loan(loan_id: u64);
    #[payable, storage(read, write)]
    fn fill_loan_request(loan_id: u64);
    #[storage(read, write)]
    fn repay_loan(loan_id: u64);
    #[storage(read, write)]
    fn liquidate_loan(loan_id: u64);
}
