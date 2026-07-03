# senaiot — Contexto del proyecto

Stack IoT para laboratorio de Microbiologia SENA SENNOVA.
Repo: github.com/roserocarlos/senaiot

## Fixes criticos (NO olvidar en nuevas instalaciones)

1. nginx -> Home Assistant: NUNCA hardcodear la IP del gateway Docker
   (ej. 172.17.0.1, 172.19.0.1) en nginx.conf. Esa IP la asigna Docker
   al crear la red y CAMBIA entre despliegues/equipos/redes distintas.
   -> Usar host.docker.internal en el proxy_pass, y en el servicio
      nginx del docker-compose.yml agregar:
        extra_hosts:
          - "host.docker.internal:host-gateway"
   -> Funciona en Linux desde Docker 20.10+ (no solo Mac/Windows).
   -> Sin esto: "Connection refused" al pegarle a /ha/api/states,
      que en el dashboard se ve enganosamente como "verifica el token"
      (el catch{} de haFetch() en index.html no distingue la causa).
   -> Despues de editar docker-compose.yml: docker compose up -d nginx
      (restart NO alcanza, extra_hosts requiere recrear el contenedor).

2. ESPHome: los campos id: (ej. id: temp_sensor) NO aceptan guiones.
   -> Si el device_name usa guiones (ej. "am2315c-lab-01"), NUNCA
      interpolarlo dentro de un id: con ${device_name}. Usar IDs
      fijos genericos (temp_sensor, hum_sensor) - no necesitan ser
      unicos entre nodos porque cada uno compila firmware aparte.
   -> ${device_name} con guiones SI es valido en esphome.name y en
      el SSID del AP de fallback - el problema es solo en id:.

3. Dashboard (index.html) agrupa temperatura+humedad de un mismo nodo
   quitando sufijos en INGLES del entity_id (_temperature, _humidity,
   _temp, _hum). Los sensores en ESPHome deben nombrarse "Temperature"
   y "Humidity" (no "Temperatura"/"Humedad") o el dashboard los va a
   mostrar como dos sensores separados en vez de agrupar en una card.

4. api_encryption_key de ESPHome: NO es lo mismo que el token
   Long-Lived de HA. Es el cifrado del canal nativo ESPHome<->HA,
   se genera una sola vez y se reutiliza en el secrets.yaml
   compartido de todo el lab (mismo secrets.yaml para todos los
   nodos, solo se cambia device_name/friendly_name por nodo).

5. deploy.sh (paso 5/8, YA ELIMINADO) intentaba detectar la IP del
   gateway Docker con `ip route | grep default | awk '{print $3}'`.
   Eso NO es el gateway de la red Docker (sena_net) - es el gateway
   del router WiFi/LAN del host. El script terminaba escribiendo la
   IP del router en nginx.conf, que nunca tiene a Home Assistant
   escuchando, y el resultado era "Connection refused" en el proxy.
   -> Resuelto de raiz usando host.docker.internal (ver fix #1),
      que no necesita detectar ninguna IP. Si algun deploy.sh viejo
      todavia tiene ese bloque de HOST_IP, borrarlo.

## Arquitectura de red (por que pasa el fix #1)

Home Assistant corre con network_mode: host - escucha directo en el
host (la Orange Pi), no en la red Docker sena_net. Nginx si vive
dentro de sena_net, asi que para llegar a HA tiene que salir por el
gateway de esa red hacia el host. host.docker.internal resuelve esto
sin importar que IP le toque a esa red en cada despliegue.

## Setup del token de Home Assistant (una sola vez por instalacion)

El index.html NO trae token hardcodeado a proposito (antes lo tenia,
se saco por seguridad - un repo publico con el token adentro le da
lectura de HA a cualquiera). El flujo correcto:

1. Generar Long-Lived Access Token en HA (perfil de usuario -> abajo
   del todo -> "Long-Lived Access Tokens" -> crear).
2. Abrir el dashboard UNA vez con el token en la URL:
   http://<hostname>.local:8087/?token=TU_TOKEN
3. El JS lo guarda en localStorage del navegador. De ahi en adelante
   la URL normal (sin ?token=) funciona sola.
4. Si se abre el dashboard desde un navegador/dispositivo nuevo, hay
   que repetir el paso 2 una vez para ese navegador (localStorage es
   por navegador, no compartido).

## Mosquitto en modo anónimo (decisión de diseño, no bug)

allow_anonymous true a proposito. Las redes de laboratorio SENA son
cerradas, no expuestas a campo abierto/internet. Se prioriza deploy
sin friccion (MVP "un click") sobre autenticacion MQTT. Si el lab
llega a conectarse a una red menos confiable, revertir a
allow_anonymous false + password_file en mosquitto.conf, y volver a
agregar MQTT_USER/MQTT_PASSWORD en .env + deploy.sh paso 4/8.

Esto tambien saco MQ_USER/MQ_PASS hardcodeados de index.html (mismo
problema de fondo que el HA_TOKEN hardcodeado - ver seccion de arriba).
