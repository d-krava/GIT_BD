#!/bin/bash

echo "==================================================="
echo " OUTIL DE RESTAURATION POSTGRESQL (DOCKER RUN)"
echo "==================================================="

# 0. On coupe le service de fond
echo " Arret du service de fond pour eviter les conflits..."
docker compose -f /opt/postgres/docker-compose.yml stop postgres_restoration

# 1. Demander quelle base restaurer
read -p " Quelle base de donnees veux-tu restaurer ? (ex: app1, as_cc) : " DB_NAME

# read -p "Quelle est la version PostgreSQL de cette base ? (ex: 15, 18) : " PG_VERSION
# # On exporte la variable pour que docker compose la lise dans le fichier .yml
# export PG_VERSION=${PG_VERSION}

# 2. Lister les sauvegardes
echo " "
echo " Recherche des sauvegardes pour la base $DB_NAME..."
docker compose -f /opt/postgres/docker-compose.yml run --rm --entrypoint bash postgres_restoration -c "/usr/local/bin/wal-g_${DB_NAME}.sh backup-list"

# 3. Demander le nom de la sauvegarde cible
echo " "
read -p " Copie-colle le nom de la sauvegarde a restaurer (ex: base_000...) : " BACKUP_NAME

# ---  VÉRIFICATION STRICTE ---
echo " "
echo " Verification stricte de la sauvegarde $BACKUP_NAME..."
# Le -w force grep a chercher le mot exact, pas juste un bout de mot !
BACKUP_EXISTS=$(docker compose -f /opt/postgres/docker-compose.yml run --rm --entrypoint bash postgres_restoration -c "/usr/local/bin/wal-g_${DB_NAME}.sh backup-list | grep -w '${BACKUP_NAME}'")

if [ -z "$BACKUP_EXISTS" ]; then
  echo " ERREUR FATALE : La sauvegarde '${BACKUP_NAME}' est introuvable."
  echo " Redemarrage du service de fond pour annuler..."
  docker compose -f /opt/postgres/docker-compose.yml start postgres_restoration
  echo " Arret du script."
  exit 1
fi
echo " Sauvegarde validee ! On continue."
# ----------------------------------------

# 4. Processus complet avec interception d'erreur (Fail Fast)
echo " "
echo " Preparation et telechargement en cours (cela peut prendre du temps)..."

# Si cette grosse commande echoue (!), on rentre dans le 'then'
if ! docker compose -f /opt/postgres/docker-compose.yml run --rm --entrypoint bash postgres_restoration -c "
  echo '>> Nettoyage du volume...' &&
  rm -rf /mnt/* &&
  echo '>> Telechargement de la sauvegarde...' &&
  mkdir -p /tmp/restoration &&
  /usr/local/bin/wal-g_${DB_NAME}.sh backup-fetch /tmp/restoration ${BACKUP_NAME} &&
  echo '>> Configuration du mode Recovery...' &&
  touch /tmp/restoration/recovery.signal &&
  echo \"recovery_target_action = 'promote'\" >> /tmp/restoration/postgresql.auto.conf &&
  echo \"restore_command = '/usr/local/bin/wal-g_${DB_NAME}.sh wal-fetch \\\"%f\\\" \\\"%p\\\"'\" >> /tmp/restoration/postgresql.auto.conf &&
  echo '>> Installation des fichiers dans le volume final...' &&
  mv /tmp/restoration/* /mnt/ &&
  echo '>> Application des droits de securite...' &&
  chown -R postgres:postgres /mnt
"; then
  echo " "
  echo " ERREUR CRITIQUE : Le telechargement ou la preparation a echoue."
  echo "Veuillez verifier les logs ci-dessus. Le service PostgreSQL ne sera pas redemarre."
  exit 1
fi

# 5. Redémarrer le vrai service uniquement si tout s'est bien passé
echo " "
echo " Lancement du moteur PostgreSQL pour appliquer la restauration..."
docker compose -f /opt/postgres/docker-compose.yml start postgres_restoration

echo " "
echo " SUCCES ! La procedure est terminee."
echo " Pour suivre l'avancement, tape : docker compose logs -f postgres_restoration"