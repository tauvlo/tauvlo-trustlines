use core::num::traits::Zero;
use starknet::ContractAddress;
use starknet::contract_address_const;

use trustlines_erc::trustlines::TrustlinesComponent;
use trustlines_erc::trustlines::TrustlinesComponent::Trustline;
use trustlines_erc::trustlines::TrustlinesComponent::TrustlineTrait;
use trustlines_erc::trustlines::ITrustlinesDispatcher;
use trustlines_erc::trustlines::ITrustlinesDispatcherTrait;
use trustlines_erc::tests::mocks::trustlines_mock::TrustlinesMock;


const TEN_K: u256 = 10000000000000000000000;
const FIFTY_K: u256 = 50000000000000000000000;


fn USER_1() -> ContractAddress {
    contract_address_const::<'USER_1'>()
}
fn USER_2() -> ContractAddress {
    contract_address_const::<'USER_2'>()
}
fn USER_3() -> ContractAddress {
    contract_address_const::<'USER_3'>()
}

use snforge_std::{declare, ContractClassTrait, prank, CheatTarget, CheatSpan,};

fn setup() -> ContractAddress {
    let token_contract = declare("TrustlinesMock").unwrap();
    let mut calldata = ArrayTrait::<felt252>::new();
    let (address, _) = token_contract.deploy(@calldata).unwrap();
    address
}

// TODO: Spy event emition at relevant tests 

#[test]
fn test_propose_new_trustline() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // Test proposed Trustline between user 1 and 2
    let users_1_2_line = trustline.get_trustline(USER_1(), USER_2());
    assert(users_1_2_line.amount_effective == 0, 'No effective amount yet');
    assert(users_1_2_line.amount_proposed == FIFTY_K, 'Wrong proposed amount');
    assert(users_1_2_line.proposing_party == USER_1(), 'Wrong proposer');
    assert(users_1_2_line.party_a_used == 0, 'No usage yet');
    assert(users_1_2_line.party_b_used == 0, 'No usage yet');

    if users_1_2_line.party_a == USER_1() {
        assert(users_1_2_line.party_b == USER_2(), 'Wrong party');
    } else {
        assert(users_1_2_line.party_a == USER_2(), 'Wrong party');
        assert(users_1_2_line.party_b == USER_1(), 'Wrong party');
    }

    // Now test that if we read the trustline with reversed users then it
    // still returns the same trustline
    let users_1_2_line_reversed = trustline.get_trustline(USER_2(), USER_1());
    assert(users_1_2_line_reversed.party_a == users_1_2_line.party_a, 'Trustlines not the same');
    assert(users_1_2_line_reversed.party_b == users_1_2_line.party_b, 'Trustlines not the same');
    assert(
        users_1_2_line_reversed.amount_effective == users_1_2_line.amount_effective,
        'Trustlines not the same'
    );
    assert(
        users_1_2_line_reversed.amount_proposed == users_1_2_line.amount_proposed,
        'Trustlines not the same'
    );
    assert(
        users_1_2_line_reversed.proposing_party == users_1_2_line.proposing_party,
        'Trustlines not the same'
    );
    assert(
        users_1_2_line_reversed.party_a_used == users_1_2_line.party_a_used,
        'Trustlines not the same'
    );
    assert(
        users_1_2_line_reversed.party_b_used == users_1_2_line.party_b_used,
        'Trustlines not the same'
    );
}

#[test]
#[should_panic(expected: ('Proposed trustline exists',))]
fn test_propose_new_trustline_already_proposed_same_amount() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // Try to proposed the same amount by the same user again
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_new_trustline(USER_2(), FIFTY_K);
}

#[test]
#[should_panic(expected: ('Proposed trustline exists',))]
fn test_propose_new_trustline_already_proposed_different_amount() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // Try to proposed the same amount by the same user again
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_new_trustline(USER_2(), TEN_K);
}

