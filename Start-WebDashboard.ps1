# Start-WebDashboard.ps1
# Inicia o Servidor Web nativo (Pode) para o Dashboard
# Executar como Administrador
#
# ARQUITETURA:
# 1. Arranca o Update-DashboardCache.ps1 em background
#    (atualiza os JSON de 30 em 30 segundos)
# 2. Arranca o Pode que serve o HTML + le os JSON do cache
#    (resposta instantanea, sem executar scripts nos pedidos)

$Host.UI.RawUI.WindowTitle = "Servidor Web Dashboard (Pode)"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  A INICIAR SERVIDOR WEB DASHBOARD" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# 0. Garantir pasta de cache
$CacheDir = "C:\SysAdmin\cache"
if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}

# 1. Instalar o modulo Pode se nao existir
if (-not (Get-Module -ListAvailable -Name Pode)) {
    Write-Host "`n[+] Modulo 'Pode' nao detetado. A instalar da PSGallery..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
    Install-Module -Name Pode -Force -AllowClobber
    Write-Host "[OK] Modulo Pode instalado com sucesso!" -ForegroundColor Green
}

Import-Module Pode

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 2. Arrancar o cache updater em background
Write-Host "`n[+] A arrancar o atualizador de cache em background..." -ForegroundColor Yellow
$cacheScript = "$ProjectRoot\Update-DashboardCache.ps1"
$cacheJob = Start-Process powershell.exe `
    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$cacheScript`"" `
    -PassThru -WindowStyle Minimized

Write-Host "[OK] Cache updater PID: $($cacheJob.Id)" -ForegroundColor Green

# 3. Fazer uma primeira atualizacao do cache antes de arrancar o Pode
Write-Host "[+] A gerar cache inicial (pode demorar uns segundos)..." -ForegroundColor Yellow
Start-Sleep -Seconds 8  # dar tempo ao cache updater para o primeiro ciclo

Write-Host "[+] A arrancar o servidor web na porta 80..." -ForegroundColor Yellow
Write-Host "[+] Dashboard: http://localhost" -ForegroundColor White
Write-Host "[+] Fecha esta janela para desligar o servidor.`n" -ForegroundColor Gray

# 4. Configurar o Servidor Web
Start-PodeServer {
    Add-PodeEndpoint -Address * -Port 80 -Protocol Http

    # Servir ficheiros estaticos do Dashboard
    Add-PodeStaticRoute -Path '/' -Source "$ProjectRoot\dashboard"

    # ==========================================
    # ROTAS DA API - Leem ficheiros de cache
    # ==========================================
    # Cada rota simplesmente le o ficheiro JSON correspondente
    # de C:\SysAdmin\cache\. Resposta instantanea (<1ms).
    # O cache e atualizado pelo Update-DashboardCache.ps1 em background.

    Add-PodeRoute -Method Get -Path '/api/stats.ps1' -ScriptBlock {
        $file = "C:\SysAdmin\cache\stats.json"
        if (Test-Path $file) {
            $json = [System.IO.File]::ReadAllText($file)
        } else {
            $json = '{"erro":"cache ainda nao disponivel","timestamp":"' + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + '"}'
        }
        Write-PodeTextResponse -Value $json -ContentType 'application/json'
    }

    Add-PodeRoute -Method Get -Path '/api/users.ps1' -ScriptBlock {
        $file = "C:\SysAdmin\cache\users.json"
        if (Test-Path $file) {
            $json = [System.IO.File]::ReadAllText($file)
        } else {
            $json = '{"erro":"cache ainda nao disponivel","totalUsers":0,"totalGroups":0,"ativos":0,"inativos":0,"users":[],"groups":[]}'
        }
        Write-PodeTextResponse -Value $json -ContentType 'application/json'
    }

    Add-PodeRoute -Method Get -Path '/api/filesystem.ps1' -ScriptBlock {
        $file = "C:\SysAdmin\cache\filesystem.json"
        if (Test-Path $file) {
            $json = [System.IO.File]::ReadAllText($file)
        } else {
            $json = '{"erro":"cache ainda nao disponivel","discos":[],"ficheirosGrandes":[],"recentes":[],"suspeitos":[],"shares":[],"totalGrandes":0,"totalSuspeitos":0}'
        }
        Write-PodeTextResponse -Value $json -ContentType 'application/json'
    }

    Add-PodeRoute -Method Get -Path '/api/services.ps1' -ScriptBlock {
        $file = "C:\SysAdmin\cache\services.json"
        if (Test-Path $file) {
            $json = [System.IO.File]::ReadAllText($file)
        } else {
            $json = '{"erro":"cache ainda nao disponivel","totalAtivos":0,"totalParados":0,"criticosDown":0,"criticos":[],"parados":[],"roles":[],"alertas":[]}'
        }
        Write-PodeTextResponse -Value $json -ContentType 'application/json'
    }

    Add-PodeRoute -Method Get -Path '/api/network.ps1' -ScriptBlock {
        $file = "C:\SysAdmin\cache\network.json"
        if (Test-Path $file) {
            $json = [System.IO.File]::ReadAllText($file)
        } else {
            $json = '{"erro":"cache ainda nao disponivel","interfaces":[],"trafego":[],"portas":[],"conexoes":[],"dns":[],"ping":[],"totalPortas":0,"totalConex":0}'
        }
        Write-PodeTextResponse -Value $json -ContentType 'application/json'
    }

    Add-PodeRoute -Method Get -Path '/api/security.ps1' -ScriptBlock {
        $file = "C:\SysAdmin\cache\security.json"
        if (Test-Path $file) {
            $json = [System.IO.File]::ReadAllText($file)
        } else {
            $json = '{"erro":"cache ainda nao disponivel","loginsFalhados":[],"loginsSucesso":[],"totalFalhados":0,"totalSucesso":0,"portasAbertas":[],"firewall":[],"contasBloqueadas":[],"alertas":[]}'
        }
        Write-PodeTextResponse -Value $json -ContentType 'application/json'
    }

    Add-PodeRoute -Method Get -Path '/api/backup.ps1' -ScriptBlock {
        $file = "C:\SysAdmin\cache\backup.json"
        if (Test-Path $file) {
            $json = [System.IO.File]::ReadAllText($file)
        } else {
            $json = '{"erro":"cache ainda nao disponivel","totalBackups":0,"totalSizeMB":0,"ultimoBackup":"Nenhum","backups":[],"agendados":[]}'
        }
        Write-PodeTextResponse -Value $json -ContentType 'application/json'
    }
}

# 5. Quando o Pode parar (janela fechada), matar o cache updater
Write-Host "`n[+] A parar o cache updater..." -ForegroundColor Yellow
if ($cacheJob -and -not $cacheJob.HasExited) {
    Stop-Process -Id $cacheJob.Id -Force -ErrorAction SilentlyContinue
}
Write-Host "[OK] Servidor parado." -ForegroundColor Green
