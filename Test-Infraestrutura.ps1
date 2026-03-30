# ==============================================================
# Test-Infraestrutura.ps1
# Verifica se toda a infraestrutura está operacional
# Executar no servidor após tudo configurado
# ==============================================================

# Deteta a pasta raiz do repositório automaticamente
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  TESTE DE INFRAESTRUTURA" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan
Write-Host "  Pasta do projeto: $ProjectRoot" -ForegroundColor Gray
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
            Write-Host "  [ERRO] Formato invalido. Exemplo: 192.168.1.1" -ForegroundColor Red
            Write-Host ""
        }
    } while (-not $valido)
    return $val
}

# ── RECOLHA DE PARÂMETROS ───────────────────────────────────────

Write-Host "-- IPs da Infraestrutura --" -ForegroundColor White
$IPGateway = Prompt-IP -Mensagem "IP do Gateway (pfSense)" -Sugestao "192.168.1.1"
$IPCliente = Prompt-IP -Mensagem "IP do Cliente"           -Sugestao "192.168.1.20"
$Dominio   = Prompt-Value -Mensagem "Nome do dominio (FQDN)" -Sugestao "atec.local"

Write-Host ""

# ── FUNÇÕES DE TESTE ─────────────────────────────────────────────
$erros = 0

function Test-OK   { param($msg) Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Test-ERR  { param($msg) Write-Host "  [FAIL] $msg" -ForegroundColor Red; $script:erros++ }
function Test-WARN { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }

# ── 1. CONECTIVIDADE DE REDE ─────────────────────────────────────
Write-Host "[1] Conectividade de Rede" -ForegroundColor White

if (Test-Connection $IPGateway -Count 1 -Quiet) { Test-OK  "Ping gateway pfSense ($IPGateway)" }
else                                             { Test-ERR "Ping gateway pfSense ($IPGateway)" }

if (Test-Connection $IPCliente -Count 1 -Quiet) { Test-OK  "Ping cliente ($IPCliente)" }
else                                             { Test-WARN "Ping cliente ($IPCliente) — pode estar offline" }

if (Test-Connection "8.8.8.8" -Count 1 -Quiet)  { Test-OK  "Acesso a internet (8.8.8.8)" }
else                                             { Test-ERR "Sem acesso a internet" }

# ── 2. ACTIVE DIRECTORY E DNS ────────────────────────────────────
Write-Host "`n[2] Active Directory e DNS" -ForegroundColor White

try {
    $domain = Get-ADDomain -ErrorAction Stop
    Test-OK "AD DS ativo — Dominio: $($domain.DNSRoot)"
} catch {
    Test-ERR "AD DS nao acessivel — $($_.Exception.Message)"
}

$dnsTest = Resolve-DnsName $Dominio -ErrorAction SilentlyContinue
if ($dnsTest) { Test-OK  "DNS resolve '$Dominio' → $($dnsTest[0].IPAddress)" }
else          { Test-ERR "DNS nao resolve '$Dominio'" }

# ── 3. ROLES INSTALADAS ──────────────────────────────────────────
Write-Host "`n[3] Windows Features / Roles" -ForegroundColor White

$roles = @{
    "AD-Domain-Services" = "Active Directory Domain Services"
    "DNS"                = "DNS Server"
    "FS-FileServer"      = "File Server"
    "Web-Server"         = "IIS"
    "Web-CGI"            = "IIS CGI"
}

foreach ($role in $roles.Keys) {
    $f = Get-WindowsFeature -Name $role
    if ($f.Installed) { Test-OK  "$($roles[$role]) instalado" }
    else              { Test-ERR "$($roles[$role]) NAO instalado ($role)" }
}

# ── 4. SERVIÇOS CRÍTICOS ─────────────────────────────────────────
Write-Host "`n[4] Servicos do Sistema" -ForegroundColor White

$servicos = @{
    "ADWS"     = "Active Directory Web Services"
    "DNS"      = "DNS Server"
    "Netlogon" = "Net Logon"
    "W3SVC"    = "IIS (World Wide Web)"
}

foreach ($svc in $servicos.Keys) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -eq "Running") { Test-OK  "$($servicos[$svc]) a correr" }
    elseif ($s)                          { Test-ERR "$($servicos[$svc]) parado (Status: $($s.Status))" }
    else                                 { Test-WARN "$($servicos[$svc]) nao encontrado" }
}

# ── 5. DASHBOARD WEB ─────────────────────────────────────────────
Write-Host "`n[5] Dashboard Web" -ForegroundColor White

try {
    $resp = Invoke-WebRequest -Uri "http://localhost" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
    if ($resp.StatusCode -eq 200) { Test-OK "Dashboard acessivel em http://localhost" }
    else                          { Test-ERR "Dashboard retornou HTTP $($resp.StatusCode)" }
} catch {
    Test-WARN "Dashboard nao acessivel — IIS pode nao estar configurado ainda"
}

# ── RESULTADO FINAL ──────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Cyan
if ($erros -eq 0) {
    Write-Host "  TUDO OK — Infraestrutura operacional!" -ForegroundColor Green
} else {
    Write-Host "  $erros ERRO(S) ENCONTRADO(S)" -ForegroundColor Red
    Write-Host "  Resolve os erros antes de avancar." -ForegroundColor Yellow
}
Write-Host "============================================`n" -ForegroundColor Cyan

# Guardar log
$logDir = "$ProjectRoot\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Test-Infraestrutura: $erros erros encontrados"
Add-Content -Path "$logDir\setup.log" -Value $logEntry
Write-Host "[LOG] Resultado guardado em $logDir\setup.log" -ForegroundColor Gray
