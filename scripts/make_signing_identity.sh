#!/bin/bash
# Creates the "QuickNote Signing" certificate that every build is signed with, once per Mac you build on.
#
# macOS remembers the Accessibility permission by the app's signature. An ad-hoc signature is just a
# hash of that exact build, so every rebuild looked like a new app and lost the permission. Signed
# with the same certificate every time, a rebuild is the same app and keeps it. It's self-signed:
# free, and fine for this; it changes nothing about Gatekeeper.
#
# The only copy of the key outside the keychain is ~/Library/QuickNote Signing/identity.p12, encrypted
# with a password you choose. Keep both safe: anyone with them can sign an app as QuickNote, and every
# Mac that allowed QuickNote would trust it too. Building with a different certificate means turning
# the Accessibility permission back on once.
set -euo pipefail
NAME="QuickNote Signing"
DIR="$HOME/Library/$NAME"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "\"$NAME\" is already in your login keychain."
  exit 0
fi
if [[ -e "$DIR/identity.p12" ]]; then
  echo "$DIR already has a backup: double-click identity.p12 there and enter its password," >&2
  echo "instead of making a new certificate." >&2
  exit 1
fi
[[ -r /dev/tty ]] || { echo "Run this in a terminal: it asks for a password for the backup." >&2; exit 1; }

echo "Choose a password for the backup ($DIR/identity.p12), e.g. in a password manager."
while :; do
  read -rsp "Password (12+ characters): " PASSWORD </dev/tty; echo
  read -rsp "Again: " AGAIN </dev/tty; echo
  if (( ${#PASSWORD} < 12 )); then
    echo "Too short."
  elif [[ "$PASSWORD" != "$AGAIN" ]]; then
    echo "They don't match."
  else
    break
  fi
done

# Everything is made in a temporary folder, so a failed run leaves nothing behind and the unencrypted
# key never outlives the script.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
# macOS's importer only reads the older PKCS#12 encryption. The password is read from the environment,
# so it never shows up in a command line.
P12_PASSWORD="$PASSWORD" openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -passout env:P12_PASSWORD -out "$TMP/identity.p12"
# The keychain gets its own copy under a throwaway password, since `security import` only takes it as an argument.
IMPORT_PASSWORD="$(openssl rand -hex 16)"
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -passout "pass:$IMPORT_PASSWORD" -out "$TMP/import.p12"

# Backup first: if the import below fails, a re-run points at the backup instead of making a new key.
mkdir -p "$DIR" && chmod 700 "$DIR"
mv "$TMP/identity.p12" "$DIR/identity.p12"
chmod 600 "$DIR/identity.p12"
security import "$TMP/import.p12" -k "$KEYCHAIN" -P "$IMPORT_PASSWORD" -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\" in your login keychain (encrypted backup in $DIR/identity.p12)."
