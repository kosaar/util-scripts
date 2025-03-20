#!/bin/bash

# Validate input
if [ $# -ne 1 ]; then
    echo "Usage: $0 <feature_number>"
    exit 1
fi

FEATURE_NUMBER=$1
FEATURE_DIR="/opt/data/feature${FEATURE_NUMBER}"
CONTAINER_PATH="$FEATURE_DIR"
COMPOSE_FILE="$FEATURE_DIR/docker-compose.yml"

# Check if docker-compose.yml exists
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Error: docker-compose.yml not found at $COMPOSE_FILE"
    exit 1
fi

# Function to get container name from docker-compose
get_container_from_compose() {
    # Get the first service name from docker-compose.yml
    SERVICE_NAME=$(docker compose -f "$COMPOSE_FILE" config --services | head -1)

    # Get the container name for this service
    CONTAINER_NAME=$(docker compose -f "$COMPOSE_FILE" ps -q "$SERVICE_NAME")

    # If empty, try to start the service
    if [ -z "$CONTAINER_NAME" ]; then
        echo "No running container found for service $SERVICE_NAME. Starting it..."
        docker compose -f "$COMPOSE_FILE" up -d "$SERVICE_NAME"
        CONTAINER_NAME=$(docker compose -f "$COMPOSE_FILE" ps -q "$SERVICE_NAME")
    fi

    echo "$CONTAINER_NAME"
}

# Initialize container name
CONTAINER_NAME=$(get_container_from_compose)

# Function to show menu
show_menu() {
    clear
    echo "Docker File Transfer - Feature $FEATURE_NUMBER"
    echo "=========================================="
    echo "Target path: $CONTAINER_PATH"
    echo "Container: $CONTAINER_NAME"
    echo "Docker Compose file: $COMPOSE_FILE"
    echo
    echo "1) Copy file from local to container"
    echo "2) Copy file from container to local"
    echo "3) List files in container directory"
    echo "4) Change service from docker-compose"
    echo "5) View docker-compose services"
    echo "6) Start all services"
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
    docker exec $CONTAINER_NAME mkdir -p $CONTAINER_PATH

    # Get filename
    FILENAME=$(basename "$LOCAL_FILE")

    # Copy the file
    echo "Copying $LOCAL_FILE to $CONTAINER_PATH/$FILENAME..."
    docker cp "$LOCAL_FILE" "$CONTAINER_NAME:$CONTAINER_PATH/$FILENAME"

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
    docker exec $CONTAINER_NAME ls -la $CONTAINER_PATH

    echo "Enter file name to copy from container:"
    read CONTAINER_FILE

    echo "Enter local destination directory:"
    read -e LOCAL_DIR

    # Create local directory if it doesn't exist
    mkdir -p "$LOCAL_DIR"

    # Copy the file
    echo "Copying $CONTAINER_PATH/$CONTAINER_FILE to $LOCAL_DIR..."
    docker cp "$CONTAINER_NAME:$CONTAINER_PATH/$CONTAINER_FILE" "$LOCAL_DIR/"

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
    docker exec $CONTAINER_NAME ls -la $CONTAINER_PATH 2>/dev/null || echo "Directory doesn't exist or is empty."
    read -p "Press Enter to continue..."
}

# Function to change service
change_service() {
    echo "Available services in docker-compose.yml:"
    docker compose -f "$COMPOSE_FILE" config --services
    echo
    echo "Enter service name:"
    read SERVICE_NAME

    # Verify service exists
    docker compose -f "$COMPOSE_FILE" config --services | grep -q "^$SERVICE_NAME$"
    if [ $? -eq 0 ]; then
        # Get container ID for this service
        CONTAINER_ID=$(docker compose -f "$COMPOSE_FILE" ps -q "$SERVICE_NAME")

        # Start the service if not running
        if [ -z "$CONTAINER_ID" ]; then
            echo "Service not running. Starting it..."
            docker compose -f "$COMPOSE_FILE" up -d "$SERVICE_NAME"
            CONTAINER_ID=$(docker compose -f "$COMPOSE_FILE" ps -q "$SERVICE_NAME")
        fi

        CONTAINER_NAME=$CONTAINER_ID
        echo "Service changed to $SERVICE_NAME (Container ID: $CONTAINER_NAME)"
    else
        echo "Error: Service not found in docker-compose.yml!"
    fi

    read -p "Press Enter to continue..."
}

# Function to view docker-compose services
view_services() {
    echo "Services defined in docker-compose.yml:"
    echo "-------------------------------------"
    docker compose -f "$COMPOSE_FILE" ps
    read -p "Press Enter to continue..."
}

# Function to start all services
start_all_services() {
    echo "Starting all services defined in docker-compose.yml..."
    docker compose -f "$COMPOSE_FILE" up -d
    echo "Services started."
    read -p "Press Enter to continue..."
}

# Main loop
while true; do
    show_menu
    read OPTION

    case $OPTION in
        1) copy_to_container ;;
        2) copy_from_container ;;
        3) list_container_files ;;
        4) change_service ;;
        5) view_services ;;
        6) start_all_services ;;
        0) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option!"; read -p "Press Enter to continue..." ;;
    esac
done