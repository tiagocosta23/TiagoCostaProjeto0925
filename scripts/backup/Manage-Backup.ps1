# ==============================================================
# Manage-Backup.ps1
# Sistema de Backup Automatico
# Backup completo, incremental, agendamento, verificacao
# ==============================================================

param(
    [Parameter(Position=0)]
    [ValidateSet("completo","incremental","listar","verificar","restaurar","agendar","json")]
    [string]$Acao,

    [string]$Origem = "C:\Users",
    [string]$Destino,
    [string]$BackupFile
)

$ErrorActionPreference = "SilentlyContinue"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
$LogFile = "$ProjectRoot\logs\backup.log"
$BackupDir = if ($Destino) { $Destino } else { "$ProjectRoot\backups" }
$BackupIndex = "$BackupDir\backup-index.json"

function Write-Log {
    param([string]$Msg)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    if (-not (Test-Path (Split-Path $LogFile))) { New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null }
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
}

function Get-BackupIndex {
    if (Test-Path $BackupIndex) {
        return Get-Content $BackupIndex -Raw | ConvertFrom-Json
    }
    return @()
}

function Save-BackupIndex {
    param($Index)
    $Index | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupIndex -Encoding UTF8
}

# ── Modo JSON (para a API do Dashboard) ──
if ($Acao -eq "json") {
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

    $backups = @()
    $ficheiros = Get-ChildItem -Path $BackupDir -Filter "*.zip" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 20

    foreach ($f in $ficheiros) {
        $tipo = if ($f.Name -match "completo") { "Completo" }
                elseif ($f.Name -match "incremental") { "Incremental" }
                else { "Outro" }
        $backups += @{
            nome     = $f.Name
            tipo     = $tipo
            sizeMB   = [math]::Round($f.Length / 1MB, 2)
            data     = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            caminho  = $f.FullName
        }
    }

    # Verificar tarefas agendadas de backup
    $agendados = @()
    try {
        $tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*Backup*" }
        foreach ($t in $tasks) {
            $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -ErrorAction SilentlyContinue
            $agendados += @{
                nome       = $t.TaskName
                estado     = $t.State.ToString()
                ultimaExec = if ($info.LastRunTime -and $info.LastRunTime.Year -gt 2000) {
                    $info.LastRunTime.ToString("yyyy-MM-dd HH:mm")
                } else { "Nunca" }
                resultado  = if ($info.LastTaskResult -eq 0) { "Sucesso" } else { "Erro ($($info.LastTaskResult))" }
            }
        }
    } catch {}

    $totalSize = ($ficheiros | Measure-Object -Property Length -Sum).Sum
    $totalSizeMB = [math]::Round($totalSize / 1MB, 2)

    $resultado = @{
        timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        totalBackups = ($backups | Measure-Object).Count
        totalSizeMB  = $totalSizeMB
        ultimoBackup = if ($backups.Count -gt 0) { $backups[0].data } else { "Nenhum" }
        backups      = $backups
        agendados    = $agendados
        backupDir    = $BackupDir
    }

    $resultado | ConvertTo-Json -Depth 5
    return
}

# ── Funcoes CLI ──

function Backup-Completo {
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $zipName = "backup-completo-$timestamp.zip"
    $zipPath = "$BackupDir\$zipName"

    Write-Host ""
    Write-Host "  BACKUP COMPLETO" -ForegroundColor Cyan
    Write-Host "  Origem:  $Origem" -ForegroundColor Gray
    Write-Host "  Destino: $zipPath" -ForegroundColor Gray
    Write-Host "  A comprimir..." -ForegroundColor Yellow

    try {
        Compress-Archive -Path $Origem -DestinationPath $zipPath -Force
        $size = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
        Write-Host "  [OK] Backup completo criado: $zipName ($size MB)" -ForegroundColor Green
        Write-Log "Backup COMPLETO: $zipName ($size MB) | Origem: $Origem"

        # Verificar integridade
        $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.Substring(0,16)
        Write-Host "  [OK] Hash SHA256: $hash..." -ForegroundColor Gray
    } catch {
        Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "ERRO backup completo: $($_.Exception.Message)"
    }
}

