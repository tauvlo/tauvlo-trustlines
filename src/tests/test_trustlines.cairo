use core::num::traits::Zero;
use starknet::ContractAddress;
use starknet::contract_address_const;

use trustlines_erc::trustlines::TrustlinesComponent;
use trustlines_erc::trustlines::TrustlinesComponent::Trustline;
use trustlines_erc::trustlines::TrustlinesComponent::TrustlineTrait;
use trustlines_erc::trustlines::ITrustlinesDispatcher;
use trustlines_erc::trustlines::ITrustlinesDispatcherTrait;
use trustlines_erc::tests::mocks::trustlines_mock::TrustlinesMock;

use trustlines_erc::tests::utils::ZERO_ADDR;
use trustlines_erc::tests::utils::USER_1;
use trustlines_erc::tests::utils::USER_2;
use trustlines_erc::tests::utils::USER_3;
use trustlines_erc::tests::utils::TEN_K;
use trustlines_erc::tests::utils::FIFTY_K;


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
    let _ = trustline.propose_new_trustline(ZERO_ADDR(), FIFTY_K);
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


#[test]
fn test_propose_modify_trustline() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // Read the trustline again and check the proposal is there
    let tline2 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_proposed == FIFTY_K * 2, 'Should be no proposed');
    assert(tline2.proposing_party == USER_1(), 'Should be no proposed');
}

#[test]
#[should_panic(expected: ('Trustline does not exist',))]
fn test_propose_modify_trustline_non_existing() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // Propose modify trustline as user 1 with user 2 (no such trustline existing)
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K);
}

#[test]
#[should_panic(expected: ('Proposed must be > effective',))]
fn test_propose_modify_trustline_lower_amount() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1 with lower amount
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), TEN_K);
}

#[test]
#[should_panic(expected: ('Proposed must be > effective',))]
fn test_propose_modify_trustline_same_amount() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1 with same amount as effective
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K);
}

#[test]
#[should_panic(expected: ('Parties are the same',))]
fn test_propose_modify_trustline_caller_same_as_other_party() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Propose modify trustline as user 1 with other party being user 1
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_1(), FIFTY_K);
}

#[test]
#[should_panic(expected: ('Other party address is zero',))]
fn test_propose_modify_trustline_other_party_zero() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Propose modify trustline as user 1 with other party being 0 addr
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(ZERO_ADDR(), FIFTY_K);
}

#[test]
#[should_panic(expected: ('Trustline already has proposal',))]
fn test_propose_modify_trustline_already_proposed() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Propose modify trustline as user 1 
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // Propose modify trustline again
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K * 2);
}


#[test]
#[should_panic(expected: ('Trustline already has proposal',))]
fn test_propose_modify_trustline_already_proposed_by_different_user() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Propose modify trustline as user 1 
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // Propose modify trustline as user 2
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_1(), FIFTY_K * 2);
}

#[test]
fn test_accept_modify_trustline() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // Accept modify as user 2
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.accept_modify_trustline_proposal(USER_1(), FIFTY_K * 2);

    // Read the trustline again and check the effective is correct
    let tline2 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_proposed == 0, 'Should be no proposed');
    assert(tline2.proposing_party == ZERO_ADDR(), 'Should be no proposed');
    assert(tline2.amount_effective == FIFTY_K * 2, 'Effective wrong');
}


#[test]
#[should_panic(expected: ('Proposed < effective',))]
fn test_accept_modify_trustline_amount_below_effective() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // Accept modify as user 2 with amount below current effective
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.accept_modify_trustline_proposal(USER_1(), TEN_K);
}

#[test]
fn test_accept_modify_trustline_amount_below_proposed() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    let amount = FIFTY_K * 2 - TEN_K;

    // Accept modify as user 2 with amount below current proposed amount
    // (but above current effective)
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.accept_modify_trustline_proposal(USER_1(), amount);

    // Read the trustline again and check the effective is correct
    let tline2 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_proposed == 0, 'Should be no proposed');
    assert(tline2.proposing_party == ZERO_ADDR(), 'Should be no proposed');
    assert(tline2.amount_effective == amount, 'Effective wrong');
}

#[test]
fn test_accept_modify_trustline_amount_above_proposed() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // Accept modify as user 2 with amount below current effective
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.accept_modify_trustline_proposal(USER_1(), FIFTY_K * 2 + TEN_K);

    // Read the trustline again and check the effective is correct
    let tline2 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_proposed == 0, 'Should be no proposed');
    assert(tline2.proposing_party == ZERO_ADDR(), 'Should be no proposed');
    assert(tline2.amount_effective == FIFTY_K * 2, 'Effective wrong');
}

