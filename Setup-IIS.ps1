# ==============================================================
# Setup-IIS.ps1
# Configura o IIS para servir o Dashboard Web e a API PowerShell
# Executar como Administrador no Windows Server
# Deve ser executado APÓS Setup-ADDomain.ps1 (após o 2º reinício)
# ==============================================================

# Deteta a pasta raiz do repositório automaticamente
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SETUP IIS — DASHBOARD WEB" -ForegroundColor Cyan
Write-Host "============================================`n" -ForegroundColor Cyan
Write-Host "  Pasta do projeto detetada: $ProjectRoot" -ForegroundColor Gray
Write-Host "  Preenche as opcoes abaixo." -ForegroundColor Gray
Write-Host "  Prime ENTER para aceitar o valor sugerido.`n" -ForegroundColor Gray

# ── FUNÇÕES DE INPUT ────────────────────────────────────────────

function Prompt-Value {
    param([string]$Mensagem, [string]$Sugestao)
    $val = Read-Host "$Mensagem [$Sugestao]"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Sugestao }
    return $val.Trim()
}

function Prompt-Int {
    param([string]$Mensagem, [string]$Sugestao, [int]$Min, [int]$Max)
    do {
        $val = Prompt-Value -Mensagem $Mensagem -Sugestao $Sugestao
        $num = 0
        $valido = [int]::TryParse($val, [ref]$num) -and $num -ge $Min -and $num -le $Max
        if (-not $valido) { Write-Host ("  [ERRO] Valor deve ser entre " + $Min + " e " + $Max + ".`n") -ForegroundColor Red }
    } while (-not $valido)
    return $num
}

function Prompt-SimNao {
    param([string]$Mensagem, [string]$Sugestao = "S")
    do {
        $val = Prompt-Value -Mensagem $Mensagem -Sugestao $Sugestao
        $valido = $val -match '^[SsNn]$'
        if (-not $valido) { Write-Host "  [ERRO] Responde com S ou N.`n" -ForegroundColor Red }
    } while (-not $valido)
    return ($val -match '^[Ss]$')
}

# ── RECOLHA DE PARÂMETROS ───────────────────────────────────────

Write-Host "-- Configuracao do Site IIS --" -ForegroundColor White
$NomeSite      = Prompt-Value -Mensagem "Nome do site IIS"                        -Sugestao "SistemaAdmin"
$PortaDashboard= Prompt-Int   -Mensagem "Porta do Dashboard (HTTP)"               -Sugestao "80" -Min 1 -Max 65535
$PortaAPI      = Prompt-Int   -Mensagem "Porta da API PowerShell"                 -Sugestao "8080" -Min 1 -Max 65535

Write-Host "`n-- Caminhos no Servidor --" -ForegroundColor White
$BaseDir       = Prompt-Value -Mensagem "Pasta base do projeto"                   -Sugestao $ProjectRoot
$DashboardPath = Prompt-Value -Mensagem "Pasta do Dashboard (ficheiros HTML/JS)"  -Sugestao "$BaseDir\dashboard"
$ApiPath       = Prompt-Value -Mensagem "Pasta da API (scripts wrapper IIS)"      -Sugestao "$BaseDir\iis-api"

# ── CONFIRMAÇÃO ─────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  RESUMO DAS OPCOES:" -ForegroundColor White
Write-Host "  Nome do site    : $NomeSite"
Write-Host "  Porta Dashboard : $PortaDashboard"
Write-Host "  Porta API       : $PortaAPI"
Write-Host "  Pasta base      : $BaseDir"
Write-Host "  Pasta dashboard : $DashboardPath"
Write-Host "  Pasta API       : $ApiPath"
Write-Host "============================================`n" -ForegroundColor Cyan

$confirma = Prompt-SimNao -Mensagem "Prosseguir com estas opcoes?" -Sugestao "S"
if (-not $confirma) {
    Write-Host "[CANCELADO] Executa o script novamente para reconfigurar." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# ── 1. VERIFICAR IIS ────────────────────────────────────────────
Write-Host "[1/6] A verificar se o IIS esta instalado..." -ForegroundColor Yellow
$iis = Get-WindowsFeature -Name Web-Server
if (-not $iis.Installed) {
    Write-Host "[ERRO] IIS nao esta instalado!" -ForegroundColor Red
    Write-Host "       Executa primeiro o Setup-Server.ps1 com IIS = S" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] IIS instalado." -ForegroundColor Green

# ── 2. CRIAR PASTAS ─────────────────────────────────────────────
Write-Host "`n[2/6] A garantir que as pastas existem..." -ForegroundColor Yellow
foreach ($p in @($DashboardPath, $ApiPath)) {
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Write-Host "[OK] Criada: $p" -ForegroundColor Green
    } else {
        Write-Host "[JA EXISTE] $p" -ForegroundColor Gray
    }
}

# ── 3. CONFIGURAR SITE IIS ──────────────────────────────────────
Write-Host "`n[3/6] A configurar site IIS '$NomeSite'..." -ForegroundColor Yellow
Import-Module WebAdministration

