#!/bin/bash

# GCP Cloud Run V2Ray(VLESS/Trojan) Deployment
# Modified Version: Hardcoded values and auto-generation

set -euo pipefail

# ------------------------------------------------------------------------------
# 1. GLOBAL VARIABLES & STYLES
# ------------------------------------------------------------------------------

# Colors
RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m' # Header Color
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global Configuration Variables (Defaults)
PROTOCOL=""
UUID=""
TROJAN_PASSWORD=""
TELEGRAM_DESTINATION="none"

# --- USER REQUESTED HARDCODED VALUES ---
REGION="us-central1"
CPU="2"
MEMORY="2Gi"
SERVICE_NAME="ksgcp"
HOST_DOMAIN="m.googleapis.com"
# --- END HARDCODED VALUES ---

# Protocol Specific Defaults
VLESS_PATH="/ksgcp"
TROJAN_PATH="/ksgcp"
VLESS_GRPC_SERVICE_NAME="ksgcp"

# Telegram Variables (will be set during selection)
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHANNEL_ID=""

# Emojis (will be set by show_emojis)
EMOJI_SUCCESS=""
EMOJI_WARN=""
EMOJI_ERROR=""
EMOJI_INFO=""
EMOJI_SELECT=""
EMOJI_PROC=""
EMOJI_DEPLOY=""
EMOJI_CHECK=""
EMOJI_CLEAN=""


# ------------------------------------------------------------------------------
# 2. UTILITY FUNCTIONS (LOGGING, UI, VALIDATION)
# ------------------------------------------------------------------------------

# Emoji Function
show_emojis() {
    EMOJI_SUCCESS="✅"
    EMOJI_WARN="⚠️"
    EMOJI_ERROR="❌"
    EMOJI_INFO="💡"
    EMOJI_SELECT="🎯"
    EMOJI_PROC="⚙️"
    EMOJI_DEPLOY="🚀"
    EMOJI_CHECK="📋"
    EMOJI_CLEAN="🧹"
}

