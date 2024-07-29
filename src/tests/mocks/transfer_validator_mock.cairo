#[starknet::contract]
pub(crate) mod TransferValidatorMock {
    use trustlines_erc::contract::ITransferValidator;
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[abi(embed_v0)]
    impl TransferValidator of ITransferValidator<ContractState> {
        fn is_transfer_valid(
            self: @ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
        ) -> bool {
            false
        }
    }
}
