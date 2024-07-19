use core::num::traits::Zero;
use starknet::ContractAddress;
use starknet::contract_address_const;

use trustlines_erc::holding_limits::IHoldingLimitsDispatcher;
use trustlines_erc::holding_limits::IHoldingLimitsDispatcherTrait;

use trustlines_erc::tests::utils::ZERO_ADDR;
use trustlines_erc::tests::utils::USER_1;
use trustlines_erc::tests::utils::TEN_K;
use trustlines_erc::tests::utils::FIFTY_K;

use snforge_std::{declare, ContractClassTrait, prank, CheatTarget, CheatSpan,};

fn setup() -> ContractAddress {
    let token_contract = declare("HoldingLimitsMock").unwrap();
    let mut calldata = ArrayTrait::<felt252>::new();
    let (address, _) = token_contract.deploy(@calldata).unwrap();
    address
}


#[test]
fn test_set_limit_new() {
    let address = setup();
    let limits = IHoldingLimitsDispatcher { contract_address: address };

    // Set holding limit
    limits.set_holding_limit(USER_1(), TEN_K);

    // Assert that the limit is correct
    let user_limit = limits.get_holding_limit(USER_1());
    assert(user_limit == TEN_K, 'Wrong limit');
}

#[test]
fn test_set_limit_update() {
    let address = setup();
    let limits = IHoldingLimitsDispatcher { contract_address: address };

    // Set holding limit
    limits.set_holding_limit(USER_1(), TEN_K);

    // Assert that the limit is correct
    let user_limit = limits.get_holding_limit(USER_1());
    assert(user_limit == TEN_K, 'Wrong limit');

    // Set holding limit again
    limits.set_holding_limit(USER_1(), TEN_K * 2);
    let user_limit1 = limits.get_holding_limit(USER_1());
    assert(user_limit1 == TEN_K * 2, 'Wrong limit');

    // Set holding limit again
    limits.set_holding_limit(USER_1(), TEN_K / 2);
    let user_limit2 = limits.get_holding_limit(USER_1());
    assert(user_limit2 == TEN_K / 2, 'Wrong limit');

    // Set holding limit to zero
    limits.set_holding_limit(USER_1(), 0);
    let user_limit3 = limits.get_holding_limit(USER_1());
    assert(user_limit3 == 0, 'Wrong limit');
}

#[test]
#[should_panic(expected: ('Cant set limit for zero',))]
fn test_set_limit_zero_address() {
    let address = setup();
    let limits = IHoldingLimitsDispatcher { contract_address: address };

    // Set holding limit for zero address
    limits.set_holding_limit(ZERO_ADDR(), TEN_K);
}


#[test]
fn test_validate_holdings() {
    let address = setup();
    let limits = IHoldingLimitsDispatcher { contract_address: address };

    // Set holding limit
    limits.set_holding_limit(USER_1(), TEN_K);

    limits.validate_holdings(USER_1(), TEN_K / 2);
    limits.validate_holdings(USER_1(), TEN_K / 5);
    limits.validate_holdings(USER_1(), 1);
}

#[test]
#[should_panic(expected: ('Holdings over limit',))]
fn test_validate_holdings_failing() {
    let address = setup();
    let limits = IHoldingLimitsDispatcher { contract_address: address };

    // Set holding limit
    limits.set_holding_limit(USER_1(), TEN_K);

    limits.validate_holdings(USER_1(), TEN_K * 2);
}
