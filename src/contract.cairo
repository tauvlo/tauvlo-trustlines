/// A trustline-based ERC20 token implementation with additional features like holding limits, 
/// asset freezing, and transfer validation. This contract combines standard ERC20 functionality 
/// with trustlines, access control, and upgradability.

use starknet::ContractAddress;
use starknet::ClassHash;
use trustlines_erc::trustlines::TrustlinesComponent::Trustline;
use trustlines_erc::holding_limits::HoldingLimitsComponent::HoldingLimit;

// Interface for transfer validator
#[starknet::interface]
pub trait ITransferValidator<TState> {
    fn is_transfer_valid(
        self: @TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
}

/// Interface for the trustERC20 contract
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
        // Custom storage vars
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

        /// Transfers tokens from the caller to a recipient.
        /// 
        /// Arguments:
        ///     - `recipient` - The address to receive the tokens
        ///     - `amount` - The amount of tokens to transfer
        /// 
        /// Returns:
        ///     - Returns `true` if the transfer was successful
        /// 
        /// Panics:
        /// Panics if the transfer is denied by the validator, if either party is frozen,
        /// if the recipient's balance exceeds their holding limit after the transfer
        /// or if the trustline is at limit.
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();

            let can_transfer = is_transfer_valid(caller, recipient, amount);
            assert(can_transfer, 'Transfer denied by validator');

            assert_not_frozen(caller, 'Sender frozen');
            assert_not_frozen(recipient, 'Recipient frozen');
            let result = self.erc20.transfer(recipient, amount);

            if is_marketplace(recipient) {
                trustline_transfer_to_marketplace(caller, amount);
            } else {
                self.trustlines.trustline_transfer(caller, recipient, amount);
            }

            assert_balance_not_over_holding_limit(recipient);

