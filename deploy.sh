#!/bin/bash

#-------------------------------------------------------------------
# GCP Cloud Run (gRPC + REALITY) Auto-Deploy Script
#
# This script is simplified and hardcoded for a specific setup.
# It deploys a Vless (gRPC + REALITY) service using fixed
# configuration values.
#-------------------------------------------------------------------

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Logging Functions ---
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}
error() {
    echo -e "${RED}[ERROR]${NC} $1"
}
info() {
    echo -e "${BLUE}‣${NC} $1"
}

# --- Hardcoded Configuration ---
readonly SERVICE_NAME="ksgcp"
readonly REGION="us-central1"
readonly CPU="2"
readonly MEMORY="2Gi"
readonly REPO_URL="https://github.com/gcp0xop/gcphop.git"
readonly REPO_DIR="gcphop"

# --- gRPC + REALITY Hardcoded Test Config ---
# WARNING: These are public test keys. Do not use for production.
readonly UUID="ba0e3984-ccc9-48a3-8074-b2f507f41ce8"
readonly GRPC_SERVICE_NAME="gprc-vless"
readonly REALITY_PUBLIC_KEY="qYq9y1aL9m/nOiFqjVq31Lw+K/1QGhAawIe7iWqP1XA="
readonly REALITY_SNI="www.google.com"

# --- Function to validate Telegram Bot Token ---
validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    if [[ ! $1 =~ $token_pattern ]]; then
        error "Invalid Telegram Bot Token format"
        return 1
    fi
    return 0
}

# --- Function to validate Channel ID ---
validate_channel_id() {
    if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
        error "Invalid Channel ID format"
        return 1
    fi
    return 0
}

# --- Function to get required user input (Telegram only) ---
get_user_input() {
    echo
    info "=== Telegram Configuration (Channel Only) ==="
    
    while true; do
        read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
        if validate_bot_token "$TELEGRAM_BOT_TOKEN"; then
            break
        fi
    done
    
    while true; do
        read -p "Enter Telegram Channel ID (must start with -): " TELEGRAM_CHANNEL_ID
        if validate_channel_id "$TELEGRAM_CHANNEL_ID"; then
            break
        fi
    done
}

# --- Validation functions ---
validate_prerequisites() {
    log "Validating prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    if ! command -v git &> /dev/null; then
        error "git is not installed. Please install git."
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq (e.g., sudo apt install jq)."
        error "jq is required for URL encoding."
        exit 1
    fi
    
    local PROJECT_ID=$(gcloud config get-value project)
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
        error "No project configured. Run: gcloud config set project PROJECT_ID"
        exit 1
    fi
}

# --- Cleanup function ---
cleanup() {
    log "Cleaning up temporary directory: ${REPO_DIR}"
    if [[ -d "${REPO_DIR}" ]]; then
        rm -rf "${REPO_DIR}"
    fi
}

# --- Telegram Sender ---
send_to_telegram() {
    local chat_id="$1"
    local message="$2"
    local response
    
    response=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"${chat_id}\",
            \"text\": \"$message\",
            \"parse_mode\": \"HTML\",
            \"disable_web_page_preview\": true
        }" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage")
    
    local http_code="${response: -3}"
    local content="${response%???}"
    
    if [[ "$http_code" == "200" ]]; then
        log "✅ Successfully sent to Telegram Channel"
    else
        error "❌ Failed to send to Telegram (HTTP $http_code): $content"
        warn "Please check your Bot Token and Channel ID."
    fi
}

