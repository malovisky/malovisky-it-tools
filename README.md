# MALOVISKY IT TOOLS

**Powered by Thomaz J**  
**Versão atual: v1.3.0 — 12/11/2026**

Conjunto de ferramentas em **Windows PowerShell 5.1** para manutenção, suporte e diagnóstico em ambientes Windows. Menu interativo com identidade visual **Matrix** (preto e verde), publicado no Cloudflare Pages e versionado no GitHub.

**Endereço oficial:** https://scripts.malovisky.com.br  
**Sobre o projeto:** https://scripts.malovisky.com.br/sobre/

## Iniciar

Abra o **Windows PowerShell** e, após conferir o código e confirmar que confia na origem, execute:

```powershell
irm https://scripts.malovisky.com.br | iex
```

> **Atenção:** este comando executa código obtido da internet. Utilize apenas em máquinas sob sua administração, com autorização e backups válidos. Algumas operações exigem PowerShell elevado (Executar como administrador).

Para inspecionar o código do menu antes de executar:

```powershell
(Invoke-WebRequest 'https://scripts.malovisky.com.br/menu.ps1' -UseBasicParsing).Content
```

## Funcionalidades — menu v1.3.0

| Opção | Ferramenta | O que faz |
|---|---|---|
| **1** | **AnyDesk** | Instalação, reinstalação, cópia/renomeação de configurações e diagnóstico. Ao concluir a instalação, solicita a abertura elevada e mostra o popup de confirmação. |
| **2** | **Firewall de fabricantes** | Localiza executáveis selecionados e permite simular, criar ou remover regras de bloqueio de entrada/saída. |
| **3** | **Otimização do Windows** | Rotinas de manutenção, otimização e reparação do Windows. |
| **4** | **Autodesk Deep Clean — NOVO** | Simula ou executa limpeza profunda de resíduos Autodesk, Autodesk Shared, arquivos de licença Autodesk no FLEXnet e chaves de registro selecionadas. |

### Novo: Autodesk Deep Clean

Adicionado em **v1.3.0**: `public/scripts/Malovisky_Autodesk_DeepClean.ps1`.

- **Modo 1 — SIMULAR (padrão):** identifica resíduos e produz relatório sem remover arquivos, parar serviços ou encerrar o Explorer.
- **Modo 2 — EXECUTAR:** após confirmação explícita, para serviços/processos Autodesk, encerra o Explorer da sessão, limpa alvos selecionados e restaura o Explorer ao final.
- **Modo 3 — EXECUTAR com FlexNet compartilhado:** operação de **alto risco**, exige confirmação adicional no menu; pode afetar softwares de outros fornecedores.
- Detecta produtos Autodesk ainda registrados como instalados e **interrompe a limpeza executiva** nesses casos: desinstale-os oficialmente primeiro.
- Exporta backups das chaves Autodesk que pretende remover, registra contagens e erros em log e exibe um resumo em popup ao final da execução.

**Atenção:** a remoção é destrutiva; pode eliminar preferências, configurações, arquivos ou materiais personalizados. O script não substitui o desinstalador oficial e não promete recuperar licenças ou corrigir todos os problemas de instalação. Revise a simulação e faça backup antes de executar.

## Changelog

### v1.3.0 — 12/11/2026

- Adicionada a **opção 4 — Autodesk Deep Clean** ao menu principal.
- Criado submenu de execução com simulação padrão, limpeza normal e modo opcional para FlexNet compartilhado.
- Incluída a checagem SHA-256 do novo módulo no build.
- Atualizados o README, a página informativa e a versão exibida no menu.

### v1.2 — versão anterior

- Menu Matrix com opções AnyDesk, Firewall e Otimização.
- Integração GitHub → Cloudflare Pages e conferência SHA-256 dos módulos publicados.

## Estrutura do projeto

```text
README.md
build.mjs
public/
  entry.txt
  menu.ps1
  _redirects
  _headers
  sobre/index.html
  scripts/
    Malovisky-IT-Tools.ps1
    Bloquear_Fabricantes_Firewall_Menu.ps1
    Otimizacao_windows.ps1
    Malovisky_Autodesk_DeepClean.ps1
```

## Publicação automática — Cloudflare Pages

O repositório `malovisky/malovisky-it-tools` está conectado ao Cloudflare Pages; cada alteração na branch `main` inicia um novo build e deploy, sujeito ao resultado da publicação.

| Configuração | Valor |
|---|---|
| Production branch | `main` |
| Framework preset | `None` |
| Build command | `node build.mjs` |
| Build output directory | `public` |
| Root directory | `/` |

Durante a compilação, `build.mjs` calcula o **SHA-256 dos quatro módulos** e o insere nos menus `entry.txt` e `menu.ps1`. O menu confere o hash do módulo baixado antes de iniciá-lo.

**Para incluir outras funções futuramente:** adicione o `.ps1` em `public/scripts/`, registre-o nos menus e na lista `modules` de `build.mjs`.

## Responsabilidade

Projeto destinado ao suporte técnico autorizado. **Use por sua conta e risco.** Avalie as consequências de cada rotina, mantenha backups e execute primeiro os modos de simulação sempre que disponíveis. O uso indevido pode interromper softwares, acesso remoto ou serviços.
