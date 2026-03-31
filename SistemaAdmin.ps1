# ==============================================================
# SistemaAdmin.ps1
# Menu Principal - Sistema de Administracao e Monitorizacao
# Executar como Administrador no Windows Server
# ==============================================================

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Host.UI.RawUI.WindowTitle = "SistemaAdmin - Painel de Administracao"

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  +===========================================================+" -ForegroundColor Cyan
    Write-Host "  |                                                           |" -ForegroundColor Cyan
    Write-Host "  |   SISTEMA AUTOMATIZADO DE ADMINISTRACAO                   |" -ForegroundColor Cyan
    Write-Host "  |   E MONITORIZACAO DE INFRAESTRUTURA DE TI                 |" -ForegroundColor Cyan
    Write-Host "  |                                                           |" -ForegroundColor Cyan
    Write-Host "  |   Servidor: $($env:COMPUTERNAME.PadRight(20))                       |" -ForegroundColor Cyan
    Write-Host "  |   Data:     $($(Get-Date -Format 'yyyy-MM-dd HH:mm').PadRight(20))                       |" -ForegroundColor Cyan
    Write-Host "  |                                                           |" -ForegroundColor Cyan
    Write-Host "  +===========================================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Show-MainMenu {
    Write-Host "  +-----------------------------------------+" -ForegroundColor White
    Write-Host "  |          MENU PRINCIPAL                 |" -ForegroundColor White
    Write-Host "  +-----------------------------------------+" -ForegroundColor White
    Write-Host "  |  1. Monitorizacao de Recursos           |" -ForegroundColor Gray
    Write-Host "  |  2. Gestao de Processos                 |" -ForegroundColor Gray
    Write-Host "  |  3. Gestao de Utilizadores e Grupos     |" -ForegroundColor Gray
    Write-Host "  |  4. Sistema de Ficheiros                |" -ForegroundColor Gray
    Write-Host "  |  5. Servicos e Servidores               |" -ForegroundColor Gray
    Write-Host "  |  6. Rede e Conectividade                |" -ForegroundColor Gray
    Write-Host "  |  7. Seguranca do Sistema                |" -ForegroundColor Gray
    Write-Host "  |  8. Backup e Recuperacao                |" -ForegroundColor Gray
    Write-Host "  |  9. Dashboard Web (abrir no browser)    |" -ForegroundColor Gray
    Write-Host "  |  0. Sair                                |" -ForegroundColor Gray
    Write-Host "  +-----------------------------------------+" -ForegroundColor White
    Write-Host ""
}

function Show-SubMenu {
    param([string]$Titulo, [string[]]$Opcoes)
    Write-Host ""
    Write-Host "  -- $Titulo --" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $Opcoes.Count; $i++) {
        Write-Host "  $($i+1). $($Opcoes[$i])" -ForegroundColor Gray
    }
    Write-Host "  0. Voltar ao menu principal" -ForegroundColor DarkGray
    Write-Host ""
}

function Pause-Menu {
    Write-Host ""
    Write-Host "  Prime ENTER para continuar..." -ForegroundColor DarkGray
    Read-Host | Out-Null
}

# ==========================================
# SUBMENUS
# ==========================================

function Menu-Monitorizacao {
    do {
        Show-Banner
        Show-SubMenu "MONITORIZACAO DE RECURSOS" @(
            "Ver resumo geral (CPU, RAM, Disco, Rede)",
            "Monitorizar em tempo real (5 ciclos)",
            "Gerar relatorio de recursos"
        )
        $op = Read-Host "  Opcao"
        switch ($op) {
            "1" {
                & "$ProjectRoot\scripts\monitoring\Get-SystemStats.ps1" |
                    ConvertFrom-Json | Format-List
                Pause-Menu
            }
            "2" {
                for ($i = 1; $i -le 5; $i++) {
                    Write-Host ""
                    Write-Host "  -- Amostra $i/5 ($(Get-Date -Format 'HH:mm:ss')) --" -ForegroundColor Yellow
                    $stats = & "$ProjectRoot\scripts\monitoring\Get-SystemStats.ps1" | ConvertFrom-Json
                    Write-Host "  CPU: $($stats.cpu.usedPct)% | RAM: $($stats.ram.usedPct)% ($($stats.ram.usedGB)/$($stats.ram.totalGB) GB)" -ForegroundColor White
                    foreach ($d in $stats.discos) {
                        Write-Host "  Disco $($d.drive): $($d.usedPct)% ($($d.usedGB)/$($d.totalGB) GB)" -ForegroundColor Gray
                    }
                    if ($i -lt 5) { Start-Sleep -Seconds 3 }
                }
                Pause-Menu
            }
            "3" {
                $reportDir = "$ProjectRoot\reports"
                if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
                $reportFile = "$reportDir\recursos-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
                & "$ProjectRoot\scripts\monitoring\Get-SystemStats.ps1" | Out-File $reportFile -Encoding UTF8
                Write-Host "  [OK] Relatorio guardado: $reportFile" -ForegroundColor Green
                Pause-Menu
            }
        }
    } while ($op -ne "0")
}

