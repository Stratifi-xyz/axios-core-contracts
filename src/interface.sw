library;

use std::bytes::Bytes;
use pyth_interface::data_structures::price::PriceFeedId;

pub enum Status {
    Pending: u8, // 0
    Canceled: u8, // 1
    Active: u8, // 2
    Repaid: u8, // 3
    Liquidated: u8, // 4
    ExpiredClaim: u8, // 5
}
pub struct Liquidation {
    pub liquidation_request: bool,
    pub liquidation_threshold_in_bps: u64,
    pub liquidation_flag_internal: bool,
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
    EMsgSenderAndLenderNotSame: (),
    EAmountLessThanOrEqualToRepaymentAmount: (),
    ESameAssetSameCollateral: (),
    EInvalidDuration: (),
    EInvalidDecimal: (),
    EInvalidStatus: (),
    EAlreadyExpired: (),
    EInvalidCollateral: (),
    EInvalidCollateralAmount: (),
    EInvalidAsset: (),
    EInvalidAssetAmount: (),
    EDurationNotFinished: (),
    ELoanReqNotExpired: (),
    ELoanOfferNotExpired: (),
    ENoOracleFeedAvailable: (),
    EInvalidLiqThreshold: (),
    EOracleNotSet: (),
    EOraclePriceZero: (),
    EOraclePriceStale: (),
    ENotEnoughForOracleUpdate: (),
    ENotOracleBaseAssetId: (),
}

abi FixedMarket {
    #[payable, storage(read, write)]
    fn request_loan(loan_info: Loan);
    #[storage(read, write)]
    fn cancel_loan(loan_id: u64);
    #[payable, storage(read, write)]
    fn fill_loan_request(loan_id: u64);
    #[payable, storage(read, write)]
    fn repay_loan(loan_id: u64);
    #[storage(read, write)]
    fn liquidate_loan(loan_id: u64);
    #[storage(read, write)]
    fn claim_expired_loan_req(loan_id: u64);

    // offer loan
    #[payable, storage(read, write)]
    fn offer_loan(loan_info: Loan);
    #[payable, storage(read, write)]
    fn fill_lender_request(loan_id: u64);
    #[storage(read, write)]
    fn cancel_lender_offer(loan_id: u64);
    #[storage(read, write)]
    fn claim_expired_loan_offer(loan_id: u64);
    // oracle
    #[payable, storage(read)]
    fn pay_and_update_price_feeds(update_data: Vec<Bytes>);
    #[storage(read)]
    fn get_price_from_oracle(feed_id: PriceFeedId) -> u64;
    // Storage Read Function
    #[storage(read)]
    fn get_loan(loan_id: u64) -> Loan;
    #[storage(read)]
    fn get_loan_status(loan_id: u64) -> u64;
    #[storage(read)]
    fn get_loan_length() -> u64;
    #[storage(read)]
    fn is_loan_liquidation_by_oracle(loan_id: u64) -> bool;
}

// Only for query of decimals
abi SRC20 {
    #[storage(read)]
    fn total_assets() -> u64;
    #[storage(read)]
    fn total_supply(asset: AssetId) -> Option<u64>;
    #[storage(read)]
    fn decimals(asset: AssetId) -> Option<u8>;
}