function Backup-Incremental {
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

    # Encontrar o ultimo backup para comparar datas
    $ultimoBackup = Get-ChildItem -Path $BackupDir -Filter "*.zip" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    $desde = if ($ultimoBackup) { $ultimoBackup.LastWriteTime } else { (Get-Date).AddDays(-1) }

    Write-Host ""
    Write-Host "  BACKUP INCREMENTAL" -ForegroundColor Cyan
    Write-Host "  Origem:  $Origem" -ForegroundColor Gray
    Write-Host "  Desde:   $($desde.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Gray

    # Encontrar ficheiros alterados desde o ultimo backup
    $alterados = Get-ChildItem -Path $Origem -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $desde }

    if ($alterados.Count -eq 0) {
        Write-Host "  [INFO] Nenhum ficheiro alterado desde o ultimo backup." -ForegroundColor Yellow
        Write-Log "Backup incremental: nenhum ficheiro alterado"
        return
    }

    Write-Host "  Ficheiros alterados: $($alterados.Count)" -ForegroundColor Gray

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $zipName = "backup-incremental-$timestamp.zip"
    $zipPath = "$BackupDir\$zipName"

    # Criar pasta temp com os ficheiros alterados
    $tempDir = "$env:TEMP\backup-inc-$timestamp"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    foreach ($f in $alterados) {
        $relPath = $f.FullName.Replace($Origem, "").TrimStart("\")
        $destPath = "$tempDir\$relPath"
        $destDir  = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item $f.FullName -Destination $destPath -Force
    }

    try {
        Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force
        $size = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
        Write-Host "  [OK] Backup incremental: $zipName ($size MB, $($alterados.Count) ficheiros)" -ForegroundColor Green
        Write-Log "Backup INCREMENTAL: $zipName ($size MB, $($alterados.Count) ficheiros)"
    } catch {
        Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red
    }

    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Listar-Backups {
    Write-Host ""
    Write-Host "  BACKUPS EXISTENTES" -ForegroundColor Cyan
    Write-Host "  ===================" -ForegroundColor Cyan
    Write-Host "  Pasta: $BackupDir" -ForegroundColor Gray
    Write-Host ""

    if (-not (Test-Path $BackupDir)) {
        Write-Host "  [INFO] Pasta de backups nao existe ainda." -ForegroundColor Yellow
        return
    }

    $backups = Get-ChildItem -Path $BackupDir -Filter "*.zip" | Sort-Object LastWriteTime -Descending
    if ($backups.Count -eq 0) {
        Write-Host "  [INFO] Nenhum backup encontrado." -ForegroundColor Yellow
        return
    }

    $backups | Format-Table @{L='Data';E={$_.LastWriteTime.ToString("yyyy-MM-dd HH:mm")}},
        @{L='Tamanho (MB)';E={[math]::Round($_.Length/1MB,2)}}, Name -AutoSize | Out-Host

    $totalMB = [math]::Round(($backups | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    Write-Host "  Total: $($backups.Count) backups ($totalMB MB)" -ForegroundColor Gray
}

function Verificar-Backup {
    if (-not $BackupFile) {
        $backups = Get-ChildItem -Path $BackupDir -Filter "*.zip" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
        if ($backups.Count -eq 0) {
            Write-Host "  [INFO] Nenhum backup para verificar." -ForegroundColor Yellow
            return
        }
        $BackupFile = $backups[0].FullName
        Write-Host "  A verificar o backup mais recente: $($backups[0].Name)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "  VERIFICACAO DE INTEGRIDADE" -ForegroundColor Cyan
    try {
        # Testar que o ZIP abre sem erros
        $null = [System.IO.Compression.ZipFile]::OpenRead($BackupFile)
        $hash = (Get-FileHash $BackupFile -Algorithm SHA256).Hash
        $size = [math]::Round((Get-Item $BackupFile).Length / 1MB, 2)
        Write-Host "  [OK] Ficheiro integro: $(Split-Path $BackupFile -Leaf)" -ForegroundColor Green
        Write-Host "       Tamanho: $size MB" -ForegroundColor Gray
        Write-Host "       SHA256:  $($hash.Substring(0,32))..." -ForegroundColor Gray
        Write-Log "Verificacao OK: $(Split-Path $BackupFile -Leaf)"
    } catch {
        Write-Host "  [ERRO] Backup corrompido: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Verificacao FALHOU: $(Split-Path $BackupFile -Leaf)"
    }
}

function Restaurar-Backup {
    if (-not $BackupFile) { $BackupFile = Read-Host "  Caminho do ficheiro .zip" }
    $destRestauro = Read-Host "  Pasta de destino para restauro"

    if (-not (Test-Path $BackupFile)) {
        Write-Host "  [ERRO] Ficheiro nao encontrado: $BackupFile" -ForegroundColor Red
        return
    }

    try {
        Expand-Archive -Path $BackupFile -DestinationPath $destRestauro -Force
        Write-Host "  [OK] Restauro concluido em: $destRestauro" -ForegroundColor Green
        Write-Log "Restauro de $BackupFile para $destRestauro"
    } catch {
        Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Agendar-Backup {
    Write-Host ""
    Write-Host "  AGENDAR BACKUP AUTOMATICO" -ForegroundColor Cyan
    $hora = Read-Host "  Hora de execucao diaria (formato HH:MM, ex: 02:00)"
    if ($hora -notmatch '^\d{2}:\d{2}$') { $hora = "02:00" }

    $taskName = "SistemaAdmin-BackupDiario"
    $script   = "$ProjectRoot\scripts\backup\Manage-Backup.ps1"
    $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`" completo -Origem `"$Origem`""
    $trigger  = New-ScheduledTaskTrigger -Daily -At $hora
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
            -User "SYSTEM" -RunLevel Highest
        Write-Host "  [OK] Backup agendado: todos os dias as $hora" -ForegroundColor Green
        Write-Host "       Tarefa: $taskName" -ForegroundColor Gray
        Write-Log "Backup agendado: $taskName as $hora"
    } catch {
        Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Carregar assembly para verificacao ZIP
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

# ── Execucao ──
switch ($Acao) {
    "completo"    { Backup-Completo }
    "incremental" { Backup-Incremental }
    "listar"      { Listar-Backups }
    "verificar"   { Verificar-Backup }
    "restaurar"   { Restaurar-Backup }
    "agendar"     { Agendar-Backup }
    default {
        Write-Host ""
        Write-Host "  Uso: .\Manage-Backup.ps1 <acao> [-Origem C:\Users] [-Destino C:\backups]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Acoes: completo, incremental, listar, verificar, restaurar, agendar, json"
        Write-Host ""
    }
}