function Menu-Processos {
    do {
        Show-Banner
        Show-SubMenu "GESTAO DE PROCESSOS" @(
            "Listar top processos (CPU)",
            "Listar top processos (RAM)",
            "Procurar processo por nome",
            "Terminar processo por PID",
            "Terminar processo por nome"
        )
        $op = Read-Host "  Opcao"
        switch ($op) {
            "1" {
                Get-Process | Sort-Object CPU -Descending | Select-Object -First 20 |
                    Format-Table @{L='PID';E={$_.Id}}, ProcessName,
                    @{L='CPU (s)';E={[math]::Round($_.CPU,2)}},
                    @{L='RAM (MB)';E={[math]::Round($_.WorkingSet64/1MB,2)}} -AutoSize | Out-Host
                Pause-Menu
            }
            "2" {
                Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 |
                    Format-Table @{L='PID';E={$_.Id}}, ProcessName,
                    @{L='CPU (s)';E={[math]::Round($_.CPU,2)}},
                    @{L='RAM (MB)';E={[math]::Round($_.WorkingSet64/1MB,2)}} -AutoSize | Out-Host
                Pause-Menu
            }
            "3" {
                $nome = Read-Host "  Nome do processo"
                Get-Process -Name "*$nome*" -ErrorAction SilentlyContinue |
                    Format-Table Id, ProcessName, @{L='CPU';E={[math]::Round($_.CPU,2)}},
                    @{L='RAM (MB)';E={[math]::Round($_.WorkingSet64/1MB,2)}} -AutoSize | Out-Host
                Pause-Menu
            }
            "4" {
                $pid = Read-Host "  PID do processo"
                try {
                    Stop-Process -Id $pid -Force
                    Write-Host "  [OK] Processo $pid terminado." -ForegroundColor Green
                } catch { Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red }
                Pause-Menu
            }
            "5" {
                $nome = Read-Host "  Nome do processo"
                try {
                    Stop-Process -Name $nome -Force
                    Write-Host "  [OK] Processo(s) '$nome' terminado(s)." -ForegroundColor Green
                } catch { Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red }
                Pause-Menu
            }
        }
    } while ($op -ne "0")
}

function Menu-Utilizadores {
    do {
        Show-Banner
        Show-SubMenu "GESTAO DE UTILIZADORES E GRUPOS" @(
            "Listar utilizadores",
            "Criar utilizador",
            "Remover utilizador",
            "Listar grupos",
            "Criar grupo",
            "Adicionar utilizador a grupo",
            "Remover utilizador de grupo",
            "Gerar relatorio completo"
        )
        $op = Read-Host "  Opcao"
        $script = "$ProjectRoot\scripts\users\Manage-ADUsers.ps1"
        switch ($op) {
            "1" { & $script listar; Pause-Menu }
            "2" { & $script criar; Pause-Menu }
            "3" { & $script remover; Pause-Menu }
            "4" { & $script grupo-listar; Pause-Menu }
            "5" { & $script grupo-criar; Pause-Menu }
            "6" { & $script grupo-adicionar; Pause-Menu }
            "7" { & $script grupo-remover; Pause-Menu }
            "8" { & $script relatorio; Pause-Menu }
        }
    } while ($op -ne "0")
}

function Menu-Ficheiros {
    do {
        Show-Banner
        Show-SubMenu "SISTEMA DE FICHEIROS" @(
            "Analisar espaco em disco",
            "Encontrar ficheiros grandes",
            "Verificar permissoes de pasta",
            "Ficheiros alterados recentemente",
            "Ficheiros suspeitos",
            "Relatorio completo"
        )
        $op = Read-Host "  Opcao"
        $script = "$ProjectRoot\scripts\filesystem\Audit-FileSystem.ps1"
        switch ($op) {
            "1" { & $script espaco; Pause-Menu }
            "2" { & $script grandes; Pause-Menu }
            "3" {
                $path = Read-Host "  Caminho da pasta"
                & $script permissoes -Caminho $path
                Pause-Menu
            }
            "4" { & $script recentes; Pause-Menu }
            "5" { & $script suspeitos; Pause-Menu }
            "6" { & $script relatorio; Pause-Menu }
        }
    } while ($op -ne "0")
}

