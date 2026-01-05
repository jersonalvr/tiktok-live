param(
    [int]$SampleSeconds = 5,        # segundos de muestreo
    [int]$MinUploadKBps = 100,       # KB/s minimos para considerar LIVE (reducido)
    [string]$ProcessMatch = "TikTok",
    [int]$MinConnections = 2        # Minimo de conexiones activas
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

# 3. Estadisticas iniciales de TODAS las interfaces
$totalSentBefore = 0
foreach ($adapter in $adapters) {
    $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
    if ($stats) {
        $totalSentBefore += $stats.SentBytes
    }
}

Write-Host "[INFO] Monitoreando trafico durante $SampleSeconds segundos..." -ForegroundColor Gray

Start-Sleep -Seconds $SampleSeconds

# 4. Estadisticas finales de TODAS las interfaces
$totalSentAfter = 0
foreach ($adapter in $adapters) {
    $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
    if ($stats) {
        $totalSentAfter += $stats.SentBytes
    }
}

# 5. Calcular trafico
$deltaBytes = $totalSentAfter - $totalSentBefore
$kbps = [math]::Round(($deltaBytes / 1KB) / $SampleSeconds, 2)

Write-Host "[INFO] Trafico saliente total: $kbps KB/s" -ForegroundColor Cyan

# 6. Analizar conexiones TikTok (mas detallado)
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

if ($streamServers) {
    Write-Host "[INFO] Servidores de streaming detectados:" -ForegroundColor Gray
    foreach ($server in $streamServers | Select-Object -First 3) {
        Write-Host "  - $($server.Name):$($server.Group[0].RemotePort) ($($server.Count) conexiones)" -ForegroundColor DarkGray
    }
}

# 7. Decision FINAL mejorada (combinando trafico y conexiones)
$isLive = $false
$reason = ""

if ($activeConnections -ge $MinConnections -and $kbps -ge $MinUploadKBps) {
    $isLive = $true
    $reason = "Trafico sostenido ($kbps KB/s) + $activeConnections conexiones activas"
}
elseif ($rtmpConnections -gt 0 -or $httpsConnections -ge 3) {
    # Si hay conexiones RTMP o multiples conexiones HTTPS, probablemente estes en LIVE
    if ($kbps -ge ($MinUploadKBps * 0.3)) {  # Al menos 30% del umbral
        $isLive = $true
        $reason = "Patron de conexiones de streaming detectado"
    }
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
