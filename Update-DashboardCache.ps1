# Update-DashboardCache.ps1
# Corre em background e atualiza os ficheiros de cache JSON
# para o Dashboard. Executado automaticamente pelo Start-WebDashboard.ps1
#
# NAO executar manualmente - e gerido pelo servidor web.

param(
    [int]$IntervaloSegundos = 30
)

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$CacheDir    = "C:\SysAdmin\cache"

# Criar pasta de cache
if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}

# Mapeamento: nome do cache -> script + argumento
$scripts = @(
    @{ cache = "stats.json";      script = "$ProjectRoot\scripts\monitoring\Get-SystemStats.ps1"; args = "" }
    @{ cache = "users.json";      script = "$ProjectRoot\scripts\users\Manage-ADUsers.ps1";      args = "json" }
    @{ cache = "filesystem.json"; script = "$ProjectRoot\scripts\filesystem\Audit-FileSystem.ps1"; args = "json" }
    @{ cache = "services.json";   script = "$ProjectRoot\scripts\services\Monitor-Services.ps1";  args = "json" }
    @{ cache = "network.json";    script = "$ProjectRoot\scripts\network\Monitor-Network.ps1";    args = "json" }
    @{ cache = "security.json";   script = "$ProjectRoot\scripts\security\Monitor-Security.ps1";  args = "json" }
    @{ cache = "backup.json";     script = "$ProjectRoot\scripts\backup\Manage-Backup.ps1";       args = "json" }
)

Write-Host "[Cache] A iniciar atualizacao de cache a cada ${IntervaloSegundos}s..." -ForegroundColor Yellow
Write-Host "[Cache] Pasta: $CacheDir" -ForegroundColor Gray
Write-Host "[Cache] Scripts: $($scripts.Count)" -ForegroundColor Gray
Write-Host ""

# Loop infinito de atualizacao
while ($true) {
    $inicio = Get-Date

    foreach ($item in $scripts) {
        $cacheFile = "$CacheDir\$($item.cache)"
        $scriptPath = $item.script

        if (-not (Test-Path $scriptPath)) {
            Write-Host "[Cache] AVISO: Script nao encontrado: $scriptPath" -ForegroundColor Red
            continue
        }

        try {
            # Executar o script e capturar o output
            $ErrorActionPreference = "SilentlyContinue"
            if ($item.args) {
                $output = & $scriptPath $item.args 2>$null | Out-String
            } else {
                $output = & $scriptPath 2>$null | Out-String
            }
            $json = $output.Trim()

            # Validar que e JSON
            if ($json -and $json.StartsWith('{')) {
                # Escrever para ficheiro temporario e depois mover (atomico)
                $tempFile = "$cacheFile.tmp"
                [System.IO.File]::WriteAllText($tempFile, $json, [System.Text.Encoding]::UTF8)
                if (Test-Path $cacheFile) { Remove-Item $cacheFile -Force }
                Rename-Item $tempFile $cacheFile -Force
            }
        } catch {
            # Silenciar - nao queremos que o loop pare por causa de um erro
        }
    }

    $duracao = [math]::Round(((Get-Date) - $inicio).TotalSeconds, 1)
    $hora = Get-Date -Format "HH:mm:ss"
    Write-Host "[Cache] $hora - Atualizado em ${duracao}s" -ForegroundColor DarkGray

    # Esperar ate ao proximo ciclo
    $espera = [math]::Max(1, $IntervaloSegundos - $duracao)
    Start-Sleep -Seconds $espera
}
