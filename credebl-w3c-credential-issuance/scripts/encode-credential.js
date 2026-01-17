#!/usr/bin/env node
/**
 * encode-credential.js
 *
 * Encodes a W3C Verifiable Credential using PixelPass for Inji Verify compatibility.
 *
 * Usage:
 *   node encode-credential.js <credential.json> [output.txt]
 *   cat credential.json | node encode-credential.js > qrdata.txt
 *
 * The output is a PixelPass-encoded string that can be used to generate
 * a QR code compatible with Inji Verify.
 */

const { generateQRData, decode } = require('@injistack/pixelpass');
const fs = require('fs');

function printUsage() {
  console.error(`
Usage:
  node encode-credential.js <credential.json> [output.txt]
  cat credential.json | node encode-credential.js > qrdata.txt

Options:
  --verify    Verify the encoding by decoding it back
  --help      Show this help message

Examples:
  # Encode a credential file
  node encode-credential.js credential.json qrdata.txt

  # Encode from stdin
  cat credential.json | node encode-credential.js

  # Encode and verify
  node encode-credential.js credential.json --verify
`);
  process.exit(1);
}

async function main() {
  const args = process.argv.slice(2);
  let inputFile = null;
  let outputFile = null;
  let verify = false;

  // Parse arguments
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--help' || args[i] === '-h') {
      printUsage();
    } else if (args[i] === '--verify') {
      verify = true;
    } else if (!inputFile) {
      inputFile = args[i];
    } else if (!outputFile) {
      outputFile = args[i];
    }
  }

  let credentialJson;

  // Read credential from file or stdin
  if (inputFile) {
    if (!fs.existsSync(inputFile)) {
      console.error(`Error: File not found: ${inputFile}`);
      process.exit(1);
    }
    credentialJson = fs.readFileSync(inputFile, 'utf8');
  } else if (!process.stdin.isTTY) {
    // Read from stdin
    credentialJson = fs.readFileSync(0, 'utf8');
  } else {
    console.error('Error: No input provided');
    printUsage();
  }

  // Parse and validate credential
  let credential;
  try {
    credential = JSON.parse(credentialJson);
  } catch (e) {
    console.error(`Error: Invalid JSON: ${e.message}`);
    process.exit(1);
  }

  // Validate it looks like a credential
  if (!credential['@context'] || !credential.type) {
    console.error('Error: Input does not appear to be a valid Verifiable Credential');
    console.error('  Missing @context or type field');
    process.exit(1);
  }

  // Encode with PixelPass
  const encoded = generateQRData(JSON.stringify(credential));

  // Verify if requested
  if (verify) {
    console.error('Verifying encoding...');
    try {
      const decoded = decode(encoded);
      const decodedCredential = JSON.parse(decoded);

      if (JSON.stringify(credential) === JSON.stringify(decodedCredential)) {
        console.error('Verification: SUCCESS - Credential can be decoded correctly');
      } else {
        console.error('Verification: WARNING - Decoded credential differs from original');
      }
    } catch (e) {
      console.error(`Verification: FAILED - ${e.message}`);
      process.exit(1);
    }
  }

  // Output
  if (outputFile) {
    fs.writeFileSync(outputFile, encoded);
    console.error(`Encoded credential saved to: ${outputFile}`);
    console.error(`Encoded length: ${encoded.length} characters`);
  } else {
    process.stdout.write(encoded);
  }
}

main().catch(e => {
  console.error(`Error: ${e.message}`);
  process.exit(1);
});
