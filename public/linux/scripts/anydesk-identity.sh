#!/usr/bin/env bash
# MALOVISKY IT TOOLS - AnyDesk Linux Identity Reset
# Powered by Thomaz J | Linux Edition 1.0
set -Eeuo pipefail
umask 077

mode="${1:---diagnose}"
case "$mode" in --diagnose|--simulate|--reset) ;; *) echo 'Uso: anydesk-identity.sh --diagnose|--simulate|--reset' >&2; exit 2;; esac

if [[ -t 1 ]]; then
  GREEN='\033[1;32m'; DIM='\033[0;32m'; RESET='\033[0m'
else
  GREEN=''; DIM=''; RESET=''
fi
info() { printf '%b%s%b\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%bAVISO: %s%b\n' "$DIM" "$*" "$RESET" >&2; }
fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

# AnyDesk GUI nao deve ser iniciado como root; a CLI abaixo so consulta o ID.
query_id() {
  command -v anydesk >/dev/null 2>&1 || return 0
  local u="${SUDO_USER:-}"
  if (( EUID == 0 )) && [[ -n "$u" && "$u" != root ]] && command -v runuser >/dev/null 2>&1; then
    timeout 8s runuser -u "$u" -- anydesk --get-id 2>/dev/null | head -n 1 || true
  else
    timeout 8s anydesk --get-id 2>/dev/null | head -n 1 || true
  fi
}

