# senaiot — Stack IoT Laboratorio SENA SENNOVA

Sistema de monitoreo ambiental para laboratorios de formación profesional.
Desarrollado por [Ingenio+](https://ingenio.plus) para el SENA.

## Stack

| Servicio | Puerto | Función |
|---|---|---|
| Dashboard Lab | 8087 | Portal aprendices y instructores |
| Home Assistant | 8123 | Autodescubrimiento ESPHome |
| Node-RED | 1880 | Transformación + alertas |
| InfluxDB | 8086 | Historial series temporales |
| Grafana | 3000 | Panel admin instructores |
| Mosquitto | 1883/9001 | Broker MQTT con autenticación |

## Deploy en un comando

```bash
git clone https://github.com/roserocarlos/senaiot
cd senaiot && bash deploy.sh
```

Sin IPs para editar a mano, sin tokens en el código — el stack queda
funcional en cualquier equipo/red de cero. Ver `CONTEXT.md` si algo
no arranca; ahí están documentados los fixes conocidos.

## Hardware compatible

- **Servidor:** Orange Pi 5B, Arduino UNO Q, Raspberry Pi 4/5
- **Sensores:** ESP32-C3 + AM2315C (temperatura + humedad ambiente)
- **Firmware:** ESPHome — carpeta `esphome/`, ver abajo

## Flujo de datos

```
ESP32-C3 + AM2315C
  -> ESPHome (WiFi)
    -> Home Assistant (autodescubrimiento)
      -> REST API -> Dashboard laboratorio
      -> MQTT -> Node-RED -> InfluxDB -> Grafana
```

## Agregar un sensor nuevo (nodo ESP32-C3 + AM2315C)

1. Copiar `esphome/secrets.yaml.example` a `esphome/secrets.yaml` y
   completar con el WiFi del laboratorio (una sola vez para todo el
   lab — todos los nodos comparten el mismo `secrets.yaml`).
2. En `esphome/am2315c-lab.yaml`, cambiar `device_name` y
   `friendly_name` en `substitutions:` (único cambio por nodo).
3. Compilar y flashear:
   ```bash
   esphome compile am2315c-lab.yaml
   ```
   Primer flasheo (USB): subir el `firmware.factory.bin` generado
   vía [web.esphome.io](https://web.esphome.io) (esquiva bloqueos de
   Device Guard/políticas corporativas en Windows, ya que usa Web
   Serial del navegador en vez de un ejecutable local).
   Flasheos siguientes (ya instalado): OTA por WiFi,
   `esphome run am2315c-lab.yaml --device <device_name>.local`.
4. Home Assistant lo descubre solo — aceptar la notificación de
   "nuevo dispositivo" en HA (o agregarlo manualmente la primera vez
   en Configuración → Dispositivos y servicios → ESPHome).
5. Aparece en el dashboard automáticamente, sin tocar `index.html`.

## Setup del token de Home Assistant (una sola vez por instalación)

El dashboard no trae ningún token en el código (por seguridad — el
repo es público). Después del primer deploy:

1. Generar un Long-Lived Access Token en HA: perfil de usuario →
   "Long-Lived Access Tokens" → crear.
2. Abrir el dashboard **una vez** con el token en la URL:
   ```
   http://{hostname}.local:8087/?token=TU_TOKEN
   ```
3. El navegador lo guarda solo (localStorage) — de ahí en adelante,
   la URL normal sin `?token=` funciona. Hay que repetir este paso
   una vez por cada navegador/dispositivo nuevo que abra el dashboard.

## Acceso por nombre

```
http://{hostname}.local:8087    <- Dashboard
http://{hostname}.local:8123    <- Home Assistant
```

Resuelto vía Avahi/mDNS, configurado automáticamente por `deploy.sh`.

## Documentación técnica

Ver [`CONTEXT.md`](./CONTEXT.md) para arquitectura de red, fixes
críticos conocidos y por qué existen (útil antes de reportar un bug
o de pedirle ayuda a una IA para seguir desarrollando esto).

---
*Desarrollado por [Ingenio+](https://ingenio.plus) · Sistema de Monitoreo IoT Agroindustrial*
