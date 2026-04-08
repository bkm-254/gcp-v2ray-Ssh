#!/usr/bin/env bash
set -euo pipefail

if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & error handler =====
LOG_FILE="/tmp/fnet_ssh_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO" | tee -a "$LOG_FILE" >&2
  exit $rc
}
trap on_err ERR

# =================== FNET VPN Custom UI ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'
  C_FNET_RED=$'\e[38;5;196m'; C_FNET_BLUE=$'\e[38;5;39m'; C_FNET_GREEN=$'\e[38;5;46m'     
  C_FNET_YELLOW=$'\e[38;5;226m'; C_FNET_PURPLE=$'\e[38;5;93m'; C_FNET_GRAY=$'\e[38;5;214m'     
  C_FNET_CYAN=$'\e[38;5;51m'      
else
  RESET= BOLD= C_FNET_RED= C_FNET_BLUE= C_FNET_GREEN= C_FNET_YELLOW= C_FNET_PURPLE= C_FNET_GRAY= C_FNET_CYAN=
fi

show_fnet_banner() {
  clear
  printf "\n\n${C_FNET_RED}${BOLD}"
  printf "╔══════════════════════════════════════════════════════════════════╗\n"
  printf "║                                                                  ║\n"
  printf "║   ███████╗███╗   ██╗███████╗████████╗    ██╗   ██╗██████╗ ███╗   ██╗ ║\n"
  printf "║   ██╔════╝████╗  ██║██╔════╝╚══██╔══╝    ██║   ██║██╔══██╗████╗  ██║ ║\n"
  printf "║   █████╗  ██╔██╗ ██║█████╗     ██║       ██║   ██║██████╔╝██╔██╗ ██║ ║\n"
  printf "║   ██╔══╝  ██║╚██╗██║██╔══╝     ██║       ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║ ║\n"
  printf "║   ██║     ██║ ╚████║███████╗   ██║        ╚████╔╝ ██║     ██║ ╚████║ ║\n"
  printf "║   ╚═╝     ╚═╝  ╚═══╝╚══════╝   ╚═╝         ╚═══╝  ╚═╝     ╚═╝  ╚═══╝ ║\n"
  printf "║                                                                  ║\n"
  printf "║         ${C_FNET_YELLOW}🚀 SSH over WEBSOCKET SYSTEM => VERSION - 2.4          ${C_FNET_RED}║\n"
  printf "║         ${C_FNET_GREEN}⚡ Powered by FNET Developer                           ${C_FNET_RED}║\n"
  printf "╚══════════════════════════════════════════════════════════════════╝${RESET}\n\n"
}

show_step() { printf "\n${C_FNET_PURPLE}${BOLD}┌─── STEP $1 ──────────────────────────────────────────┐${RESET}\n${C_FNET_PURPLE}${BOLD}│${RESET} ${C_FNET_CYAN}$2${RESET}\n${C_FNET_PURPLE}${BOLD}└──────────────────────────────────────────────────────┘${RESET}\n"; }
show_success() { printf "${C_FNET_GREEN}${BOLD}✓${RESET} ${C_FNET_GREEN}%s${RESET}\n" "$1"; }
show_info() { printf "${C_FNET_BLUE}${BOLD}ℹ${RESET} ${C_FNET_BLUE}%s${RESET}\n" "$1"; }
show_warning() { printf "${C_FNET_YELLOW}${BOLD}⚠${RESET} ${C_FNET_YELLOW}%s${RESET}\n" "$1"; }
show_error() { printf "${C_FNET_RED}${BOLD}✗${RESET} ${C_FNET_RED}%s${RESET}\n" "$1"; }
show_divider() { printf "${C_FNET_GRAY}%s${RESET}\n" "──────────────────────────────────────────────────────────"; }
show_kv() { printf "   ${C_FNET_GRAY}%s${RESET}  ${C_FNET_CYAN}%s${RESET}\n" "$1" "$2"; }

