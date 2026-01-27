#!/usr/bin/env node
/**
 * JSON-XT Encoder for Verifiable Credentials
 *
 * Encodes JSON-LD credentials to compact JSON-XT URIs using the Consensas jsonxt library.
 *
 * Usage:
 *   node jsonxt-encode.js <credential-file> <type> <version> [resolver]
 *
 * Examples:
 *   node jsonxt-encode.js /tmp/education-credential.json educ 1 local
 *   node jsonxt-encode.js /tmp/employment-credential.json empl 1 local
 *
 * Output:
 *   Prints the JSON-XT URI to stdout (e.g., jxt:local:educ:1:...)
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

async function encodeCredential(credentialPath, type, version, resolverName) {
    // Load credential
    if (!fs.existsSync(credentialPath)) {
        throw new Error(`Credential file not found: ${credentialPath}`);
    }
    const credential = JSON.parse(fs.readFileSync(credentialPath, 'utf8'));

    // Load templates
    const templates = await loadTemplates();

    // Verify template exists
    const templateKey = `${type}:${version}`;
    if (!templates[templateKey]) {
        throw new Error(`Template not found: ${templateKey}. Available: ${Object.keys(templates).join(', ')}`);
    }

    // Pack credential to JSON-XT URI
    const packed = await jsonxt.pack(credential, templates, type, version, resolverName || 'local');

    return packed;
}

// CLI interface
async function main() {
    const args = process.argv.slice(2);

    if (args.length < 3) {
        console.error('Usage: node jsonxt-encode.js <credential-file> <type> <version> [resolver]');
        console.error('');
        console.error('Arguments:');
        console.error('  credential-file  Path to JSON-LD credential file');
        console.error('  type             Template type (educ, empl)');
        console.error('  version          Template version (1)');
        console.error('  resolver         Resolver name for URI (default: local)');
        console.error('');
        console.error('Examples:');
        console.error('  node jsonxt-encode.js /tmp/education-credential.json educ 1');
        console.error('  node jsonxt-encode.js /tmp/employment-credential.json empl 1 local');
        process.exit(1);
    }

    const [credentialPath, type, version, resolver] = args;

    try {
        const packed = await encodeCredential(credentialPath, type, version, resolver);
        console.log(packed);
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
module.exports = { encodeCredential, loadTemplates };
