use starknet::ContractAddress;
use core::num::traits::Zero;
use trustlines_erc::tests::utils::{deploy_token, OWNER, ISSUER, MARKETPLACE};

use openzeppelin::access::accesscontrol::DEFAULT_ADMIN_ROLE;
use trustlines_erc::contract::ItrustERC20DispatcherTrait;
use trustlines_erc::contract::ItrustERC20Dispatcher;

use trustlines_erc::constants::OWNER_ROLE;
use trustlines_erc::constants::ISSUER_ROLE;

use trustlines_erc::tests::utils::USER_1;
use trustlines_erc::tests::utils::USER_2;
use trustlines_erc::tests::utils::USER_3;
use trustlines_erc::tests::utils::TEN_K;
use trustlines_erc::tests::utils::FIFTY_K;


use snforge_std::{declare, prank, CheatTarget, CheatSpan,};

fn setup() -> (ContractAddress, ItrustERC20Dispatcher) {
    let token_addr = deploy_token(0, OWNER(), OWNER(), ISSUER(), MARKETPLACE(), false);

    let token = ItrustERC20Dispatcher { contract_address: token_addr };
    (token_addr, token)
}

#[test]
fn test_deploy() {
    let (_, token) = setup();

    assert(token.total_supply() == 0, 'Supply wrong');
    assert(token.name() == "Token", 'Name wrong');
    assert(token.symbol() == "TKN", 'Symbol wrong');
    assert(token.decimals() == 18, 'Decimals wrong');

    assert(token.has_role(DEFAULT_ADMIN_ROLE, OWNER()), 'Wrong owner role');
    assert(!token.has_role(DEFAULT_ADMIN_ROLE, ISSUER()), 'Wrong owner role');
    assert(!token.has_role(DEFAULT_ADMIN_ROLE, USER_1()), 'Wrong owner role');
    assert(!token.has_role(DEFAULT_ADMIN_ROLE, USER_2()), 'Wrong owner role');
    assert(!token.has_role(DEFAULT_ADMIN_ROLE, USER_3()), 'Wrong owner role');

    assert(token.has_role(OWNER_ROLE, OWNER()), 'Wrong owner role');
    assert(token.has_role(ISSUER_ROLE, ISSUER()), 'Wrong issuer role');
    assert(!token.get_transfer_validation_status(), 'wrong validation status');
}

#[test]
fn test_accesscontrol_get_role_admin() {
    let (_, token) = setup();
    assert(token.get_role_admin(OWNER_ROLE) == DEFAULT_ADMIN_ROLE, 'Wrong admin role');
    assert(token.get_role_admin(ISSUER_ROLE) == DEFAULT_ADMIN_ROLE, 'Wrong admin role');
}

#[test]
fn test_accesscontrol_has_role_admin() {
    let (_, token) = setup();

    assert(token.has_role(DEFAULT_ADMIN_ROLE, OWNER()), 'Should be admin');
    assert(!token.has_role(DEFAULT_ADMIN_ROLE, ISSUER()), 'Should not be admin');
}

