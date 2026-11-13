# Sauvegarde WordPress chiffrée

Ce dossier contient deux scripts Bash pour sauvegarder et vérifier une installation
WordPress située dans `/var/www`.

## Fichiers

- `backup.sh` : crée une archive déterministe de `/var/www`, calcule son
  empreinte SHA-256, la compresse et la chiffre en AES-256-CBC. La clé AES est
  ensuite protégée avec `age`, puis l’archive, les métadonnées JSON et la clé
  chiffrée sont transférées vers la VM distante en SCP. Une validation distante
  est lancée à la fin.
- `verify_restore.sh` : vérifie les fichiers reçus, contrôle l’empreinte de
  l’archive, déchiffre la clé AES et l’archive, restaure les fichiers, puis
  compare l’empreinte de la restauration avec l’empreinte initiale.
- `wordpress_20261113_020000.json` : exemple du fichier JSON de métadonnées
  généré par `backup.sh`. Il contient l’identifiant, la date, les chemins et les
  empreintes de contrôle de la sauvegarde. Ce fichier est un exemple et ne
  constitue pas, à lui seul, une sauvegarde complète.

## Utilisation

Les scripts sont prévus pour être exécutés sur Linux avec Bash et les outils
`tar`, `gzip`, `openssl`, `age`, `jq`, `ssh` et `scp`.

Pour lancer une sauvegarde :

```bash
sudo bash backup.sh
```

Pour vérifier et restaurer une sauvegarde sur la machine distante :

```bash
bash verify_restore.sh wordpress_YYYYMMDD_HHMMSS
```

La restauration est créée dans :

```text
/srv/wordpress-backups/restore/<BACKUP_ID>/
```

Les paramètres réseau, les chemins, les clés SSH et les emplacements de
stockage sont définis au début de chaque script et doivent être adaptés à
l’environnement utilisé.
