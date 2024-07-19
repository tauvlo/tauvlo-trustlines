use starknet::ContractAddress;
#[starknet::interface]
pub trait IHoldingLimits<TContractState> {
    fn set_holding_limit(ref self: TContractState, address: ContractAddress, amount: u256);
    fn validate_holdings(self: @TContractState, address: ContractAddress, holdings: u256);
}

#[starknet::component]
pub(crate) mod HoldingLimitsComponent {
    use core::num::traits::Zero;
    use starknet::ContractAddress;

    #[storage]
    struct Storage {
        holding_limits: LegacyMap<ContractAddress, u256>
    }

    #[derive(starknet::Event, Drop)]
    struct HoldingLimitSet {
        address: ContractAddress,
        limit: u256,
        previous_limit: u256
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        HoldingLimitSet: HoldingLimitSet
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn set_holding_limit(
            ref self: ComponentState<TContractState>, address: ContractAddress, limit: u256
        ) {
            assert(!address.is_zero(), 'Cant set limit for zero');

            let previous_limit = self.holding_limits.read(address);
            self.holding_limits.write(address, limit);

            self
                .emit(
                    HoldingLimitSet {
                        address: address, limit: limit, previous_limit: previous_limit
                    }
                );
        }
        fn validate_holdings(
            self: @ComponentState<TContractState>, address: ContractAddress, holdings: u256
        ) {
            let limit = self.holding_limits.read(address);
            assert(holdings <= limit, 'Holdings over limit');
        }
    }
}
