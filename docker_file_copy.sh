#!/bin/bash

# Afficher les informations d'utilisation
usage() {
    echo "Script d'Automatisation de Transfert de Fichiers Docker"
    echo "-----------------------------------------------------"
    echo "Ce script automatise le transfert de fichiers entre la machine locale et les conteneurs Docker"
    echo "en utilisant Docker Compose dans des répertoires spécifiques."
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h, --help           Afficher ce message d'aide"
    echo "  -r, --remote HÔTE    Se connecter à l'hôte distant (requis)"
    echo "  -u, --user UTILISATEUR    Nom d'utilisateur distant (demandera si non fourni)"
    echo "  -k, --key CHEMIN_CLÉ   Utiliser une clé privée SSH pour l'authentification"
    echo "  -n, --netrc          Utiliser le fichier .netrc pour les identifiants"
    echo "  -b, --base CHEMIN      Chemin de base pour le projet Docker Compose"
    echo "  -f, --feature NUM    Numéro de fonctionnalité à cibler /opt/data/feature-<numéro_fonctionnalité>"
    echo "                       Si fourni avec --base, --base prend la priorité"
    echo
    echo "Exemples:"
    echo "  $0 -r serveur.com -f 42                Se connecter au serveur distant, fonctionnalité 42"
    echo "  $0 -r serveur.com -b /opt/custom/path  Se connecter au serveur distant, chemin personnalisé"
    echo "  $0 -r serveur.com -u admin -k ~/.ssh/id_rsa -f 42"
    echo
    exit 1
}

# Valeurs par défaut
REMOTE_HOST=""
REMOTE_USER=""
SSH_KEY=""
USE_NETRC=false
FEATURE_NUMBER=""
BASE_PATH=""

# Analyser les arguments de la ligne de commande
parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -r|--remote)
                REMOTE_HOST="$2"
                shift 2
                ;;
            -u|--user)
                REMOTE_USER="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY="$2"
                shift 2
                ;;
            -n|--netrc)
                USE_NETRC=true
                shift
                ;;
            -b|--base)
                BASE_PATH="$2"
                shift 2
                ;;
            -f|--feature)
                # Vérifier si le numéro de fonctionnalité est un entier positif
                if ! [[ $2 =~ ^[0-9]+$ ]]; then
                    echo "Erreur: Le numéro de fonctionnalité doit être un entier positif"
                    usage
                fi
                FEATURE_NUMBER="$2"
                shift 2
                ;;
            *)
                echo "Option inconnue: $1"
                usage
                ;;
        esac
    done

    # S'assurer que l'hôte distant est fourni
    if [ -z "$REMOTE_HOST" ]; then
        echo "Erreur: L'hôte distant est requis"
        usage
    fi

    # Définir le chemin de base en fonction des options fournies
    if [ -z "$BASE_PATH" ]; then
        if [ -n "$FEATURE_NUMBER" ]; then
            # Si le numéro de fonctionnalité est fourni mais pas de chemin de base, utiliser le chemin de fonctionnalité
            BASE_PATH="/opt/data/feature-${FEATURE_NUMBER}"
        else
            # Chemin de base par défaut si ni le chemin de base ni le numéro de fonctionnalité ne sont fournis
            BASE_PATH="/opt/data"
        fi
    fi
    # Remarque: si BASE_PATH et FEATURE_NUMBER sont tous deux fournis, BASE_PATH a la priorité
}

