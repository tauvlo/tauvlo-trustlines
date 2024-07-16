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
                && !self.party_b.is_zero()
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

        fn with_updated_usage(
            self: Trustline, party_a_used: u256, party_b_used: u256
        ) -> Trustline {
            Trustline { party_a_used: party_a_used, party_b_used: party_b_used, ..self }
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
    /// `effective_amount` is the new size of the trustline
    /// `previous_amount` is the previous trustline amount (0 in case new trustline is being established)
    #[derive(starknet::Event, Drop)]
    struct TrustlineEstablished {
        party_a: ContractAddress,
        party_b: ContractAddress,
        effective_amount: u256,
        previous_amount: u256
    }

    #[derive(starknet::Event, Drop)]
    struct TrustlineTransfer {
        from: ContractAddress,
        to: ContractAddress,
        amount: u256,
        trustline_after: Trustline
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TrustlineProposed: TrustlineProposed,
        TrustlineEstablished: TrustlineEstablished,
        TrustlineTransfer: TrustlineTransfer
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
        pub const INVALID_DECREASE_AMOUNT: felt252 = 'Decrease amount invalid';
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
            // TODO: Here we're checking that it doesnt exist, however if there
            //      already exists a proposal and the caller is the proposer
            //      then we should probably let him alter the proposal
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

        // TODO: Maybe we can delete the functions for accepting the proposals
        // and only have the proposal functions
        // TODO: Add function for canceling the proposal
        // TODO: Function for querying the current state of trustline
        // (if both parties propose then new trustline is established with min of the amounts)
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

            // TODO: Doesnt check that there isn't an outstanding proposal already
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
            // TODO: What if the amount is lower than what is currently used?
            assert(amount < trustline.amount_effective, Errors::INVALID_DECREASE_AMOUNT);

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

        fn trustline_transfer(
            ref self: ComponentState<TContractState>,
            from: ContractAddress,
            to: ContractAddress,
            amount: u256
        ) -> bool {
            assert(from != to, 'From and to addresses same');
            assert(!from.is_zero(), '`From` address zero');
            assert(!to.is_zero(), '`To` address zero');
            assert(amount > 0, 'Amount is zero');

            let trustline = self._read_trustline(from, to);
            assert(trustline.exists(), Errors::NO_TRUSTLINE_FOUND);
            assert(trustline.amount_effective > 0, 'Trustline not effective');

            // Example: 
            // Alice and Bob setup a trustline of 50k
            // Case A - no transfers yet:
            //      Alice wants to transfer 30k and since there has been
            //      no traansfers yet, her limit is 50k and the transfer works, 
            //      now the limits are: Bob - 80k, Alice - 20k
            // Case B - transfered already: 
            //      Now Alice wants to send 30k again, however since she already
            //      used 30k of the trustline, the transfer will fail as she 
            //      only has 20k limit left, the limits are still the same 
            // Case C - bob transfers:
            //      Bob now transfers 60k to alice. Since she sent him 30k already
            //      it's not a problem (his limit was 80k because of that).
            //      So after the transfer, Bob's limit is decreased by 60k and 
            //      Alice limit is increase. State after transfer: Bob - 20k, Alice - 80k
            // Case D- bob transfers again:
            //      Now bob transfers 20k. State after transfer: Bob-0, Alice-100k
            // Note: All this should happen in terms of `party_a_used` and
            // `party_b_used` fields of trustline struct, ensuring that the used is 
            // never above effective amount. For example, in state after case A, 
            // Alice used 30k of the trustline, so the fields would be: 
            // `party_a_used` = 30k, `party_b_used` = 0, and Bob implicitly can spend 80k (30k to decrease alice limit to 0, then 50k of his own)

            let (from_used, to_used) = if from == trustline.party_a {
                (trustline.party_a_used, trustline.party_b_used)
            } else {
                (trustline.party_b_used, trustline.party_a_used)
            };

            // TODO: What if after proposal from_used is higher thatn amount_effective? This could underflow
            let available_from_limit = if from_used >= to_used {
                trustline.amount_effective - from_used
            } else {
                trustline.amount_effective + to_used
            };

            assert(amount <= available_from_limit, 'Amount over limit');

            let decrease_used_to_by = min(to_used, amount);
            let increase_used_from_by = amount - decrease_used_to_by;

            let new_used_from = from_used + increase_used_from_by;
            let new_used_to = to_used - decrease_used_to_by;

            // TODO: What if after proposal used is higher that amount_effective? This check could fail.
            assert(new_used_from <= trustline.amount_effective, 'From used too much');
            assert(new_used_to <= trustline.amount_effective, 'To used too much');

            assert(new_used_from * new_used_to == 0, 'Usage product not zero');

            let new_trustline = if (from == trustline.party_a) {
                trustline.with_updated_usage(new_used_from, new_used_to)
            } else {
                trustline.with_updated_usage(new_used_to, new_used_from)
            };

            self._write_trustline(new_trustline);

            self
                .emit(
                    TrustlineTransfer {
                        from: from, to: to, amount: amount, trustline_after: new_trustline
                    }
                );

            true
        }

        fn get_trustline(
            self: @ComponentState<TContractState>,
            party_a: ContractAddress,
            party_b: ContractAddress,
        ) -> Trustline {
            self._read_trustline(party_a, party_b)
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

