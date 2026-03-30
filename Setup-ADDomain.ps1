# Setup-ADDomain.ps1
# Passo 2 de 2 - Promover a Domain Controller e criar a forest
# Executar como Administrador APOS reinicio do Setup-Server.ps1
# O servidor vai REINICIAR automaticamente no final

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SETUP AD DS - PASSO 2/2" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Preenche as opcoes abaixo." -ForegroundColor Gray
Write-Host "  Prime ENTER para aceitar o valor sugerido." -ForegroundColor Gray
Write-Host ""

function Prompt-Value {
    param([string]$Mensagem, [string]$Sugestao)
    $val = Read-Host "$Mensagem [$Sugestao]"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Sugestao }
    return $val.Trim()
}

function Prompt-SimNao {
    param([string]$Mensagem, [string]$Sugestao = "S")
    do {
        $val = Prompt-Value -Mensagem $Mensagem -Sugestao $Sugestao
        $valido = $val -match '^[SsNn]$'
        if (-not $valido) {
            Write-Host "  [ERRO] Responde com S ou N." -ForegroundColor Red
            Write-Host ""
        }
    } while (-not $valido)
    return ($val -match '^[Ss]$')
}

function Prompt-Password {
    param([string]$Mensagem)
    do {
        $p1 = Read-Host "$Mensagem" -AsSecureString
        $p2 = Read-Host "Confirma a password" -AsSecureString
        $p1plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
        $p2plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
        if ($p1plain -ne $p2plain) {
            Write-Host "  [ERRO] As passwords nao coincidem. Tenta novamente." -ForegroundColor Red
            Write-Host ""
            $iguais = $false
        } elseif ($p1plain.Length -lt 8) {
            Write-Host "  [ERRO] A password deve ter pelo menos 8 caracteres." -ForegroundColor Red
            Write-Host ""
            $iguais = $false
        } else {
            $iguais = $true
        }
    } while (-not $iguais)
    return $p1
}

Write-Host "-- Configuracao do Dominio --" -ForegroundColor White
$DomainName    = Prompt-Value -Mensagem "Nome do dominio (FQDN)"          -Sugestao "atec.local"
$DomainNetbios = Prompt-Value -Mensagem "Nome NetBIOS (aparece no login)" -Sugestao "ATEC"

Write-Host ""
Write-Host "-- Password de Recuperacao (DSRM) --" -ForegroundColor White
Write-Host "  Usada em modo de recuperacao do AD. Guarda-a num local seguro." -ForegroundColor Gray
$DSRMPassword = Prompt-Password -Mensagem "Password DSRM"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RESUMO DAS OPCOES:" -ForegroundColor White
Write-Host "  Dominio FQDN : $DomainName"
Write-Host "  NetBIOS      : $DomainNetbios"
Write-Host "  Forest Mode  : Windows Server 2016+ (WinThreshold)"
Write-Host "  DNS Server   : Sera instalado automaticamente"
Write-Host "============================================"
Write-Host ""
Write-Host "  ATENCAO: O servidor vai REINICIAR automaticamente no final." -ForegroundColor Yellow
Write-Host ""

$confirma = Prompt-SimNao -Mensagem "Prosseguir e promover a Domain Controller?" -Sugestao "S"
if (-not $confirma) {
    Write-Host "[CANCELADO] Executa o script novamente para reconfigurar." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# 1. VERIFICAR PRE-REQUISITOS
Write-Host "[1/3] A verificar pre-requisitos..." -ForegroundColor Yellow

$adFeature = Get-WindowsFeature -Name AD-Domain-Services
if (-not $adFeature.Installed) {
    Write-Host "[ERRO] AD-Domain-Services nao esta instalado!" -ForegroundColor Red
    Write-Host "       Executa primeiro o Setup-Server.ps1" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] AD DS instalado." -ForegroundColor Green

$isDC = (Get-WmiObject -Class Win32_ComputerSystem).DomainRole
if ($isDC -ge 4) {
    Write-Host "[JA OK] Este servidor ja e Domain Controller." -ForegroundColor Gray
    exit 0
}

# 2. PROMOVER A DC
Write-Host ""
Write-Host "[2/3] A promover Domain Controller para '$DomainName'..." -ForegroundColor Yellow
Write-Host "       O servidor vai reiniciar automaticamente no final." -ForegroundColor Gray
Write-Host ""

Import-Module ADDSDeployment

Install-ADDSForest `
    -DomainName                    $DomainName `
    -DomainNetbiosName             $DomainNetbios `
    -SafeModeAdministratorPassword $DSRMPassword `
    -DomainMode                    "WinThreshold" `
    -ForestMode                    "WinThreshold" `
    -DatabasePath                  "C:\Windows\NTDS" `
    -LogPath                       "C:\Windows\NTDS" `
    -SysvolPath                    "C:\Windows\SYSVOL" `
    -InstallDns                    $true `
    -Force                         $true `
    -NoRebootOnCompletion          $false

# 3. LOG
Write-Host ""
Write-Host "[3/3] A guardar log..." -ForegroundColor Yellow
$logDir = "$ProjectRoot\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Setup-ADDomain.ps1 concluido. Dominio: $DomainName"
Add-Content -Path "$logDir\setup.log" -Value $logEntry

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  AD DS CONFIGURADO COM SUCESSO!" -ForegroundColor Green
Write-Host "  Dominio : $DomainName  |  NetBIOS: $DomainNetbios" -ForegroundColor White
Write-Host ""
Write-Host "  Apos reinicio, verifica com:" -ForegroundColor White
Write-Host "  Get-ADDomain" -ForegroundColor Yellow
Write-Host "  Resolve-DnsName $DomainName" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Depois junta o cliente ao dominio '$DomainName'" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Cyan
