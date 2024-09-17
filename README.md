**Ephemeral Approvals**

Asking users to approve ERC-20 token amounts to spend is a standard accepted practice. However, there are a few UX and security issues with the standard model. The standard ERC-20 interface does not allow a user to provide a timebound approval for token spends. This means if you provide an approval for 100 tokens to a contract, the said contract will have the right to spend those 100 tokens forever or till the approval is reset to 0. The user thus needs to preferably remember to revoke approvals and this is not just bad UX but also a security vulnerability.

With native account abstraction on starknet, the solution is simple. We define a new additional interface that account contracts implement

`approve(spender, token, amount, valid_till) - callable only by account owner`

`transfer_to(recipient, token, amount)`

The logic is similar to how it works with standard ERC-20 but with an additional check to verify whether the approval is still valid. This opens up a new way of doing token transfers - the `transfer_to` function can implement logic to do arbitrary checks before transferring the tokens - and this would not require any change to the vanilla ERC-20 tokens being used.