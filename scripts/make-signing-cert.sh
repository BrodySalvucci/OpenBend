#!/bin/zsh
# Creates a self-signed code-signing certificate named "OpenBend Dev" in your login keychain.
# scripts/build.sh signs with it automatically when present, which keeps the code signature
# stable across rebuilds so macOS keeps the Screen Recording grant.
set -euo pipefail
NAME="OpenBend Dev"
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "'$NAME' already exists"; exit 0
fi
TMP=$(mktemp -d)
cat > "$TMP/ext.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/ext.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" -passout pass:openbend -legacy 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" -passout pass:openbend
security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P openbend -T /usr/bin/codesign -T /usr/bin/security
# Trust the cert for code signing (asks for your password once).
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$TMP/cert.pem"
rm -rf "$TMP"
echo "Created '$NAME'. Rebuild with: make"
