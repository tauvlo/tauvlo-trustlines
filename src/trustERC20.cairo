const OWNER_ROLE: felt252 = selector!("OWNER_ROLE");
const ISSUER_ROLE: felt252 = selector!("ISSUER_ROLE");
const THIRD_PARTY_ROLE: felt252 = selector!("THIRD_ROLE"); //  TODO: Better name

#[starknet::contract]
mod trustERC20 {
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;

    use super::OWNER_ROLE;
    use super::ISSUER_ROLE;
    use super::THIRD_PARTY_ROLE;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);

    // ERC20 Mixin
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // AccessControl
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    // SRC5
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;


    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        initial_supply: u256,
        recipient: ContractAddress,
        owner: ContractAddress,
        issuer: ContractAddress,
        third_party: ContractAddress, // TODO: Better name for last role
    ) {
        let name = "Token";
        let symbol = "TKN";

        self.erc20.initializer(name, symbol);
        self.erc20._mint(recipient, initial_supply);

        self.accesscontrol.initializer();

        self.accesscontrol._grant_role(OWNER_ROLE, owner);
        self.accesscontrol._grant_role(ISSUER_ROLE, issuer);
        self.accesscontrol._grant_role(THIRD_PARTY_ROLE, third_party);
    // Set admins of roles
    // self.accesscontrol.set_role_admin(OWNER_ROLE, owner);
    // self.accesscontrol.set_role_admin(ISSUER_ROLE, issuer);
    // self.accesscontrol.set_role_admin(THIRD_PARTY_ROLE, third_party);
    }
}

