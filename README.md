# Sistema Automatizado de Administração e Monitorização de Infraestrutura de TI

Toolkit completo em PowerShell para configuração, administração e monitorização de uma infraestrutura Windows Server com Active Directory — incluindo um dashboard web em tempo real.

---

## Sobre o Projeto

Este projeto implementa um sistema centralizado de gestão de infraestrutura Windows Server, cobrindo todo o ciclo de vida: desde a configuração inicial do servidor e domínio AD, até à monitorização contínua de recursos, segurança, rede, serviços e backups.

O sistema é composto por scripts interativos de setup, um menu CLI unificado para operações do dia-a-dia, módulos especializados por área, e um dashboard web com atualização automática a cada 30 segundos.

### Arquitetura da Infraestrutura

| Componente | Função |
|---|---|
| **Windows Server** | Domain Controller, DNS, File Server, Print Server |
| **pfSense** | Gateway / Firewall (192.168.1.1) |
| **Cliente Windows 10/11** | Estação de trabalho no domínio |

---

## Estrutura do Repositório

```
TiagoCostaProjeto0925/
│
├── Setup-Server.ps1            # Passo 1/2 — Hostname, IP, roles base
├── Setup-ADDomain.ps1          # Passo 2/2 — Promoção a Domain Controller
├── Setup-Client.ps1            # Configurar e juntar cliente ao domínio
├── Setup-Projeto.ps1           # Criar estrutura de pastas do projeto
├── SistemaAdmin.ps1            # Menu principal de administração (CLI)
├── Start-WebDashboard.ps1      # Servidor web do dashboard (Pode)
├── Update-DashboardCache.ps1   # Atualizador de cache em background
├── Test-Infraestrutura.ps1     # Validação completa da infraestrutura
│
├── scripts/
│   ├── monitoring/
│   │   └── Get-SystemStats.ps1       # CPU, RAM, disco, rede, processos
│   ├── users/
│   │   └── Manage-ADUsers.ps1        # CRUD utilizadores e grupos AD
│   ├── filesystem/
│   │   └── Audit-FileSystem.ps1      # Espaço, ficheiros grandes, suspeitos
│   ├── services/
│   │   └── Monitor-Services.ps1      # Serviços críticos, auto-reinício
│   ├── network/
│   │   └── Monitor-Network.ps1       # Interfaces, portas, DNS, tráfego
│   ├── backup/
│   │   └── Manage-Backup.ps1         # Completo, incremental, agendamento
│   └── security/
│       └── Monitor-Security.ps1      # Logins falhados, firewall, eventos
│
└── dashboard/
    └── index.html                    # Dashboard web (single-page)
```

Os dados operacionais (logs, relatórios, backups, cache) são guardados em `C:\SysAdmin` para não poluir o repositório.

---

## Guia de Instalação

### Pré-requisitos

- Windows Server 2016 ou superior
- PowerShell 5.1+
- Executar todos os scripts como **Administrador**
- Acesso à internet (para instalar o módulo Pode no dashboard)

### Passo a Passo

**1. Clonar o repositório no servidor:**

