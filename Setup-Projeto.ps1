# Setup-Projeto.ps1
# Cria a estrutura de pastas operacionais e a pasta partilhada (File Server)
# Executar como Administrador uma vez, no inicio do projeto
#
# As pastas do projeto (scripts, dashboard) ja vem do repositorio GitHub.
# Este script cria apenas as pastas de dados operacionais e a partilha SMB.

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SETUP PROJETO - ESTRUTURA E PARTILHA" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Pasta do projeto: $base" -ForegroundColor Gray
Write-Host ""

# ── Pastas de dados operacionais (fora do repositorio) ──
$DataRoot = "C:\SysAdmin"
$pastasData = @(
    "$DataRoot\logs",
    "$DataRoot\reports",
    "$DataRoot\backups"
)

Write-Host "-- Dados Operacionais ($DataRoot) --" -ForegroundColor White
foreach ($pasta in $pastasData) {
    if (-not (Test-Path $pasta)) {
        New-Item -ItemType Directory -Path $pasta -Force | Out-Null
        Write-Host "[OK] Criada: $pasta" -ForegroundColor Green
    } else {
        Write-Host "[JA EXISTE] $pasta" -ForegroundColor Yellow
    }
}

# ── Pasta Partilhada (File Server) ──
Write-Host ""
Write-Host "-- Pasta Partilhada (File Server) --" -ForegroundColor White

$SharePath = "C:\Partilha"
$ShareName = "Partilha"

# Criar a pasta
if (-not (Test-Path $SharePath)) {
    New-Item -ItemType Directory -Path $SharePath -Force | Out-Null
    Write-Host "[OK] Pasta criada: $SharePath" -ForegroundColor Green
} else {
    Write-Host "[JA EXISTE] $SharePath" -ForegroundColor Yellow
}

# Criar a partilha SMB
$shareExiste = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
if (-not $shareExiste) {
    try {
        New-SmbShare -Name $ShareName -Path $SharePath -FullAccess "Everyone" -ErrorAction Stop | Out-Null
        Write-Host "[OK] Partilha SMB criada: \\$env:COMPUTERNAME\$ShareName" -ForegroundColor Green
    } catch {
        Write-Host "[ERRO] Falha ao criar partilha: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "[JA EXISTE] Partilha SMB: \\$env:COMPUTERNAME\$ShareName" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  [DONE] Estrutura completa criada." -ForegroundColor Green
Write-Host "  Dados:     $DataRoot" -ForegroundColor Gray
Write-Host "  Partilha:  \\$env:COMPUTERNAME\$ShareName" -ForegroundColor Gray
Write-Host ""
Write-Host "  Para testar no cliente:" -ForegroundColor White
Write-Host "  \\$((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' } | Select-Object -First 1).IPAddress)\$ShareName" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
