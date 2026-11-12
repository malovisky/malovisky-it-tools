# MALOVISKY IT TOOLS

**Powered by Thomaz J**  
**Versão Windows: v1.4.0 | Linux Edition: v1.0 — 12/11/2026**

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

## Funcionalidades — menu v1.4.1

| Opção | Ferramenta | O que faz |
|---|---|---|
| **1** | **AnyDesk** | Instalação, reinstalação, cópia/renomeação de configurações e diagnóstico. Ao concluir a instalação, solicita a abertura elevada e mostra o popup de confirmação. |
| **2** | **Firewall de fabricantes** | Localiza executáveis selecionados e permite simular, criar ou remover regras de bloqueio de entrada/saída. |
| **3** | **Otimização do Windows** | Rotinas de manutenção, otimização e reparação do Windows. |
| **4** | **Autodesk Deep Clean** | Simula ou executa limpeza profunda de resíduos Autodesk, Autodesk Shared, arquivos de licença Autodesk no FLEXnet e chaves de registro selecionadas. |
| **5** | **Gerenciador de HOSTS — NOVO** | Consulta o arquivo HOSTS, identifica entradas ativas, remove uma linha específica, redefine para o padrão do Windows e restaura backup. |

### Novo: Autodesk Deep Clean

Adicionado em **v1.3.0**: `public/scripts/Malovisky_Autodesk_DeepClean.ps1`.

- **Modo 1 — SIMULAR (padrão):** identifica resíduos e produz relatório sem remover arquivos, parar serviços ou encerrar o Explorer.
- **Modo 2 — EXECUTAR:** após confirmação explícita, para serviços/processos Autodesk, encerra o Explorer da sessão, limpa alvos selecionados e restaura o Explorer ao final.
- **Modo 3 — EXECUTAR com FlexNet compartilhado:** operação de **alto risco**, exige confirmação adicional no menu; pode afetar softwares de outros fornecedores.
- Detecta produtos Autodesk ainda registrados como instalados e **interrompe a limpeza executiva** nesses casos: desinstale-os oficialmente primeiro.
- Exporta backups das chaves Autodesk que pretende remover, registra contagens e erros em log e exibe um resumo em popup ao final da execução.

**Atenção:** a remoção é destrutiva; pode eliminar preferências, configurações, arquivos ou materiais personalizados. O script não substitui o desinstalador oficial e não promete recuperar licenças ou corrigir todos os problemas de instalação. Revise a simulação e faça backup antes de executar.

### Novo: Gerenciador de HOSTS (opção 5)

Adicionado em **v1.4.0**: `public/scripts/Malovisky_Hosts_Manager.ps1`.

- **Consultar:** exibe linhas numeradas, distinguindo comentários e entradas ativas.
- **Remover linha:** exclui somente a linha escolhida, após confirmação explícita e backup.
- **Redefinir:** cria `hosts.bkp` e substitui o conteúdo por um modelo padrão comentado do Windows com a marca `#REDEFINIDO COM MALOVISKY IT TOOLS`.
- **Restaurar:** repõe o arquivo salvo em `hosts.bkp`, preservando cópia do estado anterior à restauração.
- Backups `.bkp` já existentes são arquivados com data/hora, evitando perda de versões; operações de escrita exigem privilégios administrativos e solicitam limpeza de cache DNS.

**Atenção:** o HOSTS pode conter configurações essenciais para VPN, aplicações corporativas, desenvolvimento ou bloqueios locais. A redefinição apaga todas as entradas personalizadas do arquivo ativo. Examine as linhas e o backup antes de redefinir.

## Linux Edition v1.0 — NOVO: AnyDesk em Ubuntu clonado

Adicionado um menu Bash independente para computadores Ubuntu que possuem AnyDesk instalado como serviço systemd. O menu Windows continua na versão v1.4.0.

### Execução no terminal Ubuntu

```bash
curl -fsSL https://scripts.malovisky.com.br/linux/menu.sh -o /tmp/malovisky-linux.sh
less /tmp/malovisky-linux.sh
bash /tmp/malovisky-linux.sh
```

Os módulos Linux são baixados e validados por SHA-256. O menu disponibiliza:

- **1 — Diagnóstico:** exibe versão, serviço, ID e diretórios de configuração do AnyDesk, sem modificar nada.
- **2 — Simulação:** utiliza `sudo` para localizar também configurações de todos os usuários e mostra quais diretórios seriam transferidos ao backup, sem parar serviços nem alterar arquivos.
- **3 — Redefinição profunda de ID:** exige sudo e confirmação `REDEFINIR-ID`, encerra o AnyDesk, transfere as pastas de configuração para backup e reinicia o serviço para gerar uma nova identidade.

**Backup restrito:** `/var/backups/malovisky-it-tools/anydesk/`, por máquina e data, incluindo manifesto dos caminhos originais. Contém informações sensíveis; não compartilhe o backup publicamente.

**Escopo:** somente as pastas do AnyDesk: `/etc/anydesk`, `/etc/anydesk_ad_*`, `~/.anydesk` e `~/.anydesk_ad_*` dos usuários locais. Não altera `/etc/machine-id`, hostname, SSH nem dados de outros aplicativos. Não desinstala o pacote AnyDesk.

**Atenção:** o reset encerra a conexão AnyDesk ativa, pode mudar ID e alias e exigir reconfiguração de acesso não supervisionado e licença. Use SSH ou console físico e confira o novo ID. O resultado depende do serviço estar funcional e da comunicação com a infraestrutura AnyDesk; se o ID não puder ser consultado, a rotina informa que a validação ficou pendente.

**Imagem-mestre:** o AnyDesk orienta a não iniciar o aplicativo antes de capturar a imagem, ou remover as configurações de identidade antes da clonagem. Ver: https://support.anydesk.com/docs/back-up-anydesk-id-and-settings
## Changelog

### v1.4.1 — 12/11/2026

- Corrigida a gravacao e restauracao do HOSTS em ambientes Windows PowerShell 5.1 nos quais `File.Replace` falhava com erro de formato de caminho.
- Preservados os backups `hosts.bkp` e as verificacoes de integridade posteriores a escrita e restauracao.
- Interface Matrix e registro de SHA-256 no build mantidos.

### Linux Edition v1.0 — 12/11/2026

- Lançado menu Bash para Ubuntu, com diagnóstico, simulação e redefinição de ID AnyDesk para discos clonados.
- Backup privado das configurações, confirmação obrigatória e validação SHA-256.

### v1.4.0 — 12/11/2026

- Criada a **opção 5 — Gerenciador de HOSTS** no menu principal Matrix.
- Incluídos consulta, remoção de linha, redefinição com `hosts.bkp` e restauração segura do backup.
- Módulo registrado no build com conferência de integridade SHA-256.
- Atualizados README, menu e página informativa.

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
    Malovisky_Hosts_Manager.ps1
  linux/
    menu.sh
    scripts/anydesk-identity.sh
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

Durante a compilação, `build.mjs` calcula o **SHA-256 dos cinco módulos Windows** e insere os valores em `entry.txt` e `menu.ps1`. Também verifica o módulo Linux e insere seu SHA-256 em `linux/menu.sh`, para validação antes da execução.

**Para incluir outras funções futuramente:** adicione o `.ps1` em `public/scripts/`, registre-o nos menus e na lista `modules` de `build.mjs`.

## Responsabilidade

Projeto destinado ao suporte técnico autorizado. **Use por sua conta e risco.** Avalie as consequências de cada rotina, mantenha backups e execute primeiro os modos de simulação sempre que disponíveis. O uso indevido pode interromper softwares, acesso remoto ou serviços.