function Menu-Servicos {
    do {
        Show-Banner
        Show-SubMenu "SERVICOS E SERVIDORES" @(
            "Ver servicos criticos",
            "Listar todos os servicos",
            "Ver servicos automaticos parados",
            "Reiniciar um servico",
            "Verificar e auto-reiniciar criticos"
        )
        $op = Read-Host "  Opcao"
        $script = "$ProjectRoot\scripts\services\Monitor-Services.ps1"
        switch ($op) {
            "1" { & $script criticos; Pause-Menu }
            "2" { & $script listar; Pause-Menu }
            "3" { & $script parados; Pause-Menu }
            "4" { & $script reiniciar; Pause-Menu }
            "5" { & $script verificar; Pause-Menu }
        }
    } while ($op -ne "0")
}

function Menu-Rede {
    do {
        Show-Banner
        Show-SubMenu "REDE E CONECTIVIDADE" @(
            "Ver interfaces de rede",
            "Portas abertas",
            "Conexoes ativas",
            "Configuracao DNS",
            "Teste de ping/conectividade",
            "Monitorizar trafego"
        )
        $op = Read-Host "  Opcao"
        $script = "$ProjectRoot\scripts\network\Monitor-Network.ps1"
        switch ($op) {
            "1" { & $script interfaces; Pause-Menu }
            "2" { & $script portas; Pause-Menu }
            "3" { & $script conexoes; Pause-Menu }
            "4" { & $script dns; Pause-Menu }
            "5" { & $script ping; Pause-Menu }
            "6" { & $script trafego; Pause-Menu }
        }
    } while ($op -ne "0")
}

function Menu-Seguranca {
    do {
        Show-Banner
        Show-SubMenu "SEGURANCA DO SISTEMA" @(
            "Tentativas de login falhadas",
            "Eventos de seguranca recentes",
            "Estado do firewall",
            "Politicas de seguranca / contas bloqueadas",
            "Relatorio completo de seguranca"
        )
        $op = Read-Host "  Opcao"
        $script = "$ProjectRoot\scripts\security\Monitor-Security.ps1"
        switch ($op) {
            "1" { & $script logins; Pause-Menu }
            "2" { & $script eventos; Pause-Menu }
            "3" { & $script firewall; Pause-Menu }
            "4" { & $script politicas; Pause-Menu }
            "5" { & $script relatorio; Pause-Menu }
        }
    } while ($op -ne "0")
}

function Menu-Backup {
    do {
        Show-Banner
        Show-SubMenu "BACKUP E RECUPERACAO" @(
            "Backup completo",
            "Backup incremental",
            "Listar backups existentes",
            "Verificar integridade de backup",
            "Restaurar backup",
            "Agendar backup automatico"
        )
        $op = Read-Host "  Opcao"
        $script = "$ProjectRoot\scripts\backup\Manage-Backup.ps1"
        switch ($op) {
            "1" { & $script completo; Pause-Menu }
            "2" { & $script incremental; Pause-Menu }
            "3" { & $script listar; Pause-Menu }
            "4" { & $script verificar; Pause-Menu }
            "5" { & $script restaurar; Pause-Menu }
            "6" { & $script agendar; Pause-Menu }
        }
    } while ($op -ne "0")
}

# ==========================================
# LOOP PRINCIPAL
# ==========================================

do {
    Show-Banner
    Show-MainMenu
    $opcao = Read-Host "  Opcao"

    switch ($opcao) {
        "1" { Menu-Monitorizacao }
        "2" { Menu-Processos }
        "3" { Menu-Utilizadores }
        "4" { Menu-Ficheiros }
        "5" { Menu-Servicos }
        "6" { Menu-Rede }
        "7" { Menu-Seguranca }
        "8" { Menu-Backup }
        "9" {
            Write-Host "  A iniciar servidor Web do Dashboard (Pode)..." -ForegroundColor Yellow
            Start-Process powershell.exe -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$ProjectRoot\Start-WebDashboard.ps1`""
            Write-Host "  A aguardar arranque do servidor..." -ForegroundColor Gray
            Start-Sleep -Seconds 5
            Start-Process "http://localhost"
        }
        "0" {
            Write-Host "`n  Ate a proxima!`n" -ForegroundColor Cyan
        }
    }
} while ($opcao -ne "0")