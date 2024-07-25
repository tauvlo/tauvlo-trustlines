use starknet::ContractAddress;
use starknet::ClassHash;
use trustlines_erc::trustlines::TrustlinesComponent::Trustline;
use trustlines_erc::holding_limits::HoldingLimitsComponent::HoldingLimit;

#[starknet::interface]
trait ITransferValidator<TState> {
    fn validate_transfer(
        self: @TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    );
}

#[starknet::interface]
pub trait ItrustERC20<TState> {
    // IERC20Metadata
    fn name(self: @TState) -> ByteArray;
    fn symbol(self: @TState) -> ByteArray;
    fn decimals(self: @TState) -> u8;

    // IERC20
    fn total_supply(self: @TState) -> u256;
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    // fn mint(ref self: TState, recipient: ContractAddress, amount: u256);
    // fn burn(ref self: TState, account: ContractAddress, amount: u256);

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

    // IHoldingLimits
    fn set_hard_holding_limit(ref self: TState, address: ContractAddress, new_hard_limit: u256);
    fn set_soft_holding_limit(ref self: TState, new_soft_limit: u256);
    fn get_holding_limits(self: @TState, address: ContractAddress) -> HoldingLimit;
    fn get_soft_holding_limit(self: @TState, address: ContractAddress) -> u256;
    fn get_hard_holding_limit(self: @TState, address: ContractAddress) -> u256;

    // IAccessControl
    fn has_role(self: @TState, role: felt252, account: ContractAddress) -> bool;
    fn get_role_admin(self: @TState, role: felt252) -> felt252;
    fn grant_role(ref self: TState, role: felt252, account: ContractAddress);
    fn revoke_role(ref self: TState, role: felt252, account: ContractAddress);
    fn renounce_role(ref self: TState, role: felt252, account: ContractAddress);

    // Freeze funtion
    fn set_freeze_status(ref self: TState, address: ContractAddress, is_frozen: bool);

    // Asset pull function
    fn pull_assets(ref self: TState, from: ContractAddress, to: ContractAddress, amount: u256);

    // Function for setting transfer validation status
    fn set_transfer_validation_status(ref self: TState, should_validate_transfer: bool);
    fn get_transfer_validation_status(self: @TState) -> bool;

    // Upgrade
    fn upgrade(ref self: TState, new_class_hash: ClassHash);
}


#[starknet::contract]
mod trustERC20 {
    use openzeppelin::token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin::access::accesscontrol::DEFAULT_ADMIN_ROLE;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;

    use starknet::{ContractAddress, get_caller_address, ClassHash};
    use core::num::traits::Zero;

    use trustlines_erc::constants::OWNER_ROLE;
    use trustlines_erc::constants::ISSUER_ROLE;

    use trustlines_erc::trustlines::TrustlinesComponent;
    use trustlines_erc::trustlines::TrustlinesComponent::Trustline;
    use trustlines_erc::holding_limits::HoldingLimitsComponent;
    use trustlines_erc::holding_limits::HoldingLimitsComponent::HoldingLimit;

