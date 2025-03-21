#!/bin/bash

# Display usage information
usage() {
    echo "Docker File Transfer Automation Script"
    echo "-------------------------------------"
    echo "This script automates file transfer between local machine and Docker containers"
    echo "using Docker Compose in feature-specific directories."
    echo
    echo "Usage: $0 <feature_number> [options]"
    echo
    echo "Parameters:"
    echo "  <feature_number>     Feature number to target /opt/data/feature<feature_number>"
    echo "                       Must be a positive integer"
    echo
    echo "Options:"
    echo "  -h, --help           Display this help message"
    echo "  -r, --remote HOST    Connect to remote host (required)"
    echo "  -u, --user USER      Remote username (will prompt if not provided)"
    echo "  -k, --key KEY_PATH   Use SSH private key for authentication"
    echo "  -n, --netrc          Use .netrc file for credentials"
    echo
    echo "Examples:"
    echo "  $0 42 -r server.com  Connect to remote server, feature 42"
    echo "  $0 42 -r server.com -u admin -k ~/.ssh/id_rsa"
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
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Ensure remote host is provided
    if [ -z "$REMOTE_HOST" ]; then
        echo "Error: Remote host is required"
        usage
    fi
}

# Function to setup SSH connection
setup_ssh_connection() {
    if $USE_NETRC; then
        if [ ! -f "$HOME/.netrc" ]; then
            echo "Error: .netrc file not found!"
            read -p "Press Enter to continue..."
            exit 1
        fi

        NETRC_DATA=$(grep -A2 "machine $REMOTE_HOST" "$HOME/.netrc")
        if [ -z "$NETRC_DATA" ]; then
            echo "Error: Host $REMOTE_HOST not found in .netrc!"
            read -p "Press Enter to continue..."
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
        read -p "Press Enter to continue..."
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
        read -p "Press Enter to continue..."
        return 1
    fi

    # Get the first service name
    SERVICE_NAME=$(echo "$SERVICES" | head -1)

    # Get the container name
    CONTAINER_NAME=$(remote_exec "cd $BASE_PATH && docker-compose ps -q $SERVICE_NAME")

    if [ -z "$CONTAINER_NAME" ]; then
        echo "Error: Container not running for service $SERVICE_NAME"
        read -p "Press Enter to continue..."
        return 1
    fi

    echo "$CONTAINER_NAME"
}

