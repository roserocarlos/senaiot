#!/bin/bash
# =============================================================================
# senaiot — Deploy en un comando
# Orange Pi 5B / Arduino UNO Q / Raspberry Pi (ARM64/ARM32/x86)
#
# Uso:
#   git clone https://github.com/roserocarlos/senaiot
#   cd senaiot && bash deploy.sh
# =============================================================================

set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[✗]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}━━ $1 ━━${NC}"; }

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DEPLOY_DIR"
HOSTNAME_LOCAL="$(hostname).local"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    senaiot — Laboratorio SENA SENNOVA                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"

# ── 1. Docker ─────────────────────────────────────────────────────────────────
section "1/8 · Docker"
command -v docker &>/dev/null || err "Docker no instalado"
docker compose version &>/dev/null || \
  { warn "Instalando docker-compose-plugin..."; sudo apt-get install -y docker-compose-plugin; }
log "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"

# ── 2. Espacio en disco ───────────────────────────────────────────────────────
section "2/8 · Espacio en disco"
ROOT_USE=$(df / --output=pcent | tail -1 | tr -d ' %')
ROOT_AVAIL_MB=$(df / --output=avail -BM | tail -1 | tr -d 'M ')
if [ "$ROOT_USE" -ge 85 ] || [ "$ROOT_AVAIL_MB" -lt 2000 ]; then
    warn "Partición raíz al ${ROOT_USE}% — buscando partición con más espacio"
    BEST_MOUNT=$(df --output=avail,target -BM 2>/dev/null | tail -n +2 | \
        grep -vE "tmpfs|/boot|^.*\s/$" | sort -rn | head -1 | awk '{print $2}')
    if [ -n "$BEST_MOUNT" ]; then
        DOCKER_DATA="${BEST_MOUNT}/docker-data"
        sudo mkdir -p "$DOCKER_DATA"
        command -v rsync &>/dev/null || sudo apt-get install -y rsync
        if [ -d /var/lib/docker ]; then sudo rsync -a /var/lib/docker/ "$DOCKER_DATA/"; fi
        sudo mkdir -p /etc/docker
        sudo python3 -c "
import json
path='/etc/docker/daemon.json'
try: cfg=json.load(open(path))
except: cfg={}
cfg['data-root']='$DOCKER_DATA'
json.dump(cfg,open(path,'w'),indent=2)"
        sudo systemctl restart docker; sleep 3
        sudo rm -rf /var/lib/docker
        log "Docker movido a $DOCKER_DATA"
    fi
else
    log "Disco OK (${ROOT_USE}% usado)"
fi

# ── 3. .env ───────────────────────────────────────────────────────────────────
section "3/8 · Variables de entorno"
[ ! -f .env ] && cp .env.example .env && log ".env creado" || log ".env ya existe"
chmod 600 .env
source .env

# ── 4. Mosquitto passwd ───────────────────────────────────────────────────────
section "4/8 · Autenticación Mosquitto"
mkdir -p mosquitto/config
if [ ! -f mosquitto/config/passwd ]; then
    docker run --rm -v "$(pwd)/mosquitto/config:/mosquitto/config" eclipse-mosquitto:2.0 \
        mosquitto_passwd -b -c /mosquitto/config/passwd "$MQTT_USER" "$MQTT_PASSWORD"
    log "Usuario MQTT '$MQTT_USER' creado"
else
    log "passwd ya existe"
fi
chmod 644 mosquitto/config/passwd 2>/dev/null || sudo chmod 644 mosquitto/config/passwd

# ── 5. Nginx — inyectar token InfluxDB ───────────────────────────────────────
section "5/8 · Configurando Nginx"
if grep -q "INFLUXDB_TOKEN_PLACEHOLDER" nginx/nginx.conf 2>/dev/null; then
    sed -i "s|INFLUXDB_TOKEN_PLACEHOLDER|${INFLUXDB_TOKEN}|g" nginx/nginx.conf
    log "Token InfluxDB inyectado"
else
    log "nginx.conf ya configurado"
fi

# Detectar IP del host Docker para proxy HA
HOST_IP=$(ip route | grep default | awk '{print $3}' | head -1)
if [ -n "$HOST_IP" ] && grep -q "172.17.0.1" nginx/nginx.conf; then
    sed -i "s|172.17.0.1|${HOST_IP}|g" nginx/nginx.conf
    log "IP host Docker actualizada: $HOST_IP"
fi

# ── 6. mDNS ──────────────────────────────────────────────────────────────────
section "6/8 · Configurando acceso por nombre (mDNS)"
if ! command -v avahi-daemon &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y avahi-daemon avahi-utils
fi
WIFI_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E "^wlan|^wlp" | head -1)
if [ -n "$WIFI_IF" ] && ! grep -q "allow-interfaces" /etc/avahi/avahi-daemon.conf 2>/dev/null; then
    sudo sed -i "/\[server\]/a allow-interfaces=${WIFI_IF}" /etc/avahi/avahi-daemon.conf
    log "Avahi restringido a $WIFI_IF"
fi
sudo mkdir -p /etc/avahi/services
sudo tee /etc/avahi/services/senaiot.service >/dev/null << EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>senaiot Lab Microbiología</name>
  <service><type>_http._tcp</type><port>8087</port></service>
</service-group>
EOF
sudo systemctl enable avahi-daemon --now 2>/dev/null
sudo systemctl restart avahi-daemon
log "Portal accesible como: ${HOSTNAME_LOCAL}:8087"

# ── 7. Stack ──────────────────────────────────────────────────────────────────
section "7/8 · Levantando stack"
docker compose up -d
log "Stack iniciado"

# ── 8. Verificar Mosquitto ────────────────────────────────────────────────────
section "8/8 · Verificando servicios"
sleep 8
MOSQ=$(docker inspect -f '{{.State.Status}}' sena_mosquitto 2>/dev/null || echo "unknown")
if [ "$MOSQ" != "running" ]; then
    warn "Mosquitto reiniciando — corrigiendo permisos"
    chmod 644 mosquitto/config/passwd 2>/dev/null || sudo chmod 644 mosquitto/config/passwd
    docker compose restart mosquitto; sleep 5
fi
MOSQ=$(docker inspect -f '{{.State.Status}}' sena_mosquitto 2>/dev/null)
[ "$MOSQ" = "running" ] && log "Mosquitto: OK" || warn "Mosquitto: revisar logs"

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         senaiot — Deploy completado                  ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}║  Dashboard Lab:  http://%-29s║${NC}\n" "${HOSTNAME_LOCAL}:8087"
printf "${GREEN}║  Node-RED:       http://%-29s║${NC}\n" "${HOSTNAME_LOCAL}:1880"
printf "${GREEN}║  Home Assistant: http://%-29s║${NC}\n" "${HOSTNAME_LOCAL}:8123"
printf "${GREEN}║  InfluxDB:       http://%-29s║${NC}\n" "${HOSTNAME_LOCAL}:8086"
printf "${GREEN}║  Grafana:        http://%-29s║${NC}\n" "${HOSTNAME_LOCAL}:3000"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
warn "Paso final: generar token HA en ${HOSTNAME_LOCAL}:8123 → perfil → Long-Lived Tokens"
warn "Agregar token en .env como HA_TOKEN y en el dashboard como parámetro ?token=XXX"
