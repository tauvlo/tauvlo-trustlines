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
    use core::num::traits::Zero;
    use core::cmp::min;
    use starknet::{ContractAddress, get_caller_address};
    use starknet::contract_address_const;

    /// 'Trustline' struct, for storing information
    /// about proposed or existing trustline between two parties
    /// 
    /// `party_a` is one party in the trustline
    /// `party_b` is the other party in the trustline
    /// `amount_effective` is the current established trustline amount
    /// `amount_proposed` current proposed amount
    ///     - either proposed for establishing the trustline or for increasing it
    /// `proposing_party` is the party that's currently proposing an amount
    ///     - other party then need to confirm 
    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct Trustline {
        party_a: ContractAddress,
        party_b: ContractAddress,
        amount_effective: u256,
        amount_proposed: u256,
        proposing_party: ContractAddress,
        party_a_used: u256,
        party_b_used: u256,
    }

    #[generate_trait]
    impl TrustlineImpl of TrustlineTrait {
        fn exists(self: Trustline) -> bool {
            (self.amount_effective > 0)
                && (self.amount_proposed > 0)
                && !self.party_a.is_zero()
                && !self.party_a.is_zero()
        }

        fn is_effective(self: Trustline) -> bool {
            self.amount_effective > 0
        }

        fn with_cleared_proposal(self: Trustline) -> Trustline {
            // Return trustline with zero proposed and
            // no proposing party
            Trustline { amount_proposed: 0, proposing_party: contract_address_const::<0>(), ..self }
        }

        fn with_new_proposal(
            self: Trustline, proposed_amount: u256, proposer: ContractAddress
        ) -> Trustline {
            Trustline { amount_proposed: proposed_amount, proposing_party: proposer, ..self }
        }

        fn with_effective_amount(self: Trustline, effective_amount: u256) -> Trustline {
            // Return trustline with new effective amount
            Trustline { amount_effective: effective_amount, ..self }
        }
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
        party_a: ContractAddress,
        party_b: ContractAddress,
        proposed_amount: u256,
        current_effective_amount: u256
    }

    /// `TrustlineEstablished` event emitted when either new trustline is established
    /// or an existing one is adjusted (increased or decreased)
    /// 
    /// `party_1` in this case is the party that accepts the new (or increased) trustline, or decreases size of trustline
    /// `previous_amount` is the previous trustline amount (0 in case new trustline is being established)
    #[derive(starknet::Event, Drop)]
    struct TrustlineEstablished {
        party_a: ContractAddress,
        party_b: ContractAddress,
        effective_amount: u256,
        previous_amount: u256
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TrustlineProposed: TrustlineProposed,
        TrustlineEstablished: TrustlineEstablished
    }

    pub mod Errors {
        pub const OTHER_PARTY_IS_CALLER: felt252 = 'Other party same as caller';
        pub const OTHER_PARTY_ZERO: felt252 = 'Other party address is zero';
        pub const PROPOSED_AMOUNT_ZERO: felt252 = 'Proposed amount is zero';
        pub const NEW_PROPOSED_TRUSTLINE_EXISTS: felt252 = 'Proposed trustline exists';
        pub const NO_PROPOSED_TRUSTLINE: felt252 = 'No trustline proposed found';
        pub const CALLER_IS_PROPOSER: felt252 = 'Caller is proposer';
        pub const TRUSTLINE_EFFECTIVE: felt252 = 'Trustline already effective';
        pub const NO_TRUSTLINE_FOUND: felt252 = 'Trustline does not exist';
        pub const INSUFFICIENT_PROPOSAL_AMOUNT: felt252 = 'Proposed must be > effective';
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn propose_new_trustline(
            ref self: ComponentState<TContractState>, other_party: ContractAddress, amount: u256
        ) -> bool {
            let proposer = get_caller_address();
            let trustline = self._read_trustline(proposer, other_party);

            assert(proposer != other_party, Errors::OTHER_PARTY_IS_CALLER);
            assert(!other_party.is_zero(), Errors::OTHER_PARTY_ZERO);
            assert(!trustline.exists(), Errors::NEW_PROPOSED_TRUSTLINE_EXISTS);

            // Assert that new proposed trustline amount is not zero
            assert(amount > 0, Errors::PROPOSED_AMOUNT_ZERO);

            // Create new Trustline struct
            // Since this is new trustline that's proposed, 
            // the effective amount and both used amounts are all zero
            let new_trustline = Trustline {
                party_a: proposer,
                party_b: other_party,
                amount_effective: 0,
                amount_proposed: amount,
                proposing_party: proposer,
                party_a_used: 0,
                party_b_used: 0,
            };

            // Save new trustline
            self._write_trustline(new_trustline);

            // Emit event
            self
                .emit(
                    TrustlineProposed {
                        party_a: proposer,
                        party_b: other_party,
                        proposed_amount: amount,
                        current_effective_amount: 0
                    }
                );

            true
        }

        fn accept_new_trustline_proposal(
            ref self: ComponentState<TContractState>, other_party: ContractAddress, amount: u256
        ) -> bool {
            let caller = get_caller_address();
            let trustline = self._read_trustline(caller, other_party);

            assert(caller != other_party, Errors::OTHER_PARTY_IS_CALLER);
            assert(amount > 0, Errors::PROPOSED_AMOUNT_ZERO);
            assert(trustline.exists(), Errors::NO_PROPOSED_TRUSTLINE);
            assert(caller != trustline.proposing_party, Errors::CALLER_IS_PROPOSER);
            assert(!trustline.is_effective(), Errors::TRUSTLINE_EFFECTIVE);

            let amount_to_be_effective = min(amount, trustline.amount_proposed);

            let new_trustline = trustline
                .with_cleared_proposal()
                .with_effective_amount(amount_to_be_effective);

            self._write_trustline(new_trustline);

            self
                .emit(
                    TrustlineEstablished {
                        party_a: caller,
                        party_b: other_party,
                        effective_amount: amount_to_be_effective,
                        previous_amount: 0
                    }
                );

            true
        }

        fn propose_modify_trustline(
            ref self: ComponentState<TContractState>, other_party: ContractAddress, amount: u256
        ) -> bool {
            // Function for proposing modification of existing trustline
            // this function is to be used **only** when increasing trustline
            // since when proposed amount is the same there is no proposal needed 
            // and when the amount proposed is lower then that can happen
            // unilaterally and function `decrease_trustline` should be used

            let proposer = get_caller_address();
            let trustline = self._read_trustline(proposer, other_party);

            assert(proposer != other_party, Errors::OTHER_PARTY_IS_CALLER);
            assert(!other_party.is_zero(), Errors::OTHER_PARTY_ZERO);
            assert(trustline.exists(), Errors::NO_TRUSTLINE_FOUND);

            assert(amount > trustline.amount_effective, Errors::INSUFFICIENT_PROPOSAL_AMOUNT);

            let new_trustline = trustline.with_new_proposal(amount, proposer);

            self._write_trustline(new_trustline);

            self
                .emit(
                    TrustlineProposed {
                        party_a: proposer,
                        party_b: other_party,
                        proposed_amount: amount,
                        current_effective_amount: new_trustline.amount_effective
                    }
                );

            true
        }

        fn accept_modify_trustline_proposal(
            ref self: ComponentState<TContractState>, other_party: ContractAddress, amount: u256
        ) -> bool {
            // Function for acception modification proposal of existing trustline

            // TODO: This function is basically the same as the one for accepting 
            // new trustlines, mby merge them to one function

            let caller = get_caller_address();
            let trustline = self._read_trustline(caller, other_party);

            assert(caller != other_party, Errors::OTHER_PARTY_IS_CALLER);
            assert(amount > 0, Errors::PROPOSED_AMOUNT_ZERO);
            assert(trustline.exists(), Errors::NO_PROPOSED_TRUSTLINE);
            assert(caller != trustline.proposing_party, Errors::CALLER_IS_PROPOSER);
            assert(trustline.is_effective(), Errors::TRUSTLINE_EFFECTIVE);

            let amount_to_be_effective = min(amount, trustline.amount_proposed);

            let new_trustline = trustline
                .with_cleared_proposal()
                .with_effective_amount(amount_to_be_effective);

            self._write_trustline(new_trustline);

            self
                .emit(
                    TrustlineEstablished {
                        party_a: caller,
                        party_b: other_party,
                        effective_amount: amount_to_be_effective,
                        previous_amount: trustline.amount_effective
                    }
                );

            true
        }

        fn decrease_trustline(
            ref self: ComponentState<TContractState>, other_party: ContractAddress, amount: u256
        ) -> bool {
            let caller = get_caller_address();
            let trustline = self._read_trustline(caller, other_party);

            assert(caller != other_party, Errors::OTHER_PARTY_IS_CALLER);
            assert(!other_party.is_zero(), Errors::OTHER_PARTY_ZERO);
            assert(trustline.exists(), Errors::NEW_PROPOSED_TRUSTLINE_EXISTS);
            assert(amount < trustline.amount_effective, 'TODO');

            let new_trustline = trustline.with_effective_amount(amount);

            self._write_trustline(new_trustline);

            self
                .emit(
                    TrustlineEstablished {
                        party_a: caller,
                        party_b: other_party,
                        effective_amount: amount,
                        previous_amount: trustline.amount_effective
                    }
                );

            true
        }

        fn _write_trustline(ref self: ComponentState<TContractState>, trustline: Trustline) {
            let _p1: felt252 = trustline.party_a.try_into().unwrap();
            let _p2: felt252 = trustline.party_b.try_into().unwrap();

            let _p1: u256 = _p1.into();
            let _p2: u256 = _p2.into();

            assert(_p1 != _p2, 'Parties are the same');

            let key = if (_p1 > _p2) {
                (trustline.party_a, trustline.party_b)
            } else {
                (trustline.party_b, trustline.party_a)
            };

            self.trustlines.write(key, trustline)
        }


        fn _read_trustline(
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