run_with_progress() {
  local label="$1"; shift; local temp_file=$(mktemp)
  if [[ -t 1 ]]; then
    printf "\e[?25l"; ("$@" 2>&1 | tee "$temp_file") >>"$LOG_FILE" 2>&1 & local pid=$!; local pct=5
    while kill -0 "$pid" 2>/dev/null; do
      pct=$(( pct + $(( (RANDOM % 5) + 2 )) )); (( pct > 98 )) && pct=98
      printf "\r${C_FNET_PURPLE}⟳${RESET} ${C_FNET_CYAN}%s...${RESET} [${C_FNET_YELLOW}%s%%${RESET}]" "$label" "$pct"
      sleep 0.8
    done
    wait "$pid" 2>/dev/null || true; local rc=$?
    printf "\r\e[K"
    if (( rc==0 )); then printf "${C_FNET_GREEN}✓${RESET} ${C_FNET_GREEN}%s...${RESET} [${C_FNET_GREEN}100%%${RESET}]\n" "$label"
    else printf "${C_FNET_RED}✗${RESET} ${C_FNET_RED}%s failed!${RESET}\n" "$label"; rm -f "$temp_file"; printf "\e[?25h"; return $rc; fi
    rm -f "$temp_file"; printf "\e[?25h"
  else "$@" >>"$LOG_FILE" 2>&1; fi
}

show_fnet_banner

# =================== Step 1: Telegram Config ===================
show_step "01" "Telegram Configuration Setup"
TELEGRAM_TOKEN=""
TELEGRAM_CHAT_ID=""
read -rp "${C_FNET_GREEN}🤖 Enter Telegram Bot Token:${RESET} " TELEGRAM_TOKEN || true
read -rp "${C_FNET_GREEN}👤 Enter Telegram Chat ID:${RESET} " TELEGRAM_CHAT_ID || true

