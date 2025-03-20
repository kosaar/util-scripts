#!/bin/bash

# Display usage information
usage() {
    echo "Docker File Transfer Automation Script"
    echo "-------------------------------------"
    echo "This script automates file transfer between local machine and Docker containers"
    echo "running on remote hosts using Docker Compose."
    echo
    echo "Usage: $0 <feature_number> -r <host> [options]"
    echo
    echo "Parameters:"
    echo "  <feature_number>     Feature number to target /opt/data/feature<feature_number>"
    echo "                       Must be a positive integer"
    echo
    echo "Required options:"
    echo "  -r, --remote HOST    Connect to remote host"
    echo
    echo "Other options:"
    echo "  -h, --help           Display this help message"
    echo "  -u, --user USER      Remote username (will prompt if not provided)"
    echo "  -k, --key KEY_PATH   Use SSH private key for authentication"
    echo "  -n, --netrc          Use .netrc file for credentials"
    echo
    echo "Examples:"
    echo "  $0 42 -r server.com -u admin"
    echo "  $0 42 -r server.com -k ~/.ssh/id_rsa"
    echo
    exit 1
}

# Default values
REMOTE_HOST=""
REMOTE_USER=""
SSH_KEY=""
USE_NETRC=false
FEATURE_NUMBER=""

# Parse command line arguments
parse_arguments() {
    if [ $# -lt 1 ]; then
        usage
    fi

    # Check if feature number is a positive integer
    if ! [[ $1 =~ ^[0-9]+$ ]]; then
        echo "Error: Feature number must be a positive integer"
        usage
    fi

    FEATURE_NUMBER=$1
    shift

    # Check if -r/--remote is provided
    FOUND_REMOTE=false

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -r|--remote)
                REMOTE_HOST="$2"
                FOUND_REMOTE=true
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
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Ensure remote host is specified
    if ! $FOUND_REMOTE; then
        echo "Error: Remote host (-r, --remote) is required"
        usage
    fi
}

# Function to setup SSH connection
setup_ssh_connection() {
    if $USE_NETRC; then
        if [ ! -f "$HOME/.netrc" ]; then
            echo "Error: .netrc file not found!"
            exit 1
        fi

        NETRC_DATA=$(grep -A2 "machine $REMOTE_HOST" "$HOME/.netrc")
        if [ -z "$NETRC_DATA" ]; then
            echo "Error: Host $REMOTE_HOST not found in .netrc!"
            exit 1
        fi

        REMOTE_USER=$(echo "$NETRC_DATA" | grep "login" | awk '{print $2}')
        REMOTE_PASS=$(echo "$NETRC_DATA" | grep "password" | awk '{print $2}')
    else
        # If no user specified, prompt for it
        if [ -z "$REMOTE_USER" ]; then
            read -p "Enter username for $REMOTE_HOST: " REMOTE_USER
        fi

        # If no key specified, prompt for password
        if [ -z "$SSH_KEY" ]; then
            read -s -p "Enter password for $REMOTE_USER@$REMOTE_HOST: " REMOTE_PASS
            echo
        fi
    fi

    # Test SSH connection
    echo "Testing connection to $REMOTE_HOST..."
    if [ -n "$SSH_KEY" ]; then
        ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" echo "Connection successful" > /dev/null
    else
        # Using sshpass for password authentication
        command -v sshpass >/dev/null 2>&1 || { echo "sshpass is required but not installed. Aborting."; exit 1; }
        sshpass -p "$REMOTE_PASS" ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" echo "Connection successful" > /dev/null
    fi

    if [ $? -ne 0 ]; then
        echo "Error: Failed to connect to $REMOTE_HOST"
        exit 1
    fi

    echo "Connection to $REMOTE_HOST established successfully."
}

# Execute remote command
remote_exec() {
    if [ -n "$SSH_KEY" ]; then
        ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" "$@"
    else
        sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_HOST" "$@"
    fi
}

