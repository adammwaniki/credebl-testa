#!/bin/bash
# issue-employment-credential.sh - Issue an Employment Verifiable Credential using did:polygon
#
# Usage: ./issue-employment-credential.sh [OPTIONS]
#   -p, --port PORT              API port (default: 8004)
#   -k, --api-key KEY            API key for authentication
#   -d, --issuer-did DID         Issuer DID
#   --employee-name NAME         Employee's full name (required)
#   --employee-did DID           Employee's DID (default: generated)
#   --employer-name NAME         Employer/Company name (required)
#   --job-title TITLE            Job title (required)
#   --department DEPT            Department name
#   --date-of-joining DATE       Date of joining (YYYY-MM-DD)
#   --employee-id ID             Employee ID
#   --employment-type TYPE       Employment type (full-time, part-time, contract)
#   -v, --verify                 Verify the credential after issuance
#   -q, --qr                     Generate Inji Verify compatible QR code
#   -o, --output FILE            Save credential to file
#   -h, --help                   Show this help message
#
# Example:
#   ./issue-employment-credential.sh \
#     --employee-name "John Doe" \
#     --employer-name "Acme Corporation" \
#     --job-title "Software Engineer" \
#     --department "Engineering" \
#     --date-of-joining "2024-01-15" \
#     --employee-id "EMP001" \
#     --employment-type "full-time" \
#     -v -q

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
PORT="8004"
API_KEY="${API_KEY:-supersecret-that-too-16chars}"
ISSUER_DID="did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd"
EMPLOYEE_NAME=""
EMPLOYEE_DID=""
EMPLOYER_NAME=""
JOB_TITLE=""
DEPARTMENT=""
DATE_OF_JOINING=""
EMPLOYEE_ID=""
EMPLOYMENT_TYPE=""
VERIFY_CREDENTIAL=false
GENERATE_QR=false
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        -k|--api-key)
            API_KEY="$2"
            shift 2
            ;;
        -d|--issuer-did)
            ISSUER_DID="$2"
            shift 2
            ;;
        --employee-name)
            EMPLOYEE_NAME="$2"
            shift 2
            ;;
        --employee-did)
            EMPLOYEE_DID="$2"
            shift 2
            ;;
        --employer-name)
            EMPLOYER_NAME="$2"
            shift 2
            ;;
        --job-title)
            JOB_TITLE="$2"
            shift 2
            ;;
        --department)
            DEPARTMENT="$2"
            shift 2
            ;;
        --date-of-joining)
            DATE_OF_JOINING="$2"
            shift 2
            ;;
        --employee-id)
            EMPLOYEE_ID="$2"
            shift 2
            ;;
        --employment-type)
            EMPLOYMENT_TYPE="$2"
            shift 2
            ;;
        -v|--verify)
            VERIFY_CREDENTIAL=true
            shift
            ;;
        -q|--qr)
            GENERATE_QR=true
            shift
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            head -30 "$0" | tail -27
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Interactive mode if required fields are missing
if [ -z "$EMPLOYEE_NAME" ]; then
    read -p "Employee Name: " EMPLOYEE_NAME
fi

if [ -z "$EMPLOYER_NAME" ]; then
    read -p "Employer/Company Name: " EMPLOYER_NAME
fi

if [ -z "$JOB_TITLE" ]; then
    read -p "Job Title: " JOB_TITLE
fi

# Optional fields - prompt if not provided
if [ -z "$DEPARTMENT" ]; then
    read -p "Department (press Enter to skip): " DEPARTMENT
fi

if [ -z "$DATE_OF_JOINING" ]; then
    read -p "Date of Joining (YYYY-MM-DD, press Enter for today): " DATE_OF_JOINING
    if [ -z "$DATE_OF_JOINING" ]; then
        DATE_OF_JOINING=$(date +%Y-%m-%d)
    fi
fi

if [ -z "$EMPLOYEE_ID" ]; then
    read -p "Employee ID (press Enter to skip): " EMPLOYEE_ID
fi

if [ -z "$EMPLOYMENT_TYPE" ]; then
    read -p "Employment Type (full-time/part-time/contract, press Enter to skip): " EMPLOYMENT_TYPE
