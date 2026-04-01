# ==============================================================
# Manage-ADUsers.ps1
# Gestao de Utilizadores e Grupos do Active Directory
# Pode ser usado via menu CLI ou individualmente
# ==============================================================

param(
    [Parameter(Position=0)]
    [ValidateSet("listar","criar","remover","grupo-criar","grupo-adicionar","grupo-remover","grupo-listar","relatorio","json")]
    [string]$Acao,

    [string]$Nome,
    [string]$Username,
    [string]$Password,
    [string]$Grupo,
    [string]$OU
)

$ErrorActionPreference = "SilentlyContinue"
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

$DataRoot = "C:\SysAdmin"
$LogFile  = "$DataRoot\logs\users.log"

function Write-Log {
    param([string]$Msg)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    if (-not (Test-Path (Split-Path $LogFile))) { New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null }
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
}

# ── Modo JSON (para a API do Dashboard) ──
if ($Acao -eq "json") {
    $users = @()
    $groups = @()

    try {
        $users = @(Get-ADUser -Filter * -Properties DisplayName, SamAccountName, Enabled, LastLogonDate, MemberOf, WhenCreated |
            Select-Object -First 50 | ForEach-Object {
                @{
                    nome        = if ($_.DisplayName) { $_.DisplayName } else { $_.SamAccountName }
                    username    = $_.SamAccountName
                    ativo       = [bool]$_.Enabled
                    ultimoLogin = if ($_.LastLogonDate) { $_.LastLogonDate.ToString("yyyy-MM-dd HH:mm") } else { "Nunca" }
                    criadoEm    = if ($_.WhenCreated) { $_.WhenCreated.ToString("yyyy-MM-dd") } else { "" }
                    grupos      = ($_.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace 'CN=','' }) -join ', '
                }
            })

        $groups = @(Get-ADGroup -Filter * -Properties Members, Description |
            Select-Object -First 30 | ForEach-Object {
                @{
                    nome      = $_.Name
                    descricao = if ($_.Description) { $_.Description } else { "" }
                    membros   = ($_.Members | Measure-Object).Count
                }
            })
    } catch {}

    $resultado = @{
        timestamp   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        totalUsers  = ($users | Measure-Object).Count
        totalGroups = ($groups | Measure-Object).Count
        ativos      = ($users | Where-Object { $_.ativo -eq $true } | Measure-Object).Count
        inativos    = ($users | Where-Object { $_.ativo -eq $false } | Measure-Object).Count
        users       = $users
        groups      = $groups
    }

    $resultado | ConvertTo-Json -Depth 5
    return
}

# ── Funcoes CLI ──

function Listar-Users {
    Write-Host ""
    Write-Host "  UTILIZADORES DO ACTIVE DIRECTORY" -ForegroundColor Cyan
    Write-Host "  ================================" -ForegroundColor Cyan
    $users = Get-ADUser -Filter * -Properties DisplayName, Enabled, LastLogonDate
    $users | Format-Table @{L='Nome';E={$_.DisplayName}}, SamAccountName, Enabled,
        @{L='Ultimo Login';E={if($_.LastLogonDate){$_.LastLogonDate.ToString("yyyy-MM-dd HH:mm")}else{"Nunca"}}} -AutoSize
    Write-Host "  Total: $($users.Count) utilizadores" -ForegroundColor Gray
    Write-Log "Listagem de utilizadores executada. Total: $($users.Count)"
}