# Beautiful Header/Banner
header() {
    local title="$1"
    local border_color="${ORANGE}"
    local text_color="${YELLOW}"
    
    local title_length=${#title}
    local padding=4 
    local total_width=$((title_length + padding))
    
    local top_bottom_fill=$(printf '━%.0s' $(seq 1 $((total_width - 2))))
    local top_bottom="${border_color}┏${top_bottom_fill}┓${NC}"
    local bottom_line="${border_color}┗${top_bottom_fill}┛${NC}"
    
    local title_line="${border_color}┃${NC} ${text_color}${BOLD}${title}${NC} ${border_color}┃${NC}"
    
    echo -e "${top_bottom}"
    echo -e "${title_line}"
    echo -e "${bottom_line}"
}

# Simple Logs with Emoji
log() {
    echo -e "${GREEN}${BOLD}${EMOJI_SUCCESS} [LOG]${NC} ${WHITE}$1${NC}"
}

warn() {
    echo -e "${YELLOW}${BOLD}${EMOJI_WARN} [WARN]${NC} ${WHITE}$1${NC}"
}

error() {
    echo -e "${RED}${BOLD}${EMOJI_ERROR} [ERROR]${NC} ${WHITE}$1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}${BOLD}${EMOJI_INFO} [INFO]${NC} ${WHITE}$1${NC}"
}

selected_info() {
    echo -e "${GREEN}${BOLD}${EMOJI_SELECT} Selected:${NC} ${CYAN}$1${NC}"
}

# Spinner for background processes
spinner() {
    local pid=$1
    local delay=0.1
    local spin='/-\|' 
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        local index=$((i % ${#spin}))
        echo -ne "\r${ORANGE}  [${spin:$index:1}]${NC} ${WHITE}$2...${NC}"
        sleep $delay
        i=$((i + 1))
    done
    echo -ne "\r${GREEN}  [${EMOJI_SUCCESS}]${NC} ${WHITE}$2... Done!${NC}\n"
}

# Function to validate Telegram IDs
validate_id() {
    if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
        warn "Invalid Telegram ID format. Must be a number (e.g., -1001234567890)."
        return 1
    fi
    return 0
}

# Function to validate Telegram Bot Token
validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    if [[ ! $1 =~ $token_pattern ]]; then
        warn "Invalid Telegram Bot Token format. Please try again."
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# 3. USER INPUT FUNCTIONS (SIMPLIFIED)
# ------------------------------------------------------------------------------

# A. Telegram Destination Selection (Simplified)
select_telegram_destination() {
    header "📱 Telegram Notification Settings"
    
    while true; do
        read -p "$(echo -e "${CYAN}Send link to Telegram Channel? (y/n) [n]: ${NC}")" telegram_choice
        telegram_choice=${telegram_choice:-n}
        
        case $telegram_choice in
            [Yy]*) 
                TELEGRAM_DESTINATION="channel"
                break
                ;;
            [Nn]*)
                TELEGRAM_DESTINATION="none"
                break
                ;;
            *) 
                echo -e "${RED}Invalid selection. Please enter 'y' or 'n'.${NC}"
                ;;
        esac
    done

    if [[ "$TELEGRAM_DESTINATION" == "channel" ]]; then
        echo
        while true; do
            read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
            if validate_bot_token "$TELEGRAM_BOT_TOKEN"; then break; else continue; fi
        done
        
        while true; do
            read -p "Enter Telegram Channel ID: " TELEGRAM_CHANNEL_ID
            if validate_id "$TELEGRAM_CHANNEL_ID"; then break; fi
        done

        selected_info "Bot Token: ${TELEGRAM_BOT_TOKEN:0:8}..."
        selected_info "Channel ID: $TELEGRAM_CHANNEL_ID"
    fi
    
    selected_info "Telegram Destination: $TELEGRAM_DESTINATION"
    echo
}

# B. Protocol Selection (Unchanged)
select_protocol() {
    header "🌐 V2RAY Protocol Selection"
    echo -e "${CYAN}Choose your preferred V2Ray protocol for the Cloud Run instance:${NC}"
    echo -e "${BOLD}1.${NC} VLESS-WS (VLESS + WebSocket + TLS) ${GREEN}[DEFAULT]${NC}"
    echo -e "${BOLD}2.${NC} VLESS-gRPC (VLESS + gRPC + TLS)"
    echo -e "${BOLD}3.${NC} Trojan-WS (Trojan + WebSocket + TLS)"
    echo
    
    while true; do
        read -p "Select V2Ray Protocol (1): " protocol_choice
        protocol_choice=${protocol_choice:-1}
        case $protocol_choice in
            1) PROTOCOL="VLESS-WS"; break ;;
            2) PROTOCOL="VLESS-gRPC"; break ;;
            3) PROTOCOL="Trojan-WS"; break ;;
            *) echo -e "${RED}Invalid selection. Please enter a number between 1-3.${NC}" ;;
        esac
    done
    
    selected_info "Protocol: $PROTOCOL"
    echo
}

# C. Region Selection (REMOVED)
# D. CPU Configuration (REMOVED)
# E. Memory Configuration (REMOVED)
# F. Service Name Configuration (REMOVED)
# G. Host Domain Configuration (REMOVED)