fi

# Generate employee DID if not provided
if [ -z "$EMPLOYEE_DID" ]; then
    EMPLOYEE_DID="did:example:employee:$(echo -n "$EMPLOYEE_NAME" | md5sum | cut -c1-16)"
fi

# Validate required fields
if [ -z "$EMPLOYEE_NAME" ] || [ -z "$EMPLOYER_NAME" ] || [ -z "$JOB_TITLE" ]; then
    echo "ERROR: Employee name, employer name, and job title are required"
    exit 1
fi

echo "==========================================="
echo "  Employment Credential Issuance"
echo "==========================================="
echo ""
echo "Credential Details:"
echo "  Employee Name: $EMPLOYEE_NAME"
echo "  Employee DID: $EMPLOYEE_DID"
echo "  Employer: $EMPLOYER_NAME"
echo "  Job Title: $JOB_TITLE"
[ -n "$DEPARTMENT" ] && echo "  Department: $DEPARTMENT"
[ -n "$DATE_OF_JOINING" ] && echo "  Date of Joining: $DATE_OF_JOINING"
[ -n "$EMPLOYEE_ID" ] && echo "  Employee ID: $EMPLOYEE_ID"
[ -n "$EMPLOYMENT_TYPE" ] && echo "  Employment Type: $EMPLOYMENT_TYPE"
echo ""
echo "Issuer DID: $ISSUER_DID"
echo ""

# Get JWT token
echo "1. Getting JWT token..."
JWT_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/agent/token" \
    -H "Authorization: $API_KEY")

if ! echo "$JWT_RESPONSE" | grep -q "token"; then
    echo "   [FAIL] Failed to get JWT token"
    echo "   Response: $JWT_RESPONSE"
    exit 1
fi

JWT_TOKEN=$(echo "$JWT_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
echo "   [OK] JWT token obtained"

# Build credentialSubject dynamically
ISSUANCE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Start building the credential subject JSON
SUBJECT_JSON="{
        \"id\": \"$EMPLOYEE_DID\",
        \"type\": \"EmploymentCredential\",
        \"employeeName\": \"$EMPLOYEE_NAME\",
        \"employerName\": \"$EMPLOYER_NAME\",
        \"jobTitle\": \"$JOB_TITLE\""

# Add optional fields if provided
[ -n "$DEPARTMENT" ] && SUBJECT_JSON="$SUBJECT_JSON,
        \"department\": \"$DEPARTMENT\""

[ -n "$DATE_OF_JOINING" ] && SUBJECT_JSON="$SUBJECT_JSON,
        \"dateOfJoining\": \"$DATE_OF_JOINING\""

[ -n "$EMPLOYEE_ID" ] && SUBJECT_JSON="$SUBJECT_JSON,
        \"employeeId\": \"$EMPLOYEE_ID\""

[ -n "$EMPLOYMENT_TYPE" ] && SUBJECT_JSON="$SUBJECT_JSON,
        \"employmentType\": \"$EMPLOYMENT_TYPE\""

# Close the subject JSON
SUBJECT_JSON="$SUBJECT_JSON
    }"

# Create the full credential payload
# Include inline JSON-LD context for employment credential terms using schema.org vocabulary
CREDENTIAL_PAYLOAD=$(cat <<EOF
{
    "credential": {
        "@context": [
            "https://www.w3.org/2018/credentials/v1",
            {
                "EmploymentCredential": "https://schema.org/EmployeeRole",
                "employeeName": "https://schema.org/name",
                "employerName": "https://schema.org/legalName",
                "jobTitle": "https://schema.org/jobTitle",
                "department": "https://schema.org/department",
                "dateOfJoining": "https://schema.org/startDate",
                "employeeId": "https://schema.org/identifier",
                "employmentType": "https://schema.org/employmentType"
            }
        ],
        "type": ["VerifiableCredential", "EmploymentCredential"],
        "issuer": "$ISSUER_DID",
        "issuanceDate": "$ISSUANCE_DATE",
        "credentialSubject": $SUBJECT_JSON
    },
    "verificationMethod": "${ISSUER_DID}#key-1",
    "proofType": "EcdsaSecp256k1Signature2019"
}
EOF
)