# Remove Default Web Site se existir
if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
    Remove-Website -Name "Default Web Site"
    Write-Host "       Removido 'Default Web Site'" -ForegroundColor Gray
}

# Remove site com o mesmo nome se já existir
if (Get-Website -Name $NomeSite -ErrorAction SilentlyContinue) {
    Remove-Website -Name $NomeSite
    Write-Host "       Removido site '$NomeSite' anterior" -ForegroundColor Gray
}

# Cria o site do Dashboard
New-Website -Name $NomeSite -Port $PortaDashboard -PhysicalPath $DashboardPath -Force | Out-Null
Write-Host "[OK] Site '$NomeSite' criado na porta $PortaDashboard → $DashboardPath" -ForegroundColor Green

# ── 4. CONFIGURAR VIRTUAL DIRECTORY /api ────────────────────────
Write-Host "`n[4/6] A criar virtual directory /api na porta $PortaAPI..." -ForegroundColor Yellow

# Remove app /api anterior se existir
if (Get-WebApplication -Site $NomeSite -Name "api" -ErrorAction SilentlyContinue) {
    Remove-WebApplication -Site $NomeSite -Name "api"
}

New-WebApplication -Site $NomeSite -Name "api" -PhysicalPath $ApiPath | Out-Null
Write-Host "[OK] Virtual directory /api → $ApiPath" -ForegroundColor Green

# ── 5. REGISTAR POWERSHELL COMO CGI HANDLER ─────────────────────
Write-Host "`n[5/6] A registar PowerShell como CGI handler..." -ForegroundColor Yellow

$psPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

# Remove handler anterior se existir
$handlers = Get-WebConfiguration -Filter "system.webServer/handlers/add[@name='PowerShellHandler']" `
    -PSPath "IIS:\Sites\$NomeSite\api" -ErrorAction SilentlyContinue
if ($handlers) {
    Remove-WebConfigurationLock -Filter "system.webServer/handlers" `
        -PSPath "IIS:\Sites\$NomeSite\api" -ErrorAction SilentlyContinue
}

Add-WebConfiguration -Filter "system.webServer/handlers" `
    -PSPath "IIS:\Sites\$NomeSite\api" -Value @{
        name            = "PowerShellHandler"
        path            = "*.ps1"
        verb            = "GET,POST"
        modules         = "CgiModule"
        scriptProcessor = "$psPath -NoProfile -NonInteractive -File `"%s`" %s"
        resourceType    = "File"
    }
Write-Host "[OK] Handler PowerShell (.ps1) registado no IIS." -ForegroundColor Green

# ── 6. PERMISSÕES ───────────────────────────────────────────────
Write-Host "`n[6/6] A definir permissoes para IIS_IUSRS..." -ForegroundColor Yellow

# Permissão de leitura/execução na pasta API
$acl = Get-Acl $ApiPath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "IIS_IUSRS", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($rule)
Set-Acl $ApiPath $acl
Write-Host "[OK] IIS_IUSRS com ReadAndExecute em $ApiPath" -ForegroundColor Green

# Permissão de escrita na pasta de logs (para os scripts escreverem logs via IIS)
$logPath = "$BaseDir\logs"
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }
$acl2 = Get-Acl $logPath
$rule2 = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "IIS_IUSRS", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl2.SetAccessRule($rule2)
Set-Acl $logPath $acl2
Write-Host "[OK] IIS_IUSRS com Modify em $logPath" -ForegroundColor Green

# ── CRIAR WRAPPER DA API DE STATS ───────────────────────────────
Write-Host "`n  A criar wrapper stats.ps1 na pasta API..." -ForegroundColor Gray
$wrapperContent = @"
# stats.ps1 — wrapper IIS para Get-SystemStats
# Adiciona headers HTTP obrigatorios para o browser aceitar o JSON
Write-Output "Content-Type: application/json"
Write-Output "Access-Control-Allow-Origin: *"
Write-Output ""
& "$BaseDir\scripts\monitoring\Get-SystemStats.ps1"
"@
Set-Content -Path "$ApiPath\stats.ps1" -Value $wrapperContent -Encoding UTF8
Write-Host "[OK] Wrapper stats.ps1 criado." -ForegroundColor Green

# ── REINICIAR IIS ────────────────────────────────────────────────
iisreset /noforce | Out-Null

# ── LOG ─────────────────────────────────────────────────────────
$logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Setup-IIS.ps1 concluido. Site: $NomeSite | Porta: $PortaDashboard"
Add-Content -Path "$BaseDir\logs\setup.log" -Value $logEntry

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  IIS CONFIGURADO COM SUCESSO!" -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard : http://localhost:$PortaDashboard" -ForegroundColor White
Write-Host "  API Stats : http://localhost:$PortaDashboard/api/stats.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  Copia o ficheiro dashboard\index.html para:" -ForegroundColor Gray
Write-Host "  $DashboardPath" -ForegroundColor Yellow
Write-Host "============================================`n" -ForegroundColor Cyan
