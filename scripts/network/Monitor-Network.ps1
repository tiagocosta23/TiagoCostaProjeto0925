# ==============================================================
# Monitor-Network.ps1
# Monitorizacao de Rede, Portas e Conectividade
# ==============================================================

param(
    [Parameter(Position=0)]
    [ValidateSet("interfaces","portas","conexoes","dns","ping","trafego","json")]
    [string]$Acao,

    [string]$Alvo = "192.168.1.1"
)

$ErrorActionPreference = "SilentlyContinue"
$DataRoot = "C:\SysAdmin"
$LogFile  = "$DataRoot\logs\network.log"

function Write-Log {
    param([string]$Msg)
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Msg"
    if (-not (Test-Path (Split-Path $LogFile))) { New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null }
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
}

# ── Modo JSON (para a API do Dashboard) ──
# NOTA: Tem de ser rapido (<10s) para nao dar timeout no Pode.
if ($Acao -eq "json") {
    # Interfaces de rede
    $interfaces = @(Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ip = Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $speedText = $_.LinkSpeed
        if (-not $speedText) { $speedText = "N/A" }
        @{
            nome       = $_.Name
            descricao  = $_.InterfaceDescription
            mac        = $_.MacAddress
            velocidade = $speedText
            ip         = if ($ip) { $ip.IPAddress } else { "N/A" }
            estado     = $_.Status.ToString()
        }
    })

    # Trafego de rede
    $trafego = @()
    try {
        $trafego = @(Get-CimInstance -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface |
            Where-Object { $_.BytesTotalPersec -gt 0 } | ForEach-Object {
                @{
                    adapter    = $_.Name -replace '\(.*\)','' -replace '_',' '
                    bytesInKB  = [math]::Round($_.BytesReceivedPersec / 1KB, 2)
                    bytesOutKB = [math]::Round($_.BytesSentPersec / 1KB, 2)
                    totalKB    = [math]::Round($_.BytesTotalPersec / 1KB, 2)
                }
            })
    } catch {}

    # Portas abertas (listening)
    $portas = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Sort-Object LocalPort |
        Select-Object -First 30 | ForEach-Object {
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            @{
                porta     = $_.LocalPort
                endereco  = $_.LocalAddress
                pid       = $_.OwningProcess
                processo  = if ($proc) { $proc.ProcessName } else { "N/A" }
            }
        })

    # Conexoes ativas
    $conexoes = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Select-Object -First 20 | ForEach-Object {
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            @{
                localPort  = $_.LocalPort
                remoteAddr = $_.RemoteAddress
                remotePort = $_.RemotePort
                processo   = if ($proc) { $proc.ProcessName } else { "N/A" }
            }
        })

    # DNS config
    $dnsConfig = @(Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | ForEach-Object {
        @{
            interface  = $_.InterfaceAlias
            servidores = $_.ServerAddresses -join ", "
        }
    })

    # Teste de conectividade - timeout curto (1 segundo) para nao atrasar
    $pingResults = @()
    $alvos = @("192.168.1.1", "8.8.8.8", "1.1.1.1")
    foreach ($a in $alvos) {
        try {
            $test = Test-Connection -ComputerName $a -Count 1 -TimeToLive 30 -Quiet -ErrorAction SilentlyContinue
            $pingResults += @{ alvo = $a; alcancavel = [bool]$test }
        } catch {
            $pingResults += @{ alvo = $a; alcancavel = $false }
        }
    }

    $resultado = @{
        timestamp   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        interfaces  = $interfaces
        trafego     = $trafego
        portas      = $portas
        conexoes    = $conexoes
        dns         = $dnsConfig
        ping        = $pingResults
        totalPortas = ($portas | Measure-Object).Count
        totalConex  = ($conexoes | Measure-Object).Count
    }

    $resultado | ConvertTo-Json -Depth 5
    return
}

# ── Funcoes CLI ──

function Mostrar-Interfaces {
    Write-Host ""
    Write-Host "  INTERFACES DE REDE" -ForegroundColor Cyan
    Write-Host "  ====================" -ForegroundColor Cyan
    Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, MacAddress, LinkSpeed -AutoSize | Out-Host
    Write-Host "  ENDERECOS IP:" -ForegroundColor Yellow
    Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" } |
        Format-Table InterfaceAlias, IPAddress, PrefixLength -AutoSize | Out-Host
}

