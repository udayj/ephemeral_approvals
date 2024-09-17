use starknet::ContractAddress;

#[starknet::interface]
pub trait IEphemeralApproval<TState> {
    fn approve(
        ref self: TState,
        spender: ContractAddress,
        token: ContractAddress,
        amount: u256,
        valid_till: u64
    ) -> bool;
    fn transfer_to(
        ref self: TState, to: ContractAddress, token: ContractAddress, amount: u256
    ) -> bool;
}
