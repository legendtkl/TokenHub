#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/.env"
DOCKER_BIN="${DOCKER_BIN:-docker}"
CHECK_ONLY=false

usage() {
  cat <<'EOF'
Usage: ./deploy/install.sh [--env-file PATH] [--check-only]

Options:
  --env-file PATH  Use a Compose environment file other than deploy/.env.
  --check-only     Validate the deployment configuration without starting containers.
  -h, --help       Show this help message.
EOF
}

log() {
  printf '[TokenHub] %s\n' "$*"
}

error() {
  printf '[TokenHub] ERROR: %s\n' "$*" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      if [ "$#" -lt 2 ]; then
        error "--env-file requires a path"
        usage >&2
        exit 2
      fi
      ENV_FILE="$2"
      shift 2
      ;;
    --check-only)
      CHECK_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "unknown option: $1"
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v "$DOCKER_BIN" >/dev/null 2>&1; then
  error "Docker is not installed or is not available on PATH"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  error "environment file not found: $ENV_FILE"
  error "create it with: cp deploy/.env.example deploy/.env"
  exit 1
fi

compose=("$DOCKER_BIN" compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

if ! "${compose[@]}" version >/dev/null; then
  error "Docker Compose is not available"
  exit 1
fi

if ! "${compose[@]}" config --quiet; then
  error "Docker Compose could not parse $ENV_FILE"
  exit 1
fi

compose_config_json="$("${compose[@]}" config --format json)" || {
  error "Docker Compose could not render the deployment configuration"
  exit 1
}

decode_json_codepoint() {
  local codepoint="$1"
  local escaped

  if [ "$codepoint" -eq 0 ]; then
    json_decode_error="NUL is not valid in an environment variable"
    return 1
  elif [ "$codepoint" -le 127 ]; then
    printf -v escaped '\\%03o' "$codepoint"
  elif [ "$codepoint" -le 2047 ]; then
    printf -v escaped '\\%03o\\%03o' \
      "$((192 | codepoint >> 6))" \
      "$((128 | codepoint & 63))"
  elif [ "$codepoint" -le 65535 ]; then
    printf -v escaped '\\%03o\\%03o\\%03o' \
      "$((224 | codepoint >> 12))" \
      "$((128 | codepoint >> 6 & 63))" \
      "$((128 | codepoint & 63))"
  elif [ "$codepoint" -le 1114111 ]; then
    printf -v escaped '\\%03o\\%03o\\%03o\\%03o' \
      "$((240 | codepoint >> 18))" \
      "$((128 | codepoint >> 12 & 63))" \
      "$((128 | codepoint >> 6 & 63))" \
      "$((128 | codepoint & 63))"
  else
    json_decode_error="Unicode code point is out of range"
    return 1
  fi

  printf -v decoded_json_character '%b' "$escaped"
}

decode_json_string() {
  local LC_ALL=C
  local input="$1"
  local index=0
  local length="${#input}"
  local character
  local escape
  local hex
  local low_hex
  local codepoint
  local low_codepoint
  decoded_json_value=""
  json_decode_error=""

  while [ "$index" -lt "$length" ]; do
    character="${input:$index:1}"
    if [ "$character" != "\\" ]; then
      decoded_json_value="${decoded_json_value}${character}"
      index=$((index + 1))
      continue
    fi

    index=$((index + 1))
    if [ "$index" -ge "$length" ]; then
      json_decode_error="trailing backslash"
      return 1
    fi
    escape="${input:$index:1}"
    case "$escape" in
      '"') decoded_json_value="${decoded_json_value}\"" ;;
      '\') decoded_json_value="${decoded_json_value}\\" ;;
      '/') decoded_json_value="${decoded_json_value}/" ;;
      b) decoded_json_value="${decoded_json_value}"$'\b' ;;
      f) decoded_json_value="${decoded_json_value}"$'\f' ;;
      n) decoded_json_value="${decoded_json_value}"$'\n' ;;
      r) decoded_json_value="${decoded_json_value}"$'\r' ;;
      t) decoded_json_value="${decoded_json_value}"$'\t' ;;
      u)
        if [ $((index + 4)) -ge "$length" ]; then
          json_decode_error="incomplete Unicode escape"
          return 1
        fi
        hex="${input:$((index + 1)):4}"
        if [[ ! "$hex" =~ ^[0-9A-Fa-f]{4}$ ]]; then
          json_decode_error="invalid Unicode escape"
          return 1
        fi
        codepoint=$((16#$hex))
        index=$((index + 4))

        if [ "$codepoint" -ge 55296 ] && [ "$codepoint" -le 56319 ]; then
          if [ $((index + 6)) -ge "$length" ] ||
            [ "${input:$((index + 1)):2}" != '\u' ]; then
            json_decode_error="high surrogate is not followed by a low surrogate"
            return 1
          fi
          low_hex="${input:$((index + 3)):4}"
          if [[ ! "$low_hex" =~ ^[0-9A-Fa-f]{4}$ ]]; then
            json_decode_error="invalid low surrogate"
            return 1
          fi
          low_codepoint=$((16#$low_hex))
          if [ "$low_codepoint" -lt 56320 ] || [ "$low_codepoint" -gt 57343 ]; then
            json_decode_error="invalid low surrogate"
            return 1
          fi
          codepoint=$((65536 + (codepoint - 55296) * 1024 + low_codepoint - 56320))
          index=$((index + 6))
        elif [ "$codepoint" -ge 56320 ] && [ "$codepoint" -le 57343 ]; then
          json_decode_error="unexpected low surrogate"
          return 1
        fi

        if ! decode_json_codepoint "$codepoint"; then
          return 1
        fi
        decoded_json_value="${decoded_json_value}${decoded_json_character}"
        ;;
      *)
        json_decode_error="invalid escape sequence"
        return 1
        ;;
    esac
    index=$((index + 1))
  done
}

decode_environment_line() {
  local line="$1"
  local key="$2"
  local json_value="${line#*:}"
  local json_length

  while [ "${json_value# }" != "$json_value" ]; do
    json_value="${json_value# }"
  done
  json_value="${json_value%,}"
  json_length="${#json_value}"
  if [ "$json_length" -lt 2 ] ||
    [ "${json_value:0:1}" != '"' ] ||
    [ "${json_value:$((json_length - 1)):1}" != '"' ]; then
    error "Docker Compose rendered an invalid JSON string for $key"
    return 1
  fi
  json_value="${json_value:1:$((json_length - 2))}"
  if ! decode_json_string "$json_value"; then
    error "Docker Compose rendered an invalid JSON string for $key: $json_decode_error"
    return 1
  fi
}

tokenhub_environment=""
admin_token=""
bootstrap_admin_password=""
secret_key=""
tokenhub_environment_found=false
admin_token_found=false
bootstrap_admin_password_found=false
secret_key_found=false

while IFS= read -r line; do
  json_line="$line"
  while :; do
    case "$json_line" in
      ' '*) json_line="${json_line# }" ;;
      $'\t'*) json_line="${json_line#$'\t'}" ;;
      *) break ;;
    esac
  done
  case "$json_line" in
    '"TOKENHUB_ENV":'*)
      decode_environment_line "$json_line" "TOKENHUB_ENV" || exit 1
      tokenhub_environment="$decoded_json_value"
      tokenhub_environment_found=true
      ;;
    '"TOKENHUB_ADMIN_TOKEN":'*)
      decode_environment_line "$json_line" "TOKENHUB_ADMIN_TOKEN" || exit 1
      admin_token="$decoded_json_value"
      admin_token_found=true
      ;;
    '"TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD":'*)
      decode_environment_line "$json_line" "TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD" || exit 1
      bootstrap_admin_password="$decoded_json_value"
      bootstrap_admin_password_found=true
      ;;
    '"TOKENHUB_SECRET_KEY":'*)
      decode_environment_line "$json_line" "TOKENHUB_SECRET_KEY" || exit 1
      secret_key="$decoded_json_value"
      secret_key_found=true
      ;;
  esac
