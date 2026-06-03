#!/bin/bash

# LPD-92581 - Proof of concept validating the `op` CLI flow for encrypted workspace sharing.
# Tests: create password in 1Password, fetch it, encrypt a zip with AES-256, generate a share link.
# See parent epic: LPD-90511

set -euo pipefail

C_GREEN="\033[0;32m"
C_RED="\033[0;31m"
C_BLUE="\033[0;34m"
C_YELLOW="\033[1;33m"
C_NC="\033[0m"

_pass() { echo -e "${C_GREEN}[PASS]${C_NC} $1"; }
_fail() { echo -e "${C_RED}[FAIL]${C_NC} $1"; exit 1; }
_step() { echo -e "\n${C_BLUE}>>>${C_NC} $1"; }

VAULT="Private"
ITEM_TITLE="lec-share-poc-$$"
DUMMY_ZIP="/tmp/poc-workspace-$$.zip"
ENCRYPTED_OUT="/tmp/poc-workspace-$$.zip.enc"

cleanup() {
	rm -f "${DUMMY_ZIP}" "${ENCRYPTED_OUT}"

	if [[ -n "${ITEM_UUID:-}" ]]; then
		echo -e "\n${C_BLUE}>>>${C_NC} Cleaning up 1Password item..."
		op item delete "${ITEM_UUID}" --vault="${VAULT}" 2>/dev/null && echo "Deleted item ${ITEM_UUID}"
	fi
}
trap cleanup EXIT

# --- 1. Check op is available ---
_step "Checking op is available"
if ! command -v op &>/dev/null; then
	_fail "'op' not found in PATH. Install from: https://developer.1password.com/docs/cli/get-started/"
fi
_pass "op found: $(op --version)"

# --- 2. Authenticate ---
_step "Checking op is authenticated"
if ! op account list &>/dev/null; then
	_fail "No op accounts configured. Enable CLI integration in 1Password: Settings > Developer > Integrate with 1Password CLI"
fi
op signin
if ! op vault list &>/dev/null; then
	_fail "op session could not be established"
fi
account_email=$(op account list 2>/dev/null | awk 'NR==2{print $2}') || true
_pass "Signed in (account: ${account_email:-unknown})"

# --- 3. Create password item in 1Password ---
_step "Creating password item in 1Password (vault: ${VAULT})"
item_json=$(op item create \
	--category=password \
	--title="${ITEM_TITLE}" \
	--generate-password='letters,digits,symbols,32' \
	--vault="${VAULT}" \
	--format=json) || _fail "op item create failed"

if command -v jq &>/dev/null; then
	ITEM_UUID=$(echo "${item_json}" | jq -r '.id')
else
	ITEM_UUID=$(echo "${item_json}" | grep -oP '"id"\s*:\s*"\K[^"]+' | head -1)
fi
[[ -n "${ITEM_UUID}" ]] || _fail "Failed to parse item UUID from response: ${item_json}"
_pass "Created item: ${ITEM_TITLE} (${ITEM_UUID})"

# --- 4. Fetch password ---
_step "Fetching password from 1Password"
password=$(op read "op://Private/${ITEM_UUID}/password")
[[ -n "${password}" ]] || _fail "Password is empty"
_pass "Password fetched (length: ${#password})"

# --- 5. Create a dummy zip ---
_step "Creating dummy workspace zip"
DUMMY_DIR=$(mktemp -d)
echo "customer-db-export-poc" > "${DUMMY_DIR}/README.txt"
echo "db.host=postgres" > "${DUMMY_DIR}/gradle.properties"
zip -j "${DUMMY_ZIP}" "${DUMMY_DIR}"/*
rm -rf "${DUMMY_DIR}"
_pass "Created: ${DUMMY_ZIP}"

# --- 6. Encrypt with AES-256 (password via stdin — never appears in process args) ---
_step "Encrypting zip with AES-256 (openssl)"
printf '%s' "${password}" | openssl enc -aes-256-cbc -pbkdf2 -in "${DUMMY_ZIP}" -out "${ENCRYPTED_OUT}" -pass stdin
unset password
_pass "Encrypted: ${ENCRYPTED_OUT} ($(wc -c < "${ENCRYPTED_OUT}") bytes)"

# --- 7. Generate shareable link (7-day expiry) ---
# Note: --expires-in and --view-once are mutually exclusive in op item share.
# 7-day expiry is used so recipients can decrypt the archive multiple times
# (e.g. re-importing a database for environment reproduction).
_step "Generating shareable 1Password link (expires 7d)"
share_link=$(op item share "${ITEM_UUID}" --vault="${VAULT}" --expires-in 7d)
[[ -n "${share_link}" ]] || _fail "Share link is empty"
_pass "Share link: ${share_link}"

echo ""
echo -e "${C_YELLOW}==========================================${C_NC}"
echo -e "${C_YELLOW}  TO VALIDATE DECRYPTION${C_NC}"
echo -e "${C_YELLOW}==========================================${C_NC}"
echo -e "1. Open the share link to retrieve the password:\n   ${share_link}"
echo ""
echo -e "2. Decrypt (run in a real terminal — requires TTY for password prompt):"
echo -e "   openssl enc -d -aes-256-cbc -pbkdf2 -in ${ENCRYPTED_OUT} -out /tmp/poc-decrypted.zip"
echo ""
echo -e "3. Verify contents:\n   unzip -l /tmp/poc-decrypted.zip"
echo -e "${C_YELLOW}==========================================${C_NC}"
echo ""
echo -e "${C_BLUE}Note:${C_NC} The 1Password item and encrypted file are preserved until you exit this script."
echo -e "      Press Enter to clean up when done validating."
read -r

echo -e "\n${C_GREEN}Flow validated successfully.${C_NC}"
