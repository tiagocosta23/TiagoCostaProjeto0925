# ==============================================================
# Monitor-Security.ps1
# Monitorizacao de Seguranca e Analise do Sistema
# Logins falhados, portas abertas, eventos suspeitos
# ==============================================================

param(
    [Parameter(Position=0)]
    [ValidateSet("logins","eventos","portas","firewall","politicas","relatorio","json")]
    [string]$Acao,

    [int]$Horas = 24
)

$ErrorActionPreference = "SilentlyContinue"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$LogFile = "$ProjectRoot\logs\security.log"

function Write-Log {
    param([string]$Msg)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    if (-not (Test-Path (Split-Path $LogFile))) { New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null }
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
}

# ── Modo JSON (para a API do Dashboard) ──
if ($Acao -eq "json") {
    $desde = (Get-Date).AddHours(-$Horas)

    # Logins falhados (Event ID 4625)
    $loginsFalhados = @()
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Id        = 4625
            StartTime = $desde
        } -MaxEvents 20 -ErrorAction SilentlyContinue

        foreach ($evt in $events) {
            $xml = [xml]$evt.ToXml()
            $targetUser = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
            $sourceIP   = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'IpAddress' }).'#text'
            $loginsFalhados += @{
                timestamp   = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                utilizador  = if ($targetUser) { $targetUser } else { "N/A" }
                origemIP    = if ($sourceIP -and $sourceIP -ne "-") { $sourceIP } else { "Local" }
            }
        }
    } catch {}

    # Logins com sucesso (Event ID 4624, tipos interativos)
    $loginsSucesso = @()
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Id        = 4624
            StartTime = $desde
        } -MaxEvents 30 -ErrorAction SilentlyContinue

        foreach ($evt in $events) {
            $xml = [xml]$evt.ToXml()
            $targetUser = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
            $logonType  = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'LogonType' }).'#text'

            # So logins interativos (2=local, 10=RDP, 7=desbloqueio)
            if ($logonType -in @("2","7","10") -and $targetUser -notlike '*$' -and $targetUser -ne 'SYSTEM') {
                $loginsSucesso += @{
                    timestamp  = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                    utilizador = $targetUser
                    tipo       = switch ($logonType) { "2"{"Local"} "7"{"Desbloqueio"} "10"{"RDP"} default{$logonType} }
                }
            }
        }
        $loginsSucesso = $loginsSucesso | Select-Object -First 15
    } catch {}

    # Portas abertas com processos
    $portasAbertas = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Sort-Object LocalPort | Select-Object -First 20 | ForEach-Object {
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            @{
                porta    = $_.LocalPort
                processo = if ($proc) { $proc.ProcessName } else { "N/A" }
                pid      = $_.OwningProcess
            }
        }

    # Estado do Firewall
    $firewallStatus = @()
    try {
        $profiles = Get-NetFirewallProfile
        foreach ($p in $profiles) {
            $firewallStatus += @{
                perfil = $p.Name
                ativo  = [bool]$p.Enabled
            }
        }
    } catch {}

    # Alertas de seguranca
    $alertas = @()
    $totalFalhados = ($loginsFalhados | Measure-Object).Count
    if ($totalFalhados -gt 5) {
        $alertas += @{ tipo = "warning"; mensagem = "$totalFalhados tentativas de login falhadas nas ultimas ${Horas}h" }
    }
    if ($totalFalhados -gt 20) {
        $alertas += @{ tipo = "critical"; mensagem = "Possivel ataque de forca bruta: $totalFalhados logins falhados!" }
    }

    # Verificar contas bloqueadas
    $contasBloqueadas = @()
    try {
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        $contasBloqueadas = Search-ADAccount -LockedOut -ErrorAction SilentlyContinue | ForEach-Object {
            @{ username = $_.SamAccountName; nome = $_.Name }
        }
        if (($contasBloqueadas | Measure-Object).Count -gt 0) {
            $alertas += @{ tipo = "warning"; mensagem = "$(($contasBloqueadas | Measure-Object).Count) conta(s) bloqueada(s) no AD" }
        }
    } catch {}

    $resultado = @{
        timestamp        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        periodo          = "Ultimas ${Horas}h"
        loginsFalhados   = $loginsFalhados
        loginsSucesso    = $loginsSucesso
        totalFalhados    = $totalFalhados
        totalSucesso     = ($loginsSucesso | Measure-Object).Count
        portasAbertas    = $portasAbertas
        firewall         = $firewallStatus
        contasBloqueadas = $contasBloqueadas
        alertas          = $alertas
    }

    $resultado | ConvertTo-Json -Depth 5
    return
}

# ── Funcoes CLI ──

