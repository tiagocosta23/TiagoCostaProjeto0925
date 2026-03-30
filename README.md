# TiagoCostaProjeto0925

Sistema automatizado de administração e monitorização de infraestrutura de TI.
Desenvolvido em PowerShell + IIS + HTML/JS para Windows Server 2025.

---

## Arquitetura

```
Browser (cliente ou servidor)
        │  HTTP porta 80
        ▼
      IIS (Windows Server 2025)
        │  executa via CGI
        ▼
  Scripts PowerShell  →  devolvem JSON
        │  lêem
        ▼
  Windows Server (AD DS, disco, serviços, logs...)
```

## Infraestrutura VMware

| VM                  | IP            | Função                        |
|---------------------|---------------|-------------------------------|
| pfSense             | 192.168.1.1   | Gateway / Firewall            |
| Windows Server 2025 | 192.168.1.10  | AD DS, File Server, Dashboard |
| Windows 10/11       | 192.168.1.20  | Cliente do domínio            |

---

## Instalação via Git

### Pré-requisito — Permitir execução de scripts (em todas as máquinas Windows)
```powershell
Set-ExecutionPolicy RemoteSigned
```

### No Servidor (Windows Server 2025)
```powershell
git clone https://github.com/TiagoCosta/TiagoCostaProjeto0925.git C:\TiagoCostaProjeto0925
cd C:\TiagoCostaProjeto0925
```

### No Cliente (Windows 10/11)
```powershell
git clone https://github.com/TiagoCosta/TiagoCostaProjeto0925.git C:\TiagoCostaProjeto0925
cd C:\TiagoCostaProjeto0925
```

### Atualizar com novas versões
```powershell
cd C:\TiagoCostaProjeto0925
git pull
```

> **Nota:** Os scripts detetam automaticamente a pasta onde foram clonados
> usando `$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path`.
> Podes clonar para qualquer pasta — os caminhos ajustam-se sozinhos.

---

## Ordem de Execução

### FASE 1 — No Servidor

| Passo | Script                  | Reinicia? |
|-------|-------------------------|-----------|
| 1     | Setup-Projeto.ps1       | Não       |
| 2     | Setup-Server.ps1        | Sim       |
| 3     | Setup-ADDomain.ps1      | Sim (auto)|
| 4     | Setup-IIS.ps1           | Não       |

### FASE 2 — No Cliente

| Passo | Script                  | Reinicia? |
|-------|-------------------------|-----------|
| 5     | Setup-Client.ps1        | Sim       |

### FASE 3 — Verificação (no Servidor)

| Passo | Script                       | Reinicia? |
|-------|------------------------------|-----------|
| 6     | Test-Infraestrutura.ps1      | Não       |

---

## Descrição dos Scripts

### `Setup-Projeto.ps1`
Cria a estrutura de pastas do projeto a partir da raiz do repositório.
Deve ser o primeiro script a correr.

### `Setup-Server.ps1`
Configura o hostname, IP estático e instala todas as Windows Features
necessárias (AD DS, DNS, File Server, IIS, etc.). Reinicia no final.

### `Setup-ADDomain.ps1`
Promove o servidor a Domain Controller e cria a forest Active Directory.
O DNS é configurado automaticamente. O servidor reinicia automaticamente.

### `Setup-IIS.ps1`
Configura o IIS para servir o Dashboard Web e a API PowerShell.
Regista o PowerShell como handler CGI e define permissões.

### `Setup-Client.ps1`
Configura o IP estático do cliente e junta-o ao domínio.
Executar na máquina cliente, não no servidor.

### `Test-Infraestrutura.ps1`
Verifica se toda a infraestrutura está operacional — rede, AD, DNS,
roles, serviços e dashboard. Mostra OK/FAIL/WARN por componente.

### `scripts/monitoring/Get-SystemStats.ps1`
Recolhe CPU, RAM, disco, rede e processos e devolve JSON.
Chamado automaticamente pelo IIS a cada pedido do dashboard.

---

## Estrutura de Pastas

```
TiagoCostaProjeto0925/              ← raiz do repositório (git clone)
├── README.md
├── Tutorial-SistemaAdmin.docx
├── Setup-Projeto.ps1               # [1] Cria estrutura de pastas
├── Setup-Server.ps1                # [2] Hostname + IP + Roles
├── Setup-ADDomain.ps1              # [3] Promove DC + cria domínio
├── Setup-IIS.ps1                   # [4] Configura IIS + API
├── Setup-Client.ps1                # [5] Configura cliente + domínio
├── Test-Infraestrutura.ps1         # [6] Verifica tudo
├── scripts/
│   ├── monitoring/
│   │   └── Get-SystemStats.ps1     # CPU, RAM, Disco, Rede, Processos
│   ├── users/                      # (Semana 2) Gestão AD
│   ├── filesystem/                 # (Semana 2) Auditoria ficheiros
│   ├── services/                   # (Semana 3) Monitorização serviços
│   ├── network/                    # (Semana 3) Rede e portas
│   ├── backup/                     # (Semana 4) Backup automático
│   └── security/                   # (Semana 4) Logs de segurança
├── dashboard/
│   └── index.html                  # Dashboard Web
├── iis-api/
│   └── stats.ps1                   # Wrapper IIS → Get-SystemStats
├── logs/                           # Logs gerados (ignorado pelo git)
└── reports/                        # Relatórios gerados (ignorado pelo git)
```

---

## Módulos

| Módulo              | Script                  | Estado      |
|---------------------|-------------------------|-------------|
| Setup infraestrutura| Setup-*.ps1             | ✅ Completo |
| Monitorização base  | Get-SystemStats.ps1     | ✅ Completo |
| Dashboard Web       | index.html              | ✅ Completo |
| Utilizadores AD     | Manage-Users.ps1        | 🔄 Semana 2 |
| Sistema de Ficheiros| Audit-FileSystem.ps1    | 🔄 Semana 2 |
| Serviços            | Monitor-Services.ps1    | 🔄 Semana 3 |
| Rede                | Monitor-Network.ps1     | 🔄 Semana 3 |
| Backup              | Run-Backup.ps1          | 🔄 Semana 4 |
| Segurança           | Audit-Security.ps1      | 🔄 Semana 4 |

---

## Apresentação

**Data:** 2 de abril de 2026
**Repositório:** TiagoCostaProjeto0925
