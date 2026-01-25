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
    echo "4. Generating JSON-XT and Inji Verify compatible QR code..."

    PIXELPASS_DIR="/tmp/pixelpass_env"

    # Ensure PixelPass is installed
    if [ ! -d "$PIXELPASS_DIR/node_modules/@injistack/pixelpass" ]; then
        echo "   Installing PixelPass..."
        mkdir -p "$PIXELPASS_DIR"
        (cd "$PIXELPASS_DIR" && npm init -y > /dev/null 2>&1 && npm install @injistack/pixelpass --silent 2>/dev/null)
    fi

    if [ -d "$PIXELPASS_DIR/node_modules/@injistack/pixelpass" ]; then
        QR_DATA_FILE="${OUTPUT_FILE%.json}-qr.txt"
        QR_PNG_FILE="${OUTPUT_FILE%.json}-qr.png"
        JSONXT_FILE="${OUTPUT_FILE%.json}-jsonxt.json"
        MAPPER_FILE="${OUTPUT_FILE%.json}-mapper.json"

        # Encode with PixelPass and generate JSON-XT
        (cd "$PIXELPASS_DIR" && node -e "
const { generateQRData } = require('@injistack/pixelpass');
const fs = require('fs');

const credential = JSON.parse(fs.readFileSync('$OUTPUT_FILE', 'utf8'));

// JSON-XT Key Mapper for Education Credentials
// Maps long keys to short keys for compact representation
const educationCredentialMapper = {
    // W3C VC standard fields
    '@context': 'x',
    'type': 't',
    'id': 'i',
    'issuer': 'is',
    'issuanceDate': 'idt',
    'expirationDate': 'edt',
    'credentialSubject': 'cs',
    'proof': 'p',

    // Proof fields
    'verificationMethod': 'vm',
    'proofPurpose': 'pp',
    'proofValue': 'pv',
    'created': 'cr',
    'jws': 'jw',

    // Education credential fields
    'EducationCredential': 'EC',
    'VerifiableCredential': 'VC',
    'name': 'n',
    'alumniOf': 'ao',
    'degree': 'd',
    'fieldOfStudy': 'fs',
    'enrollmentDate': 'ed',
    'graduationDate': 'gd',
    'studentId': 'si',
    'gpa': 'g',
    'honors': 'h',

    // Schema.org URLs (map to short tokens)
    'https://www.w3.org/2018/credentials/v1': 'w3c',
    'https://schema.org/EducationalOccupationalCredential': 's:eoc',
    'https://schema.org/name': 's:n',
    'https://schema.org/alumniOf': 's:ao',
    'https://schema.org/educationalCredentialAwarded': 's:eca',
    'https://schema.org/programName': 's:pn',
    'https://schema.org/startDate': 's:sd',
    'https://schema.org/endDate': 's:ed',
    'https://schema.org/identifier': 's:id',
    'https://schema.org/ratingValue': 's:rv',
    'https://schema.org/honorificSuffix': 's:hs',

    // Signature types
    'EcdsaSecp256k1Signature2019': 'ES256K',
    'Ed25519Signature2018': 'EdDSA18',
    'Ed25519Signature2020': 'EdDSA20',
    'assertionMethod': 'am'
};

// Create reverse mapper for decoding
const reverseMapper = {};
for (const [key, value] of Object.entries(educationCredentialMapper)) {
    reverseMapper[value] = key;
}

// Function to recursively apply mapping to an object
function applyMapping(obj, mapper) {
    if (Array.isArray(obj)) {
        return obj.map(item => applyMapping(item, mapper));
    } else if (obj !== null && typeof obj === 'object') {
        const mapped = {};
        for (const [key, value] of Object.entries(obj)) {
            const mappedKey = mapper[key] || key;
            mapped[mappedKey] = applyMapping(value, mapper);
        }
        return mapped;
    } else if (typeof obj === 'string') {
        return mapper[obj] || obj;
    }
    return obj;
}

// Apply mapping to create JSON-XT version
const jsonxt = applyMapping(credential, educationCredentialMapper);

// Save JSON-XT credential
fs.writeFileSync('$JSONXT_FILE', JSON.stringify(jsonxt, null, 2));

// Save mapper for reference (needed for decoding)
fs.writeFileSync('$MAPPER_FILE', JSON.stringify({
    mapper: educationCredentialMapper,
    reverseMapper: reverseMapper,
    description: 'JSON-XT key mapper for Education Credentials'
}, null, 2));

// Generate QR data from original JSON-LD (for Inji compatibility)
const qrData = generateQRData(JSON.stringify(credential));
fs.writeFileSync('$QR_DATA_FILE', qrData);

// Calculate sizes
const jsonldSize = JSON.stringify(credential).length;
const jsonxtSize = JSON.stringify(jsonxt).length;
const qrSize = qrData.length;

console.log('JSON-LD size: ' + jsonldSize + ' bytes');
console.log('JSON-XT size: ' + jsonxtSize + ' bytes (' + ((1 - jsonxtSize/jsonldSize) * 100).toFixed(1) + '% smaller)');
console.log('QR data size: ' + qrSize + ' chars');
") 2>&1

        if [ -s "$QR_DATA_FILE" ]; then
            echo ""
            echo "   [OK] Credential encoded with PixelPass"
            echo "   [OK] JSON-XT version created"
            echo ""
            echo "   Output files:"
            echo "     JSON-LD:  $OUTPUT_FILE"
            echo "     JSON-XT:  $JSONXT_FILE"
            echo "     Mapper:   $MAPPER_FILE"
            echo "     QR data:  $QR_DATA_FILE"

            # Generate PNG if qrencode is available
            if command -v qrencode &> /dev/null; then
                qrencode -o "$QR_PNG_FILE" -s 10 -m 2 < "$QR_DATA_FILE"
                echo "     QR image: $QR_PNG_FILE"

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
        else
            echo "   [FAIL] PixelPass encoding failed"
        fi
    else
        echo "   [FAIL] Could not install PixelPass"
        echo "   Try manually: cd $PIXELPASS_DIR && npm install @injistack/pixelpass"
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
[ "$GENERATE_QR" = true ] && [ -f "${OUTPUT_FILE%.json}-jsonxt.json" ] && echo "  JSON-XT:    ${OUTPUT_FILE%.json}-jsonxt.json"
[ "$GENERATE_QR" = true ] && [ -f "${OUTPUT_FILE%.json}-mapper.json" ] && echo "  Mapper:     ${OUTPUT_FILE%.json}-mapper.json"
[ "$GENERATE_QR" = true ] && [ -f "${OUTPUT_FILE%.json}-qr.png" ] && echo "  QR Image:   ${OUTPUT_FILE%.json}-qr.png"
[ "$GENERATE_QR" = true ] && [ -f "${OUTPUT_FILE%.json}-qr.txt" ] && echo "  QR Data:    ${OUTPUT_FILE%.json}-qr.txt"
echo ""
