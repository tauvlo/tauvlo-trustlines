#[starknet::contract]
pub(crate) mod HoldingLimitsMock {
    use trustlines_erc::holding_limits::HoldingLimitsComponent;
    use trustlines_erc::holding_limits::HoldingLimitsComponent::HoldingLimit;
    use trustlines_erc::holding_limits::IHoldingLimits;
    use starknet::ContractAddress;

    component!(path: HoldingLimitsComponent, storage: holding_limits, event: HoldingLimitsEvent);

    impl InternalImpl = HoldingLimitsComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        holding_limits: HoldingLimitsComponent::Storage
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        HoldingLimitsEvent: HoldingLimitsComponent::Event
    }

    #[abi(embed_v0)]
    impl HoldingLimits of IHoldingLimits<ContractState> {
        fn set_hard_limit(ref self: ContractState, address: ContractAddress, new_hard_limit: u256) {
            self.holding_limits.set_hard_limit(address, new_hard_limit)
        }

        fn set_soft_limit(ref self: ContractState, address: ContractAddress, new_soft_limit: u256) {
            self.holding_limits.set_soft_limit(address, new_soft_limit)
        }

        fn validate_holdings(self: @ContractState, address: ContractAddress, holdings: u256) {
            self.holding_limits.validate_holdings(address, holdings)
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
