#!/usr/bin/env bash
# ...existing code...
# Requisitos: aws-cli v2 e jq (brew install jq)
set -euo pipefail

# Configurações
MFA_SERIAL="arn:aws:iam::635328365471:mfa/platform-engineering"
ROLE_ARN="arn:aws:iam::635328365471:role/PSP-ControlPlane-Execution-0f8e6323e0"
ROLE_SESSION_NAME="kleber-session"
PROFILE_KLEBER="kleber"
PROFILE_PLATFORM="platform"
DURATION_SECONDS=3600

# Logger simples com timestamp
log() { printf '[%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"; }

# Ative debug com AWS_DEBUG=1 (vai habilitar set -x)
if [[ "${AWS_DEBUG:-0}" == "1" ]]; then
  log "Debug habilitado: ativando set -x"
  set -x
fi

on_error() {
  rc=$?
  last_cmd=${BASH_COMMAND:-unknown}
  log "ERRO: comando falhou (rc=$rc): ${last_cmd}"
  log "Verifique saída acima para detalhes."
  exit $rc
}
trap 'on_error' ERR

if ! command -v aws >/dev/null 2>&1; then
  log "aws CLI não encontrado. Instale com: brew install awscli"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log "jq não encontrado. Instale com: brew install jq"
  exit 1
fi

read -rp "Código MFA (6 dígitos): " MFA_CODE
if [[ ! $MFA_CODE =~ ^[0-9]{6}$ ]]; then
  log "Código MFA inválido: '$MFA_CODE'"
  exit 1
fi

log "Solicitando credenciais de sessão (get-session-token) usando o perfil '$PROFILE_KLEBER'..."
GET_SESSION_JSON=$(aws sts get-session-token \
  --serial-number "$MFA_SERIAL" \
  --token-code "$MFA_CODE" \
  --duration-seconds "$DURATION_SECONDS" \
  --profile "$PROFILE_KLEBER" 2>&1) || {
  log "Erro: 'aws sts get-session-token' retornou não-zero. Saída: $GET_SESSION_JSON"
  exit 1
}

if [[ -z "$GET_SESSION_JSON" ]]; then
  log "Falha ao obter session token: resposta vazia"
  exit 1
fi

# Validar JSON antes de extrair
if ! echo "$GET_SESSION_JSON" | jq -e . >/dev/null 2>&1; then
  log "Resposta inválida JSON de get-session-token:"
  log "$GET_SESSION_JSON"
  exit 1
fi

AWS_ACCESS_KEY_ID=$(echo "$GET_SESSION_JSON" | jq -r '.Credentials.AccessKeyId')
AWS_SECRET_ACCESS_KEY=$(echo "$GET_SESSION_JSON" | jq -r '.Credentials.SecretAccessKey')
AWS_SESSION_TOKEN=$(echo "$GET_SESSION_JSON" | jq -r '.Credentials.SessionToken')
SESSION_EXPIRATION=$(echo "$GET_SESSION_JSON" | jq -r '.Credentials.Expiration')

# Gravando as credenciais obtidas no perfil 'default' (sem --profile)
log "Gravando credenciais de sessão no perfil [default] (obtidas via $PROFILE_KLEBER) ..."
if ! aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID" 2>&1; then
  log "Falha ao gravar aws_access_key_id no perfil default"
  exit 1
fi
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set aws_session_token "$AWS_SESSION_TOKEN"

log "Perfil [default] atualizado. Expira em: $SESSION_EXPIRATION"

log "Assumindo role ($ROLE_ARN) usando o perfil [default]..."
ASSUME_JSON=$(aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name "$ROLE_SESSION_NAME" \
  --duration-seconds "$DURATION_SECONDS" 2>&1) || {
  log "Erro: 'aws sts assume-role' retornou não-zero. Saída: $ASSUME_JSON"
  exit 1
}

if [[ -z "$ASSUME_JSON" ]]; then
  log "Falha ao assumir role: resposta vazia"
  exit 1
fi

if ! echo "$ASSUME_JSON" | jq -e . >/dev/null 2>&1; then
  log "Resposta inválida JSON de assume-role:"
  log "$ASSUME_JSON"
  exit 1
fi

ASSUME_ACCESS_KEY_ID=$(echo "$ASSUME_JSON" | jq -r '.Credentials.AccessKeyId')
ASSUME_SECRET_ACCESS_KEY=$(echo "$ASSUME_JSON" | jq -r '.Credentials.SecretAccessKey')
ASSUME_SESSION_TOKEN=$(echo "$ASSUME_JSON" | jq -r '.Credentials.SessionToken')
ASSUME_EXPIRATION=$(echo "$ASSUME_JSON" | jq -r '.Credentials.Expiration')

log "Atualizando perfil [$PROFILE_PLATFORM]..."
aws configure set aws_access_key_id "$ASSUME_ACCESS_KEY_ID" --profile "$PROFILE_PLATFORM"
aws configure set aws_secret_access_key "$ASSUME_SECRET_ACCESS_KEY" --profile "$PROFILE_PLATFORM"
aws configure set aws_session_token "$ASSUME_SESSION_TOKEN" --profile "$PROFILE_PLATFORM"

log "Perfil [$PROFILE_PLATFORM] atualizado. Expira em: $ASSUME_EXPIRATION"
log "Concluído."
# ...existing code...