#!/usr/bin/env node
/**
 * JSON-XT Decoder for Verifiable Credentials
 *
 * Decodes JSON-XT URIs back to full JSON-LD credentials using local templates.
 *
 * Usage:
 *   node jsonxt-decode.js <jsonxt-uri>
 *   echo "jxt:local:educ:1:..." | node jsonxt-decode.js -
 *
 * Examples:
 *   node jsonxt-decode.js "jxt:local:educ:1:did%3Apolygon%3A0x123/..."
 *   node jsonxt-decode.js /tmp/credential.jxt  # Read URI from file
 *
 * Output:
 *   Prints the decoded JSON-LD credential to stdout
 */

const jsonxt = require('jsonxt');
const fs = require('fs');
const path = require('path');

// Load templates from local file
const TEMPLATES_PATH = path.join(__dirname, 'templates', 'jsonxt-templates.json');

async function loadTemplates() {
    if (!fs.existsSync(TEMPLATES_PATH)) {
        throw new Error(`Templates file not found: ${TEMPLATES_PATH}`);
    }
    return JSON.parse(fs.readFileSync(TEMPLATES_PATH, 'utf8'));
}

/**
 * Custom resolver that uses local templates
 * @param {string} resolverName - The resolver name from the URI (e.g., "local")
 * @returns {object} Templates object
 */
async function localResolver(resolverName) {
    // For local resolver, return templates from file
    // In production, this could fetch from .well-known URLs
    return await loadTemplates();
}

async function decodeCredential(packedUri) {
    // Handle input from stdin or file
    let uri = packedUri;

    // If it's a file path, read the URI from file
    if (fs.existsSync(packedUri)) {
        uri = fs.readFileSync(packedUri, 'utf8').trim();
    }

    // Validate it's a JSON-XT URI
    if (!uri.startsWith('jxt:')) {
        throw new Error(`Invalid JSON-XT URI. Must start with "jxt:". Got: ${uri.substring(0, 50)}...`);
    }

    // Unpack using local resolver
    const credential = await jsonxt.unpack(uri, localResolver);

    return credential;
}

// CLI interface
async function main() {
    const args = process.argv.slice(2);

    if (args.length < 1) {
        console.error('Usage: node jsonxt-decode.js <jsonxt-uri|file|-');
        console.error('');
        console.error('Arguments:');
        console.error('  jsonxt-uri  JSON-XT URI string (jxt:resolver:type:version:data)');
        console.error('  file        Path to file containing JSON-XT URI');
        console.error('  -           Read URI from stdin');
        console.error('');
        console.error('Examples:');
        console.error('  node jsonxt-decode.js "jxt:local:educ:1:..."');
        console.error('  node jsonxt-decode.js /tmp/credential.jxt');
        console.error('  echo "jxt:local:educ:1:..." | node jsonxt-decode.js -');
        process.exit(1);
    }

    let input = args[0];

    try {
        // Handle stdin input
        if (input === '-') {
            input = fs.readFileSync(0, 'utf8').trim();
        }

        const credential = await decodeCredential(input);
        console.log(JSON.stringify(credential, null, 2));
    } catch (error) {
        console.error(`Error: ${error.message}`);
        process.exit(1);
    }
}

// Run if called directly
if (require.main === module) {
    main();
}

// Export for programmatic use
module.exports = { decodeCredential, loadTemplates, localResolver };
