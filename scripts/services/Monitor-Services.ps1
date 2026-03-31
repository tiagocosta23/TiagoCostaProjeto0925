# ==============================================================
# Monitor-Services.ps1
# Monitorizacao e Gestao de Servicos Windows
# Verificacao, reinicio, logs de falhas
# ==============================================================

param(
    [Parameter(Position=0)]
    [ValidateSet("listar","criticos","parados","reiniciar","verificar","json")]
    [string]$Acao,

    [string]$Servico
)

$ErrorActionPreference = "SilentlyContinue"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$LogFile = "$ProjectRoot\logs\services.log"

# Servicos criticos a monitorizar
$ServicosCriticos = @(
    "DNS",
    "NTDS",             # Active Directory
    "W3SVC",            # IIS
    "WAS",              # Windows Process Activation
    "Spooler",          # Print Spooler
    "LanmanServer",     # File Server (Server service)
    "LanmanWorkstation", # Workstation
    "DFSR",             # DFS Replication
    "Netlogon",         # Netlogon
    "EventLog",         # Windows Event Log
    "Winmgmt",          # WMI
    "WinRM"             # Windows Remote Management
)

function Write-Log {
    param([string]$Msg)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    if (-not (Test-Path (Split-Path $LogFile))) { New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null }
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
}

# ── Modo JSON (para a API do Dashboard) ──
if ($Acao -eq "json") {
    $criticos = @()
    foreach ($svcName in $ServicosCriticos) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            $criticos += @{
                nome      = $svc.DisplayName
                servico   = $svc.Name
                estado    = $svc.Status.ToString()
                startup   = $svc.StartType.ToString()
            }
        }
    }

    # Servicos parados que deviam estar a correr
    $parados = Get-Service | Where-Object {
        $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running'
    } | Select-Object -First 15 | ForEach-Object {
        @{
            nome    = $_.DisplayName
            servico = $_.Name
            estado  = $_.Status.ToString()
            startup = $_.StartType.ToString()
        }
    }

    # Roles Windows instaladas
    $roles = @()
    try {
        $roles = Get-WindowsFeature | Where-Object { $_.Installed } |
            Select-Object -First 20 | ForEach-Object {
                @{
                    nome   = $_.DisplayName
                    feat   = $_.Name
                    tipo   = $_.FeatureType.ToString()
                }
            }
    } catch {}

    $totalAtivos  = (Get-Service | Where-Object { $_.Status -eq 'Running' } | Measure-Object).Count
    $totalParados = (Get-Service | Where-Object { $_.Status -ne 'Running' } | Measure-Object).Count
    $criticosDown = ($criticos | Where-Object { $_.estado -ne 'Running' } | Measure-Object).Count

    $alertas = @()
    foreach ($c in $criticos) {
        if ($c.estado -ne "Running") {
            $alertas += @{ tipo = "critical"; mensagem = "Servico critico PARADO: $($c.nome) ($($c.servico))" }
        }
    }

    $resultado = @{
        timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        totalAtivos  = $totalAtivos
        totalParados = $totalParados
        criticosDown = $criticosDown
        criticos     = $criticos
        parados      = $parados
        roles        = $roles
        alertas      = $alertas
    }

    $resultado | ConvertTo-Json -Depth 5
    return
}

# ── Funcoes CLI ──

function Listar-Servicos {
    Write-Host ""
    Write-Host "  SERVICOS WINDOWS" -ForegroundColor Cyan
    Write-Host "  =================" -ForegroundColor Cyan
    $running = (Get-Service | Where-Object { $_.Status -eq 'Running' } | Measure-Object).Count
    $stopped = (Get-Service | Where-Object { $_.Status -ne 'Running' } | Measure-Object).Count
    Write-Host "  Ativos: $running | Parados: $stopped" -ForegroundColor Gray
    Write-Host ""
    Get-Service | Sort-Object Status -Descending |
        Format-Table Status, Name, DisplayName -AutoSize | Out-Host
}

