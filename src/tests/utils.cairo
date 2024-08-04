// use traits::{Into, TryInto};
use starknet::ContractAddress;
use starknet::contract_address_const;

use snforge_std::{
    declare,
    ContractClassTrait, // start_prank, stop_prank, start_warp, stop_warp, ContractClass, start_mock_call, stop_mock_call, start_roll
};

pub(crate) fn OWNER() -> ContractAddress {
    contract_address_const::<'OWNER'>()
}
pub(crate) fn ISSUER() -> ContractAddress {
    contract_address_const::<'ISSUER'>()
}
pub(crate) fn MARKETPLACE() -> ContractAddress {
    contract_address_const::<'MARKETPLACE'>()
}

pub(crate) fn ZERO_ADDR() -> ContractAddress {
    contract_address_const::<0>()
}
pub(crate) fn USER_1() -> ContractAddress {
    contract_address_const::<'USER_1'>()
}
pub(crate) fn USER_2() -> ContractAddress {
    contract_address_const::<'USER_2'>()
}
pub(crate) fn USER_3() -> ContractAddress {
    contract_address_const::<'USER_3'>()
}

pub(crate) const TEN_K: u256 = 10000000000000000000000;
pub(crate) const FIFTY_K: u256 = 50000000000000000000000;

pub(crate) fn deploy_token(
    initial_supply: u256,
    recipient: ContractAddress,
    owner: ContractAddress,
    issuer: ContractAddress,
    marketplace: ContractAddress,
    should_validate: bool
) -> ContractAddress {
    let token_contract = declare("trustERC20").unwrap();

    let mut token_deploy_calldata = ArrayTrait::<felt252>::new();
    token_deploy_calldata.append(initial_supply.try_into().unwrap());
    token_deploy_calldata.append(0);
    token_deploy_calldata.append(recipient.into());
    token_deploy_calldata.append(owner.into());
    token_deploy_calldata.append(issuer.into());
    token_deploy_calldata.append(marketplace.into());
    token_deploy_calldata.append(should_validate.into());

    let (token_address, _) = token_contract.deploy(@token_deploy_calldata).unwrap();

    token_address
}

