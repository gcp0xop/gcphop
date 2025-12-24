#!/bin/bash

# =================== Colors & Style ===================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
RESET='\033[0m'
BOLD='\033[1m'

clear
printf "\n${CYAN}╔════════════════════════════════════════════╗${RESET}"
printf "\n${CYAN}║    ${RED}🚀 ALPHA${YELLOW}0x1 ${BLUE}HYBRID BEAST (gRPC Edition)${CYAN}   ║${RESET}"
printf "\n${CYAN}╚════════════════════════════════════════════╝${RESET}\n"

# =================== 1. Setup & Checks ===================
if [[ -f .env ]]; then source ./.env; fi

# Check Telegram Creds
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then
    printf " ${CYAN}💎 Bot Token:${RESET} "
    read -r TELEGRAM_TOKEN
fi
if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then
    printf " ${CYAN}💎 Chat ID:${RESET} "
    read -r TELEGRAM_CHAT_IDS
fi

# =================== 2. Configuration ===================
SERVER_NAME="Alpha-GCP-$(date +%s | tail -c 4)"
UUID=$(cat /proc/sys/kernel/random/uuid)
SERVICE_NAME="alpha-gcp"  # Cloud Run name must be lowercase
REGION="us-central1"
# Using Xray for better gRPC performance
IMAGE="ghcr.io/teddysun/xray:latest" 
SERVICE_PATH="gun" # gRPC Service Name

# =================== 3. Dynamic Config Generation ===================
# Cloud Run ပေါ်မှာ Config file တင်ရခက်လို့ Command line ကနေ Config ကို လှမ်းရေးပါမယ်။
# gRPC အတွက် အထူးသန့်စင်ထားသော Config ဖြစ်ပါတယ်။

CONFIG_JSON=$(cat <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "level": 0,
            "email": "alpha0x1@req"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "${SERVICE_PATH}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
)

# Minify JSON carefully (fail-safe if jq is missing)
if command -v jq &> /dev/null; then
    CONFIG_JSON=$(echo "$CONFIG_JSON" | jq -c .)
else
    CONFIG_JSON=$(echo "$CONFIG_JSON" | tr -d '\n' | tr -d ' ')
fi

# =================== 4. Deployment ===================
echo -e "\n${YELLOW}➤ Deploying High-Performance gRPC Core...${RESET}"
echo -e "${BLUE}  • CPU: 4 vCPU | RAM: 4Gi${RESET}"
echo -e "${BLUE}  • Protocol: VLESS + gRPC (HTTP/2)${RESET}"

# Deploy Command
gcloud run deploy "$SERVICE_NAME" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="4Gi" \
  --cpu="4" \
  --timeout="3600" \
  --allow-unauthenticated \
  --use-http2 \
  --no-cpu-throttling \
  --concurrency=300 \
  --min-instances=1 \
  --max-instances=2 \
  --port=8080 \
  --command="/bin/sh" \
  --args="-c,echo '$CONFIG_JSON' > /etc/xray/config.json && /usr/bin/xray -config /etc/xray/config.json" \
  --quiet > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✔ Core deployed successfully!${RESET}"
else
    echo -e "${RED}✖ Deployment failed! Check logs below:${RESET}"
    # Show logs if failed to understand why
    echo -e "${YELLOW}Possible reasons: Quota exceeded, Service name conflict, or Permissions.${RESET}"
    gcloud run services describe "$SERVICE_NAME" --region "$REGION"
    exit 1
fi

# =================== 5. Finalizing ===================
echo -e "${YELLOW}➤ Optimizing Network Route...${RESET}"

# Get URL
URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}

if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}✖ Error: Could not retrieve URL. Deployment might have failed silently.${RESET}"
    exit 1
fi

# =================== 6. Link Generation & Notification ===================
echo -e "${YELLOW}➤ Generating Connection Keys...${RESET}"

# VLESS gRPC Link Format
VLESS_LINK="vless://${UUID}@${DOMAIN}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${SERVICE_PATH}&sni=${DOMAIN}#${SERVER_NAME}"

export TZ="Asia/Yangon"
START_LOCAL="$(date +'%d/%m %I:%M %p')"
END_LOCAL="$(date -d '+4 hours' +'%d/%m %I:%M %p')"

# ⚠️ FIXED: Changed ${URI} to ${VLESS_LINK} below
MSG="<blockquote>🚀 ${SERVER_NAME} V2RAY SERVICE</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<pre><code>${VLESS_LINK}</code></pre>

<blockquote>✅ စတင်ချိန်: <code>${START_LOCAL}</code></blockquote>
<blockquote>⏳ပြီးဆုံးအချိန်: <code>${END_LOCAL}</code></blockquote>"

# Send to Telegram
if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_IDS" ]]; then
    echo -e "${CYAN}➤ Sending to Telegram...${RESET}"
    IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
    for chat_id in "${CHAT_ID_ARR[@]}"; do
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d "chat_id=${chat_id}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=${MSG}" > /dev/null
        echo -e "${GREEN}  ➜ Sent to: ${chat_id}${RESET}"
    done
else
    echo -e "${RED}✖ No Telegram Token found. Printing Link below:${RESET}"
    echo -e "${VLESS_LINK}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}║      ✅ DEPLOYMENT COMPLETE & LIVE!        ║${RESET}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${RESET}"
