# Setup-Server.ps1
# Passo 1 de 2 - Configurar hostname, IP estatico, opcoes de rede e instalar roles base
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

function Prompt-Int {
    param([string]$Mensagem, [string]$Sugestao, [int]$Min, [int]$Max)
    do {
        $val = Prompt-Value -Mensagem $Mensagem -Sugestao $Sugestao
        $num = 0
        $valido = [int]::TryParse($val, [ref]$num) -and $num -ge $Min -and $num -le $Max
        if (-not $valido) {
            Write-Host "  [ERRO] Valor deve ser entre $Min e $Max." -ForegroundColor Red
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
            Write-Host "  [ERRO] S ou N." -ForegroundColor Red
        }
    } while (-not $valido)
    return ($val -match '^[Ss]$')
}

# ── Configuracao de Rede ──
Write-Host "-- Configuracao de Rede --" -ForegroundColor White
$Hostname      = Prompt-Value -Mensagem "Hostname do servidor" -Sugestao "SRV-WINDOWS"
$IPAddress     = Prompt-IP    -Mensagem "Endereco IP do servidor" -Sugestao "192.168.1.10"
$PrefixLength  = Prompt-Int   -Mensagem "Prefixo da mascara (24 = /24)" -Sugestao "24" -Min 8 -Max 30
$Gateway       = Prompt-IP    -Mensagem "Gateway (IP do pfSense)" -Sugestao "192.168.1.1"
$DNSPrimario   = Prompt-IP    -Mensagem "DNS Primario (127.0.0.1 = si mesmo)" -Sugestao "127.0.0.1"
$DNSSecundario = Prompt-IP    -Mensagem "DNS Secundario" -Sugestao "8.8.8.8"

Write-Host ""
Write-Host "-- Opcoes Adicionais --" -ForegroundColor White

# Timezone
$timezones = @{
    "1" = "GMT Standard Time"
    "2" = "W. Europe Standard Time"
    "3" = "Central European Standard Time"
    "4" = "Eastern Standard Time"
    "5" = "Pacific Standard Time"
}
Write-Host "  Timezones disponiveis:" -ForegroundColor Gray
Write-Host "    1. GMT (Londres/Lisboa)"
Write-Host "    2. W. Europe (Berlim/Paris)"
Write-Host "    3. Central European (Praga)"
Write-Host "    4. Eastern (Nova Iorque)"
Write-Host "    5. Pacific (Los Angeles)"
$tzChoice = Prompt-Value -Mensagem "Timezone" -Sugestao "1"
$Timezone = if ($timezones.ContainsKey($tzChoice)) { $timezones[$tzChoice] } else { "GMT Standard Time" }

$desativarIPv6   = Prompt-SimNao -Mensagem "Desativar IPv6?" -Sugestao "S"
$ativarRDP       = Prompt-SimNao -Mensagem "Ativar Remote Desktop (RDP)?" -Sugestao "S"
$desativarIEESC  = Prompt-SimNao -Mensagem "Desativar IE Enhanced Security?" -Sugestao "S"
$instalarPrint   = Prompt-SimNao -Mensagem "Instalar Print Server?" -Sugestao "S"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RESUMO DAS OPCOES:" -ForegroundColor White
Write-Host "  Hostname       : $Hostname"
Write-Host "  IP             : $IPAddress/$PrefixLength"
Write-Host "  Gateway        : $Gateway"
Write-Host "  DNS Primario   : $DNSPrimario"
Write-Host "  DNS Secundario : $DNSSecundario"
Write-Host "  Timezone       : $Timezone"
Write-Host "  IPv6           : $(if($desativarIPv6){'Desativado'}else{'Ativado'})"
Write-Host "  RDP            : $(if($ativarRDP){'Ativado'}else{'Desativado'})"
Write-Host "  IE ESC         : $(if($desativarIEESC){'Desativado'}else{'Ativado'})"
Write-Host "  Print Server   : $(if($instalarPrint){'Sim'}else{'Nao'})"
Write-Host "============================================"
Write-Host ""