# --- Main Deployment Function ---
main() {
    echo -e "${CYAN}"
    echo "==================================================="
    echo "  GCP Vless (gRPC + REALITY) Deployment Script   "
    echo "==================================================="
    echo -e "${NC}"
    
    # Get Telegram credentials
    get_user_input
    
    PROJECT_ID=$(gcloud config get-value project)
    IMAGE_NAME="gcr.io/${PROJECT_ID}/gcphop-vless-image"
    
    # Display hardcoded summary
    echo
    info "=== Deployment Configuration ==="
    info "Project ID:    ${PROJECT_ID}"
    info "Service Name:  ${SERVICE_NAME}"
    info "Region:        ${REGION}"
    info "CPU / Memory:  ${CPU} CPU / ${MEMORY} RAM"
    info "Protocol:      gRPC + REALITY"
    info "Repository:    ${REPO_URL}"
    info "Telegram:      Sending to Channel (${TELEGRAM_CHANNEL_ID})"
    echo
    
    while true; do
        read -p "Proceed with deployment? (y/n): " confirm
        case $confirm in
            [Yy]* ) break;;
            [Nn]* ) 
                info "Deployment cancelled by user"
                exit 0
                ;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
    
    log "Starting deployment..."
    
    validate_prerequisites
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    log "Enabling required APIs (run, cloudbuild)..."
    gcloud services enable \
        cloudbuild.googleapis.com \
        run.googleapis.com \
        --quiet
    
    # Clean up any existing directory
    cleanup
    
    log "Cloning repository: ${REPO_URL}"
    if ! git clone "${REPO_URL}"; then
        error "Failed to clone repository"
        exit 1
    fi
    
    cd "${REPO_DIR}"
    
    log "Building container image: ${IMAGE_NAME}"
    if ! gcloud builds submit --tag "${IMAGE_NAME}" --quiet; then
        error "Build failed"
        exit 1
    fi
    
    log "Deploying to Cloud Run: ${SERVICE_NAME}"
    if ! gcloud run deploy ${SERVICE_NAME} \
        --image "${IMAGE_NAME}" \
        --platform managed \
        --region ${REGION} \
        --allow-unauthenticated \
        --cpu ${CPU} \
        --memory ${MEMORY} \
        --use-http2 \
        --quiet; then
        error "Deployment failed"
        exit 1
    fi
    
    # Get the service URL
    SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
        --region ${REGION} \
        --format 'value(status.url)' \
        --quiet)
    
    DOMAIN=$(echo $SERVICE_URL | sed 's|https://||')
    
    log "Deployment successful. Service URL: ${SERVICE_URL}"
    
    # --- Vless Link and Message Generation ---
    
    # URL Encode the gRPC serviceName
    ENCODED_SERVICE_NAME=$(printf %s "$GRPC_SERVICE_NAME" | jq -sRr @uri)
    
    # Create Vless (gRPC + REALITY) share link
    URI="vless://${UUID}@${DOMAIN}:443?encryption=none&security=reality&sni=${REALITY_SNI}&fp=chrome&publicKey=${REALITY_PUBLIC_KEY}&type=grpc&serviceName=${ENCODED_SERVICE_NAME}#${SERVICE_NAME}"
    
    # Get expiration date (30 days from now)
    # Check for GNU date (Linux) vs BSD date (macOS)
    if date --version >/dev/null 2>&1; then
      END_LOCAL=$(date -d "+30 days" +"%Y-%m-%d %H:%M:%S")
    else
      END_LOCAL=$(date -v+30d +"%Y-%m-%d %H:%M:%S")
    fi
    
    # Create Telegram message (HTML format)
    MSG=$(cat <<EOF
<blockquote>GCP V2RAY KEY
</blockquote>
<blockquote>Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်
</blockquote>

<pre><code>${URI}</code></pre>

<blockquote>⏳ End: <code>${END_LOCAL}</code></blockquote>
EOF
)

    # Create console message
    CONSOLE_MESSAGE="GCP V2Ray (gRPC) Deployment → Successful ✅
━━━━━━━━━━━━━━━━━━━━
Service: ${SERVICE_NAME}
Region:  ${REGION}
Domain:  ${DOMAIN}
Ends:    ${END_LOCAL}

🔗 V2Ray Configuration Link:
${URI}
━━━━━━━━━━━━━━━━━━━━"
    
    # Save to file
    echo "$CONSOLE_MESSAGE" > deployment-info-grpc.txt
    log "Configuration saved to deployment-info-grpc.txt"
    
    # Display locally
    echo
    echo -e "${CYAN}=== Deployment Information ===${NC}"
    echo "$CONSOLE_MESSAGE"
    echo
    
    # Send to Telegram
    log "Sending deployment info to Telegram Channel..."
    send_to_telegram "$TELEGRAM_CHANNEL_ID" "$MSG"
    
    log "All done!"
}

# Run main function
main "$@"

