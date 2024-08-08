use aiken/dict
use aiken/hash as h
use aiken/list as l
use aiken/transaction as t
use aiken/transaction/credential as cr
use aiken/transaction/value
use okapi/okapi as ok

// PKH 
type VerificationKeyHash =
  h.Hash<h.Blake2b_224, cr.VerificationKey>

// Script
type ScriptHash =
  h.Hash<h.Blake2b_224, cr.Script>

type RaidDatum {
  q: Int,
  v: Int,
  c: VerificationKeyHash,
}

type RaidAction {
  Claim
  Update { quantity: Int }
  Close
}

type MintAction {
  AMint { q: Int, v: Int }
  ABurn
}

type RefMintAction {
  RMint { v: List<ScriptHash>, i: List<Int> }
  RBurn
}

type RefDatum {
  v: List<ScriptHash>,
  i: List<Int>,
}

type RefAction {
  RUpdate { v: List<ScriptHash>, i: List<Int> }
  RClose
}

//                     //
// Raid Minting Policy //
//                     //

validator(o: VerificationKeyHash, rp: value.PolicyId) {
  fn raidMint(r: MintAction, c: t.ScriptContext) {
    expect t.Mint(p) = c.purpose

    expect [Pair(rName, rAmt)] =
      c.transaction.mint
        |> value.from_minted_value()
        |> value.tokens(p)
        |> dict.to_pairs()

    when r is {
      AMint { q, v } -> {
        expect Some(ref) =
          l.find(
            c.transaction.reference_inputs,
            fn(input) { l.has(value.policies(input.output.value), rp) },
          )

        expect t.InlineDatum(refDatum) = ref.output.datum
        expect refDat: RefDatum = refDatum

        l.any(
          c.transaction.outputs,
          fn(output) {
            expect t.InlineDatum(datum) = output.datum
            expect dat: RaidDatum = datum

            expect Some(raidVal) = l.at(refDat.v, 0)

            output.address.payment_credential == cr.ScriptCredential(raidVal) && value.lovelace_of(
              output.value,
            ) >= ( dat.q * dat.v + 2 ) * 1000000 && dat.q == q && dat.v == v && l.has(
              c.transaction.extra_signatories,
              dat.c,
            )
          },
        )
      }
      ABurn -> rAmt == -1
    }
  }
}

//                   //
// Raid Distribution //
//                   //

validator(o: VerificationKeyHash, p: value.PolicyId) {
  fn raidVal(d: RaidDatum, r: RaidAction, c: t.ScriptContext) {
    let t.ScriptContext { transaction, purpose } = c
    expect t.Spend(ownRef) = purpose
    let t.Transaction { inputs, .. } = transaction

    expect Some(in) =
      l.find(inputs, fn(input) { input.output_reference == ownRef })

    expect 1 =
      l.length(
        l.filter(
          inputs,
          fn(input) {
            input.output.address.payment_credential == in.output.address.payment_credential
          },
        ),
      )

    when r is {
      Claim -> {
        let out = ok.get_own_singleton_output(c)

        expect t.InlineDatum(datum) = out.datum
        expect outDatum: RaidDatum = datum
        expect ok.contains_single_token_of(out.value, p)

        let inValue = in.output.value

        expect
          value.lovelace_of(out.value) == value.lovelace_of(inValue) - d.v * 1000000

        ok.tx_signed_by(transaction, o) && outDatum.q == d.q - 1 && outDatum.c == d.c && outDatum.v == d.v && value.without_lovelace(
          in.output.value,
        ) == value.without_lovelace(out.value)
      }
      Update { quantity } -> {
        let out = ok.get_own_singleton_output(c)
        expect t.InlineDatum(datum) = out.datum
        expect outD: RaidDatum = datum

        outD.q == quantity && value.lovelace_of(out.value) >= (
          outD.q * outD.v + 2
        ) * 1000000 && outD.c == d.c && ok.tx_signed_by(transaction, d.c)
      }
      Close -> {
        expect [Pair(burnName, -1)] =
          transaction.mint
            |> value.from_minted_value()
            |> value.tokens(p)
            |> dict.to_pairs()

        expect [Pair(raidName, 1)] =
          in.output.value
            |> value.tokens(p)
            |> dict.to_pairs()

        d.q == 0 && ok.tx_signed_by(transaction, d.c) && raidName == burnName
      }
    }
  }
}

