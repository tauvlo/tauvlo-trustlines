#[starknet::contract]
pub(crate) mod TrustlinesMock {
    use trustlines_erc::trustlines::TrustlinesComponent;
    use trustlines_erc::trustlines::TrustlinesComponent::Trustline;
    use trustlines_erc::trustlines::ITrustlines;
    use starknet::ContractAddress;

    component!(path: TrustlinesComponent, storage: trustlines, event: TrustlinesEvent);

    impl InternalImpl = TrustlinesComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        trustlines: TrustlinesComponent::Storage
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        TrustlinesEvent: TrustlinesComponent::Event
    }

    #[abi(embed_v0)]
    impl Trustlines of ITrustlines<ContractState> {
        fn propose_new_trustline(
            ref self: ContractState, other_party: ContractAddress, amount: u256
        ) -> bool {
            self.trustlines.propose_new_trustline(other_party, amount)
        }

        fn get_trustline(
            self: @ContractState, party_a: ContractAddress, party_b: ContractAddress,
        ) -> Trustline {
            self.trustlines.get_trustline(party_a, party_b)
        }
    }
}

