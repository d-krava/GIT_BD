# Documentation de l'infrastructure PostgresSQL
Ce dépôt contient le code d'infrastructure pour le déploiement, la gestion et la sauvegarde continue des clusters PostgresSQL via GitLab CI/CD et Ansible.

--- 

## PROCÉDURE : Ajout d'une nouvelle base de données (Cluster)

**Objectif:** Déployer un nouveau cluster PostgresSQL isolé avec sa politique de sauvegarde WAL-G vers S3, de manière 100% automatisée.

### Étape 1 : Déclaration dans Visual Studio code

1. Ouvrez le projet d'infrastructure dans **VSCode**.
2. Ouvrez le fichier de variables `cluster.yml`.
3. Ajoutez le nouveau bloc à la fin du fichier en veillant absolument à utiliser un **port réseau unique**.

> **Exemple pour l'ajout d'un nouveau cluster nommé "app2" :**

```yaml
  app2:
    user: app2user
    password: un_mot_de_passe_fort
    database: app2
    superuser_password: pgpass_app2
    port: 5434
    extensions:
      - postgis
    schemas:
      - public
```

### Étape 2 : Déploiement GitOps (Commit & Push)

1. Dans onglet **Contrôle de code source** de VSCode (icône Git à gauche), préparer votre validation en tapant un message clair (ex: `add the cluster app2`).
2. Cliquez sur le bouton **Valider (Commit)**.
3. Cliquez ensuite sur **Synchroniser les modifications (Push)** pour envoyer votre code sur le dépôt.
4. Ouvrez lz terminal de machine `ansible` et tapez la command : `git pull` depuis le dossier Hebergement.

### Étape 3 : Vérifications

* **GitLab :** Le pipeline d'intégration continue se déclench instantanément. Vérifiez dans l'onglet *Pipelines* de notre projet que le job Ansible s'exécute et se termine avec succès (pastille verte).

## PROCÉDURE : Suppression d'un cluster PostgreSQL

Pour supprimer définitivement un cluster de base se sonnées sans laisser de données résiduelles et sans perturber le reste de l'infrastructure, suis cruprlement ces trois étapes dans l'ordre:

### Étape 1 : Arrêt et suppression du conteneur

Avant de modifier le code, il faut éteindre proprement le service actif via Docker:

* Connectez-vous en SSH sur le serveur `srvpgcloud`.
* Exécutez la commande suivante en remplaçant `[NOM_DU_CLUSTER]` par le nom du service

```bash
  docker compose rm -s -f [NOM_DU_CLUSTER]
```

### Étape 2 : Mise à jour de la configuration (GitLab)

Pour empêcher Ansible de recréer le cluster automatiquement, vous devez modifier la source de vérité:

* Ouvres le fichier `cluster.yml`.
* Supprimez (ou commentez avec # **Ctrl + :**) le bloc de configuration correspondant au cluster que vous souhaitez supprimer.
* Effectuez un **Commit** et un **Push** vers GitLab.

`**Note :**` Une fois le pipeline terminé, Ansible aura automatiquement mis à jour le fichier `docker-compose.yml` présent sur le serveur.

### Étape 3 : Nettoyage du volume de données (Serveur)

**Attention !!!** Cette action est irréversible et supprime toutes les données conteneurs dans la base de données.

* Sur le serveur `srvpgcloud`, supprimez le volume persistant associé :

```bash
  docker volume rm postgres_postgres_[NOM_DU_CLUSTER]_data
```
* (Optionnel) Supprimez le script de sauvegarde associé s'il existe:

```bash
  sudo rm /opt/postgres/wal-g_[NOM_DU_CLUSTER].sh
```

## PROCÉDURE : Restauration d'une Base de Données 

cette procédure explique comment restaurer une sauvegarde complète depuis le stockage S3 vers  le conteneur de secours `postgres_restoration`.

### Étape 1 : Identifier la sauvegarde à restaurer

Connectez-vous au conteneur de restauration pour lister les sauvegardes disponibles.

1. Sur le serveur `srvpgcloud`, entrez dans le conteneur de restauration:

```bash
  docker compose exec postgres_restoration bash
```
2. Listez les sauvegardes disponibles pour la base ciblée (ex: `app1`):

```bash
  wal-g_app1.sh backup-list
```
* Notez le nom de la sauvegarde que vous souhaitez restaurer (ex: `base_000000010000000000000021`).

### Étape 2 : Télécharger et préparer les données (Dans le conteneur)

Toujours dans le conteneur de restauration, nous allons télécharger les données dans un dossier temporaire et y appliquer les bons droits.

1. Placez-vous dans le répertoire monté `/mnt` et créez un dossier de transition (`restoration_tmp`):

```bash
  cd /mnt
  mkdir restoration_tmp
```
2. Lancez le téléchargement de la sauvegarde vers ce dossier:

```bash
  wal-g_app1.sh backup-fetch restoration_tmp [NOM_DE_LA_SAUV]
```
3. Une fois l'extraction terminée (Backup exctraction complete) rentrez dans le dossier :

```bash
  cd restoration_tmp
```
4. Créez le fichier de signal indispensable pour indiquer à PostgreSQL de démarrer en mode "récupération":

```bash
  touch recovery.signal
```
5. **Action critique (Droits)** : Donneé la propriété de **tout le dossier** (fichiers de base + recovery.signal) à l'utilisateur `postgres` : 

```bash
  chown -R postgres:postgres .
```
6. Sortez du conteneur : 

```bash
  exit
```

### Étape 3 : Déplacer les fichiers à la racine du volume (Sur l'hôte)

Maintenant que les fichiers sont prêts avec les bons droits, il faut les placer au bon endroit pour que PostgreSQL les trouve à son démarrage.

1. Sur le serveur `srvpgcloud`, passez en super-utilisateur (`root`):

```bash
  sudo bash
```
2. Naviquez dans le volume de données du conteneur de restauration:

```bash
  cd /var/lib/docker/volumes/postgres_postgres_restoration/_data
```
3. Déplacez tout le contenu du dossier temporaire vers la racine du volume, puis supprimez le dossier vide:

```bash
  mv restoration_tmp/* .
  rmdir restoration_tmp
```
4. Quittez la session `root`:

```bash
  exit
```

### Étape 4 : Déclencher et valider la restauration

Les fichiers et les droits sont en place. Il suffit de redémarrer le service.

1. Redémarrez le conteneur de restauration:

```bash
  docker compose restart postgres_restoration
```
2. Surveillez les logs pour valider la réussite de l'opération:

```bash
  docker compose logs -f postgres_restoration
```
**Validation :**
La restauration est terminée et réussie lorsque les logs affichent ces deux messages successifs:

* `consistent recovery state reached`
* `database system is ready to accept connections`