#!/bin/bash

# Configuration
CONFIG_FILE="$HOME/.ssh_tunnel_manager.conf"
TUNNEL_DIR="$HOME/.ssh_tunnels"
LOG_FILE="$HOME/.ssh_tunnel_manager.log"

# Application definitions with remote host and port
declare -A APPS=(
    ["app1"]="app1-host.example.com:3000"
    ["app2"]="app2-host.example.com:3001"
    ["app3"]="app3-host.example.com:3002"
    ["app4"]="app4-host.example.com:3003"
    ["app5"]="app5-host.example.com:3004"
    ["app6"]="app6-host.example.com:3005"
    ["app7"]="app7-host.example.com:3006"
    ["app8"]="app8-host.example.com:3007"
)

# Minimum and maximum local port range
MIN_PORT=49152
MAX_PORT=65535

# Create necessary directories and files
setup() {
    mkdir -p "$TUNNEL_DIR"
    touch "$LOG_FILE"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "SSH_USER=remote_user" > "$CONFIG_FILE"
    fi
}

# Load configuration
load_config() {
    source "$CONFIG_FILE"
}

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "$1"
}

# Find a free local port
find_free_port() {
    local port
    while true; do
        # Generate random port number within range
        port=$(shuf -i $MIN_PORT-$MAX_PORT -n 1)
        # Check if port is in use
        if ! netstat -tuln | grep -q ":$port "; then
            echo "$port"
            return 0
        fi
    done
}

# Create a new SSH tunnel
create_tunnel() {
    local app=$1
    
    if [[ -z "${APPS[$app]}" ]]; then
        log "Error: Application '$app' not found"
        return 1
    fi
    
    # Get remote host and port from APPS configuration
    IFS=':' read -r remote_host remote_port <<< "${APPS[$app]}"
    
    # Find a free local port
    local local_port=$(find_free_port)
    
    local tunnel_id="$app-$local_port-$(date +%s)"
    local pid_file="$TUNNEL_DIR/$tunnel_id.pid"
    
    # Create SSH tunnel
    ssh -f -N -L "$local_port:$remote_host:$remote_port" "$SSH_USER@$remote_host" -o ExitOnForwardFailure=yes
    local ssh_pid=$!
    
    if [[ $? -eq 0 ]]; then
        echo "$ssh_pid" > "$pid_file"
        echo "$app:$local_port:$remote_host:$remote_port:$ssh_pid" >> "$TUNNEL_DIR/active_tunnels"
        log "Created tunnel for $app"
        echo "Success! Access $app via localhost:$local_port (remote: $remote_host:$remote_port, PID: $ssh_pid)"
    else
        log "Failed to create tunnel for $app"
        return 1
    fi
}

# List all active tunnels
list_tunnels() {
    echo "Active SSH Tunnels:"
    echo "----------------------------------------------------------------"
    echo "APP      LOCAL    REMOTE HOST            REMOTE PORT    PID    STATUS"
    echo "----------------------------------------------------------------"
    
    if [[ -f "$TUNNEL_DIR/active_tunnels" ]]; then
        while IFS=: read -r app local remote_host remote_port pid; do
            if kill -0 "$pid" 2>/dev/null; then
                status="RUNNING"
            else
                status="DEAD"
            fi
            printf "%-8s %-8s %-21s %-13s %-7s %s\n" "$app" "$local" "$remote_host" "$remote_port" "$pid" "$status"
        done < "$TUNNEL_DIR/active_tunnels"
    fi
}

# Delete a specific tunnel
delete_tunnel() {
    local pid=$1
    
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        log "Terminated tunnel with PID: $pid"
        
        # Remove from active tunnels file
        sed -i "/:$pid$/d" "$TUNNEL_DIR/active_tunnels"
        rm -f "$TUNNEL_DIR/*-$pid.pid"
    else
        log "No active tunnel found with PID: $pid"
        return 1
    fi
}

# Delete all tunnels for a specific application
delete_app_tunnels() {
    local app=$1
    
    if [[ -f "$TUNNEL_DIR/active_tunnels" ]]; then
        while IFS=: read -r tunnel_app local remote_host remote_port pid; do
            if [[ "$tunnel_app" == "$app" ]]; then
                delete_tunnel "$pid"
            fi
        done < "$TUNNEL_DIR/active_tunnels"
    fi
}

# Clean up dead tunnels
cleanup() {
    if [[ -f "$TUNNEL_DIR/active_tunnels" ]]; then
        while IFS=: read -r app local remote_host remote_port pid; do
            if ! kill -0 "$pid" 2>/dev/null; then
                sed -i "/:$pid$/d" "$TUNNEL_DIR/active_tunnels"
                rm -f "$TUNNEL_DIR/*-$pid.pid"
                log "Cleaned up dead tunnel: $app (PID: $pid)"
            fi
        done < "$TUNNEL_DIR/active_tunnels"
    fi
}

# Show information about available applications
show_apps() {
    echo "Available applications:"
    echo "----------------------------------------"
    echo "APP      REMOTE HOST            PORT"
    echo "----------------------------------------"
    for app in "${!APPS[@]}"; do
        IFS=':' read -r host port <<< "${APPS[$app]}"
        printf "%-8s %-21s %s\n" "$app" "$host" "$port"
    done
}

# Show usage information
usage() {
    echo "Usage: $0 <command> [arguments]"
    echo
    echo "Commands:"
    echo "  create <app>              Create a new SSH tunnel (auto-assigns local port)"
    echo "  list                      List all active tunnels"
    echo "  delete <pid>              Delete a specific tunnel by PID"
    echo "  delete-app <app>          Delete all tunnels for an application"
    echo "  cleanup                   Clean up dead tunnels"
    echo "  apps                      List available applications"
    echo
    echo "Configuration:"
    echo "  - Edit $CONFIG_FILE to set SSH user"
    echo "  - Edit script APPS array to configure applications"
    show_apps
}

# Main script execution
setup
load_config

case "$1" in
    create)
        if [[ -z "$2" ]]; then
            usage
            exit 1
        fi
        create_tunnel "$2"
        ;;
    list)
        list_tunnels
        ;;
    delete)
        if [[ -z "$2" ]]; then
            usage
            exit 1
        fi
        delete_tunnel "$2"
        ;;
    delete-app)
        if [[ -z "$2" ]]; then
            usage
            exit 1
        fi
        delete_app_tunnels "$2"
        ;;
    cleanup)
        cleanup
        ;;
    apps)
        show_apps
        ;;
    *)
        usage
        exit 1
        ;;
esac
