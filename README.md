# TikTok LIVE Detector

Detector automático de transmisiones en vivo de TikTok basado en análisis de tráfico de red y conexiones de procesos.

## 🎯 Características

- **Detección basada en tráfico**: Monitorea el tráfico saliente (upload) para identificar si estás transmitiendo en vivo
- **Análisis de conexiones**: Detecta patrones de conexiones a servidores de TikTok
- **Servidor WebSocket**: API en tiempo real para clientes WebSocket
- **Integración TikTok Live Connector**: Se conecta automáticamente a la API oficial de TikTok cuando detecta un live
- **Monitoreo automático**: Ejecuta verificaciones cada 8 segundos cuando no está transmitiendo

## 📋 Requisitos

### Windows
- PowerShell (incluido en Windows)
- Node.js 14+
- npm

### Python (opcional)
- Python 3.7+
- Módulos: `websocket-client`, `pytz`

## 🚀 Instalación

```bash
# Clonar o descargar el repositorio
cd tiktok

# Instalar dependencias de Node.js
npm install

# Instalar colores para salida con color en la consola
npm install colors ws tiktok-live-connector
```

## 📝 Configuración

Edita `server.js` y actualiza el nombre de usuario de TikTok:

```javascript
const TIKTOK_USERNAME = 'tu_usuario_tiktok'; // Cambiar esto
```

## ▶️ Uso

### Iniciar el servidor Node.js

```bash
npm start
```

O ejecutar directamente:

```bash
node server.js
```

El servidor iniciará en `ws://localhost:21213`

### Ejecutar el detector de TikTok LIVE (PowerShell)

```powershell
powershell.exe -ExecutionPolicy Bypass -File detect_tiktok_live.ps1
```

**Parámetros opcionales:**

```powershell
# Con parámetros personalizados
powershell.exe -ExecutionPolicy Bypass -File detect_tiktok_live.ps1 -SampleSeconds 5 -MinUploadKBps 100
```

### Escuchar eventos con WebSocket (Python)

```bash
python ws_listener.py
```

## 📊 Monitoreo

El detector funciona automáticamente:

1. **Cuando NO estás en LIVE**: Ejecuta `detect_tiktok_live.ps1` cada 8 segundos
2. **Cuando detecta un LIVE**: Se conecta a la API de TikTok y detiene el monitoreo
3. **Cuando termina el LIVE**: Reanuda el monitoreo automático

## 🔍 Cómo funciona

### detect_tiktok_live.ps1

- Detecta el proceso TikTok Studio en Windows
- Mide el tráfico de red durante 5 segundos
- Analiza las conexiones establecidas con servidores de TikTok
- Determina si estás en LIVE basándose en:
  - Tráfico saliente ≥ 100 KB/s
  - Múltiples conexiones activas
  - Patrones de conexión de streaming (HTTPS, RTMP)

### server.js

- Servidor WebSocket que:
  - Ejecuta el detector cada 8 segundos
  - Se conecta a TikTok Live cuando detecta un live
  - Retransmite eventos de TikTok a los clientes WebSocket
  - Notifica cambios de estado (inicio/fin de transmisión)

### ws_listener.py

Script de escucha que se conecta al WebSocket y muestra los eventos en tiempo real.

## 📡 Eventos WebSocket

El servidor emite eventos:

```json
{
  "event": "liveStatus",
  "data": { "isLive": true/false }
}
```

Eventos de TikTok cuando está en LIVE:

- `chat`: Mensajes del chat
- `like`: Likes recibidos
- `gift`: Regalos recibidos
- `follow`: Seguidores nuevos
- `member`: Miembros que se unen
- `share`: Comparticiones
- `subscribe`: Suscriptores nuevos
- Y más eventos de TikTok...

## 🛠️ Estructura del Proyecto

```
tiktok/
├── server.js                      # Servidor Node.js + detector
├── detect_tiktok_live.ps1         # Script detector (PowerShell)
├── ws_listener.py                 # Cliente WebSocket (Python)
├── package.json                   # Dependencias Node.js
├── event-api.md                   # Documentación de eventos
├── README.md                       # Este archivo
└── __pycache__/                   # Cache de Python
```

## 🎨 Colores en la consola

- **Cyan**: Conexión de servidor y WebSocket
- **Green**: Éxito, conexión a TikTok
- **Red**: Errores, stream terminado
- **Yellow**: Información, desconexión
- **Gray**: Detalles secundarios

## 🐛 Solución de problemas

### No detecta cuando estoy en LIVE

- Verifica que TikTok Studio está corriendo en Windows
- Asegúrate de estar transmitiendo con suficiente bitrate
- Ejecuta manualmente: `powershell.exe -ExecutionPolicy Bypass -File detect_tiktok_live.ps1`

### Error "TikTok LIVE Studio NO esta abierto"

- Abre TikTok y accede a LIVE Studio
- Verifica que el proceso se llama "TikTok" o similar

### WebSocket connection errors

- Asegúrate que el puerto 21213 no esté siendo usado
- Instala las dependencias: `npm install`

## ⚠️ Aviso Legal

Este proyecto está diseñado para uso personal. Úsalo responsablemente y respeta los términos de servicio de TikTok.