#[test]
#[should_panic(expected: ('Proposed trustline exists',))]
fn test_propose_new_trustline_already_proposed_different_user() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // Try to propose by different user
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.propose_new_trustline(USER_1(), TEN_K);
}

#[test]
#[should_panic(expected: ('Parties are the same',))]
fn test_propose_other_user_is_caller() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_1(), FIFTY_K);
}

#[test]
#[should_panic(expected: ('Proposed amount is zero',))]
fn test_propose_zero_amount() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2 but amount is zero
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), 0);
}

#[test]
#[should_panic(expected: ('Other party address is zero',))]
fn test_propose_zero_other_party() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2 but amount is zero
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(contract_address_const::<0>(), FIFTY_K);
}


#[test]
fn test_accept_new_trustline_proposal_same_amount() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Check the trustline
    let tline = trustline.get_trustline(USER_1(), USER_2());

    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposer');
    assert(tline.amount_effective == FIFTY_K, 'Wrong effective amount');
    assert(tline.party_a_used == 0, 'Should be no used');
    assert(tline.party_b_used == 0, 'Should be no used');

    if tline.party_a == USER_1() {
        assert(tline.party_b == USER_2(), 'Wrong party');
    } else {
        assert(tline.party_a == USER_2(), 'Wrong party');
        assert(tline.party_b == USER_1(), 'Wrong party');
    }
}

#[test]
fn test_accept_new_trustline_proposal_lower_amount() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), TEN_K);

    // Check the trustline
    let tline = trustline.get_trustline(USER_1(), USER_2());

    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposer');
    assert(tline.amount_effective == TEN_K, 'Wrong effective amount');
    assert(tline.party_a_used == 0, 'Should be no used');
    assert(tline.party_b_used == 0, 'Should be no used');

    if tline.party_a == USER_1() {
        assert(tline.party_b == USER_2(), 'Wrong party');
    } else {
        assert(tline.party_a == USER_2(), 'Wrong party');
        assert(tline.party_b == USER_1(), 'Wrong party');
    }
}

#[test]
fn test_accept_new_trustline_proposal_higher_amount() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K * 2);

    // Check the trustline
    let tline = trustline.get_trustline(USER_1(), USER_2());

    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposer');
    assert(tline.amount_effective == FIFTY_K, 'Wrong effective amount');
    assert(tline.party_a_used == 0, 'Should be no used');
    assert(tline.party_b_used == 0, 'Should be no used');

    if tline.party_a == USER_1() {
        assert(tline.party_b == USER_2(), 'Wrong party');
    } else {
        assert(tline.party_a == USER_2(), 'Wrong party');
        assert(tline.party_b == USER_1(), 'Wrong party');
    }
}

#[test]
#[should_panic(expected: ('Caller is proposer',))]
fn test_accept_new_trustline_proposal_caller_is_proposer() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 1 accepts the trustline but hes the proposer
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_2(), FIFTY_K);
}

#[test]
#[should_panic(expected: ('Proposed amount is zero',))]
fn test_accept_new_trustline_proposal_amount_zero() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 1 accepts the trustline but hes the proposer
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_2(), 0);
}


#[test]
#[should_panic(expected: ('Trustline already effective',))]
fn test_accept_new_trustline_proposal_accept_again() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Check the trustline
    let tline = trustline.get_trustline(USER_1(), USER_2());

    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposer');
    assert(tline.amount_effective == FIFTY_K, 'Wrong effective amount');
    assert(tline.party_a_used == 0, 'Should be no used');
    assert(tline.party_b_used == 0, 'Should be no used');

    if tline.party_a == USER_1() {
        assert(tline.party_b == USER_2(), 'Wrong party');
    } else {
        assert(tline.party_a == USER_2(), 'Wrong party');
        assert(tline.party_b == USER_1(), 'Wrong party');
    }

    // User 2 accepts the trustline with same amount again
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);
}

#[test]
#[should_panic(expected: ('No trustline proposed found',))]
fn test_accept_new_trustline_proposal_non_existing() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 2 accepts trustline that does not exist
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);
}

