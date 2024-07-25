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

const FIVE_HUNDRED_K: u256 = 500000000000000000000000;

#[test]
fn test_deploy() {
    let (_, token) = setup();

    assert(token.total_supply() == FIVE_HUNDRED_K, 'Supply wrong');
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
fn test_trustline_decrease_trustline() {
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

#[test]
fn test_holding_limit_set_hard_limit() {
    let (token_address, token) = setup();

    // Set holding limit
    prank(CheatTarget::One(token_address), ISSUER(), CheatSpan::TargetCalls(1));
    token.set_hard_holding_limit(USER_1(), TEN_K);

    // Assert that the limit is correct
    let user_limit = token.get_holding_limits(USER_1());
    assert(user_limit.hard_limit == TEN_K, 'Wrong hard');
    assert(user_limit.soft_limit == 0, 'Wrong soft');
}

#[test]
fn test_holding_limit_set_soft_limit() {
    let (token_address, token) = setup();

    // Set holding limit
    prank(CheatTarget::One(token_address), ISSUER(), CheatSpan::TargetCalls(1));
    token.set_hard_holding_limit(USER_1(), TEN_K);

    // Assert that the limit is correct
    let user_limit = token.get_holding_limits(USER_1());
    assert(user_limit.hard_limit == TEN_K, 'Wrong hard');
    assert(user_limit.soft_limit == 0, 'Wrong soft');

    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    token.set_soft_holding_limit(TEN_K / 2);

    // Assert that the limit is correct
    let user_limit = token.get_holding_limits(USER_1());
    assert(user_limit.hard_limit == TEN_K, 'Wrong hard');
    assert(user_limit.soft_limit == TEN_K / 2, 'Wrong soft');
}

#[test]
#[should_panic(expected: ('Sender frozen',))]
fn test_freeze_sender_frozen() {
    let (token_address, token) = setup();
    set_hard_soft_limit(token_address, USER_1(), FIFTY_K, FIFTY_K,);
    create_trustline(token_address, USER_1(), MARKETPLACE(), FIFTY_K);

    // Send some funds to user
    prank(CheatTarget::One(token_address), MARKETPLACE(), CheatSpan::TargetCalls(1));
    token.transfer(USER_1(), 100);

    // Freeze user
    prank(CheatTarget::One(token_address), ISSUER(), CheatSpan::TargetCalls(1));
    token.set_freeze_status(USER_1(), true);

    // User tries to send tokens
    prank(CheatTarget::One(token_address), USER_1(), CheatSpan::TargetCalls(1));
    token.transfer(MARKETPLACE(), 100);
}

#[test]
#[should_panic(expected: ('Recipient frozen',))]
fn test_freeze_recipient_frozen() {
    let (token_address, token) = setup();
    set_hard_soft_limit(token_address, USER_1(), FIFTY_K, FIFTY_K,);
    create_trustline(token_address, USER_1(), MARKETPLACE(), FIFTY_K);

    // Freeze user
    prank(CheatTarget::One(token_address), ISSUER(), CheatSpan::TargetCalls(1));
    token.set_freeze_status(USER_1(), true);

    // Try to send some funds to user
    prank(CheatTarget::One(token_address), MARKETPLACE(), CheatSpan::TargetCalls(1));
    token.transfer(USER_1(), 100);
}


#[test]
fn test_contract_transfer() {
    let (token_address, token) = setup();

    set_hard_soft_limit(token_address, USER_1(), FIFTY_K, FIFTY_K,);
    create_trustline(token_address, MARKETPLACE(), USER_1(), FIFTY_K);

    prank(CheatTarget::One(token_address), MARKETPLACE(), CheatSpan::TargetCalls(1));
    token.transfer(USER_1(), TEN_K);

    let user_balance = token.balance_of(USER_1());
    let tline = token.get_trustline(USER_1(), MARKETPLACE());

    assert(user_balance == TEN_K, 'Wrong balance');
    assert(tline.amount_proposed == 0, 'Should be no proposed');
    assert(tline.proposing_party.is_zero(), 'Should be no proposer');
    assert(tline.amount_effective == FIFTY_K, 'Wrong effective amount');

    // Party a is market place
    assert(tline.party_a_used == TEN_K, 'Should be no used');
    assert(tline.party_b_used == 0, 'Should be no used');
}

#[test]
#[should_panic(expected: ('Amount over limit',))]
fn test_contract_transfer_over_trustline() {
    let (token_address, token) = setup();

    set_hard_soft_limit(token_address, USER_1(), FIFTY_K, FIFTY_K,);
    create_trustline(token_address, MARKETPLACE(), USER_1(), FIFTY_K);

    prank(CheatTarget::One(token_address), MARKETPLACE(), CheatSpan::TargetCalls(1));
    token.transfer(USER_1(), TEN_K + FIFTY_K);
}

#[test]
#[should_panic(expected: ('Holdings over limit',))]
fn test_contract_transfer_over_holding_limit() {
    let (token_address, token) = setup();

    set_hard_soft_limit(token_address, USER_1(), FIFTY_K, FIFTY_K,);
    create_trustline(token_address, MARKETPLACE(), USER_1(), FIFTY_K * 2);

    prank(CheatTarget::One(token_address), MARKETPLACE(), CheatSpan::TargetCalls(1));
    token.transfer(USER_1(), TEN_K + FIFTY_K);
}

#[test]
fn test_contract_pull_assets() {
    let (token_address, token) = setup();

    set_hard_soft_limit(token_address, USER_1(), FIFTY_K, FIFTY_K,);
    create_trustline(token_address, MARKETPLACE(), USER_1(), FIFTY_K);
    fund_account(token_address, USER_1(), TEN_K);

    assert(token.balance_of(USER_1()) == TEN_K, 'Wrong user bal1');
    assert(token.balance_of(OWNER()) == 0, 'Wrong owner bal1');

    prank(CheatTarget::One(token_address), ISSUER(), CheatSpan::TargetCalls(1));
    token.pull_assets(USER_1(), OWNER(), TEN_K);

    assert(token.balance_of(USER_1()) == 0, 'Wrong user bal2');
    assert(token.balance_of(OWNER()) == TEN_K, 'Wrong owner bal2');
}


// TODO TESTS
// Validate transfer
//      - failing
//      - ot failing
// Transfer
//     - Under trustline limit
//     - Over trustline limit
//     - Under holding limit
//     - Over holding limit
// Transfer to market place

////////////////////////////////////////////////
// Helper functions for easier testing
////////////////////////////////////////////////

fn setup() -> (ContractAddress, ItrustERC20Dispatcher) {
    let token_addr = deploy_token(
        FIVE_HUNDRED_K, MARKETPLACE(), OWNER(), ISSUER(), MARKETPLACE(), false
    );

    let token = ItrustERC20Dispatcher { contract_address: token_addr };
    (token_addr, token)
}

fn set_hard_soft_limit(
    token_address: ContractAddress, user_address: ContractAddress, hard: u256, soft: u256
) {
    let token = ItrustERC20Dispatcher { contract_address: token_address };
    prank(CheatTarget::One(token_address), ISSUER(), CheatSpan::TargetCalls(1));
    token.set_hard_holding_limit(user_address, hard);
    prank(CheatTarget::One(token_address), user_address, CheatSpan::TargetCalls(1));
    token.set_soft_holding_limit(soft);
}

fn fund_account(token_address: ContractAddress, user: ContractAddress, amount: u256) {
    // Send user some funds from marketplace
    let token = ItrustERC20Dispatcher { contract_address: token_address };

    prank(CheatTarget::One(token_address), MARKETPLACE(), CheatSpan::TargetCalls(1));
    token.transfer(user, amount);
}

fn create_trustline(
    token_address: ContractAddress, user1: ContractAddress, user2: ContractAddress, amount: u256
) {
    let token = ItrustERC20Dispatcher { contract_address: token_address };

    // User 1 will be party_a in trustlines
    prank(CheatTarget::One(token_address), user1, CheatSpan::TargetCalls(1));
    let _ = token.propose_new_trustline(user2, amount);

    prank(CheatTarget::One(token_address), user2, CheatSpan::TargetCalls(1));
    let _ = token.accept_new_trustline_proposal(user1, amount);
}


// Basic setup for transfer testing
fn test_transfer_setup(token_address: ContractAddress,) {
    // Set hard/soft limits for USER 1,2
    set_hard_soft_limit(token_address, USER_1(), FIFTY_K, FIFTY_K,);
    set_hard_soft_limit(token_address, USER_2(), FIFTY_K, FIFTY_K,);

    // Create trustline between user 1 and marketplace
    create_trustline(token_address, USER_1(), MARKETPLACE(), FIFTY_K);
    // Create trustline between user 1 and user 2
    create_trustline(token_address, USER_1(), USER_2(), FIFTY_K);
}