// Tests //

test raidClaim() {
  let owner = #"cafe"
  let policy = #"face"
  let tokenName = #"cece"

  let raidTokenValue = value.from_asset(policy, tokenName, 1)
  let inputValue = value.merge(value.from_lovelace(100000000), raidTokenValue)

  let outputValue = value.merge(value.from_lovelace(90000000), raidTokenValue)

  let claimValue = value.from_lovelace(10000000)

  let raidDatum = RaidDatum { q: 10, v: 10, c: owner }

  let outDatum = RaidDatum { q: 9, v: 10, c: owner }

  let raidAction = Claim

  let raidIn =
    t.Input {
      output_reference: oref(#"dead", 1),
      output: t.Output {
        address: cr.Address {
          payment_credential: cr.ScriptCredential(#"feed"),
          stake_credential: None,
        },
        value: inputValue,
        datum: t.InlineDatum(raidDatum),
        reference_script: None,
      },
    }

  let raidOut =
    t.Output {
      address: cr.Address {
        payment_credential: cr.ScriptCredential(#"feed"),
        stake_credential: None,
      },
      value: outputValue,
      datum: t.InlineDatum(outDatum),
      reference_script: None,
    }

  let userOut =
    t.Output {
      address: cr.Address {
        payment_credential: cr.VerificationKeyCredential(#"beef"),
        stake_credential: None,
      },
      value: claimValue,
      datum: t.NoDatum,
      reference_script: None,
    }

  let tx =
    t.Transaction {
      ..t.placeholder(),
      inputs: [raidIn],
      outputs: [raidOut, userOut],
      extra_signatories: [owner],
    }

  let scriptContext =
    t.ScriptContext { transaction: tx, purpose: t.Spend(oref(#"dead", 1)) }

  raidVal(owner, policy, raidDatum, raidAction, scriptContext)?
}

test raidDatumChange() {
  let owner = #"cafe"
  let policy = #"face"
  let tokenName = #"cece"

  let raidTokenValue = value.from_asset(policy, tokenName, 1)
  let inputValue = value.merge(value.from_lovelace(100000000), raidTokenValue)

  let outputValue = value.merge(value.from_lovelace(90000000), raidTokenValue)

  let claimValue = value.from_lovelace(10000000)

  let raidDatum = RaidDatum { q: 10, v: 10, c: owner }

  // claim & change DatumValue
  let outDatum = RaidDatum { q: 9, v: 6, c: owner }

  let raidAction = Claim

  let raidIn =
    t.Input {
      output_reference: oref(#"dead", 1),
      output: t.Output {
        address: cr.Address {
          payment_credential: cr.ScriptCredential(#"feed"),
          stake_credential: None,
        },
        value: inputValue,
        datum: t.InlineDatum(raidDatum),
        reference_script: None,
      },
    }

  let raidOut =
    t.Output {
      address: cr.Address {
        payment_credential: cr.ScriptCredential(#"feed"),
        stake_credential: None,
      },
      value: outputValue,
      datum: t.InlineDatum(outDatum),
      reference_script: None,
    }

  let userOut =
    t.Output {
      address: cr.Address {
        payment_credential: cr.VerificationKeyCredential(#"beef"),
        stake_credential: None,
      },
      value: claimValue,
      datum: t.NoDatum,
      reference_script: None,
    }

  let tx =
    t.Transaction {
      ..t.placeholder(),
      inputs: [raidIn],
      outputs: [raidOut, userOut],
      extra_signatories: [owner],
    }

  let scriptContext =
    t.ScriptContext { transaction: tx, purpose: t.Spend(oref(#"dead", 1)) }

  raidVal(owner, policy, raidDatum, raidAction, scriptContext)?
}

test raidDoubleSatisfaction() {
  let owner = #"cafe"
  let user = #"beef"
  let raidOwner = #"deaf"
  let policy = #"face"
  let tokenName = #"cece"
  let tN2 = #"aced"

  let raidTokenValue2 = value.from_asset(policy, tN2, 1)
  let inputValue2 = value.merge(value.from_lovelace(100000000), raidTokenValue2)

  let outputValue2 = value.merge(value.from_lovelace(90000000), raidTokenValue2)

  let raidTokenValue = value.from_asset(policy, tokenName, 1)
  let inputValue = value.merge(value.from_lovelace(100000000), raidTokenValue)

  let outputValue = value.merge(value.from_lovelace(90000000), raidTokenValue)

  let claimValue = value.from_lovelace(20000000)

  let raidDatum = RaidDatum { q: 10, v: 10, c: user }

  let outDatum = RaidDatum { q: 9, v: 10, c: user }

  let raidAction = Claim

  let raidIn =
    t.Input {
      output_reference: oref(#"dead", 1),
      output: t.Output {
        address: cr.Address {
          payment_credential: cr.ScriptCredential(#"feed"),
          stake_credential: None,
        },
        value: inputValue,
        datum: t.InlineDatum(raidDatum),
        reference_script: None,
      },
    }

  let raidIn2 =
    t.Input {
      output_reference: oref(#"dead", 2),
      output: t.Output {
        address: cr.Address {
          payment_credential: cr.ScriptCredential(#"feed"),
          stake_credential: None,
        },
        value: inputValue2,
        datum: t.InlineDatum(raidDatum),
        reference_script: None,
      },
    }

  let raidOut =
    t.Output {
      address: cr.Address {
        payment_credential: cr.ScriptCredential(#"feed"),
        stake_credential: None,
      },
      value: outputValue,
      datum: t.InlineDatum(outDatum),
      reference_script: None,
    }

  let raidOut2 =
    t.Output {
      address: cr.Address {
        payment_credential: cr.ScriptCredential(#"feed"),
        stake_credential: None,
      },
      value: outputValue2,
      datum: t.InlineDatum(outDatum),
      reference_script: None,
    }

  let userOut =
    t.Output {
      address: cr.Address {
        payment_credential: cr.VerificationKeyCredential(#"beef"),
        stake_credential: None,
      },
      value: claimValue,
      datum: t.NoDatum,
      reference_script: None,
    }

  let tx =
    t.Transaction {
      ..t.placeholder(),
      inputs: [raidIn, raidIn2],
      outputs: [raidOut, raidOut2, userOut],
      extra_signatories: [owner],
    }

  let scriptContext =
    t.ScriptContext { transaction: tx, purpose: t.Spend(oref(#"dead", 1)) }

  raidVal(owner, policy, raidDatum, raidAction, scriptContext)?
}

test raidClose() {
  let owner = #"cafe"
  let user = #"beef"
  let raidOwner = #"deaf"
  let policy = #"face"
  let tokenName = #"cece"

  let raidTokenValue = value.from_asset(policy, tokenName, 1)
  let burnValue = value.from_asset(policy, tokenName, -1)
  let inputValue = value.merge(value.from_lovelace(100000000), raidTokenValue)

  let raidDatum = RaidDatum { q: 0, v: 10, c: raidOwner }

  let raidAction = Close

  let raidIn =
    t.Input {
      output_reference: oref(#"dead", 1),
      output: t.Output {
        address: cr.Address {
          payment_credential: cr.ScriptCredential(#"feed"),
          stake_credential: None,
        },
        value: inputValue,
        datum: t.InlineDatum(raidDatum),
        reference_script: None,
      },
    }

  let tx =
    t.Transaction {
      ..t.placeholder(),
      inputs: [raidIn],
      mint: value.to_minted_value(burnValue),
      extra_signatories: [raidOwner],
    }

  let scriptContext =
    t.ScriptContext { transaction: tx, purpose: t.Spend(oref(#"dead", 1)) }

  raidVal(owner, policy, raidDatum, raidAction, scriptContext)?
}

test raidMultiClose() {
  let owner = #"cafe"
  let user = #"beef"
  let raidOwner = #"deaf"
  let policy = #"face"
  let tokenName = #"cece"
  let tN2 = #"aced"

  let raidTokenValue2 = value.from_asset(policy, tN2, 1)
  let inputValue2 = value.merge(value.from_lovelace(100000000), raidTokenValue2)

  let outputValue2 = value.merge(value.from_lovelace(90000000), raidTokenValue2)

  let raidTokenValue = value.from_asset(policy, tokenName, 1)
  let inputValue = value.merge(value.from_lovelace(100000000), raidTokenValue)

  let outputValue = value.merge(raidTokenValue2, raidTokenValue)

  let claimValue = value.from_lovelace(20000000)

  let raidDatum = RaidDatum { q: 0, v: 10, c: user }

  let raidDatum2 = RaidDatum { q: 9, v: 10, c: user }

  let raidAction = Close

  let raidIn =
    t.Input {
      output_reference: oref(#"dead", 1),
      output: t.Output {
        address: cr.Address {
          payment_credential: cr.ScriptCredential(#"feed"),
          stake_credential: None,
        },
        value: inputValue,
        datum: t.InlineDatum(raidDatum),
        reference_script: None,
      },
    }

  let raidIn2 =
    t.Input {
      output_reference: oref(#"dead", 2),
      output: t.Output {
        address: cr.Address {
          payment_credential: cr.ScriptCredential(#"feed"),
          stake_credential: None,
        },
        value: inputValue2,
        datum: t.InlineDatum(raidDatum),
        reference_script: None,
      },
    }

  let userOut =
    t.Output {
      address: cr.Address {
        payment_credential: cr.VerificationKeyCredential(#"beef"),
        stake_credential: None,
      },
      value: claimValue,
      datum: t.NoDatum,
      reference_script: None,
    }

  let tx =
    t.Transaction {
      ..t.placeholder(),
      inputs: [raidIn, raidIn2],
      outputs: [userOut],
      mint: value.to_minted_value(outputValue),
      extra_signatories: [owner],
    }

  let scriptContext =
    t.ScriptContext { transaction: tx, purpose: t.Spend(oref(#"dead", 1)) }

  raidVal(owner, policy, raidDatum, raidAction, scriptContext)?
}

//                      //
// Reference Input Mint //
//                      //

validator(o: VerificationKeyHash) {
  fn refMint(r: RefMintAction, c: t.ScriptContext) {
    let t.ScriptContext { transaction, purpose } = c
    expect t.Mint(p) = purpose
    let t.Transaction { outputs, mint, .. } = transaction

    expect [Pair(rName, rAmt)] =
      mint
        |> value.from_minted_value()
        |> value.tokens(p)
        |> dict.to_pairs()

    when r is {
      RMint { v, i } -> {
        expect Some(ownOut) =
          l.find(
            outputs,
            fn(output) {
              expect [Pair(tName, tAmt)] =
                output.value
                  |> value.without_lovelace()
                  |> value.tokens(p)
                  |> dict.to_pairs()
              tAmt == 1 && rName == tName
            },
          )
        expect t.InlineDatum(datum) = ownOut.datum
        expect outD: RefDatum = datum

        ok.tx_signed_by(transaction, o) && rAmt == 1 && outD.v == v && outD.i == i
      }
      RBurn -> ok.tx_signed_by(transaction, o) && rAmt == -1
    }
  }
}

//                     //
// Reference Validator //
//                     //

validator(o: VerificationKeyHash, p: value.PolicyId) {
  fn refVal(d: RefDatum, r: RefAction, c: t.ScriptContext) {
    let t.ScriptContext { transaction, purpose } = c
    expect t.Spend(_ownRef) = purpose

    when r is {
      RUpdate { v, i } -> {
        let out = ok.get_own_singleton_output(c)
        expect t.InlineDatum(datum) = out.datum
        expect outD: RefDatum = datum

        l.has(value.policies(out.value), p) && ok.tx_signed_by(transaction, o) && outD.v == v && outD.i == i
      }
      RClose -> ok.tx_signed_by(transaction, o)
    }
  }
}

fn oref(h: ByteArray, i: Int) -> t.OutputReference {
  t.OutputReference {
    transaction_id: t.TransactionId { hash: h },
    output_index: i,
  }
}