# Function to map container path to host path
map_container_path() {
    local container_path=$1
    local host_mounted_path=""

    # Check if the path is under /opt/data
    if [[ $container_path == /opt/data/* ]]; then
        # Since /opt/data is mounted from host, we need to map it
        host_mounted_path="/opt/data"
    else
        # Path is inside container
        host_mounted_path=""
    fi

    echo "$host_mounted_path"
}

# Function to show menu
show_menu() {
    clear
    echo "Docker File Transfer - Feature $FEATURE_NUMBER"
    echo "=========================================="
    echo "Container: $CONTAINER_NAME"
    echo "Remote host: $REMOTE_USER@$REMOTE_HOST"
    echo
    echo "1) Explore container filesystem"
    echo "2) Change container/service"
    echo "3) Docker Compose status"
    echo "4) Docker Compose up"
    echo "5) Docker Compose down"
    echo "6) Docker Compose logs"
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
    remote_exec "docker exec $CONTAINER_NAME mkdir -p $CURRENT_PATH"

    # Get filename
    FILENAME=$(basename "$LOCAL_FILE")

    # Copy to temp location on remote host
    TEMP_PATH="/tmp/$FILENAME"
    echo "Copying $LOCAL_FILE to remote host..."
    remote_copy_to "$LOCAL_FILE" "$TEMP_PATH"

    echo "Copying from remote host to container..."
    remote_exec "docker cp $TEMP_PATH $CONTAINER_NAME:$CURRENT_PATH/$FILENAME"
    remote_exec "rm $TEMP_PATH"

    if [ $? -eq 0 ]; then
        echo "File copied successfully to $CURRENT_PATH/$FILENAME"
    else
        echo "Error copying file!"
    fi

    read -p "Press Enter to continue..."
}

# Function to copy file from container
copy_from_container() {
    # List files in container path
    echo "Files in $CURRENT_PATH:"
    remote_exec "docker exec $CONTAINER_NAME ls -la $CURRENT_PATH"

    echo "Enter file name to copy from container:"
    read CONTAINER_FILE

    echo "Enter local destination directory:"
    read -e LOCAL_DIR

    # Create local directory if it doesn't exist
    mkdir -p "$LOCAL_DIR"

    TEMP_PATH="/tmp/$CONTAINER_FILE"
    echo "Copying from container to remote host..."
    remote_exec "docker cp $CONTAINER_NAME:$CURRENT_PATH/$CONTAINER_FILE $TEMP_PATH"

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

# Function to execute command in container
execute_container_command() {
    echo "Enter command to execute in container:"
    read COMMAND

    echo "----------------------------------------"
    echo "Executing: $COMMAND"
    echo "----------------------------------------"
    remote_exec "docker exec $CONTAINER_NAME sh -c \"cd $CURRENT_PATH && $COMMAND\""
    echo "----------------------------------------"

    read -p "Press Enter to continue..."
}

# Enhanced function to explore container filesystem with integrated file operations
explore_container_filesystem() {
    while true; do
        clear
        echo "File Explorer - Container: $CONTAINER_NAME"
        echo "Path: $CURRENT_PATH"
        echo "----------------------------------------"

        # Get current working directory in container
        CONTAINER_PWD=$(remote_exec "docker exec $CONTAINER_NAME pwd")
        echo "Container PWD: $CONTAINER_PWD"
        echo

        # List files in current directory
        echo "Directory contents:"
        remote_exec "docker exec $CONTAINER_NAME ls -la $CURRENT_PATH"
        echo

        # Check if we're in a mounted directory
        MOUNTED_PATH=$(map_container_path "$CURRENT_PATH")
        if [ -n "$MOUNTED_PATH" ]; then
            echo "Note: This directory is mounted from host at $MOUNTED_PATH"
            echo
        fi

        echo "Options:"
        echo "1) Navigate to subdirectory"
        echo "2) Go up one directory"
        echo "3) Change to specific path"
        echo "4) Show file content"
        echo "5) Copy file from local to container"
        echo "6) Copy file from container to local"
        echo "7) Execute command in container"
        echo "8) Return to main menu"
        echo
        echo -n "Choose an option: "
        read EXPLORE_OPTION

        case $EXPLORE_OPTION in
            1)
                echo "Enter subdirectory name:"
                read SUBDIR
                NEW_PATH="$CURRENT_PATH/$SUBDIR"
                # Check if directory exists
                if remote_exec "docker exec $CONTAINER_NAME [ -d $NEW_PATH ]"; then
                    CURRENT_PATH="$NEW_PATH"
                else
                    echo "Directory not found or not accessible."
                    read -p "Press Enter to continue..."
                fi
                ;;
            2)
                # Go up one directory
                CURRENT_PATH=$(dirname "$CURRENT_PATH")
                ;;
            3)
                echo "Enter absolute path:"
                read NEW_PATH
                # Check if directory exists
                if remote_exec "docker exec $CONTAINER_NAME [ -d $NEW_PATH ]"; then
                    CURRENT_PATH="$NEW_PATH"
                else
                    echo "Directory not found or not accessible."
                    read -p "Press Enter to continue..."
                fi
                ;;
            4)
                echo "Enter filename to view:"
                read FILENAME
                echo "----------------------------------------"
                echo "Content of $CURRENT_PATH/$FILENAME:"
                echo "----------------------------------------"
                remote_exec "docker exec $CONTAINER_NAME cat $CURRENT_PATH/$FILENAME"
                echo "----------------------------------------"
                read -p "Press Enter to continue..."
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
                echo "Invalid option!"
                read -p "Press Enter to continue..."
                ;;
        esac
    done
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

# Setup SSH connection
setup_ssh_connection

# Configure paths
CURRENT_PATH="/"

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
        1) explore_container_filesystem ;;
        2) change_container ;;
        3) docker_compose_status ;;
        4) docker_compose_up ;;
        5) docker_compose_down ;;
        6) docker_compose_logs ;;
        0) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option!"; read -p "Press Enter to continue..." ;;
    esac
done