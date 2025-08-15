contract;

mod interface;
use interface::{
    Error,
    FixedMarket,
    Loan,
    LoanCancelledEvent,
    LoanFilledEvent,
    LoanLiquidatedEvent,
    LoanRepaidEvent,
    LoanRequestedEvent,
    Status,
};

use std::auth::msg_sender;
use std::block::timestamp;
use std::logging::log;
use std::context::msg_amount;
use std::call_frames::msg_asset_id;
use std::asset::*;

// would be set while deployment as well
configurable {
    PROTOCOL_FEE: u64 = 1000,
    PROTOCOL_LIQUIDATION_FEE: u64 = 100,
    LIQUIDATOR_FEE: u64 = 100,
    PROTOCOL_FEE_RECEIVER: Address = Address::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    TIME_REQUEST_LOAN_GETS_EXPIRED: u64 = 28800,
    TIME_AFTER_REQUEST_LOAN_CAN_CANCELLED: u64 = 18800,
}

storage {
    loans: StorageMap<u64, Loan> = StorageMap {},
    loan_length: u64 = 0,
}

impl FixedMarket for Contract {
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
        // TODO: To restrict the granular orders of 1 seconds or 60 seconds. Should add minimum duration check. Indexer might dos?
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
        require(
            loan.created_timestamp + TIME_AFTER_REQUEST_LOAN_CAN_CANCELLED > timestamp(),
            Error::EAlreadyExpired,
        );
        require(
            Identity::Address(loan.borrower) == msg_sender()
                .unwrap(),
            Error::EMsgSenderAndBorrowerNotSame,
        );
        loan.status = 1;
        storage.loans.insert(loan_id, loan);
        let collateral_asset_id: AssetId = get_asset_id_from_b256(loan.collateral);
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
        require(
            loan.created_timestamp + TIME_REQUEST_LOAN_GETS_EXPIRED > timestamp(),
            Error::EAlreadyExpired,
        );
        loan.lender = get_caller_address();
        loan.start_timestamp = timestamp();
        loan.status = 2; // magic number 2 is active (ref Enum at interface)
        storage.loans.insert(loan_id, loan);
        let amount = msg_amount();
        let asset_id: b256 = msg_asset_id().into();
        require(asset_id == loan.asset, Error::EInvalidAsset);
        require(amount == loan.asset_amount, Error::EInvalidAssetAmount);
        let asset_id: AssetId = get_asset_id_from_b256(loan.asset);
        let borrower_identity: Identity = get_identity_from_address(loan.borrower);
        transfer(borrower_identity, asset_id, loan.asset_amount);
        log(LoanFilledEvent {
            loan_id,
            borrower: loan.borrower,
            lender: get_caller_address(),
        });
    }
    #[payable, storage(read, write)]
    fn repay_loan(loan_id: u64) {
        let mut loan = storage.loans.get(loan_id).read();
        // loan must be active
        require(loan.status == 2, Error::EInvalidStatus);
        let interest_in_amount: u64 = loan.repayment_amount - loan.asset_amount;
        let protocol_fee: u64 = (interest_in_amount * PROTOCOL_FEE) / 10000;
        let amount_to_lender: u64 = loan.repayment_amount - protocol_fee;
        // status is 3 i.e repaid ref (enum at interface)
        loan.status = 3;
        storage.loans.insert(loan_id, loan);
        let amount = msg_amount();
        let asset_id: b256 = msg_asset_id().into();
        require(asset_id == loan.asset, Error::EInvalidAsset);
        require(amount == loan.repayment_amount, Error::EInvalidAssetAmount);
        let asset_id: AssetId = get_asset_id_from_b256(loan.asset);
        let lender_identity: Identity = get_identity_from_address(loan.lender);
        transfer(lender_identity, asset_id, amount_to_lender);
        let collateral_asset_id: AssetId = AssetId::from(loan.collateral);
        let borrower_identity: Identity = Identity::Address(loan.borrower);
        transfer(
            borrower_identity,
            collateral_asset_id,
            loan.collateral_amount,
        );
        let protocol_fee_receiver_identity = Identity::Address(PROTOCOL_FEE_RECEIVER);
        transfer(protocol_fee_receiver_identity, asset_id, protocol_fee);
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

        // check for underflow? or edge cases
        let protocol_fee = (loan.collateral_amount * PROTOCOL_LIQUIDATION_FEE) / 10000;
        let liquidator_amount = (loan.collateral_amount * LIQUIDATOR_FEE) / 10000;
        let lender_amount = loan.collateral_amount - liquidator_amount - protocol_fee;

        loan.status = 4;
        storage.loans.insert(loan_id, loan);
        let collateral_asset_id: AssetId = get_asset_id_from_b256(loan.collateral);
        let lender_identity: Identity = get_identity_from_address(loan.lender);
        transfer(lender_identity, collateral_asset_id, lender_amount);
        transfer(
            msg_sender()
                .unwrap(),
            collateral_asset_id,
            liquidator_amount,
        );

        let protocol_fee_receiver_identity: Identity = get_identity_from_address(PROTOCOL_FEE_RECEIVER);
        transfer(
            protocol_fee_receiver_identity,
            collateral_asset_id,
            protocol_fee,
        );
        log(LoanLiquidatedEvent {
            loan_id,
            borrower: loan.borrower,
            lender: loan.lender,
            collateral_amount: loan.collateral_amount,
        });
    }

    #[storage(read)]
    fn get_loan(loan_id: u64) -> Loan {
        storage.loans.get(loan_id).read()
    }

    #[storage(read)]
    fn get_loan_status(loan_id: u64) -> u64 {
        storage.loans.get(loan_id).read().status
    }

    #[storage(read)]
    fn get_loan_length() -> u64 {
        storage.loan_length.read() - 1
    }
}

fn get_caller_address() -> Address {
    match msg_sender().unwrap() {
        Identity::Address(identity) => identity,
        _ => revert(0),
    }
}

fn get_asset_id_from_b256(asset: b256) -> AssetId {
    AssetId::from(asset)
}

fn get_identity_from_address(addr: Address) -> Identity {
    Identity::Address(addr)
}
