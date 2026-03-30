# Setup-Server.ps1
# Passo 1 de 2 - Configurar hostname, IP estatico e instalar roles
# Executar como Administrador no Windows Server
# O servidor vai REINICIAR no final

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SETUP SERVIDOR - PASSO 1/2" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Pasta do projeto: $ProjectRoot" -ForegroundColor Gray
Write-Host "  Preenche as opcoes abaixo." -ForegroundColor Gray
Write-Host "  Prime ENTER para aceitar o valor sugerido." -ForegroundColor Gray
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
            Write-Host "  [ERRO] Formato invalido. Exemplo: 192.168.1.10" -ForegroundColor Red
            Write-Host ""
        }
    } while (-not $valido)
    return $val
}

function Prompt-Int {
    param([string]$Mensagem, [string]$Sugestao, [int]$Min, [int]$Max)
    do {
        $val = Prompt-Value -Mensagem $Mensagem -Sugestao $Sugestao
        $num = 0
        $valido = [int]::TryParse($val, [ref]$num) -and $num -ge $Min -and $num -le $Max
        if (-not $valido) {
            Write-Host ("  [ERRO] Valor deve ser entre " + $Min + " e " + $Max + ".") -ForegroundColor Red
            Write-Host ""
        }
    } while (-not $valido)
    return $num
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

Write-Host "-- Identificacao do Servidor --" -ForegroundColor White
$Hostname = Prompt-Value -Mensagem "Hostname do servidor" -Sugestao "SRV-ATEC"

Write-Host ""
Write-Host "-- Configuracao de Rede --" -ForegroundColor White
$IPAddress     = Prompt-IP  -Mensagem "Endereco IP do servidor"              -Sugestao "192.168.1.10"
$PrefixLength  = Prompt-Int -Mensagem "Prefixo da mascara (24 = /24)"        -Sugestao "24" -Min 8 -Max 30
$Gateway       = Prompt-IP  -Mensagem "Gateway (IP do pfSense)"              -Sugestao "192.168.1.1"
$DNSPrimario   = Prompt-IP  -Mensagem "DNS Primario (127.0.0.1 = si mesmo)"  -Sugestao "127.0.0.1"
$DNSSecundario = Prompt-IP  -Mensagem "DNS Secundario (fallback externo)"    -Sugestao "8.8.8.8"

Write-Host ""
Write-Host "-- Roles a Instalar --" -ForegroundColor White
$instalarPrint = Prompt-SimNao -Mensagem "Instalar Print Server?"                           -Sugestao "S"
$instalarIIS   = Prompt-SimNao -Mensagem "Instalar IIS (necessario para o Dashboard Web)?"  -Sugestao "S"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RESUMO DAS OPCOES:" -ForegroundColor White
Write-Host "  Hostname       : $Hostname"
Write-Host "  IP             : $IPAddress/$PrefixLength"
Write-Host "  Gateway        : $Gateway"
Write-Host "  DNS Primario   : $DNSPrimario"
Write-Host "  DNS Secundario : $DNSSecundario"
Write-Host ("  Print Server   : " + $(if($instalarPrint){"Sim"}else{"Nao"}))
Write-Host ("  IIS Dashboard  : " + $(if($instalarIIS){"Sim"}else{"Nao"}))
Write-Host "============================================"
Write-Host ""

$confirma = Prompt-SimNao -Mensagem "Prosseguir com estas opcoes?" -Sugestao "S"
if (-not $confirma) {
    Write-Host "[CANCELADO] Executa o script novamente para reconfigurar." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# 1. HOSTNAME
Write-Host "[1/4] A configurar hostname para '$Hostname'..." -ForegroundColor Yellow
$atual = $env:COMPUTERNAME
if ($atual -ne $Hostname) {
    Rename-Computer -NewName $Hostname -Force
    Write-Host "[OK] Hostname alterado de '$atual' para '$Hostname'" -ForegroundColor Green
} else {
    Write-Host "[JA OK] Hostname ja e '$Hostname'" -ForegroundColor Gray
}

# 2. IP ESTATICO
Write-Host ""
Write-Host "[2/4] A configurar IP estatico ($IPAddress)..." -ForegroundColor Yellow

$adaptador = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if ($null -eq $adaptador) {
    Write-Host "[ERRO] Nenhum adaptador de rede ativo encontrado!" -ForegroundColor Red
    exit 1
}
Write-Host "       Adaptador detetado: $($adaptador.Name)" -ForegroundColor Gray

Remove-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute     -InterfaceIndex $adaptador.ifIndex -DestinationPrefix "0.0.0.0/0"      -Confirm:$false -ErrorAction SilentlyContinue

New-NetIPAddress `
    -InterfaceIndex $adaptador.ifIndex `
    -IPAddress      $IPAddress `
    -PrefixLength   $PrefixLength `
    -DefaultGateway $Gateway | Out-Null

Set-DnsClientServerAddress `
    -InterfaceIndex  $adaptador.ifIndex `
    -ServerAddresses @($DNSPrimario, $DNSSecundario)

Write-Host "[OK] IP: $IPAddress/$PrefixLength | Gateway: $Gateway | DNS: $DNSPrimario, $DNSSecundario" -ForegroundColor Green

# 3. ROLES
Write-Host ""
Write-Host "[3/4] A instalar roles..." -ForegroundColor Yellow
Write-Host "       Isto pode demorar alguns minutos..." -ForegroundColor Gray

$roles = @(
    "AD-Domain-Services",
    "DNS",
    "FS-FileServer",
    "RSAT-AD-PowerShell",
    "RSAT-DNS-Server"
)
if ($instalarPrint) { $roles += "Print-Server" }
if ($instalarIIS)   { $roles += @("Web-Server", "Web-CGI", "Web-Scripting-Tools") }

$resultado = Install-WindowsFeature -Name $roles -IncludeManagementTools

if ($resultado.Success) {
    Write-Host "[OK] Roles instaladas:" -ForegroundColor Green
    $roles | ForEach-Object { Write-Host "     + $_" -ForegroundColor Gray }
} else {
    Write-Host "[AVISO] Algumas roles podem nao ter instalado corretamente." -ForegroundColor Red
}

# 4. LOG
Write-Host ""
Write-Host "[4/4] A guardar log..." -ForegroundColor Yellow
$logDir = "$ProjectRoot\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Setup-Server.ps1 concluido. Hostname: $Hostname | IP: $IPAddress"
Add-Content -Path "$logDir\setup.log" -Value $logEntry
Write-Host "[OK] Log guardado em $logDir\setup.log" -ForegroundColor Green

# REINICIO
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PASSO 1 CONCLUIDO!" -ForegroundColor Green
Write-Host "  Apos o reinicio, executa: .\Setup-ADDomain.ps1" -ForegroundColor White
Write-Host "============================================"
Write-Host ""

$reinicia = Prompt-SimNao -Mensagem "Reiniciar agora?" -Sugestao "S"
if ($reinicia) {
    Restart-Computer -Force
} else {
    Write-Host "[AVISO] Reinicia manualmente antes de correr o Setup-ADDomain.ps1" -ForegroundColor Yellow
}