tg_send(){
  local text="$1"
  if [[ -z "${TELEGRAM_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then return 0; fi
  curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=${text}" -d "parse_mode=HTML" \
    >>"$LOG_FILE" 2>&1 || true
}

# =================== Step 2: Timezone Setup ===================
show_step "02" "Lab Timer Setup"
printf "\n${C_FNET_GRAY}💡 Qwiklabs ပေါ်က ကျန်နေတဲ့ အချိန်ကို ကြည့်ပြီး ထည့်ပေးပါ။ (ဥပမာ - 05:10)${RESET}\n"
read -rp "${C_FNET_GREEN}⏳ Remaining Time (H:M):${RESET} " REMAINING_TIME || true
export TZ="Asia/Bangkok"
START_EPOCH="$(date +%s)"
if [[ -z "$REMAINING_TIME" || ! "$REMAINING_TIME" =~ ^[0-9]+:[0-9]+$ ]]; then
  ADD_SECS=$(( 3 * 3600 ))
else
  HRS=$(echo "$REMAINING_TIME" | cut -d: -f1 | sed 's/^0*//'); MINS=$(echo "$REMAINING_TIME" | cut -d: -f2 | sed 's/^0*//')
  ADD_SECS=$(( ${HRS:-0} * 3600 + ${MINS:-0} * 60 ))
fi
END_LOCAL="$(date -d @"$(( START_EPOCH + ADD_SECS ))" "+%I:%M %p")"
show_success "Expire Time set to: $END_LOCAL"

# =================== Step 3: Enable APIs ===================
show_step "03" "GCP API Enablement"
APIS_TO_ENABLE=("run.googleapis.com" "cloudbuild.googleapis.com" "artifactregistry.googleapis.com")
for api in "${APIS_TO_ENABLE[@]}"; do
  if ! gcloud services list --enabled --filter="config.name:$api" --format="value(config.name)" | grep -q "$api"; then
    run_with_progress "Enabling $api" gcloud services enable "$api" --quiet
  fi
done
show_success "Required APIs enabled successfully."

# =================== Step 4: Build Server (VPN Bypass Fix) ===================
show_step "04" "Building SSH WS Proxy Server (Fake WS Supported)"
BUILD_DIR=$(mktemp -d); cd "$BUILD_DIR"

# Raw TCP Python Proxy (VPN App တွေရဲ့ Fake WS Payload ကို အပြည့်အဝ လက်ခံသည်)
cat << 'EOF' > proxy.py
import asyncio, os

async def handle_client(reader, writer):
    try:
        # HTTP Handshake ဖတ်မည်
        req = b""
        while b"\r\n\r\n" not in req:
            chunk = await reader.read(4096)
            if not chunk: break
            req += chunk
        
        # VPN App တွေအတွက် 101 Switching Protocols ကို လိုအပ်ချက်မရှိ အတင်းပို့ပေးမည်
        res = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
        writer.write(res)
        await writer.drain()

        # Local SSH ဆီသို့ လမ်းကြောင်းလွှဲမည်
        ssh_reader, ssh_writer = await asyncio.open_connection('127.0.0.1', 22)

        async def pipe(r, w):
            try:
                while True:
                    data = await r.read(8192)
                    if not data: break
                    w.write(data)
                    await w.drain()
            except Exception: pass
            finally: w.close()

        await asyncio.gather(pipe(reader, ssh_writer), pipe(ssh_reader, writer))
    except Exception:
        pass
    finally:
        writer.close()

async def main():
    port = int(os.environ.get("PORT", 8080))
    server = await asyncio.start_server(handle_client, '0.0.0.0', port)
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# websockets library ဖြုတ်ပစ်လိုက်ပါပြီ
cat << 'EOF' > Dockerfile
FROM alpine:latest
RUN apk add --no-cache openssh python3 bash
RUN ssh-keygen -A && echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    adduser -D -s /bin/bash fnet && echo "fnet:fnet" | chpasswd
COPY proxy.py /app/proxy.py
EXPOSE 8080
CMD ["/bin/bash", "-c", "/usr/sbin/sshd && python3 /app/proxy.py"]
EOF

# =================== Step 5: Deploy ===================
show_step "05" "Cloud Run Deployment"
SERVICE="fnet-ssh-ws-$(date +%s)"
REGION="us-central1"

run_with_progress "Deploying Server to Cloud Run" \
  gcloud run deploy "$SERVICE" --source="." --region="$REGION" --platform=managed --allow-unauthenticated --port=8080 --quiet

# =================== Step 6: Fetching Cloud Run URL ===================
show_step "06" "Fetching Cloud Run URL"
show_info "Waiting for Google to assign URL..."
SERVICE_URL=""
for i in {1..15}; do
  SERVICE_URL=$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)' 2>/dev/null || true)
  if [[ -n "$SERVICE_URL" ]]; then
    break
  fi
  sleep 3
done

if [[ -z "$SERVICE_URL" ]]; then
  show_error "URL ကို ဆွဲယူလို့ မရပါ။ Deployment Failed ဖြစ်သွားနိုင်ပါသည်။"
  exit 1
fi

HOST_URL=$(echo "$SERVICE_URL" | sed 's#^https://##; s#/$##')
show_success "URL fetched: $HOST_URL"

# =================== Step 7: Final Result & Telegram ===================
show_step "07" "Deployment Finished"

PAYLOAD="GET / HTTP/1.1[crlf]Host: ${HOST_URL}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"

# Screen Output
show_kv "Host:" "vpn.googleapis.com"
show_kv "Port:" "443"
show_kv "User/Pass:" "fnet / fnet"
show_kv "Payload:" "$PAYLOAD"

# Telegram Output
MSG=$(cat <<EOF
✅ <b>FNET SSH WS Deployed</b>
━━━━━━━━━━━━━━━━━━
🌍 <b>Host:</b> <code>vpn.googleapis.com</code>
🔌 <b>Port:</b> <code>443</code>
👤 <b>User:</b> <code>fnet</code>
🔑 <b>Pass:</b> <code>fnet</code>
🛡️ <b>SNI:</b> <code>vpn.googleapis.com</code>

📋 <b>PAYLOAD:</b>
<code>${PAYLOAD}</code>

⏳ <b>Expires at:</b> ${END_LOCAL}
━━━━━━━━━━━━━━━━━━
EOF
)
tg_send "$MSG"
show_success "Telegram message sent! Please check your bot."
rm -rf "$BUILD_DIR"
