#!/bin/zsh
# Creates a local self-signed code-signing identity, "GeniusSoft Development",
# in the login keychain. Signing every build with the same certificate lets
# macOS keep noNotch's privacy permissions (Accessibility, Camera, …) across
# rebuilds. Safe to run repeatedly. Remove it any time in Keychain Access.
set -euo pipefail

NAME="GeniusSoft Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "✓ \"$NAME\" already exists"
  security find-identity -p codesigning "$KEYCHAIN" | grep "$NAME" || true
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
O = GeniusSoft
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.conf" 2>/dev/null

PASS=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASS" 2>/dev/null

# -T grants codesign access to the private key without a prompt per build.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -f pkcs12 \
  -T /usr/bin/codesign -T /usr/bin/security

echo "✓ Created \"$NAME\""
security find-certificate -c "$NAME" -Z "$KEYCHAIN" | grep SHA-1