function Logins-Falhados {
    Write-Host ""
    Write-Host "  TENTATIVAS DE LOGIN FALHADAS (ultimas ${Horas}h)" -ForegroundColor Cyan
    Write-Host "  =================================================" -ForegroundColor Cyan
    $desde = (Get-Date).AddHours(-$Horas)

    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Id        = 4625
            StartTime = $desde
        } -MaxEvents 50 -ErrorAction Stop

        foreach ($evt in $events) {
            $xml = [xml]$evt.ToXml()
            $user = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
            $ip   = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'IpAddress' }).'#text'
            $time = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            Write-Host "  [FALHA] $time | User: $user | IP: $ip" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "  Total: $($events.Count) tentativas falhadas" -ForegroundColor Yellow
    } catch {
        Write-Host "  [INFO] Nenhuma tentativa falhada encontrada ou sem permissao." -ForegroundColor Green
    }
    Write-Log "Analise de logins falhados: ultimas ${Horas}h"
}

function Eventos-Seguranca {
    Write-Host ""
    Write-Host "  EVENTOS DE SEGURANCA RECENTES" -ForegroundColor Cyan
    $desde = (Get-Date).AddHours(-$Horas)

    $eventIds = @{
        4624 = "Login com sucesso"
        4625 = "Login falhado"
        4634 = "Logoff"
        4648 = "Login com credenciais explicitas"
        4720 = "Conta criada"
        4722 = "Conta ativada"
        4725 = "Conta desativada"
        4726 = "Conta eliminada"
        4740 = "Conta bloqueada"
    }

    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            Id        = @(4624,4625,4720,4722,4725,4726,4740)
            StartTime = $desde
        } -MaxEvents 30

        foreach ($evt in $events) {
            $desc = if ($eventIds.ContainsKey($evt.Id)) { $eventIds[$evt.Id] } else { "Event $($evt.Id)" }
            $cor  = if ($evt.Id -eq 4625 -or $evt.Id -eq 4740) { "Red" } else { "Gray" }
            Write-Host "  [$($evt.Id)] $($evt.TimeCreated.ToString('HH:mm:ss')) - $desc" -ForegroundColor $cor
        }
    } catch {
        Write-Host "  [INFO] Sem eventos ou sem permissao para ler o log de seguranca." -ForegroundColor Yellow
    }
}

function Estado-Firewall {
    Write-Host ""
    Write-Host "  ESTADO DO FIREWALL" -ForegroundColor Cyan
    Write-Host "  ===================" -ForegroundColor Cyan
    try {
        $profiles = Get-NetFirewallProfile
        foreach ($p in $profiles) {
            $estado = if ($p.Enabled) { "[ATIVO]" } else { "[INATIVO]" }
            $cor    = if ($p.Enabled) { "Green" } else { "Red" }
            Write-Host "  $estado $($p.Name)" -ForegroundColor $cor
        }
    } catch {
        Write-Host "  [ERRO] Nao foi possivel verificar o firewall." -ForegroundColor Red
    }
}

function Politicas-Seguranca {
    Write-Host ""
    Write-Host "  POLITICAS DE SEGURANCA" -ForegroundColor Cyan
    Write-Host "  =======================" -ForegroundColor Cyan

    # Politica de passwords
    try {
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        $policy = Get-ADDefaultDomainPasswordPolicy
        Write-Host "  Password minima: $($policy.MinPasswordLength) caracteres" -ForegroundColor Gray
        Write-Host "  Historico:       $($policy.PasswordHistoryCount) passwords" -ForegroundColor Gray
        Write-Host "  Complexidade:    $(if($policy.ComplexityEnabled){'Ativa'}else{'Inativa'})" -ForegroundColor Gray
        Write-Host "  Expiracao:       $($policy.MaxPasswordAge.Days) dias" -ForegroundColor Gray
        Write-Host "  Bloqueio apos:   $($policy.LockoutThreshold) tentativas" -ForegroundColor Gray
    } catch {
        Write-Host "  [INFO] Active Directory nao disponivel." -ForegroundColor Yellow
    }

    # Contas bloqueadas
    Write-Host ""
    Write-Host "  CONTAS BLOQUEADAS:" -ForegroundColor Yellow
    try {
        $locked = Search-ADAccount -LockedOut
        if ($locked) {
            foreach ($l in $locked) {
                Write-Host "  [BLOQUEADO] $($l.SamAccountName) - $($l.Name)" -ForegroundColor Red
            }
        } else {
            Write-Host "  [OK] Nenhuma conta bloqueada." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [INFO] Nao foi possivel verificar." -ForegroundColor Yellow
    }
}

# ── Execucao ──
switch ($Acao) {
    "logins"    { Logins-Falhados }
    "eventos"   { Eventos-Seguranca }
    "portas"    { & "$ProjectRoot\scripts\network\Monitor-Network.ps1" portas }
    "firewall"  { Estado-Firewall }
    "politicas" { Politicas-Seguranca }
    "relatorio" { Logins-Falhados; Eventos-Seguranca; Estado-Firewall; Politicas-Seguranca }
    default {
        Write-Host ""
        Write-Host "  Uso: .\Monitor-Security.ps1 <acao> [-Horas 24]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Acoes: logins, eventos, portas, firewall, politicas, relatorio, json"
        Write-Host ""
    }
}