#[test]
#[should_panic(expected: ('Proposed amount is zero',))]
fn test_accept_modify_trustline_amount_zero() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // Accept modify as user 2 with amount below current effective
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.accept_modify_trustline_proposal(USER_1(), 0);
}

#[test]
#[should_panic(expected: ('No trustline proposed found',))]
fn test_accept_modify_trustline_not_existing() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // Accept modify as user 2 but there is no trustline
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.accept_modify_trustline_proposal(USER_1(), 1);
}

#[test]
#[should_panic(expected: ('No proposed amount',))]
fn test_accept_modify_trustline_no_proposal() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Try Accept modify as user 2 
    // But there is no proposal
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.accept_modify_trustline_proposal(USER_1(), FIFTY_K * 2);
}


#[test]
#[should_panic(expected: ('Trustline not effective',))]
fn test_accept_modify_trustline_not_effective() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // Try Accept modify as user 2 
    // But the trustline is not effective (newly proposed only)
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.accept_modify_trustline_proposal(USER_1(), FIFTY_K * 2);
}


#[test]
fn test_cancel_new_trustline_proposal() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // Test proposed Trustline between user 1 and 2
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_effective == 0, 'No effective amount yet');
    assert(tline.amount_proposed == FIFTY_K, 'Wrong proposed amount');
    assert(tline.proposing_party == USER_1(), 'Wrong proposer');

    // Cancel the proposal
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.cancel_trustline_proposal(USER_2());

    // Test proposed Trustline between user 1 and 2
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_effective == 0, 'No effective amount yet');
    assert(tline.amount_proposed == 0, 'Wrong proposed amount');
    assert(tline.proposing_party == ZERO_ADDR(), 'Wrong proposer');
}

#[test]
fn test_cancel_modify_trustline_proposal() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // Cancel the proposal
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.cancel_trustline_proposal(USER_2());

    let tline2 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_proposed == 0, 'Should be no proposed');
    assert(tline2.proposing_party.is_zero(), 'Should be no proposed');
    assert(tline2.amount_effective == FIFTY_K, 'Wrong effective');
}

#[test]
#[should_panic(expected: ('Proposed trustline exists',))]
fn test_propose_new_trustline_cancel_propose_new_again() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 1 cancels the proposal 
    // (trustline already exists to it'll fail on next step)
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.cancel_trustline_proposal(USER_2());

    // User 1 tries to setup trustline with user 2 again
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);
}

#[test]
fn test_propose_new_trustline_cancel_propose_modify() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 1 cancels the proposal 
    // (trustline already exists)
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.cancel_trustline_proposal(USER_2());

    // User 1 proposes modification 
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K);

    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == FIFTY_K, 'Should be no proposed');
    assert(!tline.proposing_party.is_zero(), 'Should be no proposed');
    assert(tline.amount_effective == 0, 'Wrong effective');
}


#[test]
fn test_decrease_trustline() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_effective == FIFTY_K, 'Wrong effective');

    // User 2 decides to decrease the trustline
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.decrease_trustline(USER_1(), TEN_K);

    let tline2 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_effective == TEN_K, 'Wrong effective amount');
}

#[test]
#[should_panic(expected: ('Trustline not effective',))]
fn test_decrease_trustline_not_effective() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 decides to decrease the trustline
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.decrease_trustline(USER_1(), TEN_K);
}

#[test]
fn test_decrease_trustline_with_modify_proposal() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_effective == FIFTY_K, 'Wrong effective');

    // Propose modify trustline as user 1
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // User 2 decides to decrease the trustline
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.decrease_trustline(USER_1(), TEN_K);

    let tline2 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_effective == TEN_K, 'Wrong effective');
}

