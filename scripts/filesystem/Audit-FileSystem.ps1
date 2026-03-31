# ==============================================================
# Audit-FileSystem.ps1
# Auditoria do Sistema de Ficheiros
# Monitorizacao de disco, permissoes, ficheiros grandes/suspeitos
# ==============================================================

param(
    [Parameter(Position=0)]
    [ValidateSet("espaco","grandes","permissoes","recentes","suspeitos","relatorio","json")]
    [string]$Acao,

    [string]$Caminho = "C:\",
    [int]$TopN = 20,
    [int]$MinSizeMB = 100
)

$ErrorActionPreference = "SilentlyContinue"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$LogFile = "$ProjectRoot\logs\filesystem.log"

function Write-Log {
    param([string]$Msg)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    if (-not (Test-Path (Split-Path $LogFile))) { New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null }
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
}

# ── Modo JSON (para a API do Dashboard) ──
if ($Acao -eq "json") {
    # Discos
    $discos = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $total = [math]::Round($_.Size / 1GB, 2)
        $free  = [math]::Round($_.FreeSpace / 1GB, 2)
        $used  = [math]::Round($total - $free, 2)
        $pct   = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 1) } else { 0 }
        @{ drive = $_.DeviceID; totalGB = $total; usedGB = $used; freeGB = $free; usedPct = $pct }
    }

    # Top 10 ficheiros grandes no C:
    $grandes = @()
    try {
        $grandes = Get-ChildItem -Path "C:\" -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 50MB } |
            Sort-Object Length -Descending |
            Select-Object -First 10 | ForEach-Object {
                @{
                    nome     = $_.Name
                    caminho  = $_.FullName
                    sizeMB   = [math]::Round($_.Length / 1MB, 2)
                    alterado = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                }
            }
    } catch {}

    # Ficheiros recentes (ultimas 24h)
    $recentes = @()
    try {
        $limite = (Get-Date).AddHours(-24)
        $recentes = Get-ChildItem -Path "C:\Users","C:\Shares" -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $limite } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 15 | ForEach-Object {
                @{
                    nome     = $_.Name
                    caminho  = $_.FullName
                    sizeMB   = [math]::Round($_.Length / 1MB, 2)
                    alterado = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                }
            }
    } catch {}

    # Extensoes suspeitas
    $suspeitos = @()
    $extSuspeitas = @("*.exe","*.bat","*.cmd","*.vbs","*.ps1","*.scr","*.msi")
    try {
        $suspeitos = Get-ChildItem -Path "C:\Users" -Recurse -Include $extSuspeitas -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 10 | ForEach-Object {
                @{
                    nome     = $_.Name
                    caminho  = $_.FullName
                    sizeMB   = [math]::Round($_.Length / 1MB, 2)
                    alterado = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                    ext      = $_.Extension
                }
            }
    } catch {}

    # Pastas partilhadas
    $shares = @()
    try {
        $shares = Get-SmbShare -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '*$' } |
            ForEach-Object {
                @{
                    nome    = $_.Name
                    caminho = $_.Path
                    desc    = if ($_.Description) { $_.Description } else { "" }
                }
            }
    } catch {}

    $resultado = @{
        timestamp      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        discos         = $discos
        ficheirosGrandes = $grandes
        recentes       = $recentes
        suspeitos      = $suspeitos
        shares         = $shares
        totalGrandes   = ($grandes | Measure-Object).Count
        totalSuspeitos = ($suspeitos | Measure-Object).Count
    }

    $resultado | ConvertTo-Json -Depth 5
    return
}

# ── Funcoes CLI ──

function Analisar-Espaco {
    Write-Host ""
    Write-Host "  ANALISE DE ESPACO EM DISCO" -ForegroundColor Cyan
    Write-Host "  ==========================" -ForegroundColor Cyan
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $total = [math]::Round($_.Size / 1GB, 2)
        $free  = [math]::Round($_.FreeSpace / 1GB, 2)
        $used  = [math]::Round($total - $free, 2)
        $pct   = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 1) } else { 0 }
        $cor   = if ($pct -gt 90) { "Red" } elseif ($pct -gt 75) { "Yellow" } else { "Green" }
        Write-Host "  [$($_.DeviceID)] $used/$total GB ($pct%)" -ForegroundColor $cor
    }
    Write-Log "Analise de espaco executada"
}

