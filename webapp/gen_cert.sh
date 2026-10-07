#!/usr/bin/env bash
# ------------------------------------------------------------------
# gen_cert.sh - create the local self-signed certificate HIX serves
#               HTTPS with (hix.json -> server.ssl = true).
#
# Adhoc tool, lives inside the project folder (webapp/srs/01-requirements/DEV-compliance.md).
# openssl is used only to create the key pair; the app itself is HIX +
# Harbour and links OpenSSL through Harbour's hbnetssl (app.hbp).
#
# certs/ is gitignored: a private key must never enter the repository
# (hix/site-docs/en/hixstyle/seguridad/ssl.md, "No committed keys").
#
# This is a DEV certificate.  In production use Let's Encrypt:
#   certbot certonly --standalone -d app.example.com
# and point cert_private/cert_public at privkey.pem / fullchain.pem.
# ------------------------------------------------------------------
set -euo pipefail

DAYS=${1:-365}
DIR="$(cd "$(dirname "$0")" && pwd)/certs"

mkdir -p "$DIR"

# Only overwrite when there is no certificate or it is close to expiring.
if [ -f "$DIR/hix.crt" ] && \
   openssl x509 -checkend 86400 -noout -in "$DIR/hix.crt" >/dev/null 2>&1; then
   echo "certs/hix.crt still valid for more than a day - nothing to do."
   openssl x509 -noout -subject -enddate -in "$DIR/hix.crt"
   exit 0
fi

openssl req -x509 -newkey rsa:2048 -nodes -days "$DAYS" \
   -keyout "$DIR/hix.key" -out "$DIR/hix.crt" \
   -subj "/CN=localhost" \
   -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"

chmod 600 "$DIR/hix.key"
chmod 644 "$DIR/hix.crt"

echo "created:"
openssl x509 -noout -subject -enddate -in "$DIR/hix.crt"
echo "  $DIR/hix.key  (cert_private)"
echo "  $DIR/hix.crt  (cert_public)"
