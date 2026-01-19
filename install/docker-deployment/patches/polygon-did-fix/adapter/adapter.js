#!/usr/bin/env node
/**
 * CREDEBL-to-Inji Verify Adapter
 *
 * Bridges Inji Verify verification requests to CREDEBL agent.
 * This allows Inji Verify to verify did:polygon credentials via CREDEBL.
 */

const http = require('http');

// Configuration
const ADAPTER_PORT = process.env.ADAPTER_PORT || 8081;
const CREDEBL_AGENT_URL = process.env.CREDEBL_AGENT_URL || 'http://localhost:8004';
const CREDEBL_API_KEY = process.env.CREDEBL_API_KEY || 'supersecret-that-too-16chars';

// Helper to make HTTP requests
function httpRequest(options, postData) {
    return new Promise((resolve, reject) => {
        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, data: JSON.parse(data) });
                } catch (e) {
                    resolve({ status: res.statusCode, data: data });
                }
            });
        });
        req.on('error', reject);
        if (postData) req.write(postData);
        req.end();
    });
}

// Get JWT token from CREDEBL agent
async function getJwtToken() {
    const url = new URL(CREDEBL_AGENT_URL);
    const options = {
        hostname: url.hostname,
        port: url.port || 80,
        path: '/agent/token',
        method: 'POST',
        headers: { 'Authorization': CREDEBL_API_KEY }
    };

    const response = await httpRequest(options);
    if (response.data && response.data.token) {
        return response.data.token;
    }
    throw new Error('Failed to get JWT token: ' + JSON.stringify(response.data));
}

// Verify credential via CREDEBL agent
async function verifyCredential(credential) {
    const token = await getJwtToken();
    const url = new URL(CREDEBL_AGENT_URL);

    const postData = JSON.stringify({ credential: credential });
    const options = {
        hostname: url.hostname,
        port: url.port || 80,
        path: '/agent/credential/verify',
        method: 'POST',
        headers: {
            'Authorization': 'Bearer ' + token,
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(postData)
        }
    };

    const response = await httpRequest(options, postData);
    return response.data;
}

// Map CREDEBL response to Inji Verify format
function mapToInjiFormat(credeblResponse) {
    if (credeblResponse && credeblResponse.isValid === true) {
        return { verificationStatus: 'SUCCESS' };
    }
    return { verificationStatus: 'INVALID' };
}

// Map CREDEBL response to Inji Verify v2 format
function mapToInjiV2Format(credeblResponse) {
    const isValid = credeblResponse && credeblResponse.isValid === true;

    return {
        allChecksSuccessful: isValid,
        schemaAndSignatureCheck: {
            valid: isValid,
            error: isValid ? null : {
                errorCode: 'VERIFICATION_FAILED',
                errorMessage: 'Credential verification failed'
            }
        },
        expiryCheck: { valid: true },
        statusCheck: [],
        metadata: {}
    };
}

// HTTP Server
const server = http.createServer(async (req, res) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }

    if (req.method === 'GET' && (req.url === '/health' || req.url === '/')) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'ok', service: 'credebl-inji-adapter' }));
        return;
    }

    if (req.method === 'POST' && req.url === '/v1/verify/vc-verification') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', async () => {
            try {
                const request = JSON.parse(body);
                console.log('[ADAPTER] Received v1 verification request');

                // Support multiple input formats: verifiableCredentials array, credential object, or direct VC
                let credential;
                if (request.verifiableCredentials && request.verifiableCredentials.length > 0) {
                    credential = request.verifiableCredentials[0];
                } else if (request.credential) {
                    credential = request.credential;
                } else if (request['@context']) {
                    // Direct VC in body
                    credential = request;
                } else {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ verificationStatus: 'INVALID', error: 'No credentials found in request' }));
                    return;
                }

                console.log('[ADAPTER] Verifying credential with issuer:', credential.issuer);

                const credeblResult = await verifyCredential(credential);
                console.log('[ADAPTER] CREDEBL result: isValid =', credeblResult.isValid);

                const injiResult = mapToInjiFormat(credeblResult);
                console.log('[ADAPTER] Returning:', JSON.stringify(injiResult));

                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify(injiResult));
            } catch (error) {
                console.error('[ADAPTER] Error:', error.message);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ verificationStatus: 'INVALID', error: error.message }));
            }
        });
        return;
    }

    if (req.method === 'POST' && req.url === '/v1/verify/vc-verification/v2') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', async () => {
            try {
                const request = JSON.parse(body);
                console.log('[ADAPTER] Received v2 verification request');

                const credential = request.verifiableCredential;
                if (!credential) {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ allChecksSuccessful: false }));
                    return;
                }

                const credObj = typeof credential === 'string' ? JSON.parse(credential) : credential;
                console.log('[ADAPTER] Verifying credential with issuer:', credObj.issuer);

                const credeblResult = await verifyCredential(credObj);
                console.log('[ADAPTER] CREDEBL result: isValid =', credeblResult.isValid);

                const injiResult = mapToInjiV2Format(credeblResult);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify(injiResult));
            } catch (error) {
                console.error('[ADAPTER] Error:', error.message);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ allChecksSuccessful: false, error: error.message }));
            }
        });
        return;
    }

    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(ADAPTER_PORT, '0.0.0.0', () => {
    console.log('===========================================');
    console.log('  CREDEBL-to-Inji Verify Adapter');
    console.log('===========================================');
    console.log('Adapter listening on port:', ADAPTER_PORT);
    console.log('CREDEBL Agent URL:', CREDEBL_AGENT_URL);
    console.log('Endpoints:');
    console.log('  POST /v1/verify/vc-verification');
    console.log('  POST /v1/verify/vc-verification/v2');
    console.log('  GET  /health');
});