function Servicos-Criticos {
    Write-Host ""
    Write-Host "  SERVICOS CRITICOS" -ForegroundColor Cyan
    Write-Host "  ==================" -ForegroundColor Cyan
    Write-Host ""
    foreach ($svcName in $ServicosCriticos) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            $cor = if ($svc.Status -eq 'Running') { "Green" } else { "Red" }
            $icon = if ($svc.Status -eq 'Running') { "[OK]" } else { "[!!]" }
            Write-Host "  $icon $($svc.DisplayName) ($($svc.Name)) - $($svc.Status)" -ForegroundColor $cor
        } else {
            Write-Host "  [--] $svcName - Nao instalado" -ForegroundColor DarkGray
        }
    }
    Write-Log "Verificacao de servicos criticos executada"
}

function Servicos-Parados {
    Write-Host ""
    Write-Host "  SERVICOS AUTOMATICOS PARADOS" -ForegroundColor Cyan
    $parados = Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }
    if ($parados.Count -eq 0) {
        Write-Host "  [OK] Todos os servicos automaticos estao a correr." -ForegroundColor Green
    } else {
        $parados | Format-Table Status, Name, DisplayName -AutoSize | Out-Host
        Write-Host "  [AVISO] $($parados.Count) servicos automaticos parados!" -ForegroundColor Yellow
    }
}

function Reiniciar-Servico {
    if (-not $Servico) { $Servico = Read-Host "  Nome do servico a reiniciar" }
    try {
        Write-Host "  A reiniciar '$Servico'..." -ForegroundColor Yellow
        Restart-Service -Name $Servico -Force
        Start-Sleep -Seconds 2
        $svc = Get-Service -Name $Servico
        if ($svc.Status -eq 'Running') {
            Write-Host "  [OK] '$Servico' reiniciado com sucesso." -ForegroundColor Green
        } else {
            Write-Host "  [AVISO] '$Servico' nao esta Running apos reinicio." -ForegroundColor Yellow
        }
        Write-Log "Servico reiniciado: $Servico -> $($svc.Status)"
    } catch {
        Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "ERRO ao reiniciar $Servico : $($_.Exception.Message)"
    }
}

function Verificar-AutoRestart {
    Write-Host ""
    Write-Host "  A VERIFICAR E REINICIAR SERVICOS CRITICOS PARADOS..." -ForegroundColor Yellow
    $reiniciados = 0
    foreach ($svcName in $ServicosCriticos) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running') {
            Write-Host "  [!!] $($svc.DisplayName) esta PARADO - a tentar reiniciar..." -ForegroundColor Red
            try {
                Start-Service -Name $svcName
                Start-Sleep -Seconds 2
                $check = Get-Service -Name $svcName
                if ($check.Status -eq 'Running') {
                    Write-Host "       [OK] Reiniciado com sucesso." -ForegroundColor Green
                    $reiniciados++
                    Write-Log "Auto-restart: $svcName reiniciado com sucesso"
                }
            } catch {
                Write-Host "       [FALHOU] $($_.Exception.Message)" -ForegroundColor Red
                Write-Log "Auto-restart FALHOU: $svcName - $($_.Exception.Message)"
            }
        }
    }
    if ($reiniciados -eq 0) {
        Write-Host "  [OK] Todos os servicos criticos estao operacionais." -ForegroundColor Green
    } else {
        Write-Host "  [INFO] $reiniciados servicos reiniciados." -ForegroundColor Yellow
    }
}

# ── Execucao ──
switch ($Acao) {
    "listar"    { Listar-Servicos }
    "criticos"  { Servicos-Criticos }
    "parados"   { Servicos-Parados }
    "reiniciar" { Reiniciar-Servico }
    "verificar" { Verificar-AutoRestart }
    default {
        Write-Host ""
        Write-Host "  Uso: .\Monitor-Services.ps1 <acao> [-Servico nome]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Acoes: listar, criticos, parados, reiniciar, verificar, json"
        Write-Host ""
    }
}
