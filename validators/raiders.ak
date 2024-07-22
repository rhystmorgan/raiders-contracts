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
    expect t.Spend(_ownRef) = purpose

    when r is {
      Claim -> {
        let out = ok.get_own_singleton_output(c)

        expect t.InlineDatum(datum) = out.datum
        expect outDatum: RaidDatum = datum
        expect ok.contains_single_token_of(out.value, p)

        let inValue = ok.get_own_input_value(c)

        expect
          value.lovelace_of(out.value) == value.lovelace_of(inValue) - d.v * 1000000

        ok.tx_signed_by(transaction, o) && outDatum.q == d.q - 1
      }
      Update { quantity } -> {
        let out = ok.get_own_singleton_output(c)
        expect t.InlineDatum(datum) = out.datum
        expect outD: RaidDatum = datum

        outD.q == quantity && value.lovelace_of(out.value) >= (
          outD.q * outD.v + 2
        ) * 1000000 && outD.c == d.c && ok.tx_signed_by(transaction, d.c)
      }
      Close -> d.q == 0 && ok.tx_signed_by(transaction, d.c)
    }
  }
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