# Sign the credential
echo ""
echo "2. Signing credential..."
SIGN_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/agent/credential/sign?storeCredential=true&dataTypeToSign=jsonLd" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CREDENTIAL_PAYLOAD")

if ! echo "$SIGN_RESPONSE" | grep -q '"proof"'; then
    echo "   [FAIL] Credential signing failed"
    echo "   Response: $SIGN_RESPONSE"
    exit 1
fi

echo "   [OK] Credential signed successfully!"

# Extract just the credential (not the wrapper)
SIGNED_CREDENTIAL=$(echo "$SIGN_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
# The credential is nested inside the response
if 'credential' in data:
    print(json.dumps(data['credential'], indent=2))
else:
    print(json.dumps(data, indent=2))
" 2>/dev/null || echo "$SIGN_RESPONSE")

# Save credential to file
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="/tmp/employment-credential-$(date +%s).json"
fi
echo "$SIGNED_CREDENTIAL" > "$OUTPUT_FILE"
echo "   Saved to: $OUTPUT_FILE"

# Verify credential if requested
if [ "$VERIFY_CREDENTIAL" = true ]; then
    echo ""
    echo "3. Verifying credential..."

    VERIFY_PAYLOAD="{\"credential\": $SIGNED_CREDENTIAL}"

    VERIFY_RESPONSE=$(curl -s -X POST "http://localhost:$PORT/agent/credential/verify" \
        -H "Authorization: Bearer $JWT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$VERIFY_PAYLOAD")

    if echo "$VERIFY_RESPONSE" | grep -qi '"verified":\s*true\|"isValid":\s*true\|"valid":\s*true'; then
        echo "   [OK] Credential verification PASSED"
    else
        echo "   Verification response:"
        echo "$VERIFY_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$VERIFY_RESPONSE"
    fi
fi

# Generate QR code if requested
if [ "$GENERATE_QR" = true ]; then
    echo ""
    echo "4. Generating JSON-XT URI and Inji Verify compatible QR code..."

    PIXELPASS_DIR="/tmp/pixelpass_env"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Check Node.js version (jsonxt requires Node.js 18-22, not v24+)
    NODE_MAJOR=$(node -v 2>/dev/null | sed 's/v\([0-9]*\).*/\1/')
    if [ -n "$NODE_MAJOR" ] && [ "$NODE_MAJOR" -ge 24 ]; then
        echo "   [WARN] Node.js v$NODE_MAJOR detected. jsonxt may not work with v24+."
        echo "   [WARN] Recommended: Node.js v18-v22 LTS"
    fi

    # Ensure PixelPass and jsonxt are installed
    if [ ! -d "$PIXELPASS_DIR/node_modules/@injistack/pixelpass" ] || [ ! -d "$PIXELPASS_DIR/node_modules/jsonxt" ]; then
        echo "   Installing PixelPass and jsonxt..."
        mkdir -p "$PIXELPASS_DIR"
        (cd "$PIXELPASS_DIR" && npm init -y > /dev/null 2>&1 && npm install @injistack/pixelpass jsonxt --silent 2>/dev/null)
    fi

    # Copy templates to pixelpass directory
    if [ -d "$SCRIPT_DIR/templates" ]; then
        cp -r "$SCRIPT_DIR/templates" "$PIXELPASS_DIR/" 2>/dev/null
    fi

    if [ -d "$PIXELPASS_DIR/node_modules/@injistack/pixelpass" ] && [ -d "$PIXELPASS_DIR/node_modules/jsonxt" ]; then
        QR_DATA_FILE="${OUTPUT_FILE%.json}-qr.txt"
        QR_PNG_FILE="${OUTPUT_FILE%.json}-qr.png"
        JSONXT_FILE="${OUTPUT_FILE%.json}-jsonxt.txt"

        # Generate JSON-XT URI using real Consensas jsonxt library
        (cd "$PIXELPASS_DIR" && node -e "
const jsonxt = require('jsonxt');
const { generateQRData } = require('@injistack/pixelpass');
const fs = require('fs');
const path = require('path');

// Load templates (copied to pixelpass directory)
const templatesPath = path.join(process.cwd(), 'templates', 'jsonxt-templates.json');
const templates = JSON.parse(fs.readFileSync(templatesPath, 'utf8'));

// Load credential
const credential = JSON.parse(fs.readFileSync('$OUTPUT_FILE', 'utf8'));

async function main() {
    try {
        // Pack credential to JSON-XT URI using Consensas format
        const jsonxtUri = await jsonxt.pack(credential, templates, 'empl', '1', 'local');

        // Save JSON-XT URI to file
        fs.writeFileSync('$JSONXT_FILE', jsonxtUri);

        // Generate QR data: wrap JSON-XT URI in PixelPass for Inji compatibility
        const qrData = generateQRData(jsonxtUri);
        fs.writeFileSync('$QR_DATA_FILE', qrData);

        // Calculate sizes
        const jsonldSize = JSON.stringify(credential).length;
        const jsonxtSize = jsonxtUri.length;
        const qrSize = qrData.length;
        const compressionRatio = ((1 - jsonxtSize/jsonldSize) * 100).toFixed(1);

        console.log('JSON-LD size:  ' + jsonldSize + ' bytes');
        console.log('JSON-XT size:  ' + jsonxtSize + ' chars (' + compressionRatio + '% smaller)');
        console.log('QR data size:  ' + qrSize + ' chars');
        console.log('');
        console.log('JSON-XT URI format: jxt:local:empl:1:...');
    } catch (error) {
        console.error('Error: ' + error.message);
        process.exit(1);
    }
}

main();
") 2>&1

        if [ -s "$QR_DATA_FILE" ]; then
            echo ""
            echo "   [OK] Credential encoded to JSON-XT URI (Consensas format)"
            echo "   [OK] QR code generated with PixelPass wrapping"
            echo ""
            echo "   Output files:"
            echo "     JSON-LD:   $OUTPUT_FILE"
            echo "     JSON-XT:   $JSONXT_FILE"
            echo "     QR data:   $QR_DATA_FILE"

            # Generate PNG if qrencode is available
            if command -v qrencode &> /dev/null; then
                qrencode -o "$QR_PNG_FILE" -s 10 -m 2 < "$QR_DATA_FILE"
                echo "     QR image:  $QR_PNG_FILE"

                # Display ASCII QR in terminal
                echo ""
                echo "==========================================="
                echo "  Scan with Inji Verify"
                echo "==========================================="
                echo ""
                qrencode -t ANSIUTF8 < "$QR_DATA_FILE"
            else
                echo "   [WARN] qrencode not installed - install with: sudo apt install qrencode"
            fi

            # Show JSON-XT URI preview
            echo ""
            echo "JSON-XT URI (first 100 chars):"
            head -c 100 "$JSONXT_FILE"
            echo "..."
        else
            echo "   [FAIL] JSON-XT encoding failed"
        fi
    else
        echo "   [FAIL] Could not install required packages"
        echo "   Try manually: cd $PIXELPASS_DIR && npm install @injistack/pixelpass jsonxt"
    fi
fi

echo ""
echo "==========================================="
echo "       Employment Credential Issued!"
echo "==========================================="
echo ""
echo "Signed Credential:"
echo "$SIGNED_CREDENTIAL" | python3 -m json.tool 2>/dev/null || echo "$SIGNED_CREDENTIAL"

# Print file locations summary
echo ""
echo "Files:"
echo "  JSON-LD:    $OUTPUT_FILE"
[ "$GENERATE_QR" = true ] && [ -f "${OUTPUT_FILE%.json}-jsonxt.txt" ] && echo "  JSON-XT:    ${OUTPUT_FILE%.json}-jsonxt.txt"
[ "$GENERATE_QR" = true ] && [ -f "${OUTPUT_FILE%.json}-qr.png" ] && echo "  QR Image:   ${OUTPUT_FILE%.json}-qr.png"
[ "$GENERATE_QR" = true ] && [ -f "${OUTPUT_FILE%.json}-qr.txt" ] && echo "  QR Data:    ${OUTPUT_FILE%.json}-qr.txt"
echo ""
