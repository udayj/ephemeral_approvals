use core::num::traits::Zero;
use core::array::ArrayTrait;

use ephemeral_approvals::account::AccountWithEphemeralApproval;
use ephemeral_approvals::interfaces::iephemeralapproval::{
    IEphemeralApprovalDispatcher, IEphemeralApprovalDispatcherTrait
};
use openzeppelin::account::interface::{ISRC6, ISRC6_ID};

use openzeppelin::tests::utils;
use openzeppelin::token::erc20::interface::{IERC20DispatcherTrait, IERC20Dispatcher};
use openzeppelin::utils::selectors;
use openzeppelin::utils::serde::SerializedAppend;
use super::erc20::ERC20Upgradeable;
use starknet::ContractAddress;
use starknet::account::Call;
use starknet::contract_address_const;
use starknet::testing;
use starknet::get_contract_address;
use starknet::syscalls::{deploy_syscall, call_contract_syscall};
use super::constants::{
    PUBKEY, NEW_PUBKEY, SALT, ZERO, QUERY_OFFSET, QUERY_VERSION, MIN_TRANSACTION_VERSION
};

#[derive(Drop)]
pub(crate) struct SignedTransactionData {
    pub(crate) private_key: felt252,
    pub(crate) public_key: felt252,
    pub(crate) transaction_hash: felt252,
    pub(crate) r: felt252,
    pub(crate) s: felt252
}

pub(crate) fn SIGNED_TX_DATA() -> SignedTransactionData {
    SignedTransactionData {
        private_key: 1234,
        public_key: NEW_PUBKEY,
        transaction_hash: 0x601d3d2e265c10ff645e1554c435e72ce6721f0ba5fc96f0c650bfc6231191a,
        r: 0x6bc22689efcaeacb9459577138aff9f0af5b77ee7894cdc8efabaf760f6cf6e,
        s: 0x295989881583b9325436851934334faa9d639a2094cd1e2f8691c8a71cd4cdf
    }
}


fn CLASS_HASH() -> felt252 {
    AccountWithEphemeralApproval::TEST_CLASS_HASH
}


fn deploy(
    contract_class_hash: felt252, salt: felt252, calldata: Array<felt252>
) -> ContractAddress {
    let (address, _) = deploy_syscall(
        contract_class_hash.try_into().unwrap(), salt, calldata.span(), false
    )
        .unwrap();
    address
}

fn setup_dispatcher(
    data: Option<@SignedTransactionData>
) -> (IEphemeralApprovalDispatcher, ContractAddress) {
    testing::set_version(MIN_TRANSACTION_VERSION);

    let mut calldata = array![];
    if data.is_some() {
        let data = data.unwrap();
        testing::set_signature(array![*data.r, *data.s].span());
        testing::set_transaction_hash(*data.transaction_hash);
        //calldata.append(PUBKEY);
        calldata.append(*data.public_key);
    } else {
        calldata.append(PUBKEY);
    }
    let address = utils::deploy(CLASS_HASH(), calldata);
    (IEphemeralApprovalDispatcher { contract_address: address }, address)
}

fn deploy_erc20(recipient: ContractAddress) -> (IERC20Dispatcher, ContractAddress) {
    let owner: ContractAddress = contract_address_const::<100>();
    let name: ByteArray = "ERC20";
    let symbol: ByteArray = "TKT";
    let fixed_supply: u256 = 100;

    let mut calldata = ArrayTrait::<felt252>::new();
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    fixed_supply.serialize(ref calldata);
    recipient.serialize(ref calldata);
    owner.serialize(ref calldata);
    let erc20_token_address = deploy(ERC20Upgradeable::TEST_CLASS_HASH, 1, calldata);
    return (IERC20Dispatcher { contract_address: erc20_token_address }, erc20_token_address);
}

fn deploy_erc20_new(recipient: ContractAddress) -> (IERC20Dispatcher, ContractAddress) {
    let owner: ContractAddress = contract_address_const::<100>();
    let name: ByteArray = "ERC20";
    let symbol: ByteArray = "TKT";
    let fixed_supply: u256 = 100;

    let mut calldata = ArrayTrait::<felt252>::new();
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    fixed_supply.serialize(ref calldata);
    recipient.serialize(ref calldata);
    owner.serialize(ref calldata);
    let erc20_token_address = deploy(ERC20Upgradeable::TEST_CLASS_HASH, 2, calldata);
    return (IERC20Dispatcher { contract_address: erc20_token_address }, erc20_token_address);
}

