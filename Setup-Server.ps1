# Setup-Server.ps1
# Passo 1 de 2 - Configurar hostname, IP estatico e instalar roles base
# Executar como Administrador no Windows Server

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SETUP SERVIDOR - PASSO 1/2" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

function Prompt-Value {
    param([string]$Mensagem, [string]$Sugestao)
    $val = Read-Host "$Mensagem [$Sugestao]"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Sugestao }
    return $val.Trim()
}

function Prompt-IP {
    param([string]$Mensagem, [string]$Sugestao)
    do {
        $val = Prompt-Value -Mensagem $Mensagem -Sugestao $Sugestao
        $valido = $val -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$'
        if (-not $valido) {
            Write-Host "  [ERRO] IP Invalido." -ForegroundColor Red
        }
    } while (-not $valido)
    return $val
}

function Prompt-SimNao {
    param([string]$Mensagem, [string]$Sugestao = "S")
    do {
        $val = Prompt-Value -Mensagem $Mensagem -Sugestao $Sugestao
        $valido = $val -match '^[SsNn]$'
        if (-not $valido) {
            Write-Host "  [ERRO] S ou N." -ForegroundColor Red
        }
    } while (-not $valido)
    return ($val -match '^[Ss]$')
}

$Hostname      = Prompt-Value -Mensagem "Hostname do servidor" -Sugestao "SRV-WINDOWS"
$IPAddress     = Prompt-IP  -Mensagem "Endereco IP do servidor" -Sugestao "192.168.1.10"
$Gateway       = Prompt-IP  -Mensagem "Gateway (IP do pfSense)" -Sugestao "192.168.1.1"
$DNSPrimario   = Prompt-IP  -Mensagem "DNS Primario (127.0.0.1 = si mesmo)" -Sugestao "127.0.0.1"
$instalarPrint = Prompt-SimNao -Mensagem "Instalar Print Server?" -Sugestao "S"

Write-Host ""
Write-Host "[1/3] A configurar Hostname..." -ForegroundColor Yellow
if ($env:COMPUTERNAME -ne $Hostname) { Rename-Computer -NewName $Hostname -Force }

Write-Host "[2/3] A configurar IP..." -ForegroundColor Yellow
$adaptador = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if ($null -eq $adaptador) {
    Write-Host "[ERRO] Nenhum adaptador de rede ativo encontrado!" -ForegroundColor Red
    exit 1
}

# Limpar o IP antigo E o Gateway antigo para não haver conflitos!
Remove-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute     -InterfaceIndex $adaptador.ifIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue

New-NetIPAddress -InterfaceIndex $adaptador.ifIndex -IPAddress $IPAddress -PrefixLength 24 -DefaultGateway $Gateway | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ServerAddresses @($DNSPrimario, "8.8.8.8")

Write-Host "[3/3] A instalar Roles Base (AD, DNS, File Server)..." -ForegroundColor Yellow
$roles = @("AD-Domain-Services", "DNS", "FS-FileServer", "RSAT-AD-PowerShell", "RSAT-DNS-Server")
if ($instalarPrint) { $roles += "Print-Server" }

Install-WindowsFeature -Name $roles -IncludeManagementTools | Out-Null

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PASSO 1 CONCLUIDO!" -ForegroundColor Green
Write-Host "  O servidor vai reiniciar agora." -ForegroundColor White
Write-Host "  Apos o reinicio, executa: .\Setup-ADDomain.ps1" -ForegroundColor Yellow
Write-Host "============================================"
Start-Sleep -Seconds 5
Restart-Computer -Force