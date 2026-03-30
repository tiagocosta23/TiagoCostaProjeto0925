# ==============================================================
# Get-SystemStats.ps1
# Monitorização de CPU, RAM, Disco e Rede
# Devolve JSON para ser consumido pelo Dashboard
# ==============================================================

# --- CPU ---
$cpu = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average

# --- RAM ---
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$ramTotal  = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)   # GB
$ramFree   = [math]::Round($os.FreePhysicalMemory     / 1MB, 2)   # GB
$ramUsed   = [math]::Round($ramTotal - $ramFree, 2)
$ramPct    = [math]::Round(($ramUsed / $ramTotal) * 100, 1)

# --- Disco (todos os volumes fixos) ---
$discos = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $total = [math]::Round($_.Size / 1GB, 2)
    $free  = [math]::Round($_.FreeSpace / 1GB, 2)
    $used  = [math]::Round($total - $free, 2)
    $pct   = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 1) } else { 0 }
    @{
        drive   = $_.DeviceID
        totalGB = $total
        usedGB  = $used
        freeGB  = $free
        usedPct = $pct
    }
}

# --- Rede (adaptadores ativos) ---
$netStats = Get-CimInstance -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface |
    Where-Object { $_.BytesTotalPersec -gt 0 } |
    ForEach-Object {
        @{
            adapter    = $_.Name -replace '\(.*\)','' -replace '_',' '
            bytesInKB  = [math]::Round($_.BytesReceivedPersec / 1KB, 2)
            bytesOutKB = [math]::Round($_.BytesSentPersec / 1KB, 2)
        }
    }

# --- Processos top 10 por CPU ---
$processos = Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 | ForEach-Object {
    @{
        name    = $_.ProcessName
        pid     = $_.Id
        cpuSec  = [math]::Round($_.CPU, 2)
        ramMB   = [math]::Round($_.WorkingSet64 / 1MB, 2)
        status  = "running"
    }
}

# --- Alertas automáticos ---
$alertas = @()
if ($cpu -gt 85)      { $alertas += @{ tipo = "warning"; mensagem = "CPU acima de 85% ($cpu%)" } }
if ($ramPct -gt 85)   { $alertas += @{ tipo = "warning"; mensagem = "RAM acima de 85% ($ramPct%)" } }
foreach ($d in $discos) {
    if ($d.usedPct -gt 90) {
        $alertas += @{ tipo = "critical"; mensagem = "Disco $($d.drive) acima de 90% ($($d.usedPct)%)" }
    }
}

# --- Output JSON ---
$resultado = @{
    timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    hostname  = $env:COMPUTERNAME
    cpu       = @{
        usedPct = $cpu
    }
    ram       = @{
        totalGB = $ramTotal
        usedGB  = $ramUsed
        freeGB  = $ramFree
        usedPct = $ramPct
    }
    discos    = $discos
    rede      = $netStats
    processos = $processos
    alertas   = $alertas
}

$resultado | ConvertTo-Json -Depth 5
