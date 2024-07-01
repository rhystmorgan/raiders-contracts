# Raiders Contracts

Raiders Contracts will allow anyone to create bounties for community members to earn 
rewards for taking specific actions.

---

## Validator Descriptions

There are a few validators we will be using:

raidMint - This is the minting policy for `RaidTokens`

raidVal - This locks `RaidTokens` with their rewards

refMint - This minting policy creates a reference token used to hold the validator Dapp 
state

refVal - locks the `RefToken` with the Dapp state datum

### RaidMint

When a user wants to create a Raid, they will mint a token with this policy and send it 
to the `raidVal`.

It will require to have a specific datum which contains:

```rust
type RaidDatum {
  q: Int // Bounty Quantity
  v: Int // Bounty Value (in ADA)
  c: VerificationKeyHash // Users PubKeyHash
}
```

They will also need to deposit the appropriate amount of ADA ((q * v + 2) * 1000000)

To burn the `RaidToken` and remove the bounty the transaction must be signed by the owner 
of the bounty (RaidDatum.c)

### RaidValidator

When someone completes a bounty they can withdraw the given reward.

The bounty rewards info is held within the given `RaidToken` and will enforce the rewards 
that can be withdrawn.

This validator requires a signature from Raiders infrastructure wallet which will allow 
us to verify the bounty has been completed and will prevent anyone from trying to exploit 
the contract.

If the Raid owner wants to update their bounty to increase rewards or close the bounty, 
they can do so aswell.

To update the bounty they will need to make sure to maintain an ADA value at that matches 
the rewards calculation ((q * v + 2) * 1000000). 

This means they cant create a bounty, then withdraw the rewards themselves and get free 
interactions with no rewards for participants.

They can also close a bounty with their signature if there are no more rewards available.

### RefMint

This minting policy is for the Raid Dapp to create a `StateToken` which will be provided 
as a reference input to allow for validator upgradeability.

The reference input controls where `RaidTokens` are sent after mint so we can change the 
raidVal in the future to add different features to the Dapp without trying to organise a 
mass migration of users to the new validator ( we have seen with other projects that this 
doesn't work and can get very messy ).

All we need to do is update the `RefDatum` with the new validator hash and it will become 
the new destination for all future bounties.

This will allow us to increase the complexity of our services easily without affecting 
pre-existing bounties.

### RefValidator

This is the locking validator for our StateToken

Changes can only be made with our `InfrastructureWallet` meaning that as long as we sign 
we can do whatever we need with our reference token.

---

## Data Structures

The main data points we need for the validators are

RaidDatum - containing all of the Raid details

RefDatum - containing the ScriptHash of the RaidValidator in a list ( to allow for 
upgradability to w0 optimisation or other features) & any fees or other values in a list 
( to add fees etc in the future)

---

## Building

```sh
aiken build
```

## Testing

You can write tests in any module using the `test` keyword. For example:

```gleam
test foo() {
  1 + 1 == 2
}
```

To run all tests, simply do:

```sh
aiken check
```

To run only tests matching the string `foo`, do:

```sh
aiken check -m foo
```

## Documentation

If you're writing a library, you might want to generate an HTML documentation for it.

Use:

```sh
aiken docs
```

## Resources

Find more on the [Aiken's user manual](https://aiken-lang.org).
