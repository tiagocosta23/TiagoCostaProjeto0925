# Setup-Projeto.ps1
# Cria a estrutura de pastas do projeto no Windows Server
# Executar como Administrador uma vez, no inicio do projeto
#
# NOTA: A pasta base e detetada automaticamente a partir da
# localizacao deste script (raiz do repositorio clonado).
#
# Dados operacionais (logs, backups, reports) ficam em C:\SysAdmin
# para NAO poluir o repositorio GitHub.

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Pasta base do projeto: $base" -ForegroundColor Cyan
Write-Host ""

# ── Pastas do projeto (repositorio GitHub) ──
$pastasRepo = @(
    "$base\scripts\monitoring",
    "$base\scripts\users",
    "$base\scripts\filesystem",
    "$base\scripts\services",
    "$base\scripts\network",
    "$base\scripts\backup",
    "$base\scripts\security",
    "$base\dashboard"
)

# ── Pastas de dados operacionais (fora do repositorio) ──
$DataRoot = "C:\SysAdmin"
$pastasData = @(
    "$DataRoot\logs",
    "$DataRoot\reports",
    "$DataRoot\backups"
)

Write-Host "-- Estrutura do Projeto (GitHub) --" -ForegroundColor White
foreach ($pasta in $pastasRepo) {
    if (-not (Test-Path $pasta)) {
        New-Item -ItemType Directory -Path $pasta -Force | Out-Null
        Write-Host "[OK] Criada: $pasta" -ForegroundColor Green
    } else {
        Write-Host "[JA EXISTE] $pasta" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "-- Dados Operacionais ($DataRoot) --" -ForegroundColor White
foreach ($pasta in $pastasData) {
    if (-not (Test-Path $pasta)) {
        New-Item -ItemType Directory -Path $pasta -Force | Out-Null
        Write-Host "[OK] Criada: $pasta" -ForegroundColor Green
    } else {
        Write-Host "[JA EXISTE] $pasta" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "[DONE] Estrutura completa criada." -ForegroundColor Cyan
Write-Host "       Projeto:  $base" -ForegroundColor Gray
Write-Host "       Dados:    $DataRoot" -ForegroundColor Gray
