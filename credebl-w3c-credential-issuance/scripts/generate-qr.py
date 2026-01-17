#!/usr/bin/env python3
"""
CREDEBL QR Code Generator

Generates QR codes for DIDComm Out-of-Band invitations.

Usage:
    python generate-qr.py <invitation_url> [output_file]
    python generate-qr.py --from-api [--base-url URL] [--api-key KEY] [output_file]

Examples:
    # Generate from URL
    python generate-qr.py "https://example.com?oob=..." qr_code.png

    # Generate from API (creates new invitation)
    python generate-qr.py --from-api --base-url http://localhost:8004 --api-key mykey qr_code.png

Requirements:
    pip install qrcode pillow requests
"""

import sys
import os
import json
import argparse
from datetime import datetime

try:
    import qrcode
    from PIL import Image
except ImportError:
    print("Error: Required packages not installed.")
    print("Run: pip install qrcode pillow")
    sys.exit(1)

try:
    import requests
except ImportError:
    requests = None


def create_qr_code(data: str, output_file: str, size: int = 10) -> str:
    """Generate a QR code image from data."""
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=size,
        border=4,
    )
    qr.add_data(data)
    qr.make(fit=True)

    img = qr.make_image(fill_color="black", back_color="white")
    img.save(output_file)

    return output_file


def create_invitation_from_api(base_url: str, api_key: str, label: str = "CREDEBL Issuer") -> dict:
    """Create an OOB invitation via the credo-controller API."""
    if requests is None:
        print("Error: requests package not installed.")
        print("Run: pip install requests")
        sys.exit(1)

    url = f"{base_url}/didcomm/oob/create-invitation"
    headers = {
        "authorization": api_key,
        "Content-Type": "application/json"
    }
    payload = {
        "label": label,
        "goalCode": "issue-vc",
        "goal": "Issue Verifiable Credential",
        "handshake": True,
        "handshakeProtocols": [
            "https://didcomm.org/didexchange/1.x",
            "https://didcomm.org/connections/1.x"
        ],
        "autoAcceptConnection": True
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error creating invitation: {e}")
        sys.exit(1)


def print_terminal_qr(data: str):
    """Print a QR code to the terminal using Unicode blocks."""
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=1,
        border=2,
    )
    qr.add_data(data)
    qr.make(fit=True)

    # Print to terminal
    qr.print_ascii(invert=True)


def main():
    parser = argparse.ArgumentParser(
        description="Generate QR codes for DIDComm OOB invitations",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s "https://example.com?oob=..." qr_code.png
  %(prog)s --from-api --base-url http://localhost:8004 --api-key mykey
  %(prog)s --from-api -b http://localhost:8004 -k mykey -o invitation.png
        """
    )

    parser.add_argument(
        "invitation_url",
        nargs="?",
        help="The invitation URL to encode as QR"
    )
    parser.add_argument(
        "output_file",
        nargs="?",
        default=None,
        help="Output file path (default: qr_<timestamp>.png)"
    )
    parser.add_argument(
        "--from-api",
        action="store_true",
        help="Create invitation from API instead of using provided URL"
    )
    parser.add_argument(
        "-b", "--base-url",
        default="http://localhost:8004",
        help="Agent admin API base URL (default: http://localhost:8004)"
    )
    parser.add_argument(
        "-k", "--api-key",
        default=os.environ.get("CREDEBL_API_KEY", ""),
        help="Agent API key (default: from CREDEBL_API_KEY env var)"
    )
    parser.add_argument(
        "-l", "--label",
        default="CREDEBL Issuer",
        help="Label for the invitation (default: CREDEBL Issuer)"
    )
    parser.add_argument(
        "-o", "--output",
        dest="output_file_flag",
        help="Output file path (alternative to positional argument)"
    )
    parser.add_argument(
        "-s", "--size",
        type=int,
        default=10,
        help="QR code box size (default: 10)"
    )
    parser.add_argument(
        "-t", "--terminal",
        action="store_true",
        help="Also print QR code to terminal"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output invitation details as JSON"
    )

    args = parser.parse_args()

    # Determine output file
    output_file = args.output_file_flag or args.output_file
    if output_file is None:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_file = f"qr_{timestamp}.png"

    # Get invitation URL
    if args.from_api:
        if not args.api_key:
            print("Error: API key required when using --from-api")
            print("Set CREDEBL_API_KEY environment variable or use --api-key")
            sys.exit(1)

        print(f"Creating invitation via API...")
        print(f"  Base URL: {args.base_url}")
        print(f"  Label: {args.label}")
        print()

        invitation_data = create_invitation_from_api(
            args.base_url,
            args.api_key,
            args.label
        )

        invitation_url = invitation_data.get("invitationUrl")

        if args.json:
            print(json.dumps(invitation_data, indent=2))
            print()

        print(f"Invitation created successfully!")
        print(f"  OOB Record ID: {invitation_data.get('outOfBandRecord', {}).get('id', 'N/A')}")
        print()

    elif args.invitation_url:
        invitation_url = args.invitation_url
    else:
        print("Error: Either provide invitation_url or use --from-api")
        parser.print_help()
        sys.exit(1)

    # Generate QR code
    print(f"Generating QR code...")
    create_qr_code(invitation_url, output_file, args.size)
    print(f"  Output: {os.path.abspath(output_file)}")
    print()

    # Print to terminal if requested
    if args.terminal:
        print("Terminal QR Code:")
        print_terminal_qr(invitation_url)
        print()

    # Print invitation URL
    print("Invitation URL:")
    print(invitation_url)
    print()

    # Print online QR generator link
    encoded_url = requests.utils.quote(invitation_url) if requests else invitation_url.replace("&", "%26")
    print("Online QR Generator:")
    print(f"https://api.qrserver.com/v1/create-qr-code/?size=300x300&data={encoded_url}")
    print()

    print("Done! Scan the QR code with your mobile wallet.")


if __name__ == "__main__":
    main()