done <<<"$compose_config_json"
unset compose_config_json decoded_json_value decoded_json_character json_decode_error json_line

if [ "$tokenhub_environment_found" = false ] ||
  [ "$admin_token_found" = false ] ||
  [ "$bootstrap_admin_password_found" = false ] ||
  [ "$secret_key_found" = false ]; then
  error "Docker Compose did not render all required TokenHub credential variables"
  exit 1
fi

trim_whitespace() {
  # Keep this list aligned with Go's strings.TrimSpace (Unicode White_Space).
  # LC_ALL=C makes every pattern operate on the explicit UTF-8 byte sequences.
  local LC_ALL=C
  local value="$1"
  local whitespace
  local matched
  local whitespace_characters=(
    ' '
    $'\t'
    $'\n'
    $'\v'
    $'\f'
    $'\r'
    $'\302\205'
    $'\302\240'
    $'\341\232\200'
    $'\342\200\200'
    $'\342\200\201'
    $'\342\200\202'
    $'\342\200\203'
    $'\342\200\204'
    $'\342\200\205'
    $'\342\200\206'
    $'\342\200\207'
    $'\342\200\210'
    $'\342\200\211'
    $'\342\200\212'
    $'\342\200\250'
    $'\342\200\251'
    $'\342\200\257'
    $'\342\201\237'
    $'\343\200\200'
  )

  while [ -n "$value" ]; do
    matched=false
    for whitespace in "${whitespace_characters[@]}"; do
      case "$value" in
        "$whitespace"*)
          value="${value#"$whitespace"}"
          matched=true
          break
          ;;
      esac
    done
    if [ "$matched" = false ]; then
      break
    fi
  done

  while [ -n "$value" ]; do
    matched=false
    for whitespace in "${whitespace_characters[@]}"; do
      case "$value" in
        *"$whitespace")
          value="${value%"$whitespace"}"
          matched=true
          break
          ;;
      esac
    done
    if [ "$matched" = false ]; then
      break
    fi
  done

  printf '%s' "$value"
}

