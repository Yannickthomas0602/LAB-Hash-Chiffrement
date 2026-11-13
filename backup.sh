
#!/bin/bash

###############################################################################
# TRANSFERT : SSH / SCP
# STOCKAGE : /srv/wordpress-backups
###############################################################################

set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ======================== CONFIGURATION ====================================

SOURCE="/var/www"

WORKDIR="/opt/wordpress-backup"

LOGDIR="/var/log/wordpress-backup"

RECIPIENT_FILE="$WORKDIR/age-recipient.txt"

VM2_USER="backupadmin"
VM2_IP="10.1.60.10"

SSH_KEY="/root/.ssh/id_ed25519"

REMOTE_DIR="/srv/wordpress-backups"

VERIFY_SCRIPT="/srv/wordpress-backups/verify_restore.sh"

# ======================== IDENTIFIANT ======================================

TIMESTAMP=$(date -u +"%Y%m%d_%H%M%S")

BACKUP_ID="wordpress_$TIMESTAMP"

TMPDIR="$WORKDIR/$BACKUP_ID"

SOURCE_TAR="$TMPDIR/source.tar"

ARCHIVE="$TMPDIR/$BACKUP_ID.tar.gz.enc"

JSON_FILE="$TMPDIR/$BACKUP_ID.json"

AES_KEY="$TMPDIR/aes.key"

ENCRYPTED_KEY="$TMPDIR/aes.key.age"

LOGFILE="$LOGDIR/backup.log"

mkdir -p "$TMPDIR" "$LOGDIR"

exec >> "$LOGFILE" 2>&1

# ======================== VERROU ===========================================

exec 9>/run/lock/wordpress-backup.lock

if ! flock -n 9; then
    echo "[ERREUR] Sauvegarde déjà en cours."
    exit 1
fi

# ======================== NETTOYAGE ========================================

cleanup() {
    rm -rf "$TMPDIR"
}

trap cleanup EXIT

echo "=============================================="
echo "DEBUT SAUVEGARDE : $(date -u)"
echo "IDENTIFIANT : $BACKUP_ID"
echo "=============================================="

# ======================== ETAPE 1 ==========================================

echo "[1/5] CALCUL DU HASH INITIAL"

if [[ ! -d "$SOURCE" ]]; then
    echo "[ERREUR] Source inexistante."
    exit 1
fi

# Création d'une archive TAR déterministe.
# Elle sert de référence pour les deux calculs SHA-256.

tar \
    --sort=name \
    --mtime='@0' \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --format=gnu \
    -cf "$SOURCE_TAR" \
    -C /var www

HASH_INITIAL=$(sha256sum "$SOURCE_TAR" | awk '{print $1}')

echo "[OK] HASH INITIAL : $HASH_INITIAL"

# ======================== ETAPE 2 ==========================================

echo "[2/5] GENERATION CLE AES-256"

openssl rand -hex 32 > "$AES_KEY"

chmod 600 "$AES_KEY"

echo "[OK] Clé AES générée."

# Compression puis chiffrement AES-256-CBC.

gzip -c "$SOURCE_TAR" | \
openssl enc \
    -aes-256-cbc \
    -salt \
    -pbkdf2 \
    -iter 600000 \
    -pass file:"$AES_KEY" \
    -out "$ARCHIVE"

echo "[OK] Archive chiffrée."

# Chiffrement de la clé AES avec la clé publique de VM2.

if [[ ! -s "$RECIPIENT_FILE" ]]; then
    echo "[ERREUR] Clé publique absente."
    exit 1
fi

age \
    -R "$RECIPIENT_FILE" \
    -o "$ENCRYPTED_KEY" \
    "$AES_KEY"

echo "[OK] Clé AES protégée avec age."

# ======================== ETAPE 3 ==========================================

echo "[3/5] CREATION DES METADONNEES"

HASH_ARCHIVE=$(sha256sum "$ARCHIVE" | awk '{print $1}')

jq -n \
    --arg backup_id "$BACKUP_ID" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg source "$SOURCE" \
    --arg hash_initial "$HASH_INITIAL" \
    --arg hash_archive "$HASH_ARCHIVE" \
    '{
        backup_id: $backup_id,
        timestamp: $timestamp,
        source_path: $source,
        hash_algorithm: "SHA-256",
        hash_initial: $hash_initial,
        encrypted_archive: {
            filename: ($backup_id + ".tar.gz.enc"),
            hash: $hash_archive
        },
        encryption: "AES-256-CBC-PBKDF2",
        key_filename: "aes.key.age"
    }' > "$JSON_FILE"

echo "[OK] Métadonnées JSON créées."

# ======================== ETAPE 4 ==========================================

echo "[4/5] TRANSFERT SECURISE VERS VM2"

SSH_OPTIONS=(
    -i "$SSH_KEY"
    -o BatchMode=yes
    -o StrictHostKeyChecking=yes
)

REMOTE="$VM2_USER@$VM2_IP"

# Création du répertoire distant.

ssh "${SSH_OPTIONS[@]}" "$REMOTE" \
    "mkdir -p '$REMOTE_DIR/$BACKUP_ID'"

# Transfert des trois fichiers.

scp "${SSH_OPTIONS[@]}" \
    "$ARCHIVE" \
    "$JSON_FILE" \
    "$ENCRYPTED_KEY" \
    "$REMOTE:$REMOTE_DIR/$BACKUP_ID/"

echo "[OK] Transfert SCP terminé."

# ======================== ETAPE 5 ==========================================

echo "[5/5] VALIDATION DISTANTE"

ssh "${SSH_OPTIONS[@]}" "$REMOTE" \
    "bash '$VERIFY_SCRIPT' '$BACKUP_ID'"

echo "[OK] Validation distante terminée."

echo "=============================================="
echo "SAUVEGARDE TERMINEE AVEC SUCCES"
echo "IDENTIFIANT : $BACKUP_ID"
echo "=============================================="