    use super::ITransferValidatorDispatcher;
    use super::ITransferValidatorDispatcherTrait;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: TrustlinesComponent, storage: trustlines, event: TrustlinesEvent);
    component!(path: HoldingLimitsComponent, storage: holding_limits, event: HoldingLimitsEvent);
    component!(path: UpgradeableComponent, storage: upgrades, event: UpgradeableEvent);

    // Upgrades
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // ERC20 InternalImpl
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;

    // AccessControl InternalImpl
    impl AccessControlMixinImpl = AccessControlComponent::AccessControlMixinImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

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
        #[substorage(v0)]
        upgrades: UpgradeableComponent::Storage,
        // Custom   

        // Stores information about freezed addresses
        freezes: LegacyMap::<ContractAddress, bool>,
        // If true, then transfers are validated by a 3rd party (marketplace)
        validate_transfers: bool,
        // Address that validates the transfers (if validation is enabled)
        marketplace: ContractAddress
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
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        initial_supply: u256,
        recipient: ContractAddress,
        owner: ContractAddress,
        issuer: ContractAddress,
        marketplace: ContractAddress,
        validate_transfers: bool
    ) {
        let name = "Token";
        let symbol = "TKN";

        self.erc20.initializer(name, symbol);
        self.erc20._mint(recipient, initial_supply);

        self.accesscontrol.initializer();

        // Owner can upgrade the contract and is overall admin
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, owner);
        self.accesscontrol._grant_role(OWNER_ROLE, owner);

        // Issuer can freeze assets, pull assets and set holding limits
        self.accesscontrol._grant_role(ISSUER_ROLE, issuer);

        // Marketplace is here for two reasons:
        // If enabled, it validates the transfers
        // And also because trustlines setup with the marketplace
        // are disabled if marketplace is the target address (user can send there whatever they want)
        self.validate_transfers.write(validate_transfers);
        self.marketplace.write(marketplace);
    }

    #[abi(embed_v0)]
    impl trustERC20 of super::ItrustERC20<ContractState> {
        // IERC20Metadata
        fn name(self: @ContractState) -> ByteArray {
            self.erc20.name()
        }
        fn symbol(self: @ContractState) -> ByteArray {
            self.erc20.symbol()
        }
        fn decimals(self: @ContractState) -> u8 {
            self.erc20.decimals()
        }

        // IERC20
        fn total_supply(self: @ContractState) -> u256 {
            self.erc20.total_supply()
        }
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20.balance_of(account)
        }
        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress
        ) -> u256 {
            self.erc20.allowance(owner, spender)
        }
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.erc20.approve(spender, amount)
        }
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();

            validate_transfer(caller, recipient, amount);
            assert_not_frozen(caller, 'Sender frozen');
            assert_not_frozen(recipient, 'Recipient frozen');
            let result = self.erc20.transfer(recipient, amount);

            self.trustlines.trustline_transfer(caller, recipient, amount);
            assert_balance_not_over_holding_limit(recipient);

            result
        }
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            validate_transfer(sender, recipient, amount);
            let result = self.erc20.transfer_from(sender, recipient, amount);
            assert_not_frozen(sender, 'Sender frozen');
            assert_not_frozen(recipient, 'Recipient frozen');
            self.trustlines.trustline_transfer(sender, recipient, amount);

            assert_balance_not_over_holding_limit(recipient);
            result
        }

        // fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        //     self.accesscontrol.assert_only_role(ISSUER_ROLE);

        //     // TODO: Is this correct?
        //     let marketplace = self.marketplace.read();
        //     assert(recipient == marketplace, 'Mint only to marketplace');

        //     self.erc20._mint(recipient, amount)
        // }
        // fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
        //     self.accesscontrol.assert_only_role(ISSUER_ROLE);

        //     // TODO: Is this correct?
        //     let marketplace = self.marketplace.read();
        //     assert(account == marketplace, 'Burn only from marketplace');

        //     self.erc20._burn(account, amount)
        // }

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
            self.accesscontrol.assert_only_role(ISSUER_ROLE);
            self.holding_limits.set_hard_holding_limit(address, new_hard_limit)
        }
        fn set_soft_holding_limit(ref self: ContractState, new_soft_limit: u256) {
            // No access control needed here,
            // set_soft_holding_limit sets the limit for caller
            self.holding_limits.set_soft_holding_limit(new_soft_limit)
        }
        fn get_holding_limits(self: @ContractState, address: ContractAddress) -> HoldingLimit {
            self.holding_limits.get_holding_limits(address)
        }
        fn get_soft_holding_limit(self: @ContractState, address: ContractAddress) -> u256 {
            self.holding_limits.get_soft_holding_limit(address)
        }
        fn get_hard_holding_limit(self: @ContractState, address: ContractAddress) -> u256 {
            self.holding_limits.get_hard_holding_limit(address)
        }

        // IAccessControl
        fn has_role(self: @ContractState, role: felt252, account: ContractAddress) -> bool {
            self.accesscontrol.has_role(role, account)
        }
        fn get_role_admin(self: @ContractState, role: felt252) -> felt252 {
            self.accesscontrol.get_role_admin(role)
        }
        fn grant_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            self.accesscontrol.grant_role(role, account)
        }
        fn revoke_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            self.accesscontrol.revoke_role(role, account)
        }
        fn renounce_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            self.accesscontrol.renounce_role(role, account)
        }

        // Freeze Function
        fn set_freeze_status(ref self: ContractState, address: ContractAddress, is_frozen: bool) {
            self.accesscontrol.assert_only_role(ISSUER_ROLE);
            self.freezes.write(address, is_frozen)
        }

        // Asset pull function
        fn pull_assets(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256
        ) {
            self.accesscontrol.assert_only_role(ISSUER_ROLE);

            // Doesnt spend allowance
            self.erc20._transfer(from, to, amount);
        }

        // Set transfer validation status
        fn set_transfer_validation_status(ref self: ContractState, should_validate_transfer: bool) {
            // TODO: Is this something ISSUER should do? Or OWNER?           
            self.accesscontrol.assert_only_role(ISSUER_ROLE);
            self.validate_transfers.write(should_validate_transfer);
        }

        fn get_transfer_validation_status(self: @ContractState) -> bool {
            self.validate_transfers.read()
        }

        // Upgrade
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(OWNER_ROLE);
            self.upgrades._upgrade(new_class_hash);
        }
    }

    // Helper functions
    fn assert_balance_not_over_holding_limit(address: ContractAddress) {
        let state = unsafe_new_contract_state();

        let balance = state.erc20.ERC20_balances.read(address);
        state.holding_limits.validate_holdings(address, balance);
    }
    fn assert_not_frozen(address: ContractAddress, err_msg: felt252) {
        let state = unsafe_new_contract_state();

        let is_frozen = state.freezes.read(address);
        assert(!is_frozen, err_msg);
    }
    fn validate_transfer(sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        let state = unsafe_new_contract_state();
        let should_validate = state.validate_transfers.read();

        if should_validate {
            let validator = state.marketplace.read();
            assert(!validator.is_zero(), 'Transfer validator not set');

            let validator_contract = ITransferValidatorDispatcher { contract_address: validator };

            validator_contract.validate_transfer(sender, recipient, amount)
        }
    }
}