byte_length() {
  local LC_ALL=C
  local value="$1"
  printf '%d' "${#value}"
}

validation_errors=()
environment="$(trim_whitespace "$tokenhub_environment")"
environment="$(printf '%s' "$environment" | tr '[:upper:]' '[:lower:]')"

if [ -z "$environment" ]; then
  validation_errors+=("TOKENHUB_ENV must not be empty")
elif [[ "$environment" != "dev" && "$environment" != "development" && "$environment" != "local" && "$environment" != "test" ]]; then
  validate_secret() {
    local name="$1"
    local value="$2"
    local minimum_length="$3"
    shift 3
    value="$(trim_whitespace "$value")"

    local blocked
    for blocked in "$@"; do
      if [ "$value" = "$blocked" ]; then
        validation_errors+=("$name must not use a default placeholder value")
        return
      fi
    done

    if [ "$(byte_length "$value")" -lt "$minimum_length" ]; then
      validation_errors+=("$name must be at least $minimum_length bytes after trimming whitespace")
      return
    fi
  }

  validate_secret "TOKENHUB_ADMIN_TOKEN" "$admin_token" 32 \
    "dev_admin_token" "change-me-tokenhub-admin-token"
  validate_secret "TOKENHUB_SECRET_KEY" "$secret_key" 32 \
    "dev_tokenhub_secret_key" "change-me-tokenhub-secret-key"
  validate_secret "TOKENHUB_BOOTSTRAP_ADMIN_PASSWORD" "$bootstrap_admin_password" 12 \
    "admin123456" "change-me-tokenhub-admin-password"
fi

unset admin_token bootstrap_admin_password secret_key

if [ "${#validation_errors[@]}" -gt 0 ]; then
  error "deployment configuration is unsafe for $environment:"
  for validation_error in "${validation_errors[@]}"; do
    printf '  - %s\n' "$validation_error" >&2
  done
  error "update $ENV_FILE and run this command again"
  exit 1
fi

log "deployment configuration is valid for $environment"

if [ "$CHECK_ONLY" = true ]; then
  exit 0
fi

log "building and starting TokenHub"
compose_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
backend_container_id_before="$("${compose[@]}" ps -a -q tokenhub-backend 2>/dev/null || true)"
backend_started_at_before=""
if [ -n "$backend_container_id_before" ]; then
  backend_started_at_before="$("$DOCKER_BIN" inspect --format '{{.State.StartedAt}}' "$backend_container_id_before" 2>/dev/null || true)"
fi

if "${compose[@]}" up -d --build; then
  log "TokenHub started successfully"
  "${compose[@]}" ps
else
  status=$?
  error "Docker Compose failed to start TokenHub (exit status $status)"

  backend_container_id_after="$("${compose[@]}" ps -a -q tokenhub-backend 2>/dev/null || true)"
  backend_state=""
  backend_health=""
  backend_started_at_after=""
  if [ -n "$backend_container_id_after" ]; then
    backend_inspect="$("$DOCKER_BIN" inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}|{{.State.StartedAt}}' "$backend_container_id_after" 2>/dev/null || true)"
    IFS='|' read -r backend_state backend_health backend_started_at_after <<<"$backend_inspect"
    unset backend_inspect
  fi

  backend_changed=false
  if [ -n "$backend_container_id_after" ]; then
    if [ "$backend_container_id_after" != "$backend_container_id_before" ]; then
      backend_changed=true
    elif [ -n "$backend_started_at_before" ] &&
      [ -n "$backend_started_at_after" ] &&
      [ "$backend_started_at_after" != "$backend_started_at_before" ]; then
      backend_changed=true
    fi
  fi

  backend_failed=false
  case "$backend_state" in
    exited|restarting|dead) backend_failed=true ;;
  esac
  if [ "$backend_health" = "unhealthy" ]; then
    backend_failed=true
  fi

  if [ "$backend_changed" = true ] && [ "$backend_failed" = true ]; then
    error "tokenhub-backend logs from this startup attempt:"
    backend_logs_since="${backend_started_at_after:-$compose_started_at}"
    "${compose[@]}" logs --no-color --tail=100 --since "$backend_logs_since" tokenhub-backend >&2 || \
      error "unable to read tokenhub-backend logs"
  else
    error "tokenhub-backend did not both change and enter a failed state during this startup attempt; its logs were not included"
  fi
  exit "$status"
fi
