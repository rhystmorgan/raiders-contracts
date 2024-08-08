import {
  Blockfrost,
  C,
  Data,
  Lucid,
  SpendingValidator,
  TxHash,
  fromHex,
  toHex,
  toUnit,
  Constr,
  MintingPolicy,
  fromText,
  mintingPolicyToId,
  applyParamsToScript,
  applyDoubleCborEncoding,
  attachSpendingValidator,
  validatorToScriptHash,
  UTxO,
} from "https://deno.land/x/lucid@0.10.7/mod.ts";
import * as cbor from "https://deno.land/x/cbor@v1.4.1/index.js";

// deno run --allow-net --allow-read --allow-env RaidLucid.ts

// check the order of your validators in the './plutus.json' file 
// after you have built the project

const BLOCKFROST = ""
 
const lucid = await Lucid.new(
  new Blockfrost(
    "https://cardano-preview.blockfrost.io/api/v0",
    BLOCKFROST,
  ),
  "Preview",
);
 
lucid.selectWalletFromPrivateKey(await Deno.readTextFile("./owner.sk"));
 
const ownerPKH = lucid.utils.getAddressDetails(await Deno.readTextFile("owner.addr")).paymentCredential.hash;
console.log(ownerPKH)

const refMinting = await readRefMint()
const refCS = lucid.utils.mintingPolicyToId(refMinting)
const refVal = await readRefVal()
const mint = await readMintValidator()
const mintCS = lucid.utils.mintingPolicyToId(mint)
const raidVal = await readDistroValidator()

const refHash = lucid.utils.validatorToScriptHash(refVal)
const raidHash = lucid.utils.validatorToScriptHash(raidVal)

const validatorsC = {
  "refMint": refMinting,
  "refVal": refVal,
  "mint": mint,
  "raidVal": raidVal
}

// --- Write Validator Files

// const writeValidators = await Deno.writeTextFile('validators.json', JSON.stringify(validatorsC))
 
console.log(validatorsC)

// --- Supporting functions

async function readDistroValidator(): Promise<SpendingValidator> {
  const validator = JSON.parse(await Deno.readTextFile("plutus.json")).validators[1];
  return {
    type: "PlutusV2",
    script: applyParamsToScript(applyDoubleCborEncoding(validator.compiledCode), [infraPKH, ownerPKH, mintCS]),
  };
}

async function readMintValidator(): Promise<MintingPolicy> {
  const validator = JSON.parse(await Deno.readTextFile("plutus.json")).validators[0];
  return {
    type: "PlutusV2",
    script: applyParamsToScript(applyDoubleCborEncoding(validator.compiledCode), [ownerPKH, refCS]),
  };
}

async function readRefMint(): Promise<MintingPolicy> {
  const validator = JSON.parse(await Deno.readTextFile("plutus.json")).validators[2];
  return {
    type: "PlutusV2",
    script: applyParamsToScript(applyDoubleCborEncoding(validator.compiledCode), [ownerPKH]),
  };
}

async function readRefVal(): Promise<SpendingValidator> {
  const validator = JSON.parse(await Deno.readTextFile("plutus.json")).validators[3];
  return {
    type: "PlutusV2",
    script: applyParamsToScript(applyDoubleCborEncoding(validator.compiledCode), [ownerPKH, refCS]),
  };
}

const ownerAddress = await Deno.readTextFile("./owner.addr");

const refName = fromText("Raiders")
const tokenName = fromText("B")

// --- Datums && Redeemers

const mintRedeemer = Data.to(new Constr(0, [10n, 10n]))
const refMintAction = Data.to(new Constr(0, [[raidHash], [2000000n]]))
const burnRedeemer =Data.to(new Constr(1, [])) // this is the same for both minting policies

const rAddress = lucid.utils.validatorToAddress(raidVal)
console.log(rAddress)
const rDatum = Data.to(new Constr(0, [10n, 10n, ownerPKH]))
const raidClaimAction = Data.to(new Constr(0, []))
const raidUpdateAction = Data.to(new Constr(1, [20n]))
const raidCloseAction = Data.to(new Constr(2, []))

const bounty = 100000000n + 2000000n

const refAddress = lucid.utils.validatorToAddress(refVal)
const refDat = Data.to(new Constr(0, [[raidHash], [2000000n]]))

// --- Transactions

// v-- V2 --v //

