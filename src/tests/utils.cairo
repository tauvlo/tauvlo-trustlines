// use traits::{Into, TryInto};
use starknet::ContractAddress;
use starknet::contract_address_const;

use snforge_std::{
    declare, 
    ContractClassTrait, 
    // start_prank, stop_prank, start_warp, stop_warp, ContractClass, start_mock_call, stop_mock_call, start_roll
};

pub(crate) fn OWNER() -> ContractAddress {
    contract_address_const::<'OWNER'>()
}
pub(crate) fn ISSUER() -> ContractAddress {
    contract_address_const::<'ISSUER'>()
}
pub(crate) fn THIRD_PARTY() -> ContractAddress {
    contract_address_const::<'THIRD_PARTY'>()
}


fn deploy_token(
    initial_supply: u256,
    recipient: ContractAddress,
    owner: ContractAddress,
    issuer: ContractAddress,
    third_party: ContractAddress, // TODO: Better name for last role
) -> ContractAddress {
    
    let token_contract = declare("trustERC20").unwrap();

    let mut token_deploy_calldata = ArrayTrait::<felt252>::new();
    token_deploy_calldata.append(initial_supply.try_into().unwrap());
    token_deploy_calldata.append(0);
    token_deploy_calldata.append(recipient.into());
    token_deploy_calldata.append(owner.into());
    token_deploy_calldata.append(issuer.into());
    token_deploy_calldata.append(third_party.into());

    let (token_address, _) = token_contract.deploy(@token_deploy_calldata).unwrap();

    token_address
}

#[test]
fn tmp() {
    let _ = deploy_token(
        0,
        OWNER(),
        OWNER(),
        ISSUER(),
        THIRD_PARTY()
    );
}