$confirma = Prompt-SimNao -Mensagem "Prosseguir com estas opcoes?" -Sugestao "S"
if (-not $confirma) {
    Write-Host "[CANCELADO] Executa o script novamente para reconfigurar." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# ── 1. Hostname ──
Write-Host "[1/7] A configurar Hostname..." -ForegroundColor Yellow
if ($env:COMPUTERNAME -ne $Hostname) {
    Rename-Computer -NewName $Hostname -Force
    Write-Host "       Hostname definido: $Hostname" -ForegroundColor Green
} else {
    Write-Host "       Hostname ja esta correto." -ForegroundColor Gray
}

# ── 2. IP Estatico ──
Write-Host "[2/7] A configurar IP..." -ForegroundColor Yellow
$adaptador = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if ($null -eq $adaptador) {
    Write-Host "[ERRO] Nenhum adaptador de rede ativo encontrado!" -ForegroundColor Red
    exit 1
}
Write-Host "       Adaptador detetado: $($adaptador.Name)" -ForegroundColor Gray

# Limpar o IP antigo E o Gateway antigo para nao haver conflitos
Remove-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute     -InterfaceIndex $adaptador.ifIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue

New-NetIPAddress -InterfaceIndex $adaptador.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ServerAddresses @($DNSPrimario, $DNSSecundario)
Write-Host "       IP: $IPAddress/$PrefixLength | GW: $Gateway | DNS: $DNSPrimario, $DNSSecundario" -ForegroundColor Green

# ── 3. Desativar IPv6 ──
Write-Host "[3/7] A configurar IPv6..." -ForegroundColor Yellow
if ($desativarIPv6) {
    # Desativar IPv6 em todos os adaptadores
    Get-NetAdapterBinding -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | ForEach-Object {
        Disable-NetAdapterBinding -Name $_.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    }
    # Desativar IPv6 via registo (metodo mais fiavel, requer reboot)
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 0xFF -Type DWord -Force
    Write-Host "       IPv6 desativado." -ForegroundColor Green
} else {
    Write-Host "       IPv6 mantido ativo." -ForegroundColor Gray
}

# ── 4. Timezone ──
Write-Host "[4/7] A definir timezone..." -ForegroundColor Yellow
Set-TimeZone -Id $Timezone
Write-Host "       Timezone: $Timezone" -ForegroundColor Green

# ── 5. Remote Desktop ──
Write-Host "[5/7] A configurar Remote Desktop..." -ForegroundColor Yellow
if ($ativarRDP) {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Write-Host "       RDP ativado." -ForegroundColor Green
} else {
    Write-Host "       RDP nao alterado." -ForegroundColor Gray
}

# ── 6. IE Enhanced Security ──
Write-Host "[6/7] A configurar IE Enhanced Security..." -ForegroundColor Yellow
if ($desativarIEESC) {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey  = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0 -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $UserKey  -Name "IsInstalled" -Value 0 -Force -ErrorAction SilentlyContinue
    Write-Host "       IE ESC desativado (Admins + Users)." -ForegroundColor Green
} else {
    Write-Host "       IE ESC mantido." -ForegroundColor Gray
}

# ── 7. Instalar Roles ──
Write-Host "[7/7] A instalar Roles Base (AD, DNS, File Server)..." -ForegroundColor Yellow
$roles = @("AD-Domain-Services", "DNS", "FS-FileServer", "RSAT-AD-PowerShell", "RSAT-DNS-Server")
if ($instalarPrint) { $roles += "Print-Server" }

Install-WindowsFeature -Name $roles -IncludeManagementTools | Out-Null
Write-Host "       Roles instaladas: $($roles -join ', ')" -ForegroundColor Green

# ── Criar estrutura de dados operacionais ──
$DataRoot = "C:\SysAdmin"
@("$DataRoot\logs", "$DataRoot\reports", "$DataRoot\backups") | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PASSO 1 CONCLUIDO!" -ForegroundColor Green
Write-Host "  O servidor vai reiniciar agora." -ForegroundColor White
Write-Host "  Apos o reinicio, executa: .\Setup-ADDomain.ps1" -ForegroundColor Yellow
Write-Host "============================================"
Start-Sleep -Seconds 5
Restart-Computer -Force
