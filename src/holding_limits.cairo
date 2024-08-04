/// HoldingLimits component
/// 
/// Module for managing holding limits on user accounts.
/// Allows setting and enforcing both hard and soft limits on token holdings.
/// 
/// This component does not implement any checks and/or admin-like system. It should be only
/// used along some acces control functionality as it contains functions for permisionless 
/// state changes.

// HoldingLimits interface
use starknet::ContractAddress;
use HoldingLimitsComponent::HoldingLimit;
#[starknet::interface]
pub trait IHoldingLimits<TContractState> {
    fn set_hard_holding_limit(
        ref self: TContractState, address: ContractAddress, new_hard_limit: u256
    );
    fn set_soft_holding_limit(ref self: TContractState, new_soft_limit: u256);
    fn get_holding_limits(self: @TContractState, address: ContractAddress) -> HoldingLimit;
    fn get_soft_holding_limit(self: @TContractState, address: ContractAddress) -> u256;
    fn get_hard_holding_limit(self: @TContractState, address: ContractAddress) -> u256;
    fn validate_holdings(self: @TContractState, address: ContractAddress, holdings: u256);
}

#[starknet::component]
pub(crate) mod HoldingLimitsComponent {
    use core::num::traits::Zero;
    use starknet::{ContractAddress, get_caller_address};
    use core::cmp::min;

    /// `HoldingLimit` struct, for storing information about holding limits for an address
    /// 
    /// `hard_limit` is the maximum limit set by an authority
    /// `soft_limit` is the user-defined limit, which cannot exceed the hard limit
    #[derive(Copy, Drop, Serde, starknet::Store, Debug)]
    pub struct HoldingLimit {
        pub hard_limit: u256,
        pub soft_limit: u256
    }

    #[storage]
    struct Storage {
        limits: LegacyMap<ContractAddress, HoldingLimit>
    }


    /// `HoldingHardLimitSet` event emitted when a hard holding limit is set or changed
    /// 
    /// `address` is the address for which the limit is set
    /// `limit` is the new hard limit value
    /// `previous_limit` is the previous hard limit value
    #[derive(starknet::Event, Drop)]
    struct HoldingHardLimitSet {
        address: ContractAddress,
        limit: u256,
        previous_limit: u256
    }

    /// `HoldingSoftLimitSet` event emitted when a soft holding limit is set or changed
    /// 
    /// `address` is the address for which the limit is set
    /// `limit` is the new soft limit value
    /// `previous_limit` is the previous soft limit value
    #[derive(starknet::Event, Drop)]
    struct HoldingSoftLimitSet {
        address: ContractAddress,
        limit: u256,
        previous_limit: u256
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        HoldingSoftLimitSet: HoldingSoftLimitSet,
        HoldingHardLimitSet: HoldingHardLimitSet
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        /// Function for setting the hard holding limit for a specific address
        /// 
        /// Arguments:
        ///     - `address` - The address for which to set the limit
        ///     - `new_hard_limit` - The new hard limit value
        /// 
        /// Events:
        ///     - Emits a `HoldingHardLimitSet` event upon successful limit set
        fn set_hard_holding_limit(
            ref self: ComponentState<TContractState>, address: ContractAddress, new_hard_limit: u256
        ) {
            assert(!address.is_zero(), 'Cant set limit for zero');

            // Read old limits
            let old_limit: HoldingLimit = self.limits.read(address);

            // If we're setting new limit, it'll resolve to zero here
            // since old soft_limit will be zero
            // If the limit is already set, then it'll be either user's one,
            // or the new hard limit 
            let soft_limit = min(old_limit.soft_limit, new_hard_limit);

            let new_limit = HoldingLimit { soft_limit: soft_limit, hard_limit: new_hard_limit };

            self.limits.write(address, new_limit);

            self
                .emit(
                    HoldingHardLimitSet {
                        address: address,
                        limit: new_hard_limit,
                        previous_limit: old_limit.hard_limit
                    }
                );
        }


        /// Function for setting the soft holding limit for the caller's address
        /// 
        /// Arguments:
        ///     - `new_soft_limit` - The new soft limit value
        /// 
        /// Events:
        ///     - Emits a `HoldingSoftLimitSet` event upon successful limit set
        fn set_soft_holding_limit(ref self: ComponentState<TContractState>, new_soft_limit: u256) {
            let caller = get_caller_address();
            let old_limit = self.limits.read(caller);

            assert(!caller.is_zero(), 'Cant set limit for zero');

            // Soft limit can never by above hard limit
            assert(new_soft_limit <= old_limit.hard_limit, 'Cant set soft > hard');

            let new_limit = HoldingLimit {
                soft_limit: new_soft_limit, hard_limit: old_limit.hard_limit
            };

            self.limits.write(caller, new_limit);

            self
                .emit(
                    HoldingSoftLimitSet {
                        address: caller, limit: new_soft_limit, previous_limit: old_limit.soft_limit
                    }
                );
        }

        /// Function for retrieving the holding limits for a specific address
        /// 
        /// Arguments:
        ///     - `address` - The address for which to get the limits
        /// 
        /// Returns:
        ///     - Returns the `HoldingLimit` struct representing the limits for the address
        fn get_holding_limits(
            self: @ComponentState<TContractState>, address: ContractAddress
        ) -> HoldingLimit {
            self.limits.read(address)
        }

        /// Function for retrieving the soft holding limit for a specific address
        /// 
        /// Arguments:
        ///     - `address` - The address for which to get the soft limit
        /// 
        /// Returns:
        ///     - Returns the soft holding limit as a u256
        fn get_soft_holding_limit(
            self: @ComponentState<TContractState>, address: ContractAddress
        ) -> u256 {
            let limit: HoldingLimit = self.limits.read(address);
            limit.soft_limit
        }

        /// Function for retrieving the hard holding limit for a specific address
        /// 
        /// Arguments:
        ///     - `address` - The address for which to get the hard limit
        /// 
        /// Returns:
        ///     - Returns the hard holding limit as a u256
        fn get_hard_holding_limit(
            self: @ComponentState<TContractState>, address: ContractAddress
        ) -> u256 {
            let limit: HoldingLimit = self.limits.read(address);
            limit.hard_limit
        }

        /// Function for validating that the holdings of an address do not exceed its soft limit
        /// 
        /// Arguments:
        ///     - `address` - The address to validate
        ///     - `holdings` - The current holdings of the address
        /// 
        /// Panics:
        ///     - Panics if the holdings exceed the soft limit
        fn validate_holdings(
            self: @ComponentState<TContractState>, address: ContractAddress, holdings: u256
        ) {
            let limit: HoldingLimit = self.limits.read(address);

            // Soft limit will never be above hard limit anyway
            // so we can check only against it
            assert(holdings <= limit.soft_limit, 'Holdings over limit');
        }
    }
}