# Copy file to remote
remote_copy_to() {
    local_path=$1
    remote_path=$2

    if [ -n "$SSH_KEY" ]; then
        scp -i "$SSH_KEY" -r "$local_path" "$REMOTE_USER@$REMOTE_HOST:$remote_path"
    else
        sshpass -p "$REMOTE_PASS" scp -r "$local_path" "$REMOTE_USER@$REMOTE_HOST:$remote_path"
    fi
}

# Copy file from remote
remote_copy_from() {
    remote_path=$1
    local_path=$2

    if [ -n "$SSH_KEY" ]; then
        scp -i "$SSH_KEY" -r "$REMOTE_USER@$REMOTE_HOST:$remote_path" "$local_path"
    else
        sshpass -p "$REMOTE_PASS" scp -r "$REMOTE_USER@$REMOTE_HOST:$remote_path" "$local_path"
    fi
}

# Function to run Docker Compose commands
run_docker_compose() {
    local BASE_PATH="/opt/data/feature${FEATURE_NUMBER}"
    local DOCKER_COMPOSE_FILE="$BASE_PATH/docker-compose.yml"

    # Check if docker-compose file exists
    if ! remote_exec "[ -f $DOCKER_COMPOSE_FILE ]"; then
        echo "Error: Docker Compose file not found at $DOCKER_COMPOSE_FILE"
        return 1
    fi

    # Run docker-compose command
    remote_exec "cd $BASE_PATH && docker-compose $*"
    return $?
}

# Function to get container name from docker-compose
get_container_name() {
    local BASE_PATH="/opt/data/feature${FEATURE_NUMBER}"
    local SERVICES=$(remote_exec "cd $BASE_PATH && docker-compose ps --services")

    if [ -z "$SERVICES" ]; then
        echo "Error: No services found in docker-compose.yml or services not running"
        return 1
    fi

    # Get the first service name
    SERVICE_NAME=$(echo "$SERVICES" | head -1)

    # Get the container name
    CONTAINER_NAME=$(remote_exec "cd $BASE_PATH && docker-compose ps -q $SERVICE_NAME")

    if [ -z "$CONTAINER_NAME" ]; then
        echo "Error: Container not running for service $SERVICE_NAME"
        return 1
    fi

    echo "$CONTAINER_NAME"
}

# Function to show menu
show_menu() {
    clear
    echo "Docker File Transfer - Feature $FEATURE_NUMBER"
    echo "=========================================="
    echo "Target path: $CONTAINER_PATH"
    echo "Container: $CONTAINER_NAME"
    echo "Remote host: $REMOTE_USER@$REMOTE_HOST"
    echo
    echo "1) Copy file from local to container"
    echo "2) Copy file from container to local"
    echo "3) List files in container directory"
    echo "4) Change container/service"
    echo "5) Docker Compose status"
    echo "6) Docker Compose up"
    echo "7) Docker Compose down"
    echo "8) Docker Compose logs"
    echo "0) Exit"
    echo
    echo -n "Choose an option: "
}

# Function to copy file to container
copy_to_container() {
    echo "Enter local file path:"
    read -e LOCAL_FILE

    if [ ! -f "$LOCAL_FILE" ]; then
        echo "Error: File not found!"
        read -p "Press Enter to continue..."
        return
    fi

    # Create directory in container if it doesn't exist
    remote_exec "docker exec $CONTAINER_NAME mkdir -p $CONTAINER_PATH"

    # Get filename
    FILENAME=$(basename "$LOCAL_FILE")

    # Copy to temp location on remote host
    TEMP_PATH="/tmp/$FILENAME"
    echo "Copying $LOCAL_FILE to remote host..."
    remote_copy_to "$LOCAL_FILE" "$TEMP_PATH"

    echo "Copying from remote host to container..."
    remote_exec "docker cp $TEMP_PATH $CONTAINER_NAME:$CONTAINER_PATH/$FILENAME"
    remote_exec "rm $TEMP_PATH"

    if [ $? -eq 0 ]; then
        echo "File copied successfully."
    else
        echo "Error copying file!"
    fi

    read -p "Press Enter to continue..."
}

