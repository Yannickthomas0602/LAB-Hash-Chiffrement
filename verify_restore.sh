
#!/bin/bash

###############################################################################
# VALIDATION ET RESTAURATION WORDPRESS
# STOCKAGE LOCAL : /srv/wordpress-backups
###############################################################################

set -Eeuo pipefail
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ======================== CONFIGURATION ====================================

BASE="/srv/wordpress-backups"

PRIVATE_KEY="/home/backupadmin/.config/age/keys.txt"

LOGFILE="$BASE/verify.log"

# ======================== ARGUMENTS ========================================

if [[ $# -ne 1 ]]; then
    echo "Usage : $0 BACKUP_ID"
    exit 1
fi

BACKUP_ID="$1"

# Validation de l'identifiant.

if [[ ! "$BACKUP_ID" =~ ^wordpress_[0-9]{8}_[0-9]{6}$ ]]; then
    echo "[ERREUR] Identifiant invalide."
    exit 1
fi

WORKDIR="$BASE/$BACKUP_ID"

ARCHIVE="$WORKDIR/$BACKUP_ID.tar.gz.enc"

JSON_FILE="$WORKDIR/$BACKUP_ID.json"

ENCRYPTED_KEY="$WORKDIR/aes.key.age"

RESTORE_DIR="$BASE/restore/$BACKUP_ID"

mkdir -p "$BASE/restore"

exec >> "$LOGFILE" 2>&1

echo "=============================================="
echo "VALIDATION : $BACKUP_ID"
echo "DATE : $(date -u)"
echo "=============================================="

# ======================== VERIFICATION FICHIERS ============================

echo "[1/5] VERIFICATION DES FICHIERS"

for FILE in "$ARCHIVE" "$JSON_FILE" "$ENCRYPTED_KEY"; do

    if [[ ! -s "$FILE" ]]; then
        echo "[ERREUR] Fichier absent ou vide : $FILE"
        exit 1
    fi

done

echo "[OK] Trois fichiers présents."

# ======================== LECTURE JSON =====================================

echo "[2/5] LECTURE DES METADONNEES"

HASH_INITIAL=$(jq -er '.hash_initial' "$JSON_FILE")

HASH_ARCHIVE=$(jq -er '.encrypted_archive.hash' "$JSON_FILE")

JSON_ID=$(jq -er '.backup_id' "$JSON_FILE")

if [[ "$JSON_ID" != "$BACKUP_ID" ]]; then
    echo "[ERREUR] Identifiant JSON incorrect."
    exit 1
fi

if [[ ! "$HASH_INITIAL" =~ ^[a-fA-F0-9]{64}$ ]] ||
   [[ ! "$HASH_ARCHIVE" =~ ^[a-fA-F0-9]{64}$ ]]; then

    echo "[ERREUR] Empreinte SHA-256 invalide."
    exit 1
fi

# ======================== HASH ARCHIVE =====================================

echo "[3/5] VERIFICATION SHA-256 DE L'ARCHIVE"

HASH_CALCULE=$(sha256sum "$ARCHIVE" | awk '{print $1}')

echo "Hash JSON     : $HASH_ARCHIVE"
echo "Hash calculé  : $HASH_CALCULE"

if [[ "$HASH_CALCULE" != "$HASH_ARCHIVE" ]]; then

    echo "[ECHEC] Archive altérée."
    exit 1

fi

echo "[OK] Intégrité de l'archive confirmée."

# ======================== DECHIFFREMENT CLE ================================

echo "[4/5] RECUPERATION DE LA CLE AES"

if [[ ! -f "$PRIVATE_KEY" ]]; then
    echo "[ERREUR] Clé privée age absente."
    exit 1
fi

AES_KEY="$WORKDIR/aes.key"

age \
    -d \
    -i "$PRIVATE_KEY" \
    -o "$AES_KEY" \
    "$ENCRYPTED_KEY"

chmod 600 "$AES_KEY"

echo "[OK] Clé AES récupérée."

# ======================== DECHIFFREMENT ARCHIVE ============================

echo "[INFO] Déchiffrement AES-256"

DECRYPTED="$WORKDIR/archive.tar.gz"

openssl enc \
    -d \
    -aes-256-cbc \
    -pbkdf2 \
    -iter 600000 \
    -in "$ARCHIVE" \
    -pass file:"$AES_KEY" \
    -out "$DECRYPTED"

gzip -t "$DECRYPTED"

echo "[OK] Archive déchiffrée."

# ======================== RESTAURATION =====================================

echo "[INFO] Extraction des données"

rm -rf "$RESTORE_DIR"

mkdir -p "$RESTORE_DIR"

tar \
    --extract \
    --gzip \
    --file="$DECRYPTED" \
    --directory="$RESTORE_DIR" \
    --no-same-owner

if [[ ! -d "$RESTORE_DIR/www" ]]; then
    echo "[ERREUR] Dossier www absent."
    exit 1
fi

echo "[OK] Dossier restauré."

# ======================== HASH FINAL =======================================

echo "[5/5] VERIFICATION FINALE"

RESTORED_TAR="$WORKDIR/restored.tar"

tar \
    --sort=name \
    --mtime='@0' \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --format=gnu \
    -cf "$RESTORED_TAR" \
    -C "$RESTORE_DIR" www

HASH_RESTAURE=$(sha256sum "$RESTORED_TAR" | awk '{print $1}')

echo "=============================================="
echo "HASH INITIAL  : $HASH_INITIAL"
echo "HASH RESTAURE : $HASH_RESTAURE"
echo "=============================================="

if [[ "$HASH_INITIAL" == "$HASH_RESTAURE" ]]; then

    echo "[SUCCES] INTEGRITE VALIDEE"
    echo "[SUCCES] RESTAURATION CONFORME"

    # Suppression des éléments sensibles temporaires.
    rm -f "$AES_KEY" "$DECRYPTED" "$RESTORED_TAR"

    exit 0

else

    echo "[ECHEC] DIFFERENCE ENTRE LES HASH"
    echo "[ALERTE] RESTAURATION NON CONFORME"

    exit 1

fi
