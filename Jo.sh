#!/bin/bash

# =================== Colors ===================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

clear
printf "\n${RED}🚀 ALPHA${YELLOW}0x1 ${GREEN}gRPC FIX${RESET}\n"
echo "----------------------------------------"

# =================== 1. Setup ===================
if [[ -f .env ]]; then source ./.env; fi

if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then 
  read -p "💎 Bot Token: " TELEGRAM_TOKEN
fi

if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then 
  read -p "💎 Chat ID:   " TELEGRAM_CHAT_IDS
fi

# =================== 2. Config ===================
SERVER_NAME="Alpha0x1-$(date +%s | tail -c 4)"
GEN_UUID=$(cat /proc/sys/kernel/random/uuid)
SERVICE_NAME="alpha0x1"
REGION="us-central1"
IMAGE="a0x1/al0x1"

# =================== 3. Deploying ===================
echo ""
echo -e "${YELLOW}➤ Deploying gRPC Server (Correction)...${RESET}"

# 🔥 FIX: Added --use-http2 (Essential for gRPC)
gcloud run deploy "$SERVICE_NAME" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="4Gi" \
  --cpu="4" \
  --timeout="3600" \
  --allow-unauthenticated \
  --use-http2 \
  --set-env-vars UUID="${GEN_UUID}" \
  --port="8080" \
  --min-instances=1 \
  --max-instances=2 \
  --quiet

# Traffic Force
gcloud run services update-traffic "$SERVICE_NAME" --to-latest --region="$REGION" --quiet >/dev/null 2>&1

# Get URL
URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}

# =================== 4. Notification ===================
echo -e "${YELLOW}➤ Sending Keys...${RESET}"

# Link format verified for gRPC
URI="vless://${GEN_UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=Tg-@Alpha0x1&sni=${DOMAIN}#${SERVER_NAME}"

export TZ="Asia/Yangon"
START_LOCAL="$(date +'%d.%m.%Y %I:%M %p')"
END_LOCAL="$(date -d '+5 hours 10 minutes' +'%d.%m.%Y %I:%M %p')"

MSG="<blockquote>🚀 ${SERVER_NAME} V2RAY SERVICE</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<pre><code>${URI}</code></pre>
<blockquote>✅ စတင်ချိန်: <code>${START_LOCAL}</code></blockquote>
<blockquote>⏳ပြီးဆုံးအချိန်: <code>${END_LOCAL}</code></blockquote>"

if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_IDS" ]]; then
  IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
  for chat_id in "${CHAT_ID_ARR[@]}"; do
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${chat_id}" \
      -d "parse_mode=HTML" \
      --data-urlencode "text=${MSG}" > /dev/null
    echo -e "${GREEN}✔ Sent to ID: ${chat_id}${RESET}"
  done
else
  echo "No Token found."
fi

echo ""
echo -e "${GREEN}✅ DEPLOYMENT SUCCESSFUL!${RESET}"
