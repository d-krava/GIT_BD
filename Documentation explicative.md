# Documentation explicative de l'arborescence du projet Hébergement

Ce document détaille l'organisation du dépôt de code de l'infrastructure PostgreSQL / Garage S3. Il a pour but d'expliquer la fonction de chaque dossier et de chaque fichier afin de faciliter la prise en main, la maintenance et les évolutions futures du projet.

---

## Fichiers à la racine du projet

La racine du dépôt contient les fichiers de configuration globaux, l'inventaire des serveurs et les points d'entrée pour l'automatisation (Ansible & Gitlab CI).

* **`.gitlab-ci.yml`** : C'est le fichier de configuration du pipeline d'integration continue de Gitlab. Il définit comment le code est déployé automatiquement sur le serveur cible (srvpgcloud) à l'aide d'un runner à chaque modification du dêpot.
* **`cluster.yml`** : Fichier de variables contenant la définition de vos clusters de bases de données applicatives. Il centralise les mots de passe, les ports et les extensions  déployer.
* **`hosts.yml`** : L'inventaire Ansible. Il déclare le serveur cible et l'utilisateur système utilisé pour s'y connecter via SSH.
* **`playbook.yml`** : Le point d'entrée principal d'Ansible. Il fait le lien entre l'inventaire et le code d'automatisation en demandant l'exécution du rôle postgres sur les hôtes cibles avec les privilèges administrateur.
* **`run-ansible.yml`** : Un script utilitaire permettant de lancer manuellement la commande `ansible-playbook` avec les bons arguments sans passer par Gitlab CI.

---

## Rôle Ansible: `roles/postgres/`

Ce répertoire structure toute la logique de déploiement de l'infrastructure. Ansible fonctionne selon un principe de séparation des responsabilités à travers différents sous-dossiers.

### Dossier: `roles/postgres/tasks/`

Ce dossier contient les listes d'actions séquentielles qu'Ansible doit exécuter sur le serveur.

* **`main.yml`** : C'est le coeur du déploiement. Ce fichier installe les paquetes de base (curl, git, etc.), configure le déôt oddiciel Docker, installe Docke Compose, crée les répertoires nécessaires (`/opt/postgres/`, `/var/local/postgres`), télécharge le binaire WAL-G, et configure la tâche Cron de sauvegarde.

### Dossier: `roles/postgres/handlers/`

Les handlers sont des tâches spéciales qui ne s'exécutent que si elles sont "notifiées" par un changement dans une tâche classique.

* **`main.yml`** : Contient les instructions pour redémarrer ou recharger les services. Il définit notamment les actions "Launch Composition" (pourlancer ou mettre à jour les conteneurs PostgreSQL avec `docker compose up -d`) et "Restart Garage" (pour relancer spécifiquement le noeud de stockage).

### Dossier: `roles/postgres/templates/`

Ce dossier stocke des fichiers modèles écrits avec le langage Jinja2. Ansible va injecter les variables dans ces modèles avant de les copier sur le serveur cible.

* **`docker-compose.yml.j2`** : Le modèle d'architecture des conteneurs. Il génère dynamiquement la composition Docker en bouclant sur la liste des clusters pour créer un service PostgreSQL par cluster, tout en configurant le service unique du stockage objet Garage.
* **`wal-g.sh.j2`** : le modèle du script d'interface S3 pour PostgresSQL. Il génère un script qui configure les variables d'environnement pour que l'outil de sauvegarde WAL-G intercepte les transactions et les expédie vers le conteneur Garage.

### Dossier : `roles/postgres/files/`

Contrairement aux templates, ce dossier contient des fichiers de configuration et des scripts qui sont copiés tel quels sur le serveur, sans subir de modification de la part d'Ansible.

* **`backup-push.sh`** : Script shell transféré sur l'hôte, puis exécuté par la tâche Cron toutes les nuits à 2h00. Il commande à WAL-G de faire une sauvegarde complète et gère la rétention en supprimant automatiquement les anciennes sauvegardes pour n'en conserver que 15 complètes.
* **`garage.toml`** : Le fichier de configuration du serveur de stockage objet Garage. Il définit le mode de fonctionnement avec une réplication de niveau 1 (single-node), l'utilisation du moteur SQLite pour les métadonnées, et sécurise les ports d'API et d'admoinistration avec des clés d'accès.