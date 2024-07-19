#[starknet::interface]
pub trait ITrustlines<TState> {
    fn dummy_function(self: @TState) -> u256;
}

#[starknet::contract]
mod trustERC20 {
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin::access::accesscontrol::DEFAULT_ADMIN_ROLE;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::ContractAddress;

    use trustlines_erc::constants::OWNER_ROLE;
    use trustlines_erc::constants::ISSUER_ROLE;
    use trustlines_erc::constants::THIRD_PARTY_ROLE;

    use trustlines_erc::trustlines::TrustlinesComponent;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: TrustlinesComponent, storage: trustlines, event: TrustlinesEvent);

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

    // Trustlines
    impl TrustlinesInternalImpl = TrustlinesComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        trustlines: TrustlinesComponent::Storage
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
        #[flat]
        TrustlinesEvent: TrustlinesComponent::Event,
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

        // Owner is also the admin
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, owner);
        self.accesscontrol._grant_role(OWNER_ROLE, owner);
        self.accesscontrol._grant_role(ISSUER_ROLE, issuer);
        self.accesscontrol._grant_role(THIRD_PARTY_ROLE, third_party);
    }
// #[abi(embed_v0)]
// impl Trustlines of super::ITrustlines<ContractState> {
//     fn dummy_function(self: @ContractState) -> u256 {
//         self.trustlines.dummy_function()
//     }
// }
}
