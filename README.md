# Script de Transfert de Fichiers Docker

## Description
Ce script bash automatise le transfert de fichiers entre une machine locale et des conteneurs Docker sur un serveur distant. Il offre une interface interactive pour explorer et manipuler les systèmes de fichiers des conteneurs, ainsi que pour gérer les services Docker Compose.

## Fonctionnalités
- Connexion SSH sécurisée à un serveur distant
- Support pour l'authentification par mot de passe, clé SSH ou fichier .netrc
- Navigation et exploration du système de fichiers des conteneurs Docker
- Transfert bidirectionnel de fichiers (local vers conteneur et conteneur vers local)
- Exécution de commandes arbitraires dans les conteneurs
- Gestion des services Docker Compose (démarrage, arrêt, statut, journaux)
- Support des chemins montés et vérification des répertoires
- Ciblage de projets spécifiques avec des paramètres de fonctionnalité

## Prérequis
- `ssh` et `scp` pour les connexions distantes
- `sshpass` pour l'authentification par mot de passe (si utilisée)
- `docker` et `docker-compose` sur le serveur distant
- Permissions suffisantes pour interagir avec les conteneurs Docker

## Utilisation
```
./docker-file-transfer.sh [options]
```

### Options
- `-h, --help` : Afficher le message d'aide
- `-r, --remote HÔTE` : Se connecter à l'hôte distant (requis)
- `-u, --user UTILISATEUR` : Nom d'utilisateur distant (demande si non fourni)
- `-k, --key CHEMIN_CLÉ` : Utiliser une clé privée SSH pour l'authentification
- `-n, --netrc` : Utiliser le fichier .netrc pour les identifiants
- `-b, --base CHEMIN` : Chemin de base pour le projet Docker Compose
- `-f, --feature NUM` : Numéro de fonctionnalité à cibler dans /opt/data/feature-<numéro>

### Exemples
```
# Connexion à un serveur distant, ciblant la fonctionnalité 42
./docker-file-transfer.sh -r serveur.com -f 42

# Connexion à un serveur avec un chemin personnalisé
./docker-file-transfer.sh -r serveur.com -b /opt/custom/path

# Connexion avec authentification par clé SSH
./docker-file-transfer.sh -r serveur.com -u admin -k ~/.ssh/id_rsa -f 42
```

## Menu Principal
Une fois connecté, le script affiche un menu interactif avec les options suivantes:
1. Explorer le système de fichiers du conteneur
2. Changer de conteneur/service
3. Afficher l'état Docker Compose
4. Démarrer les services (Docker Compose up)
5. Arrêter les services (Docker Compose down)
6. Afficher les journaux Docker Compose
0. Quitter

## Explorateur de Fichiers
L'explorateur de fichiers offre les fonctionnalités suivantes:
- Navigation dans les répertoires du conteneur
- Affichage du contenu des fichiers
- Copie de fichiers vers et depuis le conteneur
- Exécution de commandes dans le contexte du répertoire actuel

## Notes
- Si aucun conteneur n'est en cours d'exécution, le script essaiera de démarrer les services automatiquement
- Le script détecte automatiquement si un chemin est monté depuis l'hôte
- Pour les chemins de fonctionnalité, le format est /opt/data/feature-<numéro>
- Utilisez avec précaution l'option Docker Compose down, car elle arrêtera tous les services du projet

## Sécurité
- Les mots de passe sont masqués lors de la saisie
- Support pour les méthodes d'authentification sécurisées (clé SSH, .netrc)
- Confirmation requise pour les opérations destructives (comme Docker Compose down)