# Function to copy file from container
copy_from_container() {
    # List files in container directory
    echo "Files in $CONTAINER_PATH:"
    remote_exec "docker exec $CONTAINER_NAME ls -la $CONTAINER_PATH"

    echo "Enter file name to copy from container:"
    read CONTAINER_FILE

    echo "Enter local destination directory:"
    read -e LOCAL_DIR

    # Create local directory if it doesn't exist
    mkdir -p "$LOCAL_DIR"

    TEMP_PATH="/tmp/$CONTAINER_FILE"
    echo "Copying from container to remote host..."
    remote_exec "docker cp $CONTAINER_NAME:$CONTAINER_PATH/$CONTAINER_FILE $TEMP_PATH"

    echo "Copying from remote host to local machine..."
    remote_copy_from "$TEMP_PATH" "$LOCAL_DIR/"
    remote_exec "rm $TEMP_PATH"

    if [ $? -eq 0 ]; then
        echo "File copied successfully to $LOCAL_DIR/$CONTAINER_FILE"
    else
        echo "Error copying file!"
    fi

    read -p "Press Enter to continue..."
}

# Function to list files in container
list_container_files() {
    echo "Files in $CONTAINER_PATH:"
    remote_exec "docker exec $CONTAINER_NAME ls -la $CONTAINER_PATH 2>/dev/null || echo \"Directory doesn't exist or is empty.\""
    read -p "Press Enter to continue..."
}

# Function to change container/service
change_container() {
    echo "Available services in docker-compose.yml:"
    run_docker_compose ps --services

    echo "Enter service name:"
    read SERVICE_NAME

    # Get container ID for the service
    NEW_CONTAINER=$(remote_exec "cd /opt/data/feature${FEATURE_NUMBER} && docker-compose ps -q $SERVICE_NAME")

    if [ -n "$NEW_CONTAINER" ]; then
        CONTAINER_NAME=$NEW_CONTAINER
        echo "Container changed to $CONTAINER_NAME (service: $SERVICE_NAME)"
    else
        echo "Error: Service not found or not running!"
    fi

    read -p "Press Enter to continue..."
}

# Docker Compose status
docker_compose_status() {
    run_docker_compose ps
    read -p "Press Enter to continue..."
}

# Docker Compose up
docker_compose_up() {
    run_docker_compose up -d
    # Get container again as it might have changed
    CONTAINER_NAME=$(get_container_name)
    read -p "Press Enter to continue..."
}

# Docker Compose down
docker_compose_down() {
    run_docker_compose down
    read -p "Press Enter to continue..."
}

# Docker Compose logs
docker_compose_logs() {
    run_docker_compose logs
    read -p "Press Enter to continue..."
}

# Main script
parse_arguments "$@"

# Configure paths
CONTAINER_PATH="/opt/data/feature${FEATURE_NUMBER}"

# Setup SSH connection
setup_ssh_connection

# Get container name
CONTAINER_NAME=$(get_container_name)
if [ -z "$CONTAINER_NAME" ]; then
    echo "No containers running. Starting containers..."
    docker_compose_up
    CONTAINER_NAME=$(get_container_name)
    if [ -z "$CONTAINER_NAME" ]; then
        echo "Failed to start containers. Exiting."
        exit 1
    fi
fi

# Main loop
while true; do
    show_menu
    read OPTION

    case $OPTION in
        1) copy_to_container ;;
        2) copy_from_container ;;
        3) list_container_files ;;
        4) change_container ;;
        5) docker_compose_status ;;
        6) docker_compose_up ;;
        7) docker_compose_down ;;
        8) docker_compose_logs ;;
        0) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option!"; read -p "Press Enter to continue..." ;;
    esac
done