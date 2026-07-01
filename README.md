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

## Hardware compatible

- **Servidor:** Orange Pi 5B, Arduino UNO Q, Raspberry Pi 4/5
- **Sensores:** ESP32-C3 + AM2315C (temperatura + humedad ambiente)
- **Firmware:** ESPHome — autodescubrimiento automático en Home Assistant

## Flujo de datos

```
ESP32-C3 + AM2315C
  → ESPHome (WiFi)
    → Home Assistant (autodescubrimiento)
      → REST API → Dashboard laboratorio
      → MQTT → Node-RED → InfluxDB → Grafana
```

## Primer sensor ESPHome

1. Flashear ESP32-C3 con ESPHome (ver `docs/guia.html`)
2. Conectar a la red WiFi del laboratorio
3. Home Assistant lo descubre automáticamente
4. Aparece en el dashboard sin configuración adicional

## Acceso por nombre

```
http://{hostname}.local:8087    ← Dashboard
http://{hostname}.local:8123    ← Home Assistant
```

---
*Desarrollado por [Ingenio+](https://ingenio.plus) · Sistema de Monitoreo IoT Agroindustrial*