#[test]
fn test_approve_and_transact() {
    let data = SIGNED_TX_DATA();
    let (account, account_address) = setup_dispatcher(Option::Some(@data));

    let (erc20, erc20_address) = deploy_erc20(account_address);
    let spender = contract_address_const::<100>();
    let recipient = contract_address_const::<200>();
    testing::set_contract_address(account_address);
    account.approve(spender, erc20_address, 50, 1000);
    println!("Sender balance before:{}", erc20.balance_of(account_address));
    println!("Recipient balance before:{}", erc20.balance_of(recipient));
    let account_before = erc20.balance_of(account_address);
    let recipient_before = erc20.balance_of(recipient);
    testing::set_contract_address(spender);
    testing::set_block_timestamp(500);

    account.transfer_to(recipient, erc20_address, 10);

    let account_after = erc20.balance_of(account_address);
    let recipient_after = erc20.balance_of(recipient);
    println!("Sender balance after:{}", erc20.balance_of(account_address));
    println!("Recipient balance after:{}", erc20.balance_of(recipient));
    assert_eq!(account_after, account_before - 10);
    assert_eq!(recipient_after, recipient_before + 10);
}

#[test]
#[should_panic(expected: ('Approval expired', 'ENTRYPOINT_FAILED'))]
fn test_approve_and_transact_after_expiry() {
    let data = SIGNED_TX_DATA();
    let (account, account_address) = setup_dispatcher(Option::Some(@data));

    let (erc20, erc20_address) = deploy_erc20(account_address);
    let spender = contract_address_const::<100>();
    let recipient = contract_address_const::<200>();
    testing::set_contract_address(account_address);
    account.approve(spender, erc20_address, 50, 1000);

    testing::set_contract_address(spender);
    testing::set_block_timestamp(1500);

    account.transfer_to(recipient, erc20_address, 10);
}

#[test]
#[should_panic(expected: ('Approval not enough for amount', 'ENTRYPOINT_FAILED'))]
fn test_not_enough_approval() {
    let data = SIGNED_TX_DATA();
    let (account, account_address) = setup_dispatcher(Option::Some(@data));

    let (erc20, erc20_address) = deploy_erc20(account_address);
    let spender = contract_address_const::<100>();
    let recipient = contract_address_const::<200>();
    testing::set_contract_address(account_address);
    account.approve(spender, erc20_address, 50, 1000);
    let account_before = erc20.balance_of(account_address);
    let recipient_before = erc20.balance_of(recipient);
    testing::set_contract_address(spender);
    testing::set_block_timestamp(500);

    account.transfer_to(recipient, erc20_address, 100);

    let account_after = erc20.balance_of(account_address);
    let recipient_after = erc20.balance_of(recipient);

    assert_eq!(account_after, account_before - 10);
    assert_eq!(recipient_after, recipient_before + 10);
}

#[test]
#[should_panic(expected: ('Approval not enough for amount', 'ENTRYPOINT_FAILED'))]
fn test_not_enough_approval_2() {
    let data = SIGNED_TX_DATA();
    let (account, account_address) = setup_dispatcher(Option::Some(@data));
    let hash = data.transaction_hash;
    let (erc20, erc20_address) = deploy_erc20(account_address);
    let spender = contract_address_const::<100>();
    let recipient = contract_address_const::<200>();
    testing::set_contract_address(account_address);
    account.approve(spender, erc20_address, 50, 1000);
    let account_before = erc20.balance_of(account_address);
    let recipient_before = erc20.balance_of(recipient);
    testing::set_contract_address(spender);
    testing::set_block_timestamp(500);

    account.transfer_to(recipient, erc20_address, 10);

    let account_after = erc20.balance_of(account_address);
    let recipient_after = erc20.balance_of(recipient);

    assert_eq!(account_after, account_before - 10);
    assert_eq!(recipient_after, recipient_before + 10);
    account.transfer_to(recipient, erc20_address, 50);
}

#[test]
#[should_panic(expected: ('Approval expired', 'ENTRYPOINT_FAILED'))]
fn test_unrecognised_erc20() {
    let data = SIGNED_TX_DATA();
    let (account, account_address) = setup_dispatcher(Option::Some(@data));
    let hash = data.transaction_hash;
    let (erc20, erc20_address) = deploy_erc20(account_address);
    let (erc20_new, erc20_address_new) = deploy_erc20_new(contract_address_const::<300>());
    let spender = contract_address_const::<100>();
    let recipient = contract_address_const::<200>();
    testing::set_contract_address(account_address);
    account.approve(spender, erc20_address, 50, 1000);

    testing::set_contract_address(spender);
    testing::set_block_timestamp(500);

    // asking to transfer from some unknown erc20
    account.transfer_to(recipient, erc20_address_new, 10);
}
