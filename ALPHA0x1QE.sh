#!/bin/bash

# =================== UI Colors ===================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
RESET='\033[0m'
BOLD='\033[1m'

clear
printf "\n${RED}${BOLD}🚀 ALPHA${YELLOW}0x1 ${RED}QUANTUM ${PURPLE}(${CYAN}Beyond Limits${PURPLE})${RESET}\n"
echo "----------------------------------------"

# =================== 1. Setup ===================
if [[ -f .env ]]; then source ./.env; fi

if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then 
  read -p "💎 Bot Token: " TELEGRAM_TOKEN
fi

if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then 
  read -p "💎 Chat ID:   " TELEGRAM_CHAT_IDS
fi

# =================== 2. Configuration ===================
SERVER_NAME="Alpha0x1-$(date +%s | tail -c 4)"
GEN_UUID=$(cat /proc/sys/kernel/random/uuid)
SERVICE_NAME="alpha0x1"
REGION="us-central1"
IMAGE="a0x1/al0x1"

# =================== 3. Deploying (QUANTUM MODE) ===================
echo ""
echo -e "${YELLOW}➤ Injecting Quantum Parameters...${RESET}"

# Enable API quietly
gcloud services enable run.googleapis.com --quiet >/dev/null 2>&1

# Deploy Command (THE ABSOLUTE LIMIT)
# 🔥 New Secret 1: V2RAY_CONF_GEOLOADER (Speed up geo-routing)
# 🔥 New Secret 2: ASYNC_IO_ENABLE=true (Non-blocking I/O for max speed)
# 🔥 New Secret 3: XRAY_TRANSPORT_GRPC_PERMIT_WITHOUT_STREAM=true (Hardcore gRPC Tweak)

gcloud run deploy "$SERVICE_NAME" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="4Gi" \
  --cpu="4" \
  --timeout="3600" \
  --no-allow-unauthenticated \
  --use-http2 \
  --no-cpu-throttling \
  --execution-environment=gen2 \
  --concurrency=500 \
  --session-affinity \
  --set-env-vars UUID="${GEN_UUID}",GOMAXPROCS="4",GOMEMLIMIT="3600MiB",GOGC="50",GODEBUG="madvdontneed=1,netdns=go",XRAY_TRANSPORT_GRPC_KEEPALIVE="20",TZ="Asia/Yangon",V2RAY_BUF_READ_SIZE="16",V2RAY_BUF_WRITE_SIZE="16",ASYNC_IO_ENABLE="true",XRAY_TRANSPORT_GRPC_PERMIT_WITHOUT_STREAM="true" \
  --port="8080" \
  --min-instances=1 \
  --max-instances=2 \
  --quiet

# Force Public Access
echo -e "${YELLOW}➤ Unlocking Access...${RESET}"
gcloud run services add-iam-policy-binding "$SERVICE_NAME" \
  --region="$REGION" \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --quiet >/dev/null 2>&1

# Traffic Optimization
echo -e "${YELLOW}➤ Quantum Routing Optimization...${RESET}"
gcloud run services update-traffic "$SERVICE_NAME" --to-latest --region="$REGION" --quiet >/dev/null 2>&1

# Get URL
URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}
curl -s -o /dev/null "https://${DOMAIN}"

# =================== 4. Notification ===================
echo -e "${YELLOW}➤ Sending Key...${RESET}"

URI="vless://${GEN_UUID}@m.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=Tg-@Alpha0x1&sni=${DOMAIN}#${SERVER_NAME}"

export TZ="Asia/Yangon"
START_LOCAL="$(date +'%d.%m.%Y %I:%M %p')"
END_LOCAL="$(date -d '+5 hours 10 minutes' +'%d.%m.%Y %I:%M %p')"

MSG="<blockquote>🚀 ${SERVER_NAME} GCP V2RAY SERVICE</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡 Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
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
echo -e "${GREEN}✅ SYSTEM OVERCLOCKED & ONLINE.${RESET}"