async function raidMint() {
  const refUtxo = await lucid.utxosAtWithUnit(refAddress, [toUnit(refCS, refName)])
  const tx = await lucid
  .newTx()
  .mintAssets({
    [toUnit(mintCS, tokenName)]: BigInt(1),
  }, mintRedeemer)
  .attachMintingPolicy(mint)
  .readFrom(refUtxo)
  .payToContract(rAddress, { inline: rDatum }, { [toUnit(mintCS, tokenName)]: BigInt(1), lovelace: bounty })
  .addSignerKey(ownerPKH) 
  .complete()
  
  const signedTx = await tx.sign().complete()
  
  return signedTx.submit()
}

async function raidDistro() {
  const unit = toUnit(mintCS, tokenName)
  const utxos: [UTxO] = await lucid.utxosAtWithUnit(rAddress, [unit])
  const utxo: UTxO = utxos[0]
  const value = await utxo.assets.lovelace
  const datum = await Data.from(utxo.datum)
  const rewards = datum.fields[1]
  const outValue = value - (rewards * 1000000n)
  const actions = datum.fields[0]
  const remaining = actions - 1n
  const outDatum = Data.to(new Constr(0, [remaining, datum.fields[1]]))
  
  const tx = await lucid
  .newTx()
  .collectFrom([utxo], raidClaimAction)
  .attachSpendingValidator(raidVal)
  .payToAddress(ownerAddress, { lovelace: rewards } )
  .payToContract(rAddress, {inline: outDatum}, { [unit]: 1n, lovelace: outValue} )
  .addSignerKey(ownerPKH)
  .complete()
  
  const signedTx = await tx.sign().complete()
  
  return signedTx.submit()
}

async function refMint() {
  const unit = toUnit(refCS, refName)
  const utxos = await lucid.utxosAt(ownerAddress)
  
  const tx = await lucid 
  .newTx()
  .collectFrom(utxos)
  .mintAssets(
    {[unit]: 1n},
    refMintAction
  )
  .attachMintingPolicy(refMinting)
  .payToContract(refAddress, { inline: refDat }, { [unit]: 1n })
  .addSignerKey(ownerPKH)
  .complete()
  
  const signedTx = await tx.sign().complete()
  
  return signedTx.submit()
}

async function refUpdate() {
  const newDat = Data.to(new Constr(0, [[raidHash], [2000000n]]))
  const unit = toUnit(refCS, refName)
  const utxos = await lucid.utxosAtWithUnit(refAddress, unit)
  console.log(utxos)
  const utxo = utxos[0]
  
  const tx = await lucid
  .newTx()
  .collectFrom([utxo], refMintAction)
  .attachSpendingValidator(refVal)
  .payToContract(refAddress, {inline: newDat }, { [unit]: 1n})
  .addSignerKey(ownerPKH)
  .complete()
  
  const signedTx = await tx.sign().complete()
  
  return signedTx.submit()
}

async function burn() {
  const utxos = await lucid.utxosAtWithUnit(rAddress, [toUnit(mintCS, tokenName)])
  const utxo = utxos[0]
  
  const tx = await lucid
  .newTx()
  .collectFrom([utxo], burnRedeemer)
  .mintAssets({
    [toUnit(mintCS, tokenName)]: -1n,
  }, burnRedeemer)
  .attachMintingPolicy(mint)
  .attachSpendingValidator(raidVal)
  .addSignerKey(ownerPKH) 
  .complete()
  
  const signedTx = await tx.sign().complete()
  
  return signedTx.submit()
}

// --- Transaction Execution

console.log(refAddress)

const mintRefToken = await refMint()

await lucid.awaitTx(mintRefToken)

console.log(`Minted Reference Token
    Tx Hash: ${mintRefToken}
    PolicyId: ${refCS}`)

// const mintToken = await raidMint()

// await lucid.awaitTx(mintToken)

// console.log(`Created Raid!
//     Tx Hash: ${mintToken}
//     PolicyID: ${mintCS}
// `)

// const distroToken = await raidDistro()

// await lucid.awaitTx(distroToken)

// console.log(`Distributed Tokens!
//     Tx Hash: ${distroToken}
// `)

// const burnToken = await burn()

// await lucid.awaitTx(burnToken)

// console.log(`Burned Token!
//     Tx Hash: ${burnToken}
// `)

// const updateToken = await updateThread()

// await lucid.awaitTx(updateToken)

// console.log(`Updated NFT!
//     Tx Hash: ${updateToken}
// `)

// const updateRef = await refUpdate()

// await lucid.awaitTx(updateRef)

// console.log(`Updated Ref Token!
//     TxHash: ${updateRef}`)
