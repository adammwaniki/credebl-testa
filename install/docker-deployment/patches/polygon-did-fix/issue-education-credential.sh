#!/bin/bash
# issue-education-credential.sh - Issue an Education Verifiable Credential using did:polygon
#
# Usage: ./issue-education-credential.sh [OPTIONS]
#   -p, --port PORT              API port (default: 8004)
#   -k, --api-key KEY            API key for authentication
#   -d, --issuer-did DID         Issuer DID
#   --student-name NAME          Student's full name (required)
#   --student-did DID            Student's DID (default: generated)
#   --institution NAME           Institution/University name (required)
#   --degree DEGREE              Degree/Qualification (required)
#   --field-of-study FIELD       Field of study/Major
#   --enrollment-date DATE       Enrollment date (YYYY-MM-DD)
#   --graduation-date DATE       Graduation date (YYYY-MM-DD)
#   --student-id ID              Student ID
#   --gpa GPA                    Grade Point Average
#   --honors HONORS              Honors (cum laude, magna cum laude, etc.)
#   -v, --verify                 Verify the credential after issuance
#   -q, --qr                     Generate Inji Verify compatible QR code
#   -o, --output FILE            Save credential to file
#   -h, --help                   Show this help message
#
# Example:
#   ./issue-education-credential.sh \
#     --student-name "Alice Johnson" \
#     --institution "State University" \
#     --degree "Bachelor of Science" \
#     --field-of-study "Computer Science" \
#     --enrollment-date "2020-09-01" \
#     --graduation-date "2024-06-15" \
#     --student-id "STU2024001" \
#     --gpa "3.85" \
#     --honors "magna cum laude" \
#     -v -q

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
PORT="8004"
API_KEY="${API_KEY:-supersecret-that-too-16chars}"
ISSUER_DID="did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd"
STUDENT_NAME=""
STUDENT_DID=""
INSTITUTION=""
DEGREE=""
FIELD_OF_STUDY=""
ENROLLMENT_DATE=""
GRADUATION_DATE=""
STUDENT_ID=""
GPA=""
HONORS=""
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
        --student-name)
            STUDENT_NAME="$2"
            shift 2
            ;;
        --student-did)
            STUDENT_DID="$2"
            shift 2
            ;;
        --institution)
            INSTITUTION="$2"
            shift 2
            ;;
        --degree)
            DEGREE="$2"
            shift 2
            ;;
        --field-of-study)
            FIELD_OF_STUDY="$2"
            shift 2
            ;;
        --enrollment-date)
            ENROLLMENT_DATE="$2"
            shift 2
            ;;
        --graduation-date)
            GRADUATION_DATE="$2"
            shift 2
            ;;
        --student-id)
            STUDENT_ID="$2"
            shift 2
            ;;
        --gpa)
            GPA="$2"
            shift 2
            ;;
        --honors)
            HONORS="$2"
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
            head -32 "$0" | tail -29
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Interactive mode if required fields are missing
if [ -z "$STUDENT_NAME" ]; then
    read -p "Student Name: " STUDENT_NAME
fi

if [ -z "$INSTITUTION" ]; then
    read -p "Institution/University Name: " INSTITUTION
fi

if [ -z "$DEGREE" ]; then
    read -p "Degree/Qualification: " DEGREE
fi

# Optional fields - prompt if not provided
if [ -z "$FIELD_OF_STUDY" ]; then
    read -p "Field of Study/Major (press Enter to skip): " FIELD_OF_STUDY
fi

if [ -z "$ENROLLMENT_DATE" ]; then
    read -p "Enrollment Date (YYYY-MM-DD, press Enter to skip): " ENROLLMENT_DATE
fi

if [ -z "$GRADUATION_DATE" ]; then
    read -p "Graduation Date (YYYY-MM-DD, press Enter to skip): " GRADUATION_DATE
fi

if [ -z "$STUDENT_ID" ]; then
    read -p "Student ID (press Enter to skip): " STUDENT_ID
fi

if [ -z "$GPA" ]; then
    read -p "GPA (press Enter to skip): " GPA
fi

if [ -z "$HONORS" ]; then
    read -p "Honors (e.g., cum laude, press Enter to skip): " HONORS
fi

# Generate student DID if not provided
if [ -z "$STUDENT_DID" ]; then
    STUDENT_DID="did:example:student:$(echo -n "$STUDENT_NAME" | md5sum | cut -c1-16)"
fi

# Validate required fields
if [ -z "$STUDENT_NAME" ] || [ -z "$INSTITUTION" ] || [ -z "$DEGREE" ]; then
    echo "ERROR: Student name, institution, and degree are required"
    exit 1
