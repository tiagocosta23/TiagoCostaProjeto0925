# ==============================================================
# Setup-Projeto.ps1
# Cria a estrutura de pastas do projeto no Windows Server
# Executar como Administrador uma vez, no início do projeto
#
# NOTA: A pasta base é detetada automaticamente a partir da
# localização deste script (raiz do repositório clonado).
# Ex: git clone <url> C:\SistemaAdmin  → base = C:\SistemaAdmin
#     git clone <url> C:\TiagoCostaProjeto0925 → base = C:\TiagoCostaProjeto0925
# ==============================================================

# Deteta a pasta raiz do repositório (onde este script está)
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Pasta base do projeto: $base" -ForegroundColor Cyan

$pastas = @(
    "$base\scripts\monitoring",
    "$base\scripts\users",
    "$base\scripts\filesystem",
    "$base\scripts\services",
    "$base\scripts\network",
    "$base\scripts\backup",
    "$base\scripts\security",
    "$base\dashboard",
    "$base\logs",
    "$base\reports",
    "$base\iis-api"
)

foreach ($pasta in $pastas) {
    if (-not (Test-Path $pasta)) {
        New-Item -ItemType Directory -Path $pasta -Force | Out-Null
        Write-Host "[OK] Criada: $pasta" -ForegroundColor Green
    } else {
        Write-Host "[JA EXISTE] $pasta" -ForegroundColor Yellow
    }
}

Write-Host "`n[DONE] Estrutura do projeto criada em $base" -ForegroundColor Cyan