# H. UUID/Password Configuration (CHANGED TO AUTO-GENERATION)
generate_credentials() {
    header "🔑 Auto-Generating Credentials"
    
    if [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        # Auto-generate a 16-char password
        if command -v openssl &> /dev/null; then
            TROJAN_PASSWORD=$(openssl rand -hex 8)
        else
            # Fallback for systems without openssl
            TROJAN_PASSWORD=$(cat /proc/sys/kernel/random/uuid | cut -c -16)
        fi
        log "Generated Trojan Password: $TROJAN_PASSWORD"
        
    else
        # Auto-generate UUID
        if command -v uuidgen &> /dev/null; then
            UUID=$(uuidgen)
        else
            UUID=$(cat /proc/sys/kernel/random/uuid)
        fi
        log "Generated UUID: $UUID"
        
        # VLESS-gRPC ServiceName will use default "ahlflk"
        if [[ "$PROTOCOL" == "VLESS-gRPC" ]]; then
            log "Using default gRPC ServiceName: $VLESS_GRPC_SERVICE_NAME"
        fi
    fi
    echo
}

# I. Summary and Confirmation (CHANGED TO SUMMARY ONLY)
show_config_summary() {
    header "${EMOJI_CHECK} Configuration Summary"
    echo -e "${CYAN}${BOLD}Project ID:${NC}    $(gcloud config get-value project)"
    echo -e "${CYAN}${BOLD}Protocol:${NC}      $PROTOCOL"
    echo -e "${CYAN}${BOLD}Region:${NC}        $REGION (Fixed)"
    echo -e "${CYAN}${BOLD}Service Name:${NC}  $SERVICE_NAME (Fixed)"
    echo -e "${CYAN}${BOLD}Host Domain:${NC}   $HOST_DOMAIN (Fixed)"
    
    if [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        echo -e "${CYAN}${BOLD}Password:${NC}      ${TROJAN_PASSWORD} (Auto-Generated)"
        echo -e "${CYAN}${BOLD}Path:${NC}          $TROJAN_PATH (Default)"
    elif [[ "$PROTOCOL" == "VLESS-gRPC" ]]; then
        echo -e "${CYAN}${BOLD}UUID:${NC}          $UUID (Auto-Generated)"
        echo -e "${CYAN}${BOLD}ServiceName:${NC}   $VLESS_GRPC_SERVICE_NAME (Default)"
    else
        echo -e "${CYAN}${BOLD}UUID:${NC}          $UUID (Auto-Generated)"
        echo -e "${CYAN}${BOLD}Path:${NC}          $VLESS_PATH (Default)"
    fi
    
    echo -e "${CYAN}${BOLD}CPU/Memory:${NC}    $CPU core(s) / $MEMORY (Fixed)"
    
    if [[ "$TELEGRAM_DESTINATION" == "channel" ]]; then
        echo -e "${CYAN}${BOLD}Telegram:${NC}      Send to Channel (Token: ${TELEGRAM_BOT_TOKEN:0:8}...)"
    else
        echo -e "${CYAN}${BOLD}Telegram:${NC}      Not configured"
    fi
    echo
    
    info "Proceeding with deployment automatically..."
    echo
}


# ------------------------------------------------------------------------------
# 4. CORE DEPLOYMENT FUNCTIONS (Unchanged from previous full script)
# ------------------------------------------------------------------------------

# Config File Preparation
prepare_config_files() {
    log "Preparing Xray config file based on $PROTOCOL..."
    
    if [[ ! -f "config.json" ]]; then
        error "config.json not found in current directory. Please create it first."
        return 1
    fi
    
    case $PROTOCOL in
        "VLESS-WS")
            sed -i "s/PLACEHOLDER_UUID/$UUID/g" config.json
            sed -i "s|/vless|$VLESS_PATH|g" config.json
            ;;
            
        "VLESS-gRPC")
            sed -i "s/PLACEHOLDER_UUID/$UUID/g" config.json
            sed -i "s|\"network\": \"ws\"|\"network\": \"grpc\"|g" config.json
            sed -i "s|\"wsSettings\": { \"path\": \"/vless\" }|\"grpcSettings\": { \"serviceName\": \"$VLESS_GRPC_SERVICE_NAME\" }|g" config.json
            ;;
            
        "Trojan-WS")
            sed -i 's|"protocol": "vless"|"protocol": "trojan"|g' config.json
            sed -i "s|\"clients\": \[ { \"id\": \"PLACEHOLDER_UUID\" } ]|\"users\": \[ { \"password\": \"$TROJAN_PASSWORD\" } ]|g" config.json
            sed -i "s|\"path\": \"/vless\"|\"path\": \"$TROJAN_PATH\"|g" config.json
            ;;
            
        *)
            error "Unknown protocol: $PROTOCOL. Cannot prepare config."
            ;;
    esac
    
    log "config.json prepared successfully."
}

# GCP Deployment
deploy_service() {
    header "${EMOJI_DEPLOY} Starting Deployment"
    info "This may take 3-5 minutes..."
    
    # This assumes a Dockerfile exists in the current directory (.)
    (
        gcloud run deploy "$SERVICE_NAME" \
            --source . \
            --region "$REGION" \
            --cpu "$CPU" \
            --memory "$MEMORY" \
            --allow-unauthenticated \
            --min-instances 0 \
            --max-instances 2 \
            --port 8080 \
            --timeout=300s \
            --quiet
    ) &> "deploy_log.txt" &
    
    local deploy_pid=$!
    spinner $deploy_pid "Deploying $SERVICE_NAME to $REGION"
    
    if ! wait $deploy_pid; then
        error "Deployment failed. Check 'deploy_log.txt' for details."
    fi
    
    log "Deployment successful."
    rm -f deploy_log.txt
}