#[test]
fn test_transfer() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // User 1 transfers 10k to user 2
    // No prank needed
    trustline.trustline_transfer(USER_1(), USER_2(), TEN_K);

    // USER_1 felt252 is party_b here
    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.party_b_used == 0, 'Wrong used b');
    assert(tline.party_a_used == TEN_K, 'Wrong used a');

    // USER_2 transfers back
    trustline.trustline_transfer(USER_2(), USER_1(), TEN_K);
    let tline2 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline2.party_b_used == 0, 'Wrong used b');
    assert(tline2.party_a_used == 0, 'Wrong used a');

    // USER_1 transfers 50k (max limit)
    trustline.trustline_transfer(USER_1(), USER_2(), FIFTY_K);
    let tline3 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline3.party_b_used == 0, 'Wrong used b');
    assert(tline3.party_a_used == FIFTY_K, 'Wrong used a');

    // USER_2 transfers 100k (he can because user1 already sent him 50k)
    trustline.trustline_transfer(USER_2(), USER_1(), FIFTY_K * 2);
    let tline4 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline4.party_b_used == FIFTY_K, 'Wrong used b');
    assert(tline4.party_a_used == 0, 'Wrong used a');

    // USER_1 transfers 50k 
    trustline.trustline_transfer(USER_1(), USER_2(), FIFTY_K);
    let tline5 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline5.party_b_used == 0, 'Wrong used b');
    assert(tline5.party_a_used == 0, 'Wrong used a');
    assert(tline5.amount_effective == FIFTY_K, 'wrong effective');
    assert(tline5.amount_proposed == 0, 'wrong proposed');
    assert(tline5.proposing_party == ZERO_ADDR(), 'Wrong proposing party');
}

#[test]
#[should_panic(expected: ('Trustline does not exist',))]
fn test_transfer_non_existing_trustline() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 tries to transfer 10k to user 2
    // but the trustline does not exist
    trustline.trustline_transfer(USER_1(), USER_2(), TEN_K);
}


#[test]
#[should_panic(expected: ('Amount over limit',))]
fn test_transfer_amount_over_effective() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // User 1 transfers 10k to user 2
    // No prank needed
    trustline.trustline_transfer(USER_1(), USER_2(), FIFTY_K * 2);
}

#[test]
#[should_panic(expected: ('Amount over limit',))]
fn test_transfer_amount_over_effective_after_transfer() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // User 1 transfers 10k to user 2
    // No prank needed
    trustline.trustline_transfer(USER_1(), USER_2(), TEN_K);

    // User 2 transfers 70k to user 1
    // No prank needed
    trustline.trustline_transfer(USER_1(), USER_2(), TEN_K * 2 + FIFTY_K);
}

#[test]
#[should_panic(expected: ('From and to addresses same',))]
fn test_transfer_from_is_to() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 transfers 10k to user 1
    trustline.trustline_transfer(USER_1(), USER_1(), TEN_K);
}

#[test]
#[should_panic(expected: ('Trustline not effective',))]
fn test_transfer_zero_effective() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // User 2 decreases trustline to 0 
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.decrease_trustline(USER_1(), 0);

    // User 1 tries to transfer
    trustline.trustline_transfer(USER_1(), USER_2(), TEN_K);
}

#[test]
fn test_propose_modify_with_transfered() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = trustline.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // User 1 transfers TEN_K
    trustline.trustline_transfer(USER_1(), USER_2(), TEN_K);

    // Propose modify trustline as user 2
    prank(CheatTarget::One(address), USER_2(), CheatSpan::TargetCalls(1));
    trustline.propose_modify_trustline(USER_1(), FIFTY_K * 2);

    let tline = trustline.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == FIFTY_K * 2, 'Wrong proposed');
    assert(tline.proposing_party == USER_2(), 'Wrong user');
    assert(tline.party_b_used == 0, 'Wrong used b');
    assert(tline.party_a_used == TEN_K, 'Wrong used a');

    // Accept modify as user 1
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    trustline.accept_modify_trustline_proposal(USER_2(), FIFTY_K * 2);

    let tline2 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_proposed == 0, 'Wrong proposed');
    assert(tline2.proposing_party == ZERO_ADDR(), 'Wrong user');
    assert(tline2.party_b_used == 0, 'Wrong used b');
    assert(tline2.party_a_used == TEN_K, 'Wrong used a');
    assert(tline2.amount_effective == FIFTY_K * 2, 'wrong effective');

    // Transfer 110k from user 2 to user 1
    trustline.trustline_transfer(USER_2(), USER_1(), FIFTY_K * 2 + TEN_K);

    let tline3 = trustline.get_trustline(USER_1(), USER_2());
    assert(tline3.amount_proposed == 0, 'Wrong proposed');
    assert(tline3.proposing_party == ZERO_ADDR(), 'Wrong user');
    assert(tline3.party_b_used == FIFTY_K * 2, 'Wrong used b');
    assert(tline3.party_a_used == 0, 'Wrong used a');
    assert(tline3.amount_effective == FIFTY_K * 2, 'wrong effective');
}

