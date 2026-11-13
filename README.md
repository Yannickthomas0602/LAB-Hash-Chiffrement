# Sauvegarde WordPress chiffrée

Ce dossier contient deux scripts Bash pour sauvegarder et vérifier la restoration d'un site
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
  empreintes de contrôle de la sauvegarde. 
