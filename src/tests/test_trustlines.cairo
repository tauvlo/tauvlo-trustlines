use starknet::ContractAddress;
use starknet::contract_address_const;

use trustlines_erc::trustlines::TrustlinesComponent;
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

#[test]
fn test_propose_new_trustline() {
    let address = setup();
    let trustline = ITrustlinesDispatcher { contract_address: address };

    // User 1 wants to setup trustline with user 2
    prank(CheatTarget::One(address), USER_1(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_2(), FIFTY_K);

    // User 3 wants to setup trustline with user 1
    prank(CheatTarget::One(address), USER_3(), CheatSpan::TargetCalls(1));
    let _ = trustline.propose_new_trustline(USER_1(), TEN_K);

    
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

    // Test proposed Trustline between user 3 and 1
    let users_3_1_line = trustline.get_trustline(USER_3(), USER_1());
    assert(users_3_1_line.amount_effective == 0, 'No effective amount yet');
    assert(users_3_1_line.amount_proposed == TEN_K, 'Wrong proposed amount');
    assert(users_3_1_line.proposing_party == USER_3(), 'Wrong proposer');
    assert(users_3_1_line.party_a_used == 0, 'No usage yet');
    assert(users_3_1_line.party_b_used == 0, 'No usage yet');

    if users_3_1_line.party_a == USER_3() {
        assert(users_3_1_line.party_b == USER_1(), 'Wrong party');
    } else {
        assert(users_3_1_line.party_a == USER_1(), 'Wrong party');
        assert(users_3_1_line.party_b == USER_3(), 'Wrong party');
    }

    // Now test that if we read the trustline with reversed users then it
    // still returns the same trustline
    let users_1_2_line_reversed = trustline.get_trustline(USER_2(), USER_1());
    assert(users_1_2_line_reversed.party_a == users_1_2_line.party_a, 'Trustlines not the same');
    assert(users_1_2_line_reversed.party_b == users_1_2_line.party_b, 'Trustlines not the same');
    assert(users_1_2_line_reversed.amount_effective == users_1_2_line.amount_effective, 'Trustlines not the same');
    assert(users_1_2_line_reversed.amount_proposed == users_1_2_line.amount_proposed, 'Trustlines not the same');
    assert(users_1_2_line_reversed.proposing_party == users_1_2_line.proposing_party, 'Trustlines not the same');
    assert(users_1_2_line_reversed.party_a_used == users_1_2_line.party_a_used, 'Trustlines not the same');
    assert(users_1_2_line_reversed.party_b_used == users_1_2_line.party_b_used, 'Trustlines not the same');

    let users_3_1_line_reversed = trustline.get_trustline(USER_1(), USER_3());
    assert(users_3_1_line_reversed.party_a == users_3_1_line.party_a, 'Trustlines not the same');
    assert(users_3_1_line_reversed.party_b == users_3_1_line.party_b, 'Trustlines not the same');
    assert(users_3_1_line_reversed.amount_effective == users_3_1_line.amount_effective, 'Trustlines not the same');
    assert(users_3_1_line_reversed.amount_proposed == users_3_1_line.amount_proposed, 'Trustlines not the same');
    assert(users_3_1_line_reversed.proposing_party == users_3_1_line.proposing_party, 'Trustlines not the same');
    assert(users_3_1_line_reversed.party_a_used == users_3_1_line.party_a_used, 'Trustlines not the same');
    assert(users_3_1_line_reversed.party_b_used == users_3_1_line.party_b_used, 'Trustlines not the same');

}



