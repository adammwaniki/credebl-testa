#!/usr/bin/env node
/**
 * QR Encode Pipeline for Testa Edu
 *
 * Reads a signed credential JSON from stdin.
 * Outputs JSON to stdout: { jsonxtUri, qrData, qrPngBase64, sizes }
 */
const jsonxt = require('jsonxt');
const { generateQRData } = require('@injistack/pixelpass');
const QRCode = require('qrcode');
const fs = require('fs');
const path = require('path');

const TEMPLATES_PATH = path.join(__dirname, '..', 'templates-data', 'jsonxt-templates.json');

async function main() {
    const input = fs.readFileSync(0, 'utf8');
    const credential = JSON.parse(input);

    const templates = JSON.parse(fs.readFileSync(TEMPLATES_PATH, 'utf8'));

    // Pack credential to JSON-XT URI
    const jsonxtUri = await jsonxt.pack(credential, templates, 'educ', '1', 'local');

    // Wrap with PixelPass for Inji Verify compatibility
    const qrData = generateQRData(jsonxtUri);

    // Generate QR code as PNG (min 10KB for Inji Verify compatibility)
    const qrPngBuffer = await QRCode.toBuffer(qrData, {
        type: 'png',
        width: 1024,
        margin: 4,
        errorCorrectionLevel: 'H'
    });
    const qrPngBase64 = qrPngBuffer.toString('base64');

    const result = {
        jsonxtUri: jsonxtUri,
        qrData: qrData,
        qrPngBase64: qrPngBase64,
        sizes: {
            jsonld: JSON.stringify(credential).length,
            jsonxt: jsonxtUri.length,
            qrData: qrData.length,
            qrPng: qrPngBuffer.length
        }
    };

    process.stdout.write(JSON.stringify(result));
}

main().catch(err => {
    process.stderr.write(err.message || String(err));
    process.exit(1);
});