            result
        }

        /// Transfers tokens from one address to another using the allowance mechanism.
        /// Arguments:
        ///     - `sender` - The address to transfer the tokens
        ///     - `recipient` - The address to receive the tokens
        ///     - `amount` - The amount of tokens to transfer
        /// 
        /// Returns:
        ///     - Returns `true` if the transfer was successful
        /// 
        /// Panics:
        /// Panics if the transfer is denied by the validator, if either party is frozen,
        /// if the recipient's balance exceeds their holding limit after the transfer
        /// or if the trustline is at limit.
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            let can_transfer = is_transfer_valid(sender, recipient, amount);
            assert(can_transfer, 'Transfer denied by validator');

            let result = self.erc20.transfer_from(sender, recipient, amount);
            assert_not_frozen(sender, 'Sender frozen');
            assert_not_frozen(recipient, 'Recipient frozen');

            if is_marketplace(recipient) {
                trustline_transfer_to_marketplace(sender, amount);
            } else {
                self.trustlines.trustline_transfer(sender, recipient, amount);
            }

            assert_balance_not_over_holding_limit(recipient);
            result
        }

        // TODO: Uncomment if neccessary
        // fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        //     self.accesscontrol.assert_only_role(ISSUER_ROLE);
        //     let marketplace = self.marketplace.read();
        //     assert(recipient == marketplace, 'Mint only to marketplace');
        //     self.erc20._mint(recipient, amount)
        // }
        // fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
        //     self.accesscontrol.assert_only_role(ISSUER_ROLE);
        //     let marketplace = self.marketplace.read();
        //     assert(account == marketplace, 'Burn only from marketplace');
        //     self.erc20._burn(account, amount)
        // }

        // ITrustlines
        /// Proposes a new trustline between the caller and another party.
        /// 
        /// Arguments:
        ///     - `other_party` - The address of the other party in the proposed trustline
        ///     - `amount` - The proposed amount for the trustline
        /// 
        /// Returns:
        ///     - Returns `true` if the proposal was successfully created
        /// 
        /// Events:
        ///     - Emits a `TrustlineProposed` event upon successful creation of the proposal
        fn propose_new_trustline(
            ref self: ContractState, other_party: ContractAddress, amount: u256
        ) -> bool {
            self.trustlines.propose_new_trustline(other_party, amount)
        }

        /// Accepts a proposed new trustline.
        /// 
        /// Arguments:
        ///     - `other_party` - The address of the party who proposed the trustline
        ///     - `amount` - The amount the caller agrees to for the trustline
        /// 
        /// Returns:
        ///     - Returns `true` if the trustline was successfully established
        /// 
        /// Events:
        ///     - Emits a `TrustlineEstablished` event upon successful acceptance
        fn accept_new_trustline_proposal(
            ref self: ContractState, other_party: ContractAddress, amount: u256
        ) -> bool {
            self.trustlines.accept_new_trustline_proposal(other_party, amount)
        }

        /// Proposes a modification to an existing trustline.
        /// 
        /// Arguments:
        ///     - `other_party` - The address of the other party in the trustline
        ///     - `amount` - The new proposed amount for the trustline
        /// 
        /// Returns:
        ///     - Returns `true` if the modification proposal was successfully created
        /// 
        /// Events:
        ///     - Emits a `TrustlineProposed` event upon successful creation of the proposal
        fn propose_modify_trustline(
            ref self: ContractState, other_party: ContractAddress, amount: u256
        ) -> bool {
            self.trustlines.propose_modify_trustline(other_party, amount)
        }

        /// Accepts a proposed modification to an existing trustline.
        /// 
        /// Arguments:
        ///     - `other_party` - The address of the party who proposed the modification
        ///     - `amount` - The amount the caller agrees to for the modified trustline
        /// 
        /// Returns:
        ///     - Returns `true` if the trustline was successfully modified
        /// 
        /// Events:
        ///     - Emits a `TrustlineEstablished` event upon successful acceptance
        fn accept_modify_trustline_proposal(
            ref self: ContractState, other_party: ContractAddress, amount: u256
        ) -> bool {
            self.trustlines.accept_modify_trustline_proposal(other_party, amount)
        }

        /// Cancels a trustline proposal.
        /// 
        /// Arguments:
        ///     - `other_party` - The address of the other party in the proposed trustline
        /// 
        /// Returns:
        ///     - Returns `true` if the proposal was successfully cancelled
        /// 
        /// Events:
        ///     - Emits a `TrustlineProposed` event with amount 0 upon successful cancellation
        fn cancel_trustline_proposal(
            ref self: ContractState, other_party: ContractAddress
        ) -> bool {
            self.trustlines.cancel_trustline_proposal(other_party)
        }

        /// Retrieves the trustline between two parties.
        /// 
        /// Arguments:
        ///     - `party_a` - The address of one party in the trustline
        ///     - `party_b` - The address of the other party in the trustline
        /// 
        /// Returns:
        ///     - Returns the `Trustline` struct representing the trustline between the parties
        fn get_trustline(
            self: @ContractState, party_a: ContractAddress, party_b: ContractAddress,
        ) -> Trustline {
            self.trustlines.get_trustline(party_a, party_b)
        }

        /// Decreases the amount of an existing trustline.
        /// 
        /// Arguments:
        ///     - `other_party` - The address of the other party in the trustline
        ///     - `amount` - The new, decreased amount for the trustline
        /// 
        /// Returns:
        ///     - Returns `true` if the trustline was successfully decreased
        /// 
        /// Events:
        ///     - Emits a `TrustlineEstablished` event upon successful decrease
        fn decrease_trustline(
            ref self: ContractState, other_party: ContractAddress, amount: u256
        ) -> bool {
            self.trustlines.decrease_trustline(other_party, amount)
        }

        // IHoldingLimits
        /// Sets the hard holding limit for a specific address.
        /// 
        /// Arguments:
        ///     - `address` - The address for which to set the limit
        ///     - `new_hard_limit` - The new hard limit value
        /// 
        /// Events:
        ///     - Emits a `HoldingHardLimitSet` event upon successful limit set
        fn set_hard_holding_limit(
            ref self: ContractState, address: ContractAddress, new_hard_limit: u256
        ) {
            self.accesscontrol.assert_only_role(ISSUER_ROLE);
            self.holding_limits.set_hard_holding_limit(address, new_hard_limit)
        }

        /// Sets the soft holding limit for the caller's address.
        /// 
        /// Arguments:
        ///     - `new_soft_limit` - The new soft limit value
        /// 
        /// Events:
        ///     - Emits a `HoldingSoftLimitSet` event upon successful limit set
        fn set_soft_holding_limit(ref self: ContractState, new_soft_limit: u256) {
            // No access control needed here,
            // set_soft_holding_limit sets the limit for caller
            self.holding_limits.set_soft_holding_limit(new_soft_limit)
        }

        /// Retrieves the holding limits for a specific address.
        /// 
        /// Arguments:
        ///     - `address` - The address for which to get the limits
        /// 
        /// Returns:
        ///     - Returns the `HoldingLimit` struct representing the limits for the address
        fn get_holding_limits(self: @ContractState, address: ContractAddress) -> HoldingLimit {
            self.holding_limits.get_holding_limits(address)
        }

        /// Retrieves the soft holding limit for a specific address.
        /// 
        /// Arguments:
        ///     - `address` - The address for which to get the soft limit
        /// 
        /// Returns:
        ///     - Returns the soft holding limit as a u256
        fn get_soft_holding_limit(self: @ContractState, address: ContractAddress) -> u256 {
            self.holding_limits.get_soft_holding_limit(address)
        }

        /// Retrieves the hard holding limit for a specific address.
        /// 
        /// Arguments:
        ///     - `address` - The address for which to get the hard limit
        /// 
        /// Returns:
        ///     - Returns the hard holding limit as a u256
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

        /// Sets the freeze status for a given address.
        /// 
        /// Arguments:
        ///     - `address` - The address to set the freeze status for
        ///     - `is_frozen` - The new freeze status
        /// 
        /// Panics
        ///     - Panics if the caller does not have the ISSUER_ROLE.
        fn set_freeze_status(ref self: ContractState, address: ContractAddress, is_frozen: bool) {
            self.accesscontrol.assert_only_role(ISSUER_ROLE);
            self.freezes.write(address, is_frozen)
        }

        /// Forcibly transfers assets from one address to another.
        /// 
        /// Arguments:
        ///     - `from` - The address to transfer assets from
        ///     - `to` - The address to transfer assets to
        ///     - `amount` - The amount of assets to transfer
        /// 
        /// Panics:
        ///     - Panics if the caller does not have the ISSUER_ROLE.
        fn pull_assets(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, amount: u256
        ) {
            self.accesscontrol.assert_only_role(ISSUER_ROLE);

            // Doesnt spend allowance
            self.erc20._transfer(from, to, amount);
        }

        /// Sets whether transfers should be validated by the marketplace contract.
        /// 
        /// Arguments:
        ///     - `should_validate_transfer` - Whether to enable transfer validation
        /// 
        /// Panics:
        ///     - Panics if the caller does not have the ISSUER_ROLE.
        fn set_transfer_validation_status(ref self: ContractState, should_validate_transfer: bool) {
            self.accesscontrol.assert_only_role(ISSUER_ROLE);
            self.validate_transfers.write(should_validate_transfer);
        }

        /// Gets the current transfer validation status.
        /// 
        /// Returns:
        ///     - `bool` - Returns true if transfer validation is enabled
        fn get_transfer_validation_status(self: @ContractState) -> bool {
            self.validate_transfers.read()
        }

        /// Upgrades the contract to a new implementation.
        /// 
        /// Arguments:
        ///     - `new_class_hash` - The class hash of the new implementation
        /// 
        /// Panics:
        ///     - Panics if the caller does not have the OWNER_ROLE.
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(OWNER_ROLE);
            self.upgrades._upgrade(new_class_hash);
        }
    }

    ////////////////////////////////////
    /// Helper functions
    ////////////////////////////////////

    /// Checks if the balance of an address is within its holding limit.
    /// 
    /// Arguments:
    ///     - `address` - The address to check
    /// 
    /// Panics:
    ///     - Panics if the balance exceeds the address's holding limit.
    fn assert_balance_not_over_holding_limit(address: ContractAddress) {
        let state = unsafe_new_contract_state();

        let balance = state.erc20.ERC20_balances.read(address);
        state.holding_limits.validate_holdings(address, balance);
    }

    /// Checks if an address is not frozen.
    /// 
    /// Arguments:
    ///     - `address` - The address to check
    ///     - `err_msg` - The error message to display if the address is frozen
    /// 
    /// Panics:
    ///     - Panics with the given error message if the address is frozen.
    fn assert_not_frozen(address: ContractAddress, err_msg: felt252) {
        let state = unsafe_new_contract_state();

        let is_frozen = state.freezes.read(address);
        assert(!is_frozen, err_msg);
    }

    /// Checks if a transfer is valid according to the marketplace validator.
    /// 
    /// Arguments:
    ///     - `sender` - The address sending tokens
    ///     - `recipient` - The address receiving tokens
    ///     - `amount` - The amount of tokens being transferred
    /// 
    /// Returns:
    ///     - Returns `true` if the transfer is valid, or if validation is disabled
    /// 
    /// Panics:
    ///     - Panics if validation is enabled but the validator address is not set.
    fn is_transfer_valid(
        sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool {
        let state = unsafe_new_contract_state();
        let should_validate = state.validate_transfers.read();

        if should_validate {
            let validator = state.marketplace.read();
            assert(!validator.is_zero(), 'Transfer validator not set');
            let validator_contract = ITransferValidatorDispatcher { contract_address: validator };

            validator_contract.is_transfer_valid(sender, recipient, amount)
        } else {
            true
        }
    }

    /// Checks if address is the same as the stored address of marketplacea
    /// 
    /// Arguments:
    ///     - `address` - The address to check
    /// 
    /// Returns:
    ///     - Returns `true` if address is marketplace
    fn is_marketplace(address: ContractAddress) -> bool {
        let state = unsafe_new_contract_state();

        address == state.marketplace.read()
    }

    /// Handles a trustline transfer from a user to the marketplace.
    /// 
    /// This function updates the trustline between the sender and the marketplace when 
    /// tokens are transferred to the marketplace. It ensures that the user's usage 
    /// remains at zero and reduces the marketplace's usage based on the transferred amount.
    /// 
    /// Arguments:
    ///     - `sender` - The address of the user sending tokens to the marketplace
    ///     - `amount` - The amount of tokens being transferred
    /// 
    /// Panics:
    ///     - Panics if the user has any recorded usage in the trustline with the marketplace
    /// 
    /// Notes:
    ///     - If the marketplace has no used amount in the trustline, this function does nothing
    ///     - The marketplace's used amount is reduced by the transferred amount, potentially to zero
    fn trustline_transfer_to_marketplace(sender: ContractAddress, amount: u256) {
        let mut state = unsafe_new_contract_state();
        let marketplace = state.marketplace.read();

        let trustline = state.trustlines.get_trustline(marketplace, sender);

        let (marketplace_used, user_used) = if marketplace == trustline.party_a {
            (trustline.party_a_used, trustline.party_b_used)
        } else {
            (trustline.party_b_used, trustline.party_a_used)
        };

        // If user sends funds to marketplace, then they do not use their limit
        // they firstly lower the usage by marketplace, but then it keeps at zero
        assert(user_used == 0, 'Wrong user usage');
        if marketplace_used == 0 {
            // Here marketplace has no used so there is no need to alter the trustline 
            return;
        } else {
            // If amount is over the used then set is to zero, otherwise decrease it
            let new_market_place_used = if amount >= marketplace_used {
                0
            } else {
                marketplace_used - amount
            };

            // Create new trustline with updated market place used
            // Order of party_a and party_b doeasnt matter here since
            // it'll be written in the LegacyMap with same keys no matter the ordering
            let new_trustline = Trustline {
                party_a: marketplace,
                party_b: sender,
                amount_effective: trustline.amount_effective,
                amount_proposed: trustline.amount_proposed,
                proposing_party: trustline.proposing_party,
                party_a_used: new_market_place_used,
                party_b_used: 0
            };

            // Modify trustline
            state.trustlines.modify_trustline(new_trustline);
        }
    }
}
