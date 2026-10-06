#!/bin/bash
# Creates the "QuickNote Signing" certificate that every build is signed with, once per Mac you build on.
#
# macOS remembers the Accessibility permission by the app's signature. An ad-hoc signature is just a
# hash of that exact build, so every rebuild looked like a new app and lost the permission. Signed
# with the same certificate every time, a rebuild is the same app and keeps it. It's self-signed:
# free, and fine for this; it changes nothing about Gatekeeper.
#
# Keep the files this writes to ~/Library/QuickNote Signing safe. Building with a different
# certificate means turning the Accessibility permission back on once.
set -euo pipefail
NAME="QuickNote Signing"
DIR="$HOME/Library/$NAME"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "\"$NAME\" is already in your login keychain."
  exit 0
fi
[[ -e "$DIR/key.pem" ]] && { echo "$DIR already has a key: import $DIR/identity.p12 (password quicknote) instead of making a new one." >&2; exit 1; }

mkdir -p "$DIR" && chmod 700 "$DIR"
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem" 2>/dev/null
chmod 600 "$DIR/key.pem"
# macOS's importer only reads the older PKCS#12 encryption; the password just protects it in transit.
openssl pkcs12 -export -legacy -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -name "$NAME" \
  -passout pass:quicknote -out "$DIR/identity.p12"
chmod 600 "$DIR/identity.p12"
security import "$DIR/identity.p12" -k "$KEYCHAIN" -P quicknote -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\" in your login keychain (backup in $DIR)."