# Somente os locais que AnyDesk usa para salvar identidade/configuracoes.
declare -a TARGETS=()
declare -A SEEN=()
add_target() {
  local p="$1"
  [[ -d "$p" && ! -L "$p" ]] || return 0
  [[ -n "${SEEN[$p]:-}" ]] && return 0
  SEEN[$p]=1
  TARGETS+=("$p")
}
collect_targets() {
  shopt -s nullglob
  local p home
  for p in /etc/anydesk /etc/anydesk_ad_*; do add_target "$p"; done
  local -a HOMES=(/root /home/*)
  if command -v getent >/dev/null 2>&1; then
    while IFS=: read -r _ _ uid _ _ home _; do
      if [[ "$uid" =~ ^[0-9]+$ ]] && (( uid >= 1000 )) && [[ "$home" = /* ]]; then
        HOMES+=("$home")
      fi
    done < <(getent passwd)
  fi
  for home in "${HOMES[@]}"; do
    [[ -d "$home" && ! -L "$home" ]] || continue
    for p in "$home"/.anydesk "$home"/.anydesk_ad_*; do add_target "$p"; done
  done
  shopt -u nullglob
}

info '============================================================'
info ' MALOVISKY IT TOOLS - Powered by Thomaz J'
info ' ANYDESK LINUX - REDEFINICAO DE ID DE CLONES'
info '============================================================'
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  info "Sistema: ${PRETTY_NAME:-Linux}"
fi
info "Host: $(hostname)"
if command -v anydesk >/dev/null 2>&1; then
  info "Versao: $(timeout 8s anydesk --version 2>/dev/null | head -n 1 || true)"
else
  warn 'Executavel anydesk nao encontrado no PATH.'
fi
if command -v systemctl >/dev/null 2>&1; then
  info "Servico: $(systemctl is-active anydesk.service 2>/dev/null || true)"
fi
old_id="$(query_id | tr -d '\r' | tr -d '\n')"
info "ID atual: ${old_id:-nao identificado pela CLI}"
collect_targets
info "Pastas de configuracao encontradas: ${#TARGETS[@]}"
for path in "${TARGETS[@]}"; do info "  $path"; done

if [[ "$mode" == --diagnose ]]; then
  info 'Diagnostico concluido. Nenhuma alteracao realizada.'
  exit 0
fi
if [[ "$mode" == --simulate ]]; then
  info 'SIMULACAO: as pastas acima seriam movidas para backup privado.'
  info 'Nenhum servico foi parado e nenhum arquivo foi alterado.'
  exit 0
fi

(( EUID == 0 )) || fail 'Execute a redefinicao com sudo (root).'
command -v systemctl >/dev/null 2>&1 || fail 'systemctl indisponivel.'
command -v anydesk >/dev/null 2>&1 || fail 'AnyDesk nao instalado. Instale pelo pacote oficial antes de redefinir.'
if ! systemctl cat anydesk.service >/dev/null 2>&1; then
  fail 'Servico anydesk.service nao encontrado. Esta rotina exige a instalacao com servico.'
fi
(( ${#TARGETS[@]} > 0 )) || fail 'Nenhuma pasta de configuracao encontrada. Nada a redefinir.'

warn 'ESSA OPERACAO ENCERRA TODAS AS CONEXOES ANYDESK DESTA MAQUINA.'
warn 'O ID, o alias, a senha de acesso nao supervisionado, licenca e preferencias podem mudar.'
warn 'Se esta conectado pelo proprio AnyDesk, use SSH ou console local primeiro.'
warn 'Nao muda /etc/machine-id, hostname, SSH nem arquivos de outros programas.'
if [[ ! -r /dev/tty ]]; then fail 'Terminal interativo necessario para confirmar.'; fi
printf 'Digite REDEFINIR-ID para continuar: ' >/dev/tty
IFS= read -r confirm </dev/tty || fail 'Confirmacao nao recebida.'
[[ "$confirm" == REDEFINIR-ID ]] || { info 'Operacao cancelada.'; exit 0; }

backup_base='/var/backups/malovisky-it-tools/anydesk'
backup="$backup_base/$(date +%Y%m%d_%H%M%S)_$$_$(hostname -s | tr -cd 'A-Za-z0-9_.-')"
install -d -m 700 "$backup" || fail 'Nao foi possivel criar a pasta de backup.'
manifest="$backup/manifest.tsv"
printf 'origem\tdestino\n' > "$manifest"
chmod 600 "$manifest"
info "Backup privado: $backup"

# Restaura o servico em qualquer saida anormal apos a parada.
restart_needed=0
restore_service() {
  if (( restart_needed == 1 )); then
    systemctl start anydesk.service >/dev/null 2>&1 || warn 'Falha ao religar servico AnyDesk; verifique systemctl status anydesk.'
  fi
}
trap restore_service EXIT

info 'Encerrando o servico AnyDesk...'
systemctl stop anydesk.service || fail 'Nao foi possivel parar o servico.'
restart_needed=1
pkill -x anydesk 2>/dev/null || true
sleep 2
if pgrep -x anydesk >/dev/null 2>&1; then
  fail 'Ainda existem processos AnyDesk ativos; cancelado antes de mover configuracoes.'
fi

moved=0
for path in "${TARGETS[@]}"; do
  [[ -d "$path" && ! -L "$path" ]] || continue
  destination="$backup/files$path"
  mkdir -p -- "$(dirname -- "$destination")" || fail 'Falha ao preparar subpasta de backup.'
  if mv -- "$path" "$destination"; then
    printf '%s\t%s\n' "$path" "$destination" >> "$manifest"
    moved=$((moved + 1))
    info "Backup concluido: $path"
  else
    fail "Falha ao mover $path. Verifique o backup e restaure manualmente, se necessario."
  fi
done

info "Pastas de identidade retiradas da instalacao ativa: $moved"
info 'Iniciando servico AnyDesk para gerar nova identidade...'
systemctl start anydesk.service || fail 'Falha ao iniciar o servico AnyDesk.'
restart_needed=0

new_id=''
for _ in {1..8}; do
  sleep 2
  new_id="$(query_id | tr -d '\r' | tr -d '\n')"
  [[ -n "$new_id" ]] && break
done
info '==================== RESUMO ===================='
info "Backup: $backup"
info "Pastas movidas: $moved"
info "Servico: $(systemctl is-active anydesk.service 2>/dev/null || true)"
info "ID anterior: ${old_id:-indisponivel}"
info "ID atual: ${new_id:-nao disponivel; conferir na interface AnyDesk}"
if [[ -n "$old_id" && -n "$new_id" && "$old_id" == "$new_id" ]]; then
  warn 'O ID retornado continua igual ao antigo. A redefinicao NAO foi confirmada.'
  exit 1
fi
if [[ -n "$new_id" && ( -z "$old_id" || "$old_id" != "$new_id" ) ]]; then
  info 'Nova identidade observada pela CLI. Confira no painel do AnyDesk.'
else
  warn 'Nova identidade ainda nao confirmada. Verifique conectividade, Xorg e o ID no AnyDesk.'
fi
warn 'Reconfigure acesso nao supervisionado e quaisquer politicas locais antes de usar remotamente.'