function Ficheiros-Grandes {
    Write-Host ""
    Write-Host "  TOP $TopN FICHEIROS GRANDES (>$MinSizeMB MB) em $Caminho" -ForegroundColor Cyan
    $files = Get-ChildItem -Path $Caminho -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt ($MinSizeMB * 1MB) } |
        Sort-Object Length -Descending |
        Select-Object -First $TopN
    $files | Format-Table @{L='Tamanho (MB)';E={[math]::Round($_.Length/1MB,2)}},
        @{L='Alterado';E={$_.LastWriteTime.ToString("yyyy-MM-dd")}}, FullName -AutoSize
    Write-Host "  Total encontrados: $($files.Count)" -ForegroundColor Gray
    Write-Log "Pesquisa de ficheiros grandes em $Caminho (>$MinSizeMB MB)"
}

function Verificar-Permissoes {
    Write-Host ""
    Write-Host "  PERMISSOES DE $Caminho" -ForegroundColor Cyan
    $acl = Get-Acl $Caminho
    Write-Host "  Dono: $($acl.Owner)" -ForegroundColor Gray
    Write-Host ""
    $acl.Access | Format-Table IdentityReference, FileSystemRights, AccessControlType, IsInherited -AutoSize
    Write-Log "Verificacao de permissoes em $Caminho"
}

function Ficheiros-Recentes {
    Write-Host ""
    Write-Host "  FICHEIROS ALTERADOS NAS ULTIMAS 24 HORAS em $Caminho" -ForegroundColor Cyan
    $limite = (Get-Date).AddHours(-24)
    $files = Get-ChildItem -Path $Caminho -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $limite } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $TopN
    $files | Format-Table @{L='Alterado';E={$_.LastWriteTime.ToString("HH:mm:ss")}},
        @{L='MB';E={[math]::Round($_.Length/1MB,2)}}, FullName -AutoSize
    Write-Host "  Total: $($files.Count)" -ForegroundColor Gray
    Write-Log "Pesquisa de ficheiros recentes em $Caminho"
}

function Ficheiros-Suspeitos {
    Write-Host ""
    Write-Host "  FICHEIROS SUSPEITOS (ultimos 7 dias)" -ForegroundColor Cyan
    $extSuspeitas = @("*.exe","*.bat","*.cmd","*.vbs","*.ps1","*.scr","*.msi")
    $files = Get-ChildItem -Path "C:\Users" -Recurse -Include $extSuspeitas -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-7) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $TopN
    if ($files.Count -eq 0) {
        Write-Host "  [OK] Nenhum ficheiro suspeito encontrado." -ForegroundColor Green
    } else {
        $files | Format-Table @{L='Alterado';E={$_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")}},
            @{L='MB';E={[math]::Round($_.Length/1MB,2)}}, Name, FullName -AutoSize
        Write-Host "  [AVISO] $($files.Count) ficheiros encontrados!" -ForegroundColor Yellow
    }
    Write-Log "Pesquisa de ficheiros suspeitos: $($files.Count) encontrados"
}

# ── Execucao ──
switch ($Acao) {
    "espaco"     { Analisar-Espaco }
    "grandes"    { Ficheiros-Grandes }
    "permissoes" { Verificar-Permissoes }
    "recentes"   { Ficheiros-Recentes }
    "suspeitos"  { Ficheiros-Suspeitos }
    "relatorio"  { Analisar-Espaco; Ficheiros-Grandes; Ficheiros-Suspeitos }
    default {
        Write-Host ""
        Write-Host "  Uso: .\Audit-FileSystem.ps1 <acao> [-Caminho C:\] [-TopN 20] [-MinSizeMB 100]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Acoes: espaco, grandes, permissoes, recentes, suspeitos, relatorio, json"
        Write-Host ""
    }
}