function Criar-User {
    if (-not $Nome)     { $Nome     = Read-Host "  Nome completo" }
    if (-not $Username) { $Username = Read-Host "  Username (SamAccountName)" }
    if (-not $Password) { $Password = Read-Host "  Password" }

    $dominio = (Get-ADDomain).DNSRoot
    $ouPath  = if ($OU) { $OU } else { (Get-ADDomain).UsersContainer }

    try {
        New-ADUser `
            -Name $Nome `
            -SamAccountName $Username `
            -UserPrincipalName "$Username@$dominio" `
            -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -Force) `
            -Enabled $true `
            -Path $ouPath `
            -ChangePasswordAtLogon $false

        Write-Host "  [OK] Utilizador '$Username' criado com sucesso." -ForegroundColor Green
        Write-Log "Utilizador criado: $Username ($Nome)"
    } catch {
        Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "ERRO ao criar utilizador $Username : $($_.Exception.Message)"
    }
}

function Remover-User {
    if (-not $Username) { $Username = Read-Host "  Username a remover" }

    try {
        $user = Get-ADUser -Identity $Username
        Remove-ADUser -Identity $Username -Confirm:$false
        Write-Host "  [OK] Utilizador '$Username' removido." -ForegroundColor Green
        Write-Log "Utilizador removido: $Username"
    } catch {
        Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "ERRO ao remover utilizador $Username : $($_.Exception.Message)"
    }
}

function Criar-Grupo {
    if (-not $Grupo) { $Grupo = Read-Host "  Nome do grupo" }
    $desc = Read-Host "  Descricao (ENTER para vazio)"

    try {
        New-ADGroup -Name $Grupo -GroupScope Global -GroupCategory Security -Description $desc
        Write-Host "  [OK] Grupo '$Grupo' criado." -ForegroundColor Green
        Write-Log "Grupo criado: $Grupo"
    } catch {
        Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Adicionar-AoGrupo {
    if (-not $Username) { $Username = Read-Host "  Username" }
    if (-not $Grupo)    { $Grupo    = Read-Host "  Nome do grupo" }

    try {
        Add-ADGroupMember -Identity $Grupo -Members $Username
        Write-Host "  [OK] '$Username' adicionado ao grupo '$Grupo'." -ForegroundColor Green
        Write-Log "Utilizador $Username adicionado ao grupo $Grupo"
    } catch {
        Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Remover-DoGrupo {
    if (-not $Username) { $Username = Read-Host "  Username" }
    if (-not $Grupo)    { $Grupo    = Read-Host "  Nome do grupo" }

    try {
        Remove-ADGroupMember -Identity $Grupo -Members $Username -Confirm:$false
        Write-Host "  [OK] '$Username' removido do grupo '$Grupo'." -ForegroundColor Green
        Write-Log "Utilizador $Username removido do grupo $Grupo"
    } catch {
        Write-Host "  [ERRO] $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Listar-Grupos {
    Write-Host ""
    Write-Host "  GRUPOS DO ACTIVE DIRECTORY" -ForegroundColor Cyan
    Write-Host "  ==========================" -ForegroundColor Cyan
    $groups = Get-ADGroup -Filter * -Properties Members, Description
    $groups | Format-Table Name, @{L='Membros';E={($_.Members|Measure-Object).Count}}, Description -AutoSize
    Write-Host "  Total: $($groups.Count) grupos" -ForegroundColor Gray
}

function Gerar-Relatorio {
    $reportDir = "$DataRoot\reports"
    if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
    $reportFile = "$reportDir\relatorio-users-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

    $content = @()
    $content += "============================================"
    $content += "  RELATORIO DE UTILIZADORES E GRUPOS"
    $content += "  Gerado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $content += "  Servidor: $env:COMPUTERNAME"
    $content += "============================================"
    $content += ""

    $users = Get-ADUser -Filter * -Properties DisplayName, Enabled, LastLogonDate, WhenCreated
    $content += "UTILIZADORES ($($users.Count) total):"
    $content += "-" * 60
    foreach ($u in $users) {
        $estado = if ($u.Enabled) { "ATIVO" } else { "INATIVO" }
        $content += "  $($u.SamAccountName) | $($u.DisplayName) | $estado | Criado: $($u.WhenCreated.ToString('yyyy-MM-dd'))"
    }

    $content += ""
    $groups = Get-ADGroup -Filter * -Properties Members
    $content += "GRUPOS ($($groups.Count) total):"
    $content += "-" * 60
    foreach ($g in $groups) {
        $membros = ($g.Members | Measure-Object).Count
        $content += "  $($g.Name) | $membros membros"
    }

    $content | Out-File -FilePath $reportFile -Encoding UTF8
    Write-Host "  [OK] Relatorio guardado em: $reportFile" -ForegroundColor Green
    Write-Log "Relatorio de utilizadores gerado: $reportFile"
}

# ── Execucao ──
switch ($Acao) {
    "listar"          { Listar-Users }
    "criar"           { Criar-User }
    "remover"         { Remover-User }
    "grupo-criar"     { Criar-Grupo }
    "grupo-adicionar" { Adicionar-AoGrupo }
    "grupo-remover"   { Remover-DoGrupo }
    "grupo-listar"    { Listar-Grupos }
    "relatorio"       { Gerar-Relatorio }
    default {
        Write-Host ""
        Write-Host "  Uso: .\Manage-ADUsers.ps1 <acao> [-Username x] [-Nome x] [-Password x] [-Grupo x]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Acoes disponiveis:" -ForegroundColor Gray
        Write-Host "    listar          - Lista todos os utilizadores"
        Write-Host "    criar           - Cria um novo utilizador"
        Write-Host "    remover         - Remove um utilizador"
        Write-Host "    grupo-criar     - Cria um grupo"
        Write-Host "    grupo-adicionar - Adiciona utilizador a um grupo"
        Write-Host "    grupo-remover   - Remove utilizador de um grupo"
        Write-Host "    grupo-listar    - Lista todos os grupos"
        Write-Host "    relatorio       - Gera relatorio completo"
        Write-Host "    json            - Devolve dados em JSON (para API)"
        Write-Host ""
    }
}
