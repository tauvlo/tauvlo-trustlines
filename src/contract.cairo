use starknet::ContractAddress;
use trustlines_erc::trustlines::TrustlinesComponent::Trustline;
use trustlines_erc::holding_limits::HoldingLimitsComponent::HoldingLimit;

#[starknet::interface]
trait ItrustERC20<TState> {
    // IERC20Metadata
    fn name(self: @TState) -> ByteArray;
    fn symbol(self: @TState) -> ByteArray;
    fn decimals(self: @TState) -> u8;

    // IERC20
    fn total_supply(self: @TState) -> u256;
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    // fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    // fn transfer_from(
    //     ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    // ) -> bool;
    // fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;

    // ITrustlines
    fn propose_new_trustline(ref self: TState, other_party: ContractAddress, amount: u256) -> bool;
    fn accept_new_trustline_proposal(
        ref self: TState, other_party: ContractAddress, amount: u256
    ) -> bool;
    fn propose_modify_trustline(
        ref self: TState, other_party: ContractAddress, amount: u256
    ) -> bool;
    fn accept_modify_trustline_proposal(
        ref self: TState, other_party: ContractAddress, amount: u256
    ) -> bool;
    fn cancel_trustline_proposal(ref self: TState, other_party: ContractAddress) -> bool;
    fn get_trustline(
        self: @TState, party_a: ContractAddress, party_b: ContractAddress,
    ) -> Trustline;
    fn decrease_trustline(ref self: TState, other_party: ContractAddress, amount: u256) -> bool;
    // fn trustline_transfer( ref self: TS, from: ContractAddress, to: ContractAddress, amount: u256) -> bool;

    // IHoldingLimits
    fn set_hard_holding_limit(ref self: TState, address: ContractAddress, new_hard_limit: u256);
    fn set_soft_holding_limit(ref self: TState, address: ContractAddress, new_soft_limit: u256);
    fn get_holding_limit(self: @TState, address: ContractAddress) -> HoldingLimit;
    fn get_soft_holding_limit(self: @TState, address: ContractAddress) -> u256;
    fn get_hard_holding_limit(self: @TState, address: ContractAddress) -> u256;
// fn validate_holdings(self: @TState, address: ContractAddress, holdings: u256);
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
    use trustlines_erc::trustlines::TrustlinesComponent::Trustline;
    use trustlines_erc::holding_limits::HoldingLimitsComponent;
    use trustlines_erc::holding_limits::HoldingLimitsComponent::HoldingLimit;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: TrustlinesComponent, storage: trustlines, event: TrustlinesEvent);
    component!(path: HoldingLimitsComponent, storage: holding_limits, event: HoldingLimitsEvent);

    // ERC20 InternalImpl
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    // AccessControl InternalImpl
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    // SRC5
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    // Trustlines
    impl TrustlinesInternalImpl = TrustlinesComponent::InternalImpl<ContractState>;

    // HoldingLimits
    impl HoldingLimitsInternalImpl = HoldingLimitsComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        trustlines: TrustlinesComponent::Storage,
        #[substorage(v0)]
        holding_limits: HoldingLimitsComponent::Storage,
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
        #[flat]
        HoldingLimitsEvent: HoldingLimitsComponent::Event,
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

    impl trustERC20 of super::ItrustERC20<ContractState> {
        // IERC20Metadata
        fn name(self: @ContractState) -> ByteArray {
            self.erc20.ERC20_name.read()
        }
        fn symbol(self: @ContractState) -> ByteArray {
            self.erc20.ERC20_symbol.read()
        }
        fn decimals(self: @ContractState) -> u8 {
            18
        }

        // IERC20
        fn total_supply(self: @ContractState) -> u256 {
            self.erc20.ERC20_total_supply.read()
        }
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20.ERC20_balances.read(account)
        }
        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.erc20.ERC20_allowances.read((owner, spender))
        }


        // ITrustlines
        fn propose_new_trustline(
            ref self: ContractState, other_party: ContractAddress, amount: u256
        ) -> bool {
            self.trustlines.propose_new_trustline(other_party, amount)
        }
        fn accept_new_trustline_proposal(
            ref self: ContractState, other_party: ContractAddress, amount: u256
        ) -> bool {
            self.trustlines.accept_new_trustline_proposal(other_party, amount)
        }
        fn propose_modify_trustline(
            ref self: ContractState, other_party: ContractAddress, amount: u256
        ) -> bool {
            self.trustlines.propose_modify_trustline(other_party, amount)
        }
        fn accept_modify_trustline_proposal(
            ref self: ContractState, other_party: ContractAddress, amount: u256
        ) -> bool {
            self.trustlines.accept_modify_trustline_proposal(other_party, amount)
        }
        fn cancel_trustline_proposal(
            ref self: ContractState, other_party: ContractAddress
        ) -> bool {
            self.trustlines.cancel_trustline_proposal(other_party)
        }
        fn get_trustline(
            self: @ContractState, party_a: ContractAddress, party_b: ContractAddress,
        ) -> Trustline {
            self.trustlines.get_trustline(party_a, party_b)
        }
        fn decrease_trustline(
            ref self: ContractState, other_party: ContractAddress, amount: u256
        ) -> bool {
            self.trustlines.decrease_trustline(other_party, amount)
        }

        // IHoldingLimits
        fn set_hard_holding_limit(
            ref self: ContractState, address: ContractAddress, new_hard_limit: u256
        ) {
            // TODO: Add access control here
            self.holding_limits.set_hard_holding_limit(address, new_hard_limit)
        }
        fn set_soft_holding_limit(
            ref self: ContractState, address: ContractAddress, new_soft_limit: u256
        ) {
            self.holding_limits.set_soft_holding_limit(new_soft_limit)
        }
        fn get_holding_limit(self: @ContractState, address: ContractAddress) -> HoldingLimit {
            self.holding_limits.get_holding_limit(address)
        }
        fn get_soft_holding_limit(self: @ContractState, address: ContractAddress) -> u256 {
            self.holding_limits.get_soft_holding_limit(address)
        }
        fn get_hard_holding_limit(self: @ContractState, address: ContractAddress) -> u256 {
            self.holding_limits.get_hard_holding_limit(address)
        }
    }
}
