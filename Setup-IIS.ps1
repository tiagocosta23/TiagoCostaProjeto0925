# Setup-IIS.ps1
# Configura o IIS para servir o Dashboard Web e a API PowerShell
# Executar como Administrador no Windows Server
# Deve ser executado APOS Setup-ADDomain.ps1 (apos o 2o reinicio)

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SETUP IIS - DASHBOARD WEB" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Pasta do projeto detetada: $ProjectRoot" -ForegroundColor Gray
Write-Host "  Preenche as opcoes abaixo." -ForegroundColor Gray
Write-Host "  Prime ENTER para aceitar o valor sugerido." -ForegroundColor Gray
Write-Host ""

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

Write-Host "-- Configuracao do Site IIS --" -ForegroundColor White
$NomeSite       = Prompt-Value -Mensagem "Nome do site IIS"               -Sugestao "SistemaAdmin"
$PortaDashboard = Prompt-Int   -Mensagem "Porta do Dashboard (HTTP)"      -Sugestao "80"   -Min 1 -Max 65535

Write-Host ""
Write-Host "-- Caminhos no Servidor --" -ForegroundColor White
$BaseDir       = Prompt-Value -Mensagem "Pasta base do projeto"                  -Sugestao $ProjectRoot
$DashboardPath = Prompt-Value -Mensagem "Pasta do Dashboard (ficheiros HTML/JS)" -Sugestao "$BaseDir\dashboard"
$ApiPath       = Prompt-Value -Mensagem "Pasta da API (scripts wrapper IIS)"     -Sugestao "$BaseDir\iis-api"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  RESUMO DAS OPCOES:" -ForegroundColor White
Write-Host "  Nome do site    : $NomeSite"
Write-Host "  Porta Dashboard : $PortaDashboard"
Write-Host "  Pasta base      : $BaseDir"
Write-Host "  Pasta dashboard : $DashboardPath"
Write-Host "  Pasta API       : $ApiPath"
Write-Host "============================================"
Write-Host ""

$confirma = Prompt-SimNao -Mensagem "Prosseguir com estas opcoes?" -Sugestao "S"
if (-not $confirma) {
    Write-Host "[CANCELADO] Executa o script novamente para reconfigurar." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# Detetar o caminho REAL do powershell.exe (pode ser C:\Windows ou C:\WINDOWS)
$psExe = (Get-Command powershell.exe).Source
Write-Host "  PowerShell detetado em: $psExe" -ForegroundColor Gray
$appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"

# 1. VERIFICAR IIS
Write-Host "[1/6] A verificar se o IIS esta instalado..." -ForegroundColor Yellow
$iis = Get-WindowsFeature -Name Web-Server
if (-not $iis.Installed) {
    Write-Host "[ERRO] IIS nao esta instalado!" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] IIS instalado." -ForegroundColor Green

# 2. CRIAR PASTAS
Write-Host ""
Write-Host "[2/6] A garantir que as pastas existem..." -ForegroundColor Yellow
foreach ($p in @($DashboardPath, $ApiPath)) {
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        Write-Host "[OK] Criada: $p" -ForegroundColor Green
    } else {
        Write-Host "[JA EXISTE] $p" -ForegroundColor Gray
    }
}

# 3. CONFIGURAR SITE IIS
Write-Host ""
Write-Host "[3/6] A configurar site IIS '$NomeSite'..." -ForegroundColor Yellow
Import-Module WebAdministration

if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
    Remove-Website -Name "Default Web Site"
    Write-Host "       Removido 'Default Web Site'" -ForegroundColor Gray
}
if (Get-Website -Name $NomeSite -ErrorAction SilentlyContinue) {
    Remove-Website -Name $NomeSite
    Write-Host "       Removido site '$NomeSite' anterior" -ForegroundColor Gray
}

New-Website -Name $NomeSite -Port $PortaDashboard -PhysicalPath $DashboardPath -Force | Out-Null
Write-Host "[OK] Site '$NomeSite' criado na porta $PortaDashboard" -ForegroundColor Green

# 4. VIRTUAL DIRECTORY /api
Write-Host ""
Write-Host "[4/6] A criar virtual directory /api..." -ForegroundColor Yellow
if (Get-WebApplication -Site $NomeSite -Name "api" -ErrorAction SilentlyContinue) {
    Remove-WebApplication -Site $NomeSite -Name "api"
}
New-WebApplication -Site $NomeSite -Name "api" -PhysicalPath $ApiPath | Out-Null
Write-Host "[OK] Virtual directory /api criada" -ForegroundColor Green

