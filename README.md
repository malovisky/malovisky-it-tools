# MALOVISKY IT TOOLS
**Powered by Thomaz J** — menu PowerShell de manutencao Windows com estilo Matrix.

## Menu v1.2
1. `Malovisky-IT-Tools.ps1` — AnyDesk
2. `Bloquear_Fabricantes_Firewall_Menu.ps1` — Firewall
3. `Otimizacao_windows.ps1` — Otimizacao do Windows

**Aviso:** ferramentas publicas e potencialmente destrutivas. Use por sua conta e risco, em computadores autorizados, com backup. A operacao 1 pode encerrar acesso remoto, a 2 pode bloquear softwares e a 3 modifica o sistema.

## Estrutura
- `public/entry.txt`: script entregue pela URL raiz por meio de `public/_redirects`.
- `public/menu.ps1`: copia do menu, para leitura direta.
- `public/scripts/`: os tres modulos.
- `public/_headers`: tipo MIME e cabecalhos de seguranca.
- `public/sobre/index.html`: pagina explicativa.
- `build.mjs`: atualiza automaticamente os SHA256 antes de cada publicacao (Node.js sem dependencias).

## Repositorio GitHub
Este projeto e mantido no repositorio `malovisky/malovisky-it-tools`, branch `main`.

## Cloudflare Pages — Git conectado
Cloudflare > Workers & Pages > Create application > Pages > Connect to Git > GitHub > repo `malovisky-it-tools`.

| Campo | Valor |
|---|---|
| Production branch | `main` |
| Framework preset | `None` |
| Build command | `node build.mjs` |
| Build output directory | `public` |
| Root directory | `/` (pasta raiz do repo) |

A cada push no `main`, o Cloudflare executara o build, recalculara os hashes e publicara os arquivos.

Se ja criou um projeto via Direct Upload, o Cloudflare nao permite convertê-lo para Git integrado: crie um **novo** projeto Pages. Teste primeiro no `*.pages.dev`, depois retire o dominio personalizado do projeto antigo e associe no novo. Nao precisa apagar o projeto antigo antecipadamente.

## Edicoes futuras
1. Altere ou adicione seu `.ps1` em `public/scripts/`.
2. Se adicionar uma opcao nova, atualize `public/menu.ps1`, `public/entry.txt` e lista `scriptFiles` em `build.mjs`.
3. `git add .` / `git commit` / `git push`.
4. Cloudflare faz o deploy automaticamente.

Para editar somente os tres scripts existentes, **nao precisa** executar manualmente `Atualizar-Hashes.ps1`: `node build.mjs` atualiza os hashes durante o build.

## Execucao (somente apos configurar o dominio)
```powershell
irm https://scripts.malovisky.com.br | iex
```

Para conferir o codigo antes de executar:
```powershell
(Invoke-WebRequest https://scripts.malovisky.com.br -UseBasicParsing).Content
```

O codigo dos scripts publicados e acessivel publicamente mesmo com repositorio GitHub privado. Nao inclua credenciais nem tokens.

### Teste antes de trocar o dominio
A URL `*.pages.dev` serve o menu, mas os downloads de modulos usam o endereco fixo `https://scripts.malovisky.com.br` no script. Portanto, teste a resposta e os hashes no endereco de preview, e execute os modulos apenas depois de associar o dominio de producao.