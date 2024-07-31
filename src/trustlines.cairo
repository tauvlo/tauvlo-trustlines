/// Trustlines Component
/// 
/// The Trustlines Component allows tokens to implement limitations on transfers by using
/// trustlines system.
/// 
/// This component does not implement any checks and/or admin-like system. It should be only
/// used along some acces control functionality as it contains functions for permisionless 
/// state changes.

// Trustline Interface
use starknet::ContractAddress;
#[starknet::interface]
pub trait ITrustlines<TContractState> {
    fn propose_new_trustline(
        ref self: TContractState, other_party: ContractAddress, amount: u256
    ) -> bool;
    fn accept_new_trustline_proposal(
        ref self: TContractState, other_party: ContractAddress, amount: u256
    ) -> bool;
    fn propose_modify_trustline(
        ref self: TContractState, other_party: ContractAddress, amount: u256
    ) -> bool;
    fn accept_modify_trustline_proposal(
        ref self: TContractState, other_party: ContractAddress, amount: u256
    ) -> bool;
    fn cancel_trustline_proposal(ref self: TContractState, other_party: ContractAddress) -> bool;
    fn get_trustline(
        self: @TContractState, party_a: ContractAddress, party_b: ContractAddress,
    ) -> TrustlinesComponent::Trustline;
    fn decrease_trustline(
        ref self: TContractState, other_party: ContractAddress, amount: u256
    ) -> bool;
    fn trustline_transfer(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, amount: u256
    ) -> bool;
}

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
    /// `party_a_used` is how much of the trustline has party_a used
    /// `party_b_used` is how much of the trustline has party_b used
    #[derive(Copy, Drop, Serde, starknet::Store, Debug)]
    pub struct Trustline {
        pub party_a: ContractAddress,
        pub party_b: ContractAddress,
        pub amount_effective: u256,
        pub amount_proposed: u256,
        pub proposing_party: ContractAddress,
        pub party_a_used: u256,
        pub party_b_used: u256,
    }

    // Trustline struct impl for more convenient usage
    #[generate_trait]
    pub impl TrustlineImpl of TrustlineTrait {
        /// Checks whether the trustline exists
        /// 
        /// Returns:
        ///     - `true` if both party addresses are non-zero, `false` otherwise
        fn exists(self: Trustline) -> bool {
            !self.party_a.is_zero() && !self.party_b.is_zero()
        }

        /// Checks whether the trustline is effective
        /// 
        /// Returns:
        ///     - `true` if the effective amount is greater than zero, `false` otherwise
        fn is_effective(self: Trustline) -> bool {
            self.amount_effective > 0
        }

        /// Checks whether a trustline proposal exists
        /// 
        /// Returns:
        ///     - `true` if the proposed amount is greater than zero, `false` otherwise
        fn is_proposed(self: Trustline) -> bool {
            self.amount_proposed > 0
        }

        /// Checks whether the trustline is being used by either party
        /// 
        /// Returns:
        ///     - `true` if either party has used any amount of the trustline, `false` otherwise
        fn is_used(self: Trustline) -> bool {
            self.party_a_used != 0 || self.party_b_used != 0
        }

        /// Returns a new Trustline with cleared proposal fields
        /// 
        /// Returns:
        ///     - A new Trustline instance with `amount_proposed` set to zero and `proposing_party` set to the zero address
        fn with_cleared_proposal(self: Trustline) -> Trustline {
            Trustline { amount_proposed: 0, proposing_party: contract_address_const::<0>(), ..self }
        }

        /// Returns a new Trustline with updated proposal fields
        /// 
        /// Arguments:
        ///     - `proposed_amount` - The new proposed amount for the trustline
        ///     - `proposer` - The address of the party proposing the new amount
        /// 
        /// Returns:
        ///     - A new Trustline instance with updated `amount_proposed` and `proposing_party`
        fn with_new_proposal(
            self: Trustline, proposed_amount: u256, proposer: ContractAddress
        ) -> Trustline {
            Trustline { amount_proposed: proposed_amount, proposing_party: proposer, ..self }
        }

        /// Returns a new Trustline with an updated effective amount
        /// 
        /// Arguments:
        ///     - `effective_amount` - The new effective amount for the trustline
        /// 
        /// Returns:
        ///     - A new Trustline instance with the updated `amount_effective`
        fn with_effective_amount(self: Trustline, effective_amount: u256) -> Trustline {
            Trustline { amount_effective: effective_amount, ..self }
        }

        /// Returns a new Trustline with updated usage amounts for both parties
        /// 
        /// Arguments:
        ///     - `party_a_used` - The new amount used by party A
        ///     - `party_b_used` - The new amount used by party B
        /// 
        /// Returns:
        ///     - A new Trustline instance with updated `party_a_used` and `party_b_used`
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

    /// `TrustlineTransfer` event emitted when a trustline transfer occurs
    /// 
    /// `from` is the address of the sender
    /// `to` is the address of the recipient
    /// `amount` is the amount transferred
    /// `trustline_after` is the state of the trustline after the transfer
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
        pub const TRUSTLINE_NOT_EFFECTIVE: felt252 = 'Trustline not effective';
        pub const NO_TRUSTLINE_FOUND: felt252 = 'Trustline does not exist';
        pub const INSUFFICIENT_PROPOSAL_AMOUNT: felt252 = 'Proposed must be > effective';
        pub const INVALID_DECREASE_AMOUNT: felt252 = 'Decrease amount invalid';
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        /// Function for proposing a new trustline between the caller and another party
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
            ref self: ComponentState<TContractState>, other_party: ContractAddress, amount: u256
        ) -> bool {
            let proposer = get_caller_address();
            let trustline = self._read_trustline(proposer, other_party);

            assert(proposer != other_party, Errors::OTHER_PARTY_IS_CALLER);
            assert(!other_party.is_zero(), Errors::OTHER_PARTY_ZERO);
            assert(!trustline.exists(), Errors::NEW_PROPOSED_TRUSTLINE_EXISTS);
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

        /// Function for accepting a proposed new trustline
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

        /// Function for proposing a modification to an existing trustline
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
            assert(!trustline.is_proposed(), 'Trustline already has proposal');

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

        /// Function for accepting a proposed modification to an existing trustline
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
            ref self: ComponentState<TContractState>, other_party: ContractAddress, amount: u256
        ) -> bool {
            // Function for acception modification proposal of existing trustline

            let caller = get_caller_address();
            let trustline = self._read_trustline(caller, other_party);

            assert(caller != other_party, Errors::OTHER_PARTY_IS_CALLER);
            assert(amount > 0, Errors::PROPOSED_AMOUNT_ZERO);
            assert(amount > trustline.amount_effective, 'Proposed < effective');
            assert(trustline.exists(), Errors::NO_PROPOSED_TRUSTLINE);
            assert(trustline.is_proposed(), 'No proposed amount');
            assert(caller != trustline.proposing_party, Errors::CALLER_IS_PROPOSER);
            assert(trustline.is_effective(), Errors::TRUSTLINE_NOT_EFFECTIVE);

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

        /// Function for cancelling a trustline proposal
        /// 
        /// Arguments:
        ///     - `other_party` - The address of the other party in the proposed trustline
        /// 
        /// Returns:
        ///     - Returns `true` if the proposal was successfully cancelled
        /// 
        /// Events:
        ///     - Emits a `TrustlineProposed` event with amount 0 upon successful cancellation
        /// 
        /// Note:
        ///     - If user cancels a new proposal, the trustline will still exist since this 
        ///       function will just delete the trustline's proposal, not the trustline itself.
        ///       So for next proposing a new trustline again, it has to be propose_modify_trustline.
        fn cancel_trustline_proposal(
            ref self: ComponentState<TContractState>, other_party: ContractAddress
        ) -> bool {
            let caller = get_caller_address();
            let trustline = self._read_trustline(caller, other_party);

            assert(caller != other_party, Errors::OTHER_PARTY_IS_CALLER);
            assert(!other_party.is_zero(), Errors::OTHER_PARTY_ZERO);
            assert(trustline.exists(), Errors::NEW_PROPOSED_TRUSTLINE_EXISTS);
            assert(trustline.is_proposed(), 'Trustline has no proposal');

            assert(trustline.proposing_party == caller, 'Can only cancel own proposal');

            let new_trustline = trustline.with_cleared_proposal();

            self._write_trustline(new_trustline);

            self
                .emit(
                    TrustlineProposed {
                        party_a: caller,
                        party_b: other_party,
                        proposed_amount: 0,
                        current_effective_amount: trustline.amount_effective
                    }
                );

            true
        }

        ///////////////
        /// Note:
        ///     - delete_trustline currently disabled,
        ///       uncomment if neccessary, however even if ie. some authority
        ///       deleted a trustline, users could just set it up again
        ///       so these functions might be redundant
        ///////////////
        /// Function for deleting a trustline between two parties
        /// 
        /// Arguments:
        ///     - `party_a` - The address of one party in the trustline
        ///     - `party_b` - The address of the other party in the trustline
        // fn delete_trustline(
        //     ref self: ComponentState<TContractState>,
        //     party_a: ContractAddress,
        //     party_b: ContractAddress
        // ) {
        //     assert(!party_a.is_zero(), 'Party a is zero');
        //     assert(!party_b.is_zero(), 'Party a is zero');

        //     let key = self._get_trustlines_storage_keys(party_a, party_b);

        //     let empty_trustline = Trustline {
        //         party_a: contract_address_const::<0>(),
        //         party_b: contract_address_const::<0>(),
        //         amount_effective: 0,
        //         amount_proposed: 0,
        //         proposing_party: contract_address_const::<0>(),
        //         party_a_used: 0,
        //         party_b_used: 0,
        //     };
        //     self.trustlines.write(key, empty_trustline);
        // }

        // Function for modifying a trustline directly 
        // 
        // Arguments:
        //     - `trustline` - The new state of the trustline to be set
        // 
        // Note:
        //     - Doesn't implement any access restriction itself
        fn modify_trustline(ref self: ComponentState<TContractState>, trustline: Trustline) {
            assert(!trustline.party_a.is_zero(), 'Party a is zero');
            assert(!trustline.party_b.is_zero(), 'Party b is zero');

            self._write_trustline(trustline);
        }

        /// Function for decreasing the amount of an existing trustline
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
        /// 
        /// Note:
        ///     -  Subsequent interactions with trustline might fail if it's decreased
        ///        below the currently used amount, preferably warn the user.
        fn decrease_trustline(
            ref self: ComponentState<TContractState>, other_party: ContractAddress, amount: u256
        ) -> bool {
            let caller = get_caller_address();
            let trustline = self._read_trustline(caller, other_party);

            assert(trustline.is_effective(), Errors::TRUSTLINE_NOT_EFFECTIVE);
            assert(caller != other_party, Errors::OTHER_PARTY_IS_CALLER);
            assert(!other_party.is_zero(), Errors::OTHER_PARTY_ZERO);
            assert(trustline.exists(), Errors::NO_TRUSTLINE_FOUND);

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

        /// Function for performing a trustline transfer
        /// 
        /// Arguments:
        ///     - `from` - The address of the sender
        ///     - `to` - The address of the recipient
        ///     - `amount` - The amount to be transferred
        /// 
        /// Returns:
        ///     - Returns `true` if the transfer was successful
        /// 
        /// Events:
        ///     - Emits a `TrustlineTransfer` event upon successful transfer
        /// 
        /// Note:
        ///     - If user decreased the effective amount of the trustline, 
        ///       and now it is below what was previously used by `from` then 
        ///       this function might fail.
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
            //      no transfers yet, her limit is 50k and the transfer works,
            //      now the limits are: Bob - 80k, Alice - 20k
            // Case B - transfered already: 
            //      Now Alice wants to send 30k again, however since she already
            //      used 30k of the trustline, the transfer will fail as she 
            //      only has 20k limit left, the limits are still the same 
            // Case C - bob transfers:
            //      Bob now transfers 60k to alice. Since she sent him 30k already
            //      it's not a problem (his limit was 80k because of that).
            //      So after the transfer, Bob's limit is decreased by 60k and 
            //      Alice limit is increased. State after transfer: Bob - 20k, Alice - 80k
            // Case D- bob transfers again:
            //      Now bob transfers 20k. State after transfer: Bob-0, Alice-100k
            // Note: All this should happen in terms of `party_a_used` and
            // `party_b_used` fields of trustline struct, ensuring that the used is 
            // never above effective amount. For example, in state after case A, 
            // Alice used 30k of the trustline, so the fields would be: 
            // `party_a_used` = 30k, `party_b_used` = 0, and Bob implicitly can spend 80k 
            // (30k to decrease alice limit to 0, then 50k of his own)

            let (from_used, to_used) = if from == trustline.party_a {
                (trustline.party_a_used, trustline.party_b_used)
            } else {
                (trustline.party_b_used, trustline.party_a_used)
            };

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

        /// Function for retrieving the trustline between two parties
        /// 
        /// Arguments:
        ///     - `party_a` - The address of one party in the trustline
        ///     - `party_b` - The address of the other party in the trustline
        /// 
        /// Returns:
        ///     - Returns the `Trustline` struct representing the trustline between the parties
        fn get_trustline(
            self: @ComponentState<TContractState>,
            party_a: ContractAddress,
            party_b: ContractAddress,
        ) -> Trustline {
            self._read_trustline(party_a, party_b)
        }

        fn _get_trustlines_storage_keys(
            self: @ComponentState<TContractState>,
            address1: ContractAddress,
            address2: ContractAddress,
        ) -> (ContractAddress, ContractAddress) {
            let _a1: felt252 = address1.into();
            let _a2: felt252 = address2.into();

            let _a1: u256 = _a1.into();
            let _a2: u256 = _a2.into();

            assert(_a1 != _a2, 'Parties are the same');

            if (_a1 > _a2) {
                (address1, address2)
            } else {
                (address2, address1)
            }
        }

        fn _write_trustline(ref self: ComponentState<TContractState>, trustline: Trustline) {
            let key = self._get_trustlines_storage_keys(trustline.party_a, trustline.party_b);
            self.trustlines.write(key, trustline)
        }


        fn _read_trustline(
            self: @ComponentState<TContractState>,
            party_a: ContractAddress,
            party_b: ContractAddress,
        ) -> Trustline {
            let key = self._get_trustlines_storage_keys(party_a, party_b);
            self.trustlines.read(key)
        }
    }
}