```powershell
git clone https://github.com/tiagocosta23/TiagoCostaProjeto0925.git
cd TiagoCostaProjeto0925
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

**2. Criar a estrutura de pastas:**

```powershell
.\Setup-Projeto.ps1
```

**3. Configurar o servidor (Passo 1/2):**

```powershell
.\Setup-Server.ps1
```

Configura hostname, IP estático, timezone, desativa IPv6, ativa RDP, instala roles (AD DS, DNS, File Server) e reinicia automaticamente.

**4. Promover a Domain Controller (Passo 2/2):**

```powershell
.\Setup-ADDomain.ps1
```

Cria a forest AD, instala o DNS integrado e reinicia. Domínio sugerido: `atec.local`.

**5. Configurar o cliente:**

No Windows 10/11 cliente, executar:

```powershell
.\Setup-Client.ps1
```

Define IP estático, testa conectividade com o DC e junta a máquina ao domínio.

**6. Validar a infraestrutura:**

```powershell
.\Test-Infraestrutura.ps1
```

Verifica conectividade, AD/DNS, roles, serviços e dashboard — apresenta um relatório com OK/FAIL/WARN.

---

## Utilização

### Menu CLI (SistemaAdmin)

```powershell
.\SistemaAdmin.ps1
```

Menu interativo com 9 áreas:

| Opção | Módulo | Funcionalidades |
|---|---|---|
| 1 | Monitorização de Recursos | Resumo geral, tempo real (5 ciclos), relatório |
| 2 | Gestão de Processos | Top CPU/RAM, procurar, terminar por PID/nome |
| 3 | Utilizadores e Grupos | Listar, criar, remover utilizadores/grupos AD, relatórios |
| 4 | Sistema de Ficheiros | Espaço em disco, ficheiros grandes, suspeitos, permissões |
| 5 | Serviços e Servidores | Serviços críticos, parados, auto-reinício |
| 6 | Rede e Conectividade | Interfaces, portas abertas, DNS, ping, tráfego |
| 7 | Segurança do Sistema | Logins falhados, eventos, firewall, contas bloqueadas |
| 8 | Backup e Recuperação | Completo, incremental, verificar, restaurar, agendar |
| 9 | Dashboard Web | Abre o dashboard no browser |

### Dashboard Web

```powershell
.\Start-WebDashboard.ps1
```

Inicia um servidor web local (módulo **Pode**) em `http://localhost` com as seguintes secções:

- **Overview** — KPIs gerais: CPU, RAM, disco, uptime, alertas
- **Processos** — Top processos por consumo de CPU/RAM
- **Utilizadores** — Lista de utilizadores e grupos do AD
- **Ficheiros** — Análise de disco, ficheiros grandes e suspeitos
- **Serviços** — Estado dos serviços críticos e alertas
- **Rede** — Interfaces, portas abertas, conexões ativas, DNS
- **Segurança** — Logins falhados/bem-sucedidos, firewall, eventos
- **Backup** — Lista de backups, tamanho total, agendamentos

O dashboard tem tema escuro estilo terminal, atualização automática a cada 30 segundos via cache JSON, e é responsivo.

### Uso Individual dos Módulos

Cada módulo pode ser executado de forma autónoma. Exemplos:

```powershell
# Obter stats do sistema em JSON
.\scripts\monitoring\Get-SystemStats.ps1

# Criar um utilizador AD
.\scripts\users\Manage-ADUsers.ps1 criar -Nome "João Silva" -Username "jsilva" -Password "Pass@123"

# Backup completo
.\scripts\backup\Manage-Backup.ps1 completo -Origem "C:\Users"

# Backup incremental
.\scripts\backup\Manage-Backup.ps1 incremental

# Agendar backup diário
.\scripts\backup\Manage-Backup.ps1 agendar

# Verificar segurança
.\scripts\security\Monitor-Security.ps1 logins

# Monitorizar rede
.\scripts\network\Monitor-Network.ps1 portas
```

---

## Rede (Configuração Sugerida)

| Dispositivo | IP | Função |
|---|---|---|
| pfSense (Gateway) | 192.168.1.1 | Firewall / Router |
| Windows Server (DC) | 192.168.1.10 | Domain Controller, DNS, File Server |
| Cliente Windows | 192.168.1.20 | Estação de trabalho |

Subnet: `192.168.1.0/24` · DNS Primário: `127.0.0.1` (no servidor) · DNS Secundário: `8.8.8.8`

---

## Tecnologias

- **PowerShell 5.1+** — Toda a lógica de administração e automação
- **Active Directory (AD DS)** — Gestão de utilizadores, grupos e domínio
- **Pode** (módulo PowerShell) — Servidor web leve para o dashboard
- **HTML/CSS/JavaScript** — Dashboard single-page com design responsivo
- **Windows Task Scheduler** — Agendamento de backups automáticos

---

## Autor

**Tiago Costa**

---

## Licença

Projeto académico / formação profissional.
