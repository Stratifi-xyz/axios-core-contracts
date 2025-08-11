contract;

mod interface;
use interface::{
    Error,
    Loan,
    LoanCancelledEvent,
    LoanFilledEvent,
    LoanLiquidatedEvent,
    LoanRepaidEvent,
    LoanRequestedEvent,
    P2PMarket,
    Status,
};

use std::auth::msg_sender;
use std::block::timestamp;
use std::logging::log;
use std::context::msg_amount;
use std::call_frames::msg_asset_id;
use std::asset::*;
storage {
    loans: StorageMap<u64, Loan> = StorageMap {},
    loan_length: u64 = 0,
}
impl P2PMarket for Contract {
    #[payable, storage(read, write)]
    fn request_loan(loan_info: Loan) {
        require(
            Identity::Address(loan_info.borrower) == msg_sender()
                .unwrap(),
            Error::EMsgSenderAndBorrowerNotSame,
        );
        require(
            loan_info
                .repayment_amount > loan_info
                .asset_amount,
            Error::EAmountLessThanOrEqualToRepaymentAmount,
        );
        require(loan_info.duration > 0, Error::EInvalidDuration);
        require(
            loan_info
                .asset != loan_info
                .collateral,
            Error::ESameAssetSameCollateral,
        );

        let amount = msg_amount();
        let asset_id: b256 = msg_asset_id().into();
        require(asset_id == loan_info.collateral, Error::EInvalidCollateral);
        require(
            amount == loan_info
                .collateral_amount,
            Error::EInvalidCollateralAmount,
        );
        let mut loan: Loan = loan_info;
        loan.created_timestamp = timestamp();
        loan.start_timestamp = 0;
        loan.status = 0;
        storage.loans.insert(storage.loan_length.read(), loan);
        storage.loan_length.write(storage.loan_length.read() + 1);
        log(LoanRequestedEvent {
            borrower: loan_info.borrower,
            loan_id: storage.loan_length.read() - 1,
        });
    }
    #[storage(read, write)]
    fn cancel_loan(loan_id: u64) {
        let mut loan = storage.loans.get(loan_id).read();
        require(loan.status == 0, Error::EInvalidStatus);
        // TODO: Add small delay to created timestamp before expire to fill by others
        require(loan.created_timestamp > timestamp(), Error::EAlreadyExpired);
        require(
            Identity::Address(loan.borrower) == msg_sender()
                .unwrap(),
            Error::EMsgSenderAndBorrowerNotSame,
        );
        loan.status = 1;
        storage.loans.insert(loan_id, loan);
        let collateral_asset_id: AssetId = AssetId::from(loan.collateral);
        transfer(
            msg_sender()
                .unwrap(),
            collateral_asset_id,
            loan.collateral_amount,
        );
        log(LoanCancelledEvent {
            borrower: loan.borrower,
            loan_id,
        });
    }

    #[payable, storage(read, write)]
    fn fill_loan_request(loan_id: u64) {
        let mut loan = storage.loans.get(loan_id).read();
        require(loan.status == 0, Error::EInvalidStatus);
        // TODO: Add small delay to created timestamp before expire to fill by others
        require(loan.created_timestamp > timestamp(), Error::EAlreadyExpired);
        loan.lender = get_caller_address();
        loan.start_timestamp = timestamp();
        loan.status = 2; // magic number 2 is active (ref Enum at interface)
        storage.loans.insert(loan_id, loan);
        //TODO: check if loan is instantly liquidateable and revert if: After oracle addition
        let amount = msg_amount();
        let asset_id: b256 = msg_asset_id().into();
        require(asset_id == loan.collateral, Error::EInvalidCollateral);
        require(
            amount == loan.collateral_amount,
            Error::EInvalidCollateralAmount,
        );
        let asset_id: AssetId = AssetId::from(loan.asset);
        transfer(msg_sender().unwrap(), asset_id, loan.asset_amount);
        log(LoanFilledEvent {
            loan_id,
            borrower: loan.borrower,
            lender: get_caller_address(),
        });
    }
    #[storage(read, write)]
    fn repay_loan(loan_id: u64) {
        let mut loan = storage.loans.get(loan_id).read();
        // loan must be active
        require(loan.status == 2, Error::EInvalidStatus);
        // TODO: calculate Protocol fee
        let protocol_fee = 0;
        let amount_to_lender = loan.repayment_amount - protocol_fee;
        // status is 3 i.e repaid ref (enum at interface)
        loan.status = 3;
        storage.loans.insert(loan_id, loan);
        let amount = msg_amount();
        let asset_id: b256 = msg_asset_id().into();
        require(asset_id == loan.asset, Error::EInvalidAsset);
        require(amount == loan.repayment_amount, Error::EInvalidAssetAmount);
        let asset_id: AssetId = AssetId::from(loan.asset);
        let lender_identity: Identity = Identity::Address(loan.lender);
        transfer(lender_identity, asset_id, amount_to_lender);
        let collateral_asset_id: AssetId = AssetId::from(loan.collateral);
        let borrower_identity: Identity = Identity::Address(loan.borrower);
        transfer(
            borrower_identity,
            collateral_asset_id,
            loan.collateral_amount,
        );
        // TODO: transfer protocol fee
        log(LoanRepaidEvent {
            loan_id,
            borrower: loan.borrower,
            lender: loan.lender,
        });
    }

    #[storage(read, write)]
    fn liquidate_loan(loan_id: u64) {
        let mut loan = storage.loans.get(loan_id).read();
        // loan must be active
        require(loan.status == 2, Error::EInvalidStatus);
        // Can be liquidated after duration
        require(
            timestamp() > loan.start_timestamp + loan.duration,
            Error::EDurationNotFinished,
        );

        // TODO: calculate protocol fee
        let protocol_fee = 0;
        // TODO: calculate liquidator fee
        let liquidator_amount = 0;
        let lender_amount = loan.collateral_amount - liquidator_amount - protocol_fee;

        loan.status = 4;
        storage.loans.insert(loan_id, loan);
        let collateral_asset_id: AssetId = AssetId::from(loan.collateral);
        let lender_identity: Identity = Identity::Address(loan.lender);
        transfer(lender_identity, collateral_asset_id, lender_amount);
        transfer(
            msg_sender()
                .unwrap(),
            collateral_asset_id,
            liquidator_amount,
        );
        // TODO: transfer to protocol fee receipient
        log(LoanLiquidatedEvent {
            loan_id,
            borrower: loan.borrower,
            lender: loan.lender,
            collateral_amount: loan.collateral_amount,
        });
    }
}
fn get_caller_address() -> Address {
    match msg_sender().unwrap() {
        Identity::Address(identity) => identity,
        _ => revert(0),
    }
}