fi

echo "==========================================="
echo "  Education Credential Issuance"
echo "==========================================="
echo ""
echo "Credential Details:"
echo "  Student Name: $STUDENT_NAME"
echo "  Student DID: $STUDENT_DID"
echo "  Institution: $INSTITUTION"
echo "  Degree: $DEGREE"
[ -n "$FIELD_OF_STUDY" ] && echo "  Field of Study: $FIELD_OF_STUDY"
[ -n "$ENROLLMENT_DATE" ] && echo "  Enrollment Date: $ENROLLMENT_DATE"
[ -n "$GRADUATION_DATE" ] && echo "  Graduation Date: $GRADUATION_DATE"
[ -n "$STUDENT_ID" ] && echo "  Student ID: $STUDENT_ID"
[ -n "$GPA" ] && echo "  GPA: $GPA"
[ -n "$HONORS" ] && echo "  Honors: $HONORS"
echo ""
echo "Issuer DID: $ISSUER_DID"
echo ""

# Determine proof type based on DID method
DID_METHOD=$(echo "$ISSUER_DID" | cut -d':' -f2)
if [ "$DID_METHOD" = "polygon" ]; then
    PROOF_TYPE="EcdsaSecp256k1Signature2019"
elif [ "$DID_METHOD" = "indy" ]; then
    PROOF_TYPE="Ed25519Signature2018"
else
    # Default to Ed25519 for did:key, did:web, etc.
    PROOF_TYPE="Ed25519Signature2018"
fi
echo "Proof Type: $PROOF_TYPE (based on $DID_METHOD)"
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
        \"id\": \"$STUDENT_DID\",
        \"type\": \"EducationCredential\",
        \"name\": \"$STUDENT_NAME\",
        \"alumniOf\": \"$INSTITUTION\",
        \"degree\": \"$DEGREE\""

# Add optional fields if provided
[ -n "$FIELD_OF_STUDY" ] && SUBJECT_JSON="$SUBJECT_JSON,
        \"fieldOfStudy\": \"$FIELD_OF_STUDY\""

[ -n "$ENROLLMENT_DATE" ] && SUBJECT_JSON="$SUBJECT_JSON,
        \"enrollmentDate\": \"$ENROLLMENT_DATE\""

[ -n "$GRADUATION_DATE" ] && SUBJECT_JSON="$SUBJECT_JSON,
        \"graduationDate\": \"$GRADUATION_DATE\""

[ -n "$STUDENT_ID" ] && SUBJECT_JSON="$SUBJECT_JSON,
        \"studentId\": \"$STUDENT_ID\""

[ -n "$GPA" ] && SUBJECT_JSON="$SUBJECT_JSON,
        \"gpa\": \"$GPA\""

[ -n "$HONORS" ] && SUBJECT_JSON="$SUBJECT_JSON,
        \"honors\": \"$HONORS\""

# Close the subject JSON
SUBJECT_JSON="$SUBJECT_JSON
    }"

# Create the full credential payload
# Include inline JSON-LD context for education credential terms using schema.org vocabulary
CREDENTIAL_PAYLOAD=$(cat <<EOF
{
    "credential": {
        "@context": [
            "https://www.w3.org/2018/credentials/v1",
            {
                "EducationCredential": "https://schema.org/EducationalOccupationalCredential",
                "name": "https://schema.org/name",
                "alumniOf": "https://schema.org/alumniOf",
                "degree": "https://schema.org/educationalCredentialAwarded",
                "fieldOfStudy": "https://schema.org/programName",
                "enrollmentDate": "https://schema.org/startDate",
                "graduationDate": "https://schema.org/endDate",
                "studentId": "https://schema.org/identifier",
                "gpa": "https://schema.org/ratingValue",
                "honors": "https://schema.org/honorificSuffix"
            }
        ],
        "type": ["VerifiableCredential", "EducationCredential"],
        "issuer": "$ISSUER_DID",
        "issuanceDate": "$ISSUANCE_DATE",
        "credentialSubject": $SUBJECT_JSON
    },
    "verificationMethod": "${ISSUER_DID}#key-1",
    "proofType": "$PROOF_TYPE"
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
    OUTPUT_FILE="/tmp/education-credential-$(date +%s).json"
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
        const jsonxtUri = await jsonxt.pack(credential, templates, 'educ', '1', 'local');

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
        console.log('JSON-XT URI format: jxt:local:educ:1:...');
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
echo "       Education Credential Issued!"
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
