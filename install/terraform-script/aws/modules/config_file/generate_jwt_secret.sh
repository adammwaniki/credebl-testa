#!/bin/bash
set -e  # Exit on error
set -x  # Print commands (for debugging)

SECRET=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
echo "{\"jwt_token_secret\": \"$SECRET\"}"