function Mostrar-Portas {
    Write-Host ""
    Write-Host "  PORTAS ABERTAS (LISTENING)" -ForegroundColor Cyan
    Write-Host "  ===========================" -ForegroundColor Cyan
    Get-NetTCPConnection -State Listen | Sort-Object LocalPort | ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        $procName = if ($proc) { $proc.ProcessName } else { "N/A" }
        [PSCustomObject]@{
            Porta    = $_.LocalPort
            Endereco = $_.LocalAddress
            PID      = $_.OwningProcess
            Processo = $procName
        }
    } | Format-Table -AutoSize | Out-Host
    Write-Log "Listagem de portas abertas executada"
}

function Mostrar-Conexoes {
    Write-Host ""
    Write-Host "  CONEXOES ATIVAS (ESTABLISHED)" -ForegroundColor Cyan
    Get-NetTCPConnection -State Established | ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Local      = "$($_.LocalAddress):$($_.LocalPort)"
            Remoto     = "$($_.RemoteAddress):$($_.RemotePort)"
            Processo   = if ($proc) { $proc.ProcessName } else { "N/A" }
        }
    } | Format-Table -AutoSize | Out-Host
}

function Testar-DNS {
    Write-Host ""
    Write-Host "  CONFIGURACAO DNS" -ForegroundColor Cyan
    Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } |
        Format-Table InterfaceAlias, ServerAddresses -AutoSize | Out-Host

    Write-Host "  TESTE DE RESOLUCAO:" -ForegroundColor Yellow
    $dominios = @("google.com", "microsoft.com")
    try {
        $dominio = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot
        if ($dominio) { $dominios = @($dominio) + $dominios }
    } catch {}

    foreach ($d in $dominios) {
        $r = Resolve-DnsName $d -ErrorAction SilentlyContinue
        if ($r) {
            Write-Host "  [OK] $d -> $($r[0].IPAddress)" -ForegroundColor Green
        } else {
            Write-Host "  [FALHA] $d -> nao resolve" -ForegroundColor Red
        }
    }
}

function Testar-Ping {
    Write-Host ""
    Write-Host "  TESTE DE CONECTIVIDADE" -ForegroundColor Cyan
    $alvos = @("192.168.1.1", "8.8.8.8", "1.1.1.1", $Alvo)
    $alvos = $alvos | Select-Object -Unique
    foreach ($a in $alvos) {
        $r = Test-Connection -ComputerName $a -Count 2 -ErrorAction SilentlyContinue
        if ($r) {
            $avg = [math]::Round(($r | Measure-Object -Property ResponseTime -Average).Average, 1)
            Write-Host "  [OK] $a - ${avg}ms" -ForegroundColor Green
        } else {
            Write-Host "  [FALHA] $a - sem resposta" -ForegroundColor Red
        }
    }
    Write-Log "Teste de conectividade executado"
}

function Mostrar-Trafego {
    Write-Host ""
    Write-Host "  TRAFEGO DE REDE (tempo real, 5 amostras)" -ForegroundColor Cyan
    for ($i = 1; $i -le 5; $i++) {
        Get-CimInstance -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface |
            Where-Object { $_.BytesTotalPersec -gt 0 } | ForEach-Object {
                $name = $_.Name -replace '\(.*\)','' -replace '_',' '
                $inKB  = [math]::Round($_.BytesReceivedPersec / 1KB, 2)
                $outKB = [math]::Round($_.BytesSentPersec / 1KB, 2)
                Write-Host "  [$i/5] $name | IN: ${inKB} KB/s | OUT: ${outKB} KB/s" -ForegroundColor Gray
            }
        if ($i -lt 5) { Start-Sleep -Seconds 2 }
    }
}

# ── Execucao ──
switch ($Acao) {
    "interfaces" { Mostrar-Interfaces }
    "portas"     { Mostrar-Portas }
    "conexoes"   { Mostrar-Conexoes }
    "dns"        { Testar-DNS }
    "ping"       { Testar-Ping }
    "trafego"    { Mostrar-Trafego }
    default {
        Write-Host ""
        Write-Host "  Uso: .\Monitor-Network.ps1 <acao> [-Alvo IP]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Acoes: interfaces, portas, conexoes, dns, ping, trafego, json"
        Write-Host ""
    }
}
