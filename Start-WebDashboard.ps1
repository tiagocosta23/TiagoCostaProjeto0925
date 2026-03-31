# Start-WebDashboard.ps1
# Inicia o Servidor Web nativo (Pode) para o Dashboard
# Executar como Administrador

$Host.UI.RawUI.WindowTitle = "Servidor Web Dashboard (Pode)"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  A INICIAR SERVIDOR WEB DASHBOARD" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

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

Write-Host "`n[+] A arrancar o servidor na porta 80..." -ForegroundColor Yellow
Write-Host "[+] Podes fechar esta janela para desligar o servidor web.`n" -ForegroundColor Gray

# Definir a diretoria raiz de onde o servidor está a ser executado
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 2. Configurar o Servidor Web
Start-PodeServer {
    Add-PodeEndpoint -Address * -Port 80 -Protocol Http

    # Servir os ficheiros estaticos (HTML/JS/CSS) do Dashboard
    Add-PodeStaticRoute -Path '/' -Source "$ProjectRoot\dashboard"

    # ==========================================
    # ROTAS DA API 
    # ==========================================
    # Em Pode, usamos $PodeContext.Server.Root para obter a pasta base 
    # de forma segura dentro das threads (Runspaces).

    Add-PodeRoute -Method Get -Path '/api/stats.ps1' -ScriptBlock {
        $base = $PodeContext.Server.Root
        $json = & "$base\scripts\monitoring\Get-SystemStats.ps1" | Out-String
        Write-PodeJsonResponse -Value (ConvertFrom-Json $json)
    }

    Add-PodeRoute -Method Get -Path '/api/users.ps1' -ScriptBlock {
        $base = $PodeContext.Server.Root
        $json = & "$base\scripts\users\Manage-ADUsers.ps1" json | Out-String
        Write-PodeJsonResponse -Value (ConvertFrom-Json $json)
    }

    Add-PodeRoute -Method Get -Path '/api/filesystem.ps1' -ScriptBlock {
        $base = $PodeContext.Server.Root
        $json = & "$base\scripts\filesystem\Audit-FileSystem.ps1" json | Out-String
        Write-PodeJsonResponse -Value (ConvertFrom-Json $json)
    }

    Add-PodeRoute -Method Get -Path '/api/services.ps1' -ScriptBlock {
        $base = $PodeContext.Server.Root
        $json = & "$base\scripts\services\Monitor-Services.ps1" json | Out-String
        Write-PodeJsonResponse -Value (ConvertFrom-Json $json)
    }

    Add-PodeRoute -Method Get -Path '/api/network.ps1' -ScriptBlock {
        $base = $PodeContext.Server.Root
        $json = & "$base\scripts\network\Monitor-Network.ps1" json | Out-String
        Write-PodeJsonResponse -Value (ConvertFrom-Json $json)
    }

    Add-PodeRoute -Method Get -Path '/api/security.ps1' -ScriptBlock {
        $base = $PodeContext.Server.Root
        $json = & "$base\scripts\security\Monitor-Security.ps1" json | Out-String
        Write-PodeJsonResponse -Value (ConvertFrom-Json $json)
    }

    Add-PodeRoute -Method Get -Path '/api/backup.ps1' -ScriptBlock {
        $base = $PodeContext.Server.Root
        $json = & "$base\scripts\backup\Manage-Backup.ps1" json | Out-String
        Write-PodeJsonResponse -Value (ConvertFrom-Json $json)
    }
}