# Fonction pour configurer la connexion SSH
setup_ssh_connection() {
    if $USE_NETRC; then
        if [ ! -f "$HOME/.netrc" ]; then
            echo "Erreur: Fichier .netrc introuvable!"
            read -p "Appuyez sur Entrée pour continuer..."
            exit 1
        fi

        NETRC_DATA=$(grep -A2 "machine $REMOTE_HOST" "$HOME/.netrc")
        if [ -z "$NETRC_DATA" ]; then
            echo "Erreur: Hôte $REMOTE_HOST non trouvé dans .netrc!"
            read -p "Appuyez sur Entrée pour continuer..."
            exit 1
        fi

        REMOTE_USER=$(echo "$NETRC_DATA" | grep "login" | awk '{print $2}')
        REMOTE_PASS=$(echo "$NETRC_DATA" | grep "password" | awk '{print $2}')
    else
        # Si aucun utilisateur n'est spécifié, demander
        if [ -z "$REMOTE_USER" ]; then
            read -p "Entrez le nom d'utilisateur pour $REMOTE_HOST: " REMOTE_USER
        fi

        # Si aucune clé n'est spécifiée, demander le mot de passe
        if [ -z "$SSH_KEY" ]; then
            read -s -p "Entrez le mot de passe pour $REMOTE_USER@$REMOTE_HOST: " REMOTE_PASS
            echo
        fi
    fi

    # Tester la connexion SSH
    echo "Test de connexion à $REMOTE_HOST..."
    if [ -n "$SSH_KEY" ]; then
        ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" echo "Connexion réussie" > /dev/null
    else
        # Utiliser sshpass pour l'authentification par mot de passe
        command -v sshpass >/dev/null 2>&1 || { echo "sshpass est requis mais n'est pas installé. Abandon."; exit 1; }
        sshpass -p "$REMOTE_PASS" ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" echo "Connexion réussie" > /dev/null
    fi

    if [ $? -ne 0 ]; then
        echo "Erreur: Échec de la connexion à $REMOTE_HOST"
        exit 1
    fi

    echo "Connexion à $REMOTE_HOST établie avec succès."
}

# Exécuter une commande à distance
remote_exec() {
    if [ -n "$SSH_KEY" ]; then
        ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "$@"
    else
        sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_HOST" "$@"
    fi
}

# Copier un fichier vers l'hôte distant
remote_copy_to() {
    local_path=$1
    remote_path=$2

    if [ -n "$SSH_KEY" ]; then
        scp -i "$SSH_KEY" -r "$local_path" "$REMOTE_USER@$REMOTE_HOST:$remote_path"
    else
        sshpass -p "$REMOTE_PASS" scp -r "$local_path" "$REMOTE_USER@$REMOTE_HOST:$remote_path"
    fi
}

# Copier un fichier depuis l'hôte distant
remote_copy_from() {
    remote_path=$1
    local_path=$2

    if [ -n "$SSH_KEY" ]; then
        scp -i "$SSH_KEY" -r "$REMOTE_USER@$REMOTE_HOST:$remote_path" "$local_path"
    else
        sshpass -p "$REMOTE_PASS" scp -r "$REMOTE_USER@$REMOTE_HOST:$remote_path" "$local_path"
    fi
}

# Fonction pour exécuter des commandes Docker Compose
run_docker_compose() {
    local DOCKER_COMPOSE_FILE="$BASE_PATH/docker-compose.yml"

    # Vérifier si le fichier docker-compose existe
    if ! remote_exec "[ -f $DOCKER_COMPOSE_FILE ]"; then
        echo "Erreur: Fichier Docker Compose introuvable à $DOCKER_COMPOSE_FILE"
        read -p "Appuyez sur Entrée pour continuer..."
        return 1
    fi

    # Exécuter la commande docker-compose
    remote_exec "cd $BASE_PATH && docker-compose $*"
    return $?
}

# Fonction pour obtenir le nom du conteneur à partir de docker-compose
get_container_name() {
    local SERVICES=$(remote_exec "cd $BASE_PATH && docker-compose ps --services")

    if [ -z "$SERVICES" ]; then
        echo "Erreur: Aucun service trouvé dans docker-compose.yml ou services non en cours d'exécution"
        read -p "Appuyez sur Entrée pour continuer..."
        return 1
    fi

    # Obtenir le premier nom de service
    SERVICE_NAME=$(echo "$SERVICES" | head -1)

    # Obtenir le nom du conteneur
    CONTAINER_NAME=$(remote_exec "cd $BASE_PATH && docker-compose ps -q $SERVICE_NAME")

    if [ -z "$CONTAINER_NAME" ]; then
        echo "Erreur: Conteneur non en cours d'exécution pour le service $SERVICE_NAME"
        read -p "Appuyez sur Entrée pour continuer..."
        return 1
    fi

    echo "$CONTAINER_NAME"
}

