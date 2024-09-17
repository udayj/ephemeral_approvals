#[starknet::contract(account)]
pub mod AccountWithEphemeralApproval {
    use core::num::traits::Zero;
    use openzeppelin::account::AccountComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::interface::{IERC20DispatcherTrait, IERC20Dispatcher};
    use starknet::{get_block_timestamp, get_caller_address, get_contract_address};
    use starknet::ContractAddress;
    use ephemeral_approvals::interfaces::iephemeralapproval::IEphemeralApproval;

    component!(path: AccountComponent, storage: account, event: AccountEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // Account Mixin
    #[abi(embed_v0)]
    pub(crate) impl AccountMixinImpl =
        AccountComponent::AccountMixinImpl<ContractState>;
    impl AccountInternalImpl = AccountComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        allowances: LegacyMap<(ContractAddress, ContractAddress), (u256, u64)>,
        #[substorage(v0)]
        account: AccountComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccountEvent: AccountComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    pub(crate) fn constructor(ref self: ContractState, public_key: felt252) {
        self.account.initializer(public_key);
    }

    #[abi(embed_v0)]
    impl EphemeralApprovalImpl of IEphemeralApproval<ContractState> {
        fn approve(
            ref self: ContractState,
            spender: ContractAddress,
            token: ContractAddress,
            amount: u256,
            valid_till: u64
        ) -> bool {
            self.account.assert_only_self();
            assert(valid_till > get_block_timestamp(), 'Cannot provide approval in past');
            assert(spender != get_contract_address(), 'Cannot approve self');
            assert(!token.is_zero(), 'Token cannot be zero');
            self.allowances.write((spender, token), (amount, valid_till));
            return true;
        }

        fn transfer_to(
            ref self: ContractState, to: ContractAddress, token: ContractAddress, amount: u256
        ) -> bool {
            let spender = get_caller_address();
            assert(spender != get_contract_address(), 'Not callable by self');

            // Check that approval is still valid
            // We dont care about un recognised tokens because valid_till be 0 for such tokens
            let (allowance, valid_till) = self.allowances.read((spender, token));
            assert(valid_till > get_block_timestamp(), 'Approval expired');

            // Check amount
            assert(amount <= allowance, 'Approval not enough for amount');
            self.allowances.write((spender, token), (allowance - amount, valid_till));

            // Do transfer
            IERC20Dispatcher { contract_address: token }.transfer(to, amount);
            return true;
        }
    }
}