# Get Deployed Service URL
get_service_url() {
    log "Fetching service URL..."
    local url
    url=$(gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format 'value(status.url)')
    
    if [[ -z "$url" ]]; then
        error "Could not retrieve service URL."
    fi
    
    # Remove https:// from the URL
    echo "${url#https://}"
}


# Share Link Creation
create_share_link() {
    local SERVICE_NAME="$1"
    local DOMAIN="$2"
    local UUID_OR_PASSWORD="$3"
    local PROTOCOL_TYPE="$4"
    local LINK=""
    
    local PATH_ENCODED
    if [[ "$PROTOCOL_TYPE" == "VLESS-gRPC" ]]; {
        PATH_ENCODED=$(echo "$VLESS_GRPC_SERVICE_NAME" | sed 's/\//%2F/g')
    } else {
        PATH_ENCODED=$(echo "${VLESS_PATH:-$TROJAN_PATH}" | sed 's/\//%2F/g')
    }
    
    local HOST_ENCODED=$(echo "$HOST_DOMAIN" | sed 's/\./%2E/g')
    
    case $PROTOCOL_TYPE in
        "VLESS-WS")
            LINK="vless://${UUID_OR_PASSWORD}@${HOST_DOMAIN}:443?path=${PATH_ENCODED}&security=tls&encryption=none&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#${SERVICE_NAME}_VLESS-WS"
            ;;
            
        "VLESS-gRPC")
            LINK="vless://${UUID_OR_PASSWORD}@${HOST_DOMAIN}:443?security=tls&encryption=none&host=${DOMAIN}&fp=randomized&type=grpc&serviceName=${PATH_ENCODED}&sni=${DOMAIN}#${SERVICE_NAME}_VLESS-gRPC"
            ;;
            
        "Trojan-WS")
            LINK="trojan://${UUID_OR_PASSWORD}@${HOST_DOMAIN}:443?path=${PATH_ENCODED}&security=tls&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#${SERVICE_NAME}_Trojan-WS"
            ;;
    esac
    
    echo "$LINK"
}

# Telegram Notification Function
send_to_telegram() {
    local chat_id="$1"
    local text_message="$2"

    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    
    # Run in background to avoid blocking script
    (
        curl -s -X POST "$url" \
            --data-urlencode "chat_id=${chat_id}" \
            --data-urlencode "text=${text_message}" \
            --data-urlencode "disable_web_page_preview=true"
    ) &> /dev/null
}

# ------------------------------------------------------------------------------
# 5. MAIN EXECUTION (Updated)
# ------------------------------------------------------------------------------
main() {
    # 1. Setup
    show_emojis
    
    # 2. Collect user inputs (Simplified)
    select_telegram_destination
    select_protocol
    
    # 3. Auto-generate credentials
    generate_credentials
    
    # 4. Show summary (no confirmation)
    show_config_summary
    
    # 5. Prepare local config.json
    prepare_config_files
    
    # 6. Deploy
    deploy_service
    
    # 7. Get deployed URL
    local service_domain
    service_domain=$(get_service_url)
    log "Service URL: https://${service_domain}"
    
    # 8. Create Share Link
    local uuid_or_pass
    if [[ "$PROTOCOL" == "Trojan-WS" ]]; then
        uuid_or_pass="$TROJAN_PASSWORD"
    else
        uuid_or_pass="$UUID"
    fi
    
    local share_link
    share_link=$(create_share_link "$SERVICE_NAME" "$service_domain" "$uuid_or_pass" "$PROTOCOL")
    
    header "${EMOJI_SUCCESS} Deployment Complete"
    echo -e "${WHITE}${BOLD}Your V2Ray Share Link:${NC}"
    echo -e "${CYAN}${share_link}${NC}"
    echo
    
    # 9. Send to Telegram (Simplified logic)
    if [[ "$TELEGRAM_DESTINATION" == "channel" ]]; then
        log "Sending link to Telegram Channel..."
        
        local message_header="✅ Deployment Successful: $SERVICE_NAME ($PROTOCOL)"
        local final_message="$message_header
Host: $service_domain

Link:
$share_link"
        
        send_to_telegram "$TELEGRAM_CHANNEL_ID" "$final_message"
        log "Telegram notification sent."
    fi
}

# --- START SCRIPT ---
main
