param(
    [int]$WindowSeconds = 10,          # segundos de ventana para calcular trafico (ultimos 10s)
    [int]$IntervalSeconds = 1,         # segundos entre reportes
    [int]$MinUploadKBps = 100,         # KB/s minimos para considerar LIVE (base)
    [string]$ProcessMatch = "TikTok",
    [int]$MinConnections = 2          # Minimo de conexiones activas (base)
)

Write-Host "== TikTok LIVE Detector (traffic-based) ==" -ForegroundColor Cyan

# 1. Detectar proceso TikTok
$processes = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like "*$ProcessMatch*" }

if (-not $processes) {
    Write-Host "[ERROR] TikTok LIVE Studio NO esta abierto" -ForegroundColor Red
    exit
}

$pidList = $processes.Id
Write-Host "[OK] TikTok LIVE Studio detectado (PID: $($pidList -join ', '))" -ForegroundColor Green

# 2. Obtener TODAS las interfaces de red activas
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

if (-not $adapters) {
    Write-Host "[ERROR] No se pudo detectar adaptador de red" -ForegroundColor Red
    exit
}

# Inicializar lista de muestras
$samples = New-Object System.Collections.Generic.List[long]

Write-Host "[INFO] Servicio iniciado. Monitoreando cada $IntervalSeconds segundos (ventana: $WindowSeconds s). Presiona Ctrl+C para detener." -ForegroundColor Cyan

# Loop continuo
while ($true) {
    # Verificar si TikTok sigue abierto
    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like "*$ProcessMatch*" }
    
    if (-not $processes) {
        Write-Host "`n[ERROR] TikTok LIVE Studio se ha cerrado. Deteniendo monitor..." -ForegroundColor Red
        exit
    }
    
    $pidList = $processes.Id

    # Tomar muestra actual
    $currentSent = 0
    foreach ($adapter in $adapters) {
        $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
        if ($stats) {
            $currentSent += $stats.SentBytes
        }
    }

    # Agregar a la lista
    $samples.Add($currentSent)

    # Mantener solo las ultimas WindowSeconds muestras (aprox, ya que intervalo es 1s)
    while ($samples.Count -gt $WindowSeconds) {
        $samples.RemoveAt(0)
    }

    # Calcular trafico si hay suficientes muestras
    if ($samples.Count -eq $WindowSeconds) {
        $deltaBytes = $samples[$samples.Count - 1] - $samples[0]
        $kbps = [math]::Round(($deltaBytes / 1KB) / $WindowSeconds, 2)

        Write-Host "[INFO] Trafico saliente total (ultimos $WindowSeconds s): $kbps KB/s" -ForegroundColor Cyan

        # 5. Analizar conexiones TikTok (mas detallado)
        $tiktokConnections = Get-NetTCPConnection -ErrorAction SilentlyContinue |
            Where-Object {
                $_.State -eq "Established" -and
                $_.OwningProcess -in $pidList
            }

        $activeConnections = $tiktokConnections | Measure-Object | Select-Object -ExpandProperty Count
        $httpsConnections = ($tiktokConnections | Where-Object { $_.RemotePort -eq 443 }).Count
        $rtmpConnections = ($tiktokConnections | Where-Object { $_.RemotePort -in @(1935, 1936) }).Count

        Write-Host "[INFO] Conexiones activas: $activeConnections (HTTPS: $httpsConnections, RTMP: $rtmpConnections)" -ForegroundColor Gray

        # Identificar servidores de streaming (usualmente puertos 443, 1935, 1936, 8080)
        $streamingPorts = @(443, 1935, 1936, 8080, 80)
        $streamServers = $tiktokConnections |
            Where-Object { $_.RemotePort -in $streamingPorts } |
            Group-Object RemoteAddress |
            Sort-Object Count -Descending

        $dominantServer = $streamServers | Select-Object -First 1
        $hasDominantServer = $dominantServer -and $dominantServer.Count -ge 3

        if ($streamServers) {
            Write-Host "[INFO] Servidores de streaming detectados:" -ForegroundColor Gray
            foreach ($server in $streamServers | Select-Object -First 3) {
                Write-Host "  - $($server.Name):$($server.Group[0].RemotePort) ($($server.Count) conexiones)" -ForegroundColor DarkGray
            }
        }

        # 6. Decision FINAL mejorada (combinando trafico y conexiones)
        $isLive = $false
        $reason = ""

        # Endurecer criterios para evitar falsos positivos (overlays, navegacion web)
        $httpsMinConns = [Math]::Max($MinConnections + 2, 4)     # minimo conexiones https para considerar live (ajustado)
        $httpsMinKbps  = [Math]::Max([Math]::Round($MinUploadKBps * 2.0), 200) # trafico alto sostenido (ajustado)
        $rtmpMinKbps   = [Math]::Max([Math]::Round($MinUploadKBps * 0.6), 120) # menos exigente si hay RTMP

        if ($rtmpConnections -gt 0 -and $kbps -ge $rtmpMinKbps) {
            # RTMP es un indicador fuerte de transmision
            $isLive = $true
            $reason = "RTMP detectado ($rtmpConnections) + $kbps KB/s"
        }
        elseif ($httpsConnections -ge $httpsMinConns -and $kbps -ge $httpsMinKbps) {
            # Muchas conexiones HTTPS + alto upload
            $isLive = $true
            $reason = "HTTPS intenso ($httpsConnections) + trafico alto ($kbps KB/s)"
        }
        elseif ($hasDominantServer -and $kbps -ge ($MinUploadKBps * 2) -and $activeConnections -ge ($MinConnections + 3)) {
            # Varias conexiones al mismo servidor + trafico duplicado del umbral
            $isLive = $true
            $reason = "Servidor dominante $($dominantServer.Name) ($($dominantServer.Count) conns) + $kbps KB/s"
        }

        if ($isLive) {
            Write-Host "`n[LIVE] ESTAS EN TIKTOK LIVE" -ForegroundColor Red
            Write-Host "[INFO] $reason" -ForegroundColor Green
        }
        else {
            Write-Host "`n[IDLE] TikTok abierto, pero NO estas en LIVE" -ForegroundColor Yellow
            if ($kbps -lt $MinUploadKBps) {
                Write-Host "[INFO] Upload insuficiente ($kbps KB/s < $MinUploadKBps KB/s)" -ForegroundColor Gray
            }
            if ($activeConnections -lt $MinConnections) {
                Write-Host "[INFO] Pocas conexiones activas ($activeConnections)" -ForegroundColor Gray
            }
        }
    }

    # Esperar al siguiente intervalo
    Start-Sleep -Seconds $IntervalSeconds
}
