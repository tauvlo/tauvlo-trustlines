/// # Trustlines Component
/// 
/// The Trustlines Component allows tokens to implement limitations on transfers by using
/// trustlines system.
/// 
/// This component does not implement any checks and/or admin-like system. It should be only
/// used along some acces control functionality as it contains functions for permisionless 
/// state changes.

#[starknet::component]
pub(crate) mod TrustlinesComponent {
    use starknet::{ContractAddress, get_caller_address};

    /// 'Trustline' struct, for storing information
    /// about proposed or existing trustline between two parties
    /// 
    /// `amount_effective` is the current established trustline amount
    /// `amount_proposed` current proposed amount
    ///     - either proposed for establishing the trustline or for increasing it
    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct Trustline {
        amount_effective: u256,
        amount_proposed: u256
    }

    #[storage]
    struct Storage {
        trustlines: LegacyMap<(ContractAddress, ContractAddress), Trustline>,
    }

    /// `TrustlineProposed` event emitted when either new trustline is proposed
    /// or an existing one is proposed to be increased
    /// 
    /// `party_1` in this case is the party that proposes the new (or increased) trustline
    /// `previous_amount` is the trustline amount that's currently effective (0 in case new trustline is proposed)
    #[derive(starknet::Event, Drop)]
    struct TrustlineProposed {
        party_1: ContractAddress,
        party_2: ContractAddress,
        proposed_amount: u256,
        previous_amount: u256
    }

    /// `TrustlineEstablished` event emitted when either new trustline is established
    /// or an existing one is adjusted (increased or decreased)
    /// 
    /// `party_1` in this case is the party that accepts the new (or increased) trustline, or decreases size of trustline
    /// `previous_amount` is the previous trustline amount (0 in case new trustline is being established)
    #[derive(starknet::Event, Drop)]
    struct TrustlineEstablished {
        party_1: ContractAddress,
        party_2: ContractAddress,
        proposed_amount: u256,
        previous_amount: u256
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TrustlineProposed: TrustlineProposed,
        TrustlineEstablished: TrustlineEstablished
    }

    pub mod Errors {}

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        // fn establish_trustline(
        //     self: @ComponentState<TContractState>,
        //     other_party: ContractAddress,
        //     amount: u256
        // ) -> bool {
        //     let caller = get_call
        //     true
        // }

        fn _write_trustline(
            ref self: ComponentState<TContractState>,
            party_1: ContractAddress,
            party_2: ContractAddress,
            trustline: Trustline
        ) {
            let _p1: felt252 = party_1.try_into().unwrap();
            let _p2: felt252 = party_2.try_into().unwrap();

            let _p1: u256 = _p1.into();
            let _p2: u256 = _p2.into();

            assert(_p1 != _p2, 'Parties are the same');

            let key = if (_p1 > _p2) {
                (party_1, party_2)
            } else {
                (party_2, party_1)
            };

            self.trustlines.write(key, trustline)
        }


        fn _get_trustline(
            self: @ComponentState<TContractState>,
            party_1: ContractAddress,
            party_2: ContractAddress,
        ) -> Trustline {
            let _p1: felt252 = party_1.try_into().unwrap();
            let _p2: felt252 = party_2.try_into().unwrap();

            let _p1: u256 = _p1.into();
            let _p2: u256 = _p2.into();

            assert(_p1 != _p2, 'Parties are the same');

            let key = if (_p1 > _p2) {
                (party_1, party_2)
            } else {
                (party_2, party_1)
            };

            self.trustlines.read(key)
        }
    }
}