# Fonction pour mapper le chemin du conteneur au chemin de l'hôte
map_container_path() {
    local container_path=$1
    local host_mounted_path=""

    # Vérifier si le chemin est sous /opt/data
    if [[ $container_path == /opt/data/* ]]; then
        # Puisque /opt/data est monté depuis l'hôte, nous devons le mapper
        host_mounted_path="/opt/data"
    else
        # Le chemin est à l'intérieur du conteneur
        host_mounted_path=""
    fi

    echo "$host_mounted_path"
}

# Fonction pour afficher le menu
show_menu() {
    clear
    echo "Transfert de Fichiers Docker"
    echo "=========================================="
    echo "Conteneur: $CONTAINER_NAME"
    echo "Hôte distant: $REMOTE_USER@$REMOTE_HOST"
    echo "Chemin de base: $BASE_PATH"
    if [ -n "$FEATURE_NUMBER" ]; then
        echo "Fonctionnalité: $FEATURE_NUMBER"
    fi
    echo
    echo "1) Explorer le système de fichiers du conteneur"
    echo "2) Changer de conteneur/service"
    echo "3) État Docker Compose"
    echo "4) Docker Compose up"
    echo "5) Docker Compose down"
    echo "6) Journaux Docker Compose"
    echo "0) Quitter"
    echo
    echo -n "Choisissez une option: "
}

# Fonction pour copier un fichier vers le conteneur
copy_to_container() {
    echo "Entrez le chemin du fichier local:"
    read -e LOCAL_FILE

    if [ ! -f "$LOCAL_FILE" ]; then
        echo "Erreur: Fichier introuvable!"
        read -p "Appuyez sur Entrée pour continuer..."
        return
    fi

    # Créer un répertoire dans le conteneur s'il n'existe pas
    remote_exec "docker exec $CONTAINER_NAME mkdir -p $CURRENT_PATH"

    # Obtenir le nom du fichier
    FILENAME=$(basename "$LOCAL_FILE")

    # Copier vers un emplacement temporaire sur l'hôte distant
    TEMP_PATH="/tmp/$FILENAME"
    echo "Copie de $LOCAL_FILE vers l'hôte distant..."
    remote_copy_to "$LOCAL_FILE" "$TEMP_PATH"

    echo "Copie depuis l'hôte distant vers le conteneur..."
    remote_exec "docker cp $TEMP_PATH $CONTAINER_NAME:$CURRENT_PATH/$FILENAME"
    remote_exec "rm $TEMP_PATH"

    if [ $? -eq 0 ]; then
        echo "Fichier copié avec succès vers $CURRENT_PATH/$FILENAME"
    else
        echo "Erreur lors de la copie du fichier!"
    fi

    read -p "Appuyez sur Entrée pour continuer..."
}

# Fonction pour copier un fichier depuis le conteneur
copy_from_container() {
    # Lister les fichiers dans le chemin du conteneur
    echo "Fichiers dans $CURRENT_PATH:"
    remote_exec "docker exec $CONTAINER_NAME ls -la $CURRENT_PATH"

    echo "Entrez le nom du fichier à copier depuis le conteneur:"
    read CONTAINER_FILE

    echo "Entrez le répertoire de destination local:"
    read -e LOCAL_DIR

    # Créer le répertoire local s'il n'existe pas
    mkdir -p "$LOCAL_DIR"

    TEMP_PATH="/tmp/$CONTAINER_FILE"
    echo "Copie depuis le conteneur vers l'hôte distant..."
    remote_exec "docker cp $CONTAINER_NAME:$CURRENT_PATH/$CONTAINER_FILE $TEMP_PATH"

    echo "Copie depuis l'hôte distant vers la machine locale..."
    remote_copy_from "$TEMP_PATH" "$LOCAL_DIR/"
    remote_exec "rm $TEMP_PATH"

    if [ $? -eq 0 ]; then
        echo "Fichier copié avec succès vers $LOCAL_DIR/$CONTAINER_FILE"
    else
        echo "Erreur lors de la copie du fichier!"
    fi

    read -p "Appuyez sur Entrée pour continuer..."
}

# Fonction pour exécuter une commande dans le conteneur
execute_container_command() {
    echo "Entrez la commande à exécuter dans le conteneur:"
    read COMMAND

    echo "----------------------------------------"
    echo "Exécution de: $COMMAND"
    echo "----------------------------------------"
    remote_exec "docker exec $CONTAINER_NAME sh -c \"cd $CURRENT_PATH && $COMMAND\""
    echo "----------------------------------------"

    read -p "Appuyez sur Entrée pour continuer..."
}

# Fonction améliorée pour explorer le système de fichiers du conteneur avec des opérations de fichiers intégrées
explore_container_filesystem() {
    while true; do
        clear
        echo "Explorateur de Fichiers - Conteneur: $CONTAINER_NAME"
        echo "Chemin: $CURRENT_PATH"
        echo "----------------------------------------"

        # Obtenir le répertoire de travail actuel dans le conteneur
        CONTAINER_PWD=$(remote_exec "docker exec $CONTAINER_NAME pwd")
        echo "PWD du conteneur: $CONTAINER_PWD"
        echo

        # Lister les fichiers dans le répertoire actuel
        echo "Contenu du répertoire:"
        remote_exec "docker exec $CONTAINER_NAME ls -la $CURRENT_PATH"
        echo

        # Vérifier si nous sommes dans un répertoire monté
        MOUNTED_PATH=$(map_container_path "$CURRENT_PATH")
        if [ -n "$MOUNTED_PATH" ]; then
            echo "Remarque: Ce répertoire est monté depuis l'hôte à $MOUNTED_PATH"
            echo
        fi

        echo "Options:"
        echo "1) Naviguer vers un sous-répertoire"
        echo "2) Remonter d'un niveau"
        echo "3) Changer vers un chemin spécifique"
        echo "4) Afficher le contenu d'un fichier"
        echo "5) Copier un fichier depuis le local vers le conteneur"
        echo "6) Copier un fichier depuis le conteneur vers le local"
        echo "7) Exécuter une commande dans le conteneur"
        echo "8) Retourner au menu principal"
        echo
        echo -n "Choisissez une option: "
        read EXPLORE_OPTION

        case $EXPLORE_OPTION in
            1)
                echo "Entrez le nom du sous-répertoire:"
                read SUBDIR
                NEW_PATH="$CURRENT_PATH/$SUBDIR"
                # Vérifier si le répertoire existe
                if remote_exec "docker exec $CONTAINER_NAME [ -d $NEW_PATH ]"; then
                    CURRENT_PATH="$NEW_PATH"
                else
                    echo "Répertoire introuvable ou non accessible."
                    read -p "Appuyez sur Entrée pour continuer..."
                fi
                ;;
            2)
                # Remonter d'un niveau
                CURRENT_PATH=$(dirname "$CURRENT_PATH")
                ;;
            3)
                echo "Entrez le chemin absolu:"
                read NEW_PATH
                # Vérifier si le répertoire existe
                if remote_exec "docker exec $CONTAINER_NAME [ -d $NEW_PATH ]"; then
                    CURRENT_PATH="$NEW_PATH"
                else
                    echo "Répertoire introuvable ou non accessible."
                    read -p "Appuyez sur Entrée pour continuer..."
                fi
                ;;
            4)
                echo "Entrez le nom du fichier à visualiser:"
                read FILENAME
                echo "----------------------------------------"
                echo "Contenu de $CURRENT_PATH/$FILENAME:"
                echo "----------------------------------------"
                remote_exec "docker exec $CONTAINER_NAME cat $CURRENT_PATH/$FILENAME"
                echo "----------------------------------------"
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            5)
                copy_to_container
                ;;
            6)
                copy_from_container
                ;;
            7)
                execute_container_command
                ;;
            8)
                return
                ;;
            *)
                echo "Option invalide!"
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
        esac
    done
}

# Fonction pour changer de conteneur/service
change_container() {
    echo "Services disponibles dans docker-compose.yml:"
    run_docker_compose ps --services

    echo "Entrez le nom du service:"
    read SERVICE_NAME

    # Obtenir l'ID du conteneur pour le service
    NEW_CONTAINER=$(remote_exec "cd $BASE_PATH && docker-compose ps -q $SERVICE_NAME")

    if [ -n "$NEW_CONTAINER" ]; then
        CONTAINER_NAME=$NEW_CONTAINER
        echo "Conteneur changé pour $CONTAINER_NAME (service: $SERVICE_NAME)"
    else
        echo "Erreur: Service introuvable ou non en cours d'exécution!"
    fi

    read -p "Appuyez sur Entrée pour continuer..."
}

# État Docker Compose
docker_compose_status() {
    run_docker_compose ps
    read -p "Appuyez sur Entrée pour continuer..."
}

# Docker Compose up
docker_compose_up() {
    run_docker_compose up -d
    # Obtenir à nouveau le conteneur car il pourrait avoir changé
    CONTAINER_NAME=$(get_container_name)
    read -p "Appuyez sur Entrée pour continuer..."
}

# Docker Compose down avec confirmation
docker_compose_down() {
    # Afficher d'abord les conteneurs en cours d'exécution
    echo "Conteneurs actuellement en cours d'exécution:"
    run_docker_compose ps

    # Demander confirmation
    echo
    echo "AVERTISSEMENT: Cela arrêtera tous les conteneurs dans $BASE_PATH"
    echo -n "Êtes-vous sûr de vouloir continuer? (o/N): "
    read CONFIRM

    # Vérifier la confirmation
    if [[ "$CONFIRM" =~ ^[Oo]$ ]]; then
        echo "Arrêt des conteneurs..."
        run_docker_compose down
        echo "Conteneurs arrêtés."
    else
        echo "Opération annulée."
    fi

    read -p "Appuyez sur Entrée pour continuer..."
}

# Journaux Docker Compose
docker_compose_logs() {
    run_docker_compose logs
    read -p "Appuyez sur Entrée pour continuer..."
}

# Script principal
parse_arguments "$@"

# Configurer la connexion SSH
setup_ssh_connection

# Configurer les chemins
CURRENT_PATH="/"

# Obtenir le nom du conteneur
CONTAINER_NAME=$(get_container_name)
if [ -z "$CONTAINER_NAME" ]; then
    echo "Aucun conteneur en cours d'exécution. Démarrage des conteneurs..."
    docker_compose_up
    CONTAINER_NAME=$(get_container_name)
    if [ -z "$CONTAINER_NAME" ]; then
        echo "Échec du démarrage des conteneurs. Sortie."
        exit 1
    fi
fi

# Boucle principale
while true; do
    show_menu
    read OPTION

    case $OPTION in
        1) explore_container_filesystem ;;
        2) change_container ;;
        3) docker_compose_status ;;
        4) docker_compose_up ;;
        5) docker_compose_down ;;
        6) docker_compose_logs ;;
        0) echo "Sortie..."; exit 0 ;;
        *) echo "Option invalide!"; read -p "Appuyez sur Entrée pour continuer..." ;;
    esac
done