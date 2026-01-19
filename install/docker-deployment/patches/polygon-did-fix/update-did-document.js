#!/usr/bin/env node
/**
 * update-did-document.js - Update on-chain DID document with publicKeyBase58
 *
 * This script updates the DID document on Polygon blockchain to include
 * publicKeyBase58 instead of blockchainAccountId, enabling external verifiers
 * (like Inji Verify) to extract the public key for signature verification.
 *
 * Usage: node update-did-document.js
 *
 * Environment variables:
 *   PRIVATE_KEY - Private key for signing transaction (required)
 *   DID_ADDRESS - Ethereum address from the DID (optional, derived from private key)
 *   POLYGON_RPC - Polygon RPC endpoint (default: https://polygon-rpc.com)
 */

const { ethers } = require('ethers');

// Configuration
const PRIVATE_KEY = process.env.PRIVATE_KEY || '52b5fe7ac274c912b5fdd2440e846a20360d78af278d2722a79051f28b44ef3a';
const POLYGON_RPC = process.env.POLYGON_RPC || 'https://polygon-rpc.com';
const DID_REGISTRY_ADDRESS = '0x0C16958c4246271622201101C83B9F0Fc7180d15';

// Ayanworks DID Registry ABI (relevant functions)
const DID_REGISTRY_ABI = [
  'function getDIDDoc(address _id) view returns (string)',
  'function updateDIDDoc(address _id, string _doc) public',
  'event DIDDocChanged(address indexed _id, string _doc)'
];

// Base58 encoding (Bitcoin alphabet)
const ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

function toBase58(buffer) {
  if (buffer.length === 0) return '';

  const bytes = Array.from(buffer);
  const digits = [0];

  for (let i = 0; i < bytes.length; i++) {
    let carry = bytes[i];
    for (let j = 0; j < digits.length; j++) {
      carry += digits[j] << 8;
      digits[j] = carry % 58;
      carry = Math.floor(carry / 58);
    }
    while (carry > 0) {
      digits.push(carry % 58);
      carry = Math.floor(carry / 58);
    }
  }

  // Handle leading zeros
  let result = '';
  for (let i = 0; i < bytes.length && bytes[i] === 0; i++) {
    result += ALPHABET[0];
  }

  for (let i = digits.length - 1; i >= 0; i--) {
    result += ALPHABET[digits[i]];
  }

  return result;
}

async function main() {
  console.log('===========================================');
  console.log('  Update DID Document with publicKeyBase58');
  console.log('===========================================');
  console.log('');

  // Create wallet from private key
  const wallet = new ethers.Wallet(PRIVATE_KEY);
  const address = wallet.address;
  const did = `did:polygon:${address}`;

  console.log('DID:', did);
  console.log('Address:', address);
  console.log('');

  // Connect to Polygon
  const provider = new ethers.providers.JsonRpcProvider(POLYGON_RPC);
  const connectedWallet = wallet.connect(provider);

  // Check balance
  const balance = await provider.getBalance(address);
  console.log('MATIC Balance:', ethers.utils.formatEther(balance), 'MATIC');

  if (balance.eq(0)) {
    console.log('');
    console.log('[WARN] Address has no MATIC for gas fees');
    console.log('       You need MATIC on Polygon Mainnet to update the DID document');
    console.log('       Get MATIC from an exchange or faucet');
  }
  console.log('');

  // Get current DID document
  console.log('1. Fetching current DID document...');
  const registry = new ethers.Contract(DID_REGISTRY_ADDRESS, DID_REGISTRY_ABI, connectedWallet);

  let currentDoc;
  try {
    const docString = await registry.getDIDDoc(address);
    currentDoc = JSON.parse(docString);
    console.log('   [OK] Current document retrieved');
    console.log('');
    console.log('Current DID Document:');
    console.log(JSON.stringify(currentDoc, null, 2));
    console.log('');
  } catch (error) {
    console.log('   [FAIL] Could not fetch current DID document:', error.message);
    console.log('   Creating new document...');
    currentDoc = null;
  }

  // Derive public key from private key
  console.log('2. Deriving public key...');

  // Get the uncompressed public key (65 bytes: 0x04 + 32 bytes X + 32 bytes Y)
  const publicKeyUncompressed = ethers.utils.computePublicKey(wallet.privateKey, false);
  console.log('   Uncompressed public key:', publicKeyUncompressed);

  // Get compressed public key (33 bytes: 0x02/0x03 + 32 bytes X)
  const publicKeyCompressed = ethers.utils.computePublicKey(wallet.privateKey, true);
  console.log('   Compressed public key:', publicKeyCompressed);

  // Convert to Base58
  const publicKeyBytes = ethers.utils.arrayify(publicKeyCompressed);
  const publicKeyBase58 = toBase58(publicKeyBytes);
  console.log('   publicKeyBase58:', publicKeyBase58);
  console.log('');

  // Create updated DID document with publicKeyBase58
  console.log('3. Creating updated DID document...');

  const updatedDoc = {
    '@context': [
      'https://www.w3.org/ns/did/v1',
      'https://w3id.org/security/suites/secp256k1-2019/v1'
    ],
    'id': did,
    'verificationMethod': [
      {
        'id': `${did}#key-1`,
        'type': 'EcdsaSecp256k1VerificationKey2019',
        'controller': did,
        'publicKeyBase58': publicKeyBase58
      }
    ],
    'authentication': [`${did}#key-1`],
    'assertionMethod': [`${did}#key-1`]
  };

  console.log('');
  console.log('Updated DID Document:');
  console.log(JSON.stringify(updatedDoc, null, 2));
  console.log('');

  // Update on-chain
  console.log('4. Updating DID document on Polygon blockchain...');

  if (balance.eq(0)) {
    console.log('   [SKIP] Cannot update - no MATIC for gas');
    console.log('');
    console.log('To update manually, fund the address with MATIC and run this script again.');
    console.log('Or use the following command with a funded wallet:');
    console.log('');
    console.log('const tx = await registry.updateDIDDoc(address, JSON.stringify(updatedDoc));');

    // Save the document for reference
    const fs = require('fs');
    const outputPath = '/tmp/updated-did-document.json';
    fs.writeFileSync(outputPath, JSON.stringify(updatedDoc, null, 2));
    console.log('');
    console.log('Updated document saved to:', outputPath);
    return;
  }

  try {
    // Estimate gas
    const gasEstimate = await registry.estimateGas.updateDIDDoc(address, JSON.stringify(updatedDoc));
    console.log('   Estimated gas:', gasEstimate.toString());

    // Get current gas price
    const gasPrice = await provider.getGasPrice();
    console.log('   Gas price:', ethers.utils.formatUnits(gasPrice, 'gwei'), 'gwei');

    const estimatedCost = gasEstimate.mul(gasPrice);
    console.log('   Estimated cost:', ethers.utils.formatEther(estimatedCost), 'MATIC');
    console.log('');

    // Send transaction with appropriate gas settings for Polygon
    console.log('   Sending transaction...');

    // Polygon requires minimum 25 gwei for priority fee
    const feeData = await provider.getFeeData();
    const maxPriorityFeePerGas = ethers.utils.parseUnits('35', 'gwei'); // 35 gwei tip
    const maxFeePerGas = feeData.maxFeePerGas
      ? feeData.maxFeePerGas.add(maxPriorityFeePerGas)
      : ethers.utils.parseUnits('100', 'gwei');

    console.log('   Max priority fee:', ethers.utils.formatUnits(maxPriorityFeePerGas, 'gwei'), 'gwei');
    console.log('   Max fee per gas:', ethers.utils.formatUnits(maxFeePerGas, 'gwei'), 'gwei');

    const tx = await registry.updateDIDDoc(address, JSON.stringify(updatedDoc), {
      gasLimit: gasEstimate.mul(120).div(100), // Add 20% buffer
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      maxFeePerGas: maxFeePerGas
    });

    console.log('   Transaction hash:', tx.hash);
    console.log('   Waiting for confirmation...');

    const receipt = await tx.wait();
    console.log('   [OK] Transaction confirmed in block', receipt.blockNumber);
    console.log('');

    // Verify the update
    console.log('5. Verifying update...');
    const verifyDoc = await registry.getDIDDoc(address);
    const parsedDoc = JSON.parse(verifyDoc);

    if (parsedDoc.verificationMethod &&
        parsedDoc.verificationMethod[0] &&
        parsedDoc.verificationMethod[0].publicKeyBase58) {
      console.log('   [OK] DID document updated successfully!');
      console.log('   publicKeyBase58:', parsedDoc.verificationMethod[0].publicKeyBase58);
    } else {
      console.log('   [WARN] Document updated but publicKeyBase58 not found');
    }

    console.log('');
    console.log('===========================================');
    console.log('         DID Document Updated!');
    console.log('===========================================');
    console.log('');
    console.log('The DID document now includes publicKeyBase58 which enables');
    console.log('external verifiers like Inji Verify to extract the public key');
    console.log('for signature verification.');
    console.log('');
    console.log('DID:', did);
    console.log('Transaction:', `https://polygonscan.com/tx/${tx.hash}`);

  } catch (error) {
    console.log('   [FAIL] Transaction failed:', error.message);

    if (error.code === 'INSUFFICIENT_FUNDS') {
      console.log('');
      console.log('You need more MATIC to cover gas fees.');
    } else if (error.code === 'UNPREDICTABLE_GAS_LIMIT') {
      console.log('');
      console.log('This may indicate you are not the controller of this DID.');
      console.log('Only the original registrant can update the DID document.');
    }

    process.exit(1);
  }
}

main().catch(error => {
  console.error('Error:', error);
  process.exit(1);
});
