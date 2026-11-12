#!/usr/bin/env bash
# MALOVISKY IT TOOLS - Powered by Thomaz J | Linux Edition 1.0
set -Eeuo pipefail
BASE='https://scripts.malovisky.com.br/linux'
ANYDESK_SCRIPT_SHA256='0000000000000000000000000000000000000000000000000000000000000000'
if [[ -t 1 ]]; then GREEN='\033[1;32m'; RESET='\033[0m'; else GREEN=''; RESET=''; fi
out() { printf '%b%s%b\n' "$GREEN" "$*" "$RESET"; }
read_choice() {
  local prompt="$1" chosen=''
  if [[ ! -r /dev/tty ]]; then out 'ERRO: terminal interativo indisponivel.' >&2; return 1; fi
  printf '%s' "$prompt" >/dev/tty
  IFS= read -r chosen </dev/tty || return 1
  REPLY="$chosen"
}
run_anydesk() {
  local opt="$1" tmp script got
  command -v curl >/dev/null 2>&1 || { out 'ERRO: instale curl para usar esta ferramenta.'; return 1; }
  command -v sha256sum >/dev/null 2>&1 || { out 'ERRO: sha256sum nao encontrado.'; return 1; }
  tmp="$(mktemp -d)" || return 1
  script="$tmp/anydesk-identity.sh"
  if ! curl --fail --silent --show-error --location --max-time 45 "$BASE/scripts/anydesk-identity.sh" -o "$script"; then
    rm -rf -- "$tmp"; out 'ERRO: falha no download do modulo.'; return 1
  fi
  got="$(sha256sum "$script" | awk '{print toupper($1)}')"
  if [[ "$got" != "$ANYDESK_SCRIPT_SHA256" ]]; then
    rm -rf -- "$tmp"; out 'ERRO: SHA256 invalido. Nenhum modulo foi executado.'; return 1
  fi
  out 'SHA256 verificado.'
  local rc=0
  if [[ "$opt" == '--reset' ]]; then
    if (( EUID == 0 )); then bash "$script" "$opt" || rc=$?; else sudo bash "$script" "$opt" || rc=$?; fi
  else
    bash "$script" "$opt" || rc=$?
  fi
  rm -rf -- "$tmp"
  return "$rc"
}
while true; do
  printf '\033[40m\033[2J\033[H' 2>/dev/null || true
  out '========================================================'
  out ' MALOVISKY IT TOOLS - Powered by Thomaz J'
  out ' LINUX EDITION v1.0 - ANYDESK / CLONAGEM'
  out '========================================================'
  out ' [1] Diagnosticar AnyDesk e consultar ID'
  out ' [2] Simular redefinicao profunda (sem alteracoes)'
  out ' [3] Redefinir ID AnyDesk com backup (IMPACTA ACESSO)'
  out ' [0] Sair'
  out '========================================================'
  out ' USE POR SUA CONTA E RISCO. BACKUP E ACESSO SSH RECOMENDADOS.'
  read_choice 'Escolha uma opcao: ' || exit 1
  case "$REPLY" in
    1) run_anydesk --diagnose || true ;;
    2) run_anydesk --simulate || true ;;
    3) run_anydesk --reset || true ;;
    0) out 'Encerrado.'; break ;;
    *) out 'Opcao invalida.' ;;
  esac
  read_choice 'Pressione ENTER para retornar ao menu...' || exit 1
done
