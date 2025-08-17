contract;

mod interface;
use interface::{
    ClaimExpiredLoanReqEvent,
    Error,
    FixedMarket,
    Loan,
    LoanCancelledEvent,
    LoanFilledEvent,
    LoanLiquidatedEvent,
    LoanRepaidEvent,
    LoanRequestedEvent,
    SRC20,
    Status,
};

use pyth_interface::{data_structures::price::{Price, PriceFeedId}, PythCore};
use std::auth::msg_sender;
use std::block::timestamp;
use std::logging::log;
use std::context::{msg_amount, this_balance};
use std::call_frames::msg_asset_id;
use std::contract_id::ContractId;
use std::bytes::Bytes;
use std::asset::*;
// would be set while deployment as well
configurable {
    PROTOCOL_FEE: u64 = 1000,
    PROTOCOL_LIQUIDATION_FEE: u64 = 100,
    LIQUIDATOR_FEE: u64 = 100,
    PROTOCOL_FEE_RECEIVER: Address = Address::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    TIME_REQUEST_LOAN_GETS_EXPIRED: u64 = 28800,
    MAX_STALENESS_SECONDS: u64 = 30,
}

storage {
    loans: StorageMap<u64, Loan> = StorageMap {},
    loan_length: u64 = 0,
    pyth_contract: ContractId = ContractId::zero(),
    // (base_asset_id, quote_asset_id) -> PythFeedId
    // eg map of (eth, usdc) -> PythFeedId (underlying type is b256)
    oracle_config: StorageMap<(b256, b256), PriceFeedId> = StorageMap {},
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
        if (loan_info.liquidation.liquidation_request) {
            let oracle_contract_id = storage.pyth_contract.read();
            require(
                oracle_contract_id != ContractId::zero(),
                Error::EOracleNotSet,
            );
            let first_pair_check: b256 = storage.oracle_config.get((loan_info.collateral, loan_info.asset)).try_read().unwrap_or(b256::zero());
            let second_pair_check: b256 = storage.oracle_config.get((loan_info.asset, loan_info.collateral)).try_read().unwrap_or(b256::zero());
            require(
                first_pair_check != second_pair_check,
                Error::ENoOracleFeedAvailable,
            );
            require(
                loan_info
                    .liquidation
                    .liquidation_threshold_in_bps < 10000,
                Error::EInvalidLiqThreshold,
            );
        }
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
        if (loan_info.liquidation.liquidation_request) {
            loan.liquidation.liquidation_flag_internal = true;
        }
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
            loan.created_timestamp + TIME_REQUEST_LOAN_GETS_EXPIRED > timestamp(),
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
    #[storage(read, write)]
    fn claim_expired_loan_req(loan_id: u64) {
        let mut loan = storage.loans.get(loan_id).read();
        require(loan.status == 0, Error::EInvalidStatus);
        require(
            timestamp() > loan.created_timestamp + TIME_REQUEST_LOAN_GETS_EXPIRED,
            Error::ELoanReqNotExpired,
        );
        require(
            Identity::Address(loan.borrower) == msg_sender()
                .unwrap(),
            Error::EMsgSenderAndBorrowerNotSame,
        );
        loan.status = 5;
        storage.loans.insert(loan_id, loan);
        let collateral_asset_id: AssetId = get_asset_id_from_b256(loan.collateral);
        transfer(
            msg_sender()
                .unwrap(),
            collateral_asset_id,
            loan.collateral_amount,
        );
        log(ClaimExpiredLoanReqEvent {
            loan_id,
            borrower: loan.borrower,
            amount: loan.collateral_amount,
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
        let can_loan_be_liquidated = can_liquidate_loan(loan_id);
        if (can_loan_be_liquidated) {
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
    }

    #[storage(read)]
    fn get_price_from_oracle(feed_id: PriceFeedId) -> u64 {
        get_price_from_oracle_internal(feed_id)
    }

    #[payable, storage(read)]
    fn pay_and_update_price_feeds(update_data: Vec<Bytes>) {
        let pyth_contract_id = storage.pyth_contract.read();
        require(pyth_contract_id != ContractId::zero(), Error::EOracleNotSet);
        let pyth_oracle_dispatcher = abi(PythCore, pyth_contract_id.bits());
        let fee_to_do_update = pyth_oracle_dispatcher.update_fee(update_data);
        // magic for now taken from pyth fuel dev docs
        let fuel_base_asset = 0xF8f8b6283d7fa5B672b530Cbb84Fcccb4ff8dC40f8176eF4544dDB1f1952AD07;
        require(
            msg_amount() >= fee_to_do_update,
            Error::ENotEnoughForOracleUpdate,
        );
        let fuel_base_asset_id: AssetId = get_asset_id_from_b256(fuel_base_asset);
        require(
            msg_asset_id() == fuel_base_asset_id,
            Error::ENotOracleBaseAssetId,
        );
        pyth_oracle_dispatcher
            .update_price_feeds {
                asset_id: fuel_base_asset,
                coins: fee_to_do_update,
            }(update_data);
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
    #[storage(read)]
    fn is_loan_liquidation_by_oracle(loan_id: u64) -> bool {
        storage.loans.get(loan_id).read().liquidation.liquidation_flag_internal
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

#[storage(read)]
fn can_liquidate_loan(loan_id: u64) -> bool {
    let loan = storage.loans.get(loan_id).read();
    if (timestamp() > loan.start_timestamp + loan.duration) {
        return true
    }

    if (loan.liquidation.liquidation_flag_internal) {
        return check_can_liquidate_based_on_price_ratio_change(loan_id)
    }
    return false
}

#[storage(read)]
fn check_can_liquidate_based_on_price_ratio_change(loan_id: u64) -> bool {
    let loan = storage.loans.get(loan_id).read();
    let price_feed_id_one: b256 = storage.oracle_config.get((loan.collateral, loan.asset)).try_read().unwrap_or(b256::zero());
    let price_feed_id_two: b256 = storage.oracle_config.get((loan.asset, loan.collateral)).try_read().unwrap_or(b256::zero());

    if (price_feed_id_one != b256::zero()) {
        let src20_dispatcher_collateral = abi(SRC20, loan.collateral);
        let collateral_asset_id = get_asset_id_from_b256(loan.collateral);
        let collateral_decimal: u8 = src20_dispatcher_collateral.decimals(collateral_asset_id).unwrap();
        let collateral_decimal_in_u32: u32 = u32::from(collateral_decimal);
        // decimal of asset
        let src20_dispatcher_asset = abi(SRC20, loan.asset);
        let asset_id = get_asset_id_from_b256(loan.asset);
        let asset_decimal: u8 = src20_dispatcher_asset.decimals(asset_id).unwrap();
        let asset_decimal_in_u32: u32 = u32::from(asset_decimal);
        // fetch price from oracle supported market eth/usdc
        let price_from_oracle: u64 = get_price_from_oracle_internal(price_feed_id_one);
        // now collateral and asset value in usd
        let collateral_in_usd = (loan.collateral_amount * price_from_oracle) / (10_u64.pow(collateral_decimal_in_u32));
        // hardcode for now the price of usdc
        let price_of_usdc: u64 = 1_u64;
        let loan_in_usd = (loan.asset_amount * price_of_usdc) / (10_u64.pow(asset_decimal_in_u32));
        // TODO: Need to introduce the precision factor to balance the decimals in u32 instead of u64 
        if loan_in_usd > (collateral_in_usd * loan.liquidation.liquidation_threshold_in_bps / 10000)
        {
            return true
        } else {
            return false
        }
    }
    if (price_feed_id_two != b256::zero()) {
        let src20_dispatcher_collateral = abi(SRC20, loan.collateral);
        let collateral_asset_id = get_asset_id_from_b256(loan.collateral);
        let collateral_decimal: u8 = src20_dispatcher_collateral.decimals(collateral_asset_id).unwrap();
        let collateral_decimal_in_u32: u32 = u32::from(collateral_decimal);

        // decimal of asset
        let src20_dispatcher_asset = abi(SRC20, loan.asset);
        let asset_id = get_asset_id_from_b256(loan.asset);
        let asset_decimal: u8 = src20_dispatcher_asset.decimals(asset_id).unwrap();
        let asset_decimal_in_u32: u32 = u32::from(asset_decimal);
        // fetch price from oracle supported market eth/usdc
        let price_from_oracle: u64 = get_price_from_oracle_internal(price_feed_id_two);
        // now collateral and asset value in usd
        let collateral_in_usd = (loan.collateral_amount * price_from_oracle) / (10_u64.pow(collateral_decimal_in_u32));
        // hardcode for now the price of usdc
        let price_of_usdc: u64 = 1_u64;
        let loan_in_usd = (loan.asset_amount * price_of_usdc) / (10_u64.pow(asset_decimal_in_u32));
        // TODO: Need to introduce the precision factor to balance the decimals in u32 instead of u64 
        if loan_in_usd > (collateral_in_usd * loan.liquidation.liquidation_threshold_in_bps / 10000)
        {
            return true
        } else {
            return false
        }
    }
    false
}

#[storage(read)]
fn get_price_from_oracle_internal(feed_id: PriceFeedId) -> u64 {
    let pyth_contract_id = storage.pyth_contract.read();
    require(pyth_contract_id != ContractId::zero(), Error::EOracleNotSet);

    let pyth_oracle_dispatcher = abi(PythCore, pyth_contract_id.bits());
    let oracle_result = pyth_oracle_dispatcher.price(feed_id);

    require(oracle_result.price > 0, Error::EOraclePriceZero);
    // Pyth oracle uses TAI64 something other block timestamp so could be ahead, type is same u64
    if (oracle_result.publish_time > timestamp()) {
        let time_elapsed_in_seconds = oracle_result.publish_time - timestamp();
        require(
            time_elapsed_in_seconds < MAX_STALENESS_SECONDS,
            Error::EOraclePriceStale,
        );
    } else {
        let time_elapsed_in_seconds = timestamp() - oracle_result.publish_time;
        require(
            time_elapsed_in_seconds < MAX_STALENESS_SECONDS,
            Error::EOraclePriceStale,
        );
    }
    // TODO: check for the spread/confidence and validate
    oracle_result.price
}