#[test]
fn test_accesscontrol_grant_role() {
    let (token_address, token) = setup();

    assert(!token.has_role(OWNER_ROLE, USER_1()), 'Should have no role');
    assert(!token.has_role(ISSUER_ROLE, USER_1()), 'Should have no role');

    prank(CheatTarget::One(token_address), OWNER(), CheatSpan::TargetCalls(1));
    token.grant_role(ISSUER_ROLE, USER_1());

    assert(!token.has_role(OWNER_ROLE, USER_1()), 'Should have no role');
    assert(token.has_role(ISSUER_ROLE, USER_1()), 'Should be ISSUER');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_accesscontrol_grant_role_with_issuer() {
    let (token_address, token) = setup();

    prank(CheatTarget::One(token_address), ISSUER(), CheatSpan::TargetCalls(1));
    token.grant_role(ISSUER_ROLE, USER_1());
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_accesscontrol_grant_role_with_user() {
    let (token_address, token) = setup();

    assert(!token.has_role(OWNER_ROLE, USER_1()), 'Should have no role');
    assert(!token.has_role(ISSUER_ROLE, USER_1()), 'Should have no role');

    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    token.grant_role(ISSUER_ROLE, USER_1());
}

#[test]
fn test_accesscontrol_revoke_role() {
    let (token_address, token) = setup();

    assert(!token.has_role(OWNER_ROLE, USER_1()), 'Should have no role');
    assert(!token.has_role(ISSUER_ROLE, USER_1()), 'Should have no role');

    prank(CheatTarget::One(token_address), OWNER(), CheatSpan::TargetCalls(1));
    token.revoke_role(ISSUER_ROLE, ISSUER());

    assert(!token.has_role(ISSUER_ROLE, ISSUER()), 'Should have no role');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_accesscontrol_revoke_role_with_issuer() {
    let (token_address, token) = setup();

    assert(!token.has_role(OWNER_ROLE, USER_1()), 'Should have no role');
    assert(!token.has_role(ISSUER_ROLE, USER_1()), 'Should have no role');

    prank(CheatTarget::One(token_address), ISSUER(), CheatSpan::TargetCalls(1));
    token.revoke_role(OWNER_ROLE, OWNER());
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_accesscontrol_revoke_role_with_user() {
    let (token_address, token) = setup();

    assert(!token.has_role(OWNER_ROLE, USER_1()), 'Should have no role');
    assert(!token.has_role(ISSUER_ROLE, USER_1()), 'Should have no role');

    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    token.revoke_role(ISSUER_ROLE, ISSUER());
}

#[test]
fn test_trustline_propose_new_trustline() {
    let (token_address, token) = setup();

    // User 1 wants to setup a trustline with user 2
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = token.propose_new_trustline(USER_2(), FIFTY_K);

    let tline = token.get_trustline(USER_1(), USER_2());
    assert(tline.amount_effective == 0, 'No effective amount yet');
    assert(tline.amount_proposed == FIFTY_K, 'Wrong proposed amount');
    assert(tline.proposing_party == USER_1(), 'Wrong proposer');
    assert(tline.party_a_used == 0, 'No usage yet');
    assert(tline.party_b_used == 0, 'No usage yet');
}


#[test]
fn test_trustline_accept_new_trustline_proposal() {
    let (token_address, token) = setup();

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = token.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(token_address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = token.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Check the trustline
    let tline = token.get_trustline(USER_1(), USER_2());

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
fn test_trustline_propose_modify_trustline() {
    let (token_address, token) = setup();

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = token.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(token_address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = token.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = token.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    token.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // Read the trustline again and check the proposal is there
    let tline2 = token.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_proposed == FIFTY_K * 2, 'Should be no proposed');
    assert(tline2.proposing_party == USER_1(), 'Should be no proposed');
}

#[test]
fn test_trustline_accept_modify_trustline() {
    let (token_address, token) = setup();

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = token.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(token_address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = token.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = token.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    token.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // Accept modify as user 2
    prank(CheatTarget::One(token_address), USER_2(), CheatSpan::TargetCalls(1));
    token.accept_modify_trustline_proposal(USER_1(), FIFTY_K * 2);

    // Read the trustline again and check the effective is correct
    let tline2 = token.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_proposed == 0, 'Should be no proposed');
    assert(tline2.proposing_party.is_zero(), 'Should be no proposed');
    assert(tline2.amount_effective == FIFTY_K * 2, 'Effective wrong');
}

#[test]
fn test_trustline_cancel_new_trustline_proposal() {
    let (token_address, token) = setup();

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = token.propose_new_trustline(USER_2(), FIFTY_K);

    // Test proposed Trustline between user 1 and 2
    let tline = token.get_trustline(USER_1(), USER_2());
    assert(tline.amount_effective == 0, 'No effective amount yet');
    assert(tline.amount_proposed == FIFTY_K, 'Wrong proposed amount');
    assert(tline.proposing_party == USER_1(), 'Wrong proposer');

    // Cancel the proposal
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    token.cancel_trustline_proposal(USER_2());

    // Test proposed Trustline between user 1 and 2
    let tline = token.get_trustline(USER_1(), USER_2());
    assert(tline.amount_effective == 0, 'No effective amount yet');
    assert(tline.amount_proposed == 0, 'Wrong proposed amount');
    assert(tline.proposing_party.is_zero(), 'Wrong proposer');
}


#[test]
fn test_trustline_cancel_modify_trustline_proposal() {
    let (token_address, token) = setup();

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = token.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(token_address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = token.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    // Make sure trustline has no proposal
    let tline = token.get_trustline(USER_1(), USER_2());
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposed');

    // Propose modify trustline as user 1
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    token.propose_modify_trustline(USER_2(), FIFTY_K * 2);

    // Cancel the proposal
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    token.cancel_trustline_proposal(USER_2());

    let tline2 = token.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_proposed == 0, 'Should be no proposed');
    assert(tline2.proposing_party.is_zero(), 'Should be no proposed');
    assert(tline2.amount_effective == FIFTY_K, 'Wrong effective');
}

#[test]
fn test_decrease_trustline() {
    let (token_address, token) = setup();

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = token.propose_new_trustline(USER_2(), FIFTY_K);

    // User 2 accepts the trustline with same amount
    prank(CheatTarget::One(token_address), USER_2(), CheatSpan::TargetCalls(1));
    let _ = token.accept_new_trustline_proposal(USER_1(), FIFTY_K);

    let tline = token.get_trustline(USER_1(), USER_2());
    assert(tline.amount_effective == FIFTY_K, 'Wrong effective');

    // User 2 decides to decrease the trustline
    prank(CheatTarget::One(token_address), USER_2(), CheatSpan::TargetCalls(1));
    token.decrease_trustline(USER_1(), TEN_K);

    let tline2 = token.get_trustline(USER_1(), USER_2());
    assert(tline2.amount_effective == TEN_K, 'Wrong effective amount');
}