# 5. REGISTAR POWERSHELL COMO CGI
Write-Host ""
Write-Host "[5/6] A registar PowerShell como CGI handler..." -ForegroundColor Yellow

# Desbloquear seccao handlers
& $appcmd unlock config -section:system.webServer/handlers | Out-Null
Write-Host "       Seccao handlers desbloqueada." -ForegroundColor Gray

# Limpar restriction list antiga e adicionar com caminho correto
& $appcmd set config -section:system.webServer/security/isapiCgiRestriction /-".[path='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe']" 2>$null
& $appcmd set config -section:system.webServer/security/isapiCgiRestriction /-".[path='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe']" 2>$null
& $appcmd set config -section:system.webServer/security/isapiCgiRestriction /-".[path='$psExe']" 2>$null

# Adicionar com o caminho real detetado
& $appcmd set config -section:system.webServer/security/isapiCgiRestriction /+".[path='$psExe',allowed='True',description='PowerShell CGI']"
Write-Host "       PowerShell adicionado a restriction list: $psExe" -ForegroundColor Gray

# Limpar handlers antigos de .ps1
& $appcmd set config -section:system.webServer/handlers /-".[name='PowerShellCGI']" 2>$null
& $appcmd set config -section:system.webServer/handlers /-".[name='PowerShellHandler']" 2>$null

# Registar handler global com o caminho real
$scriptProcessor = "$psExe -NoProfile -NonInteractive -File ""%s"" %s"
& $appcmd set config -section:system.webServer/handlers /+".[name='PowerShellCGI',path='*.ps1',verb='GET,POST',modules='CgiModule',scriptProcessor='$scriptProcessor',resourceType='File']"
Write-Host "[OK] Handler PowerShell registado com: $psExe" -ForegroundColor Green

# 6. PERMISSOES
Write-Host ""
Write-Host "[6/6] A definir permissoes..." -ForegroundColor Yellow

$acl = Get-Acl $ApiPath
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS","ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
$acl.SetAccessRule($rule)
Set-Acl $ApiPath $acl
Write-Host "[OK] IIS_IUSRS com ReadAndExecute em $ApiPath" -ForegroundColor Green

$logPath = "$BaseDir\logs"
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }
$acl2 = Get-Acl $logPath
$rule2 = New-Object System.Security.AccessControl.FileSystemAccessRule("IIS_IUSRS","Modify","ContainerInherit,ObjectInherit","None","Allow")
$acl2.SetAccessRule($rule2)
Set-Acl $logPath $acl2
Write-Host "[OK] IIS_IUSRS com Modify em $logPath" -ForegroundColor Green

# WRAPPER STATS - usando sintaxe CGI correta
Write-Host ""
Write-Host "  A criar wrapper stats.ps1..." -ForegroundColor Gray

$statsScript = "$BaseDir\scripts\monitoring\Get-SystemStats.ps1"
$wrapperLines = @(
    '# stats.ps1 - wrapper CGI para Get-SystemStats',
    '# O IIS requer que os headers HTTP sejam escritos primeiro via Write-Host',
    '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8',
    'Write-Host "Content-Type: application/json"',
    'Write-Host "Access-Control-Allow-Origin: *"',
    'Write-Host ""',
    "& `"$statsScript`""
)
$wrapperLines | Set-Content -Path "$ApiPath\stats.ps1" -Encoding UTF8
Write-Host "[OK] Wrapper stats.ps1 criado." -ForegroundColor Green

# REINICIAR IIS
iisreset /noforce | Out-Null
Write-Host "[OK] IIS reiniciado." -ForegroundColor Green

# LOG
$logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Setup-IIS.ps1 concluido. Site: $NomeSite | Porta: $PortaDashboard"
$logFile = "$BaseDir\logs\setup.log"
if (-not (Test-Path (Split-Path $logFile))) { New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null }
Add-Content -Path $logFile -Value $logEntry

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  IIS CONFIGURADO COM SUCESSO!" -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard : http://localhost:$PortaDashboard" -ForegroundColor White
Write-Host "  API Stats : http://localhost:$PortaDashboard/api/stats.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  Verifica a API no browser para confirmar que retorna JSON." -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
