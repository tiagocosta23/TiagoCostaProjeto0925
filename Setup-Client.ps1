# ==============================================================
# Setup-Client.ps1
# Configurar IP estático e juntar o cliente ao domínio
# Executar como Administrador no Windows 10/11 Cliente
# O cliente vai REINICIAR no final
# ==============================================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SETUP CLIENTE" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan
Write-Host "  Preenche as opcoes abaixo." -ForegroundColor Gray
Write-Host "  Prime ENTER para aceitar o valor sugerido.`n" -ForegroundColor Gray

# ── FUNÇÕES DE INPUT ────────────────────────────────────────────

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
            Write-Host "  [ERRO] Formato invalido. Exemplo: 192.168.1.20" -ForegroundColor Red
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

# ── RECOLHA DE PARÂMETROS ───────────────────────────────────────

Write-Host "-- Configuracao de Rede do Cliente --" -ForegroundColor White
$IPAddress    = Prompt-IP  -Mensagem "Endereco IP do cliente"           -Sugestao "192.168.1.20"
$PrefixLength = Prompt-Int -Mensagem "Prefixo da mascara (24 = /24)"   -Sugestao "24" -Min 8 -Max 30
$Gateway      = Prompt-IP  -Mensagem "Gateway (IP do pfSense)"         -Sugestao "192.168.1.1"
$DNS          = Prompt-IP  -Mensagem "DNS (IP do servidor / DC)"       -Sugestao "192.168.1.10"

Write-Host "`n-- Adesao ao Dominio --" -ForegroundColor White
$DomainName  = Prompt-Value -Mensagem "Nome do dominio (FQDN)" -Sugestao "atec.local"
$DomainAdmin = Prompt-Value -Mensagem "Utilizador administrador do dominio" -Sugestao "Administrator"

# ── CONFIRMAÇÃO ─────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  RESUMO DAS OPCOES:" -ForegroundColor White
Write-Host "  IP Cliente   : $IPAddress/$PrefixLength"
Write-Host "  Gateway      : $Gateway"
Write-Host "  DNS (DC)     : $DNS"
Write-Host "  Dominio      : $DomainName"
Write-Host "  Admin        : $DomainAdmin"
Write-Host "============================================`n" -ForegroundColor Cyan

$confirma = Prompt-SimNao -Mensagem "Prosseguir com estas opcoes?" -Sugestao "S"
if (-not $confirma) {
    Write-Host "[CANCELADO] Executa o script novamente para reconfigurar." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# ── 1. IP ESTÁTICO ──────────────────────────────────────────────
Write-Host "[1/3] A configurar IP estatico ($IPAddress)..." -ForegroundColor Yellow

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
    -ServerAddresses $DNS

Write-Host "[OK] IP: $IPAddress/$PrefixLength | Gateway: $Gateway | DNS: $DNS" -ForegroundColor Green

# ── 2. TESTAR CONECTIVIDADE ─────────────────────────────────────
Write-Host "`n[2/3] A testar conectividade com o servidor..." -ForegroundColor Yellow

$pingOK = Test-Connection -ComputerName $DNS -Count 2 -Quiet
if (-not $pingOK) {
    Write-Host "[ERRO] Nao foi possivel fazer ping ao servidor ($DNS)!" -ForegroundColor Red
    Write-Host "       Verifica se o servidor esta UP e acessivel na rede." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Servidor acessivel ($DNS)." -ForegroundColor Green

$dnsOK = Resolve-DnsName $DomainName -ErrorAction SilentlyContinue
if (-not $dnsOK) {
    Write-Host "[ERRO] DNS nao resolve '$DomainName'!" -ForegroundColor Red
    Write-Host "       Verifica se o AD DS esta configurado no servidor." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] DNS resolve '$DomainName' corretamente." -ForegroundColor Green

# ── 3. JUNTAR AO DOMÍNIO ────────────────────────────────────────
Write-Host "`n[3/3] A juntar ao dominio '$DomainName'..." -ForegroundColor Yellow
Write-Host "       Introduz a password do utilizador '$DomainAdmin':" -ForegroundColor Gray

$cred = Get-Credential -UserName "$DomainName\$DomainAdmin" -Message "Password do administrador do dominio '$DomainName'"

try {
    Add-Computer -DomainName $DomainName -Credential $cred -Force -ErrorAction Stop
    Write-Host "[OK] Maquina adicionada ao dominio '$DomainName'!" -ForegroundColor Green
} catch {
    Write-Host "[ERRO] Falhou ao juntar ao dominio:" -ForegroundColor Red
    Write-Host "       $_" -ForegroundColor Red
    exit 1
}

# ── REINÍCIO ────────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  CLIENTE CONFIGURADO!" -ForegroundColor Green
Write-Host "  Apos reinicio, faz login com:" -ForegroundColor White
Write-Host "  $DomainName\$DomainAdmin  (ou qualquer utilizador do dominio)" -ForegroundColor Yellow
Write-Host "============================================`n" -ForegroundColor Cyan

$reinicia = Prompt-SimNao -Mensagem "Reiniciar agora?" -Sugestao "S"
if ($reinicia) {
    Restart-Computer -Force
} else {
    Write-Host "[AVISO] Reinicia manualmente para completar a adesao ao dominio." -ForegroundColor Yellow
}
