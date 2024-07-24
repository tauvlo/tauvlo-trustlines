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

    #[derive(Copy, Drop, Serde, starknet::Store, Debug)]
    pub struct HoldingLimit {
        // Set by authority
        pub hard_limit: u256,
        // Set by user, can never be > hard_limit
        pub soft_limit: u256
    }

    #[storage]
    struct Storage {
        limits: LegacyMap<ContractAddress, HoldingLimit>
    }

    #[derive(starknet::Event, Drop)]
    struct HoldingHardLimitSet {
        address: ContractAddress,
        limit: u256,
        previous_limit: u256
    }

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
        /// Sets hard limit on holdings
        /// To be used by some authority in order to limit how much 
        /// user can hold, user can not his own limit higher than this one
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

            // TODO: If new limit is below user holdings, 
            // then user might be unable to send the funds anywhere
            // since even after transfer his balance would be above holding limit
            // so only choice would be to send lump sum to ie. marketplace

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

        // Sets soft limits on holding
        // To be used by user to set his own holding limits
        // Can never be above hard limit set by some authority
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

        fn get_holding_limits(
            self: @ComponentState<TContractState>, address: ContractAddress
        ) -> HoldingLimit {
            self.limits.read(address)
        }

        fn get_soft_holding_limit(
            self: @ComponentState<TContractState>, address: ContractAddress
        ) -> u256 {
            let limit: HoldingLimit = self.limits.read(address);
            limit.soft_limit
        }

        fn get_hard_holding_limit(
            self: @ComponentState<TContractState>, address: ContractAddress
        ) -> u256 {
            let limit: HoldingLimit = self.limits.read(address);
            limit.hard_limit
        }

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
