#!/usr/bin/env bash
# Start the public teamgram e2e compose on this runner only.
# SMS stays on the fixed local code. Nothing here calls api.tellomi.cn.
set -euo pipefail

artifact_dir="${ARTIFACT_DIR:-discover-sim-ui}"
if [[ "$artifact_dir" != /* ]]; then
  artifact_dir="$(pwd)/${artifact_dir}"
fi
mkdir -p "$artifact_dir"
pin="e2868f536cad6633931b210c8e88aa42ebe5f66c"

if ! docker info >/dev/null 2>&1; then
  printf '%s\n' "blocker: this Mac runner has no Docker" "local TestPhones stack was not started" "api.tellomi.cn was not contacted" | tee "${artifact_dir}/blocker.txt"
  exit 4
fi

export TELLOMI_SMS_PROVIDER=fixed
export TELLOMI_EMAIL_PROVIDER=log
export TELLOMI_ALIYUN_SMS_SIGN_NAME=
export TELLOMI_ALIYUN_SMS_TEMPLATE_CODE=
export TELLOMI_RESEND_API_KEY=
export TELLOMI_POSTAL_API_KEY=
export TELLOMI_POSTAL_BASE_URL=
export TELLOMI_ANNOUNCE=
export TELLOMI_DISCOVER=
export TELLOMI_DISCOVER_SIGNING_KEY=
export TELLOMI_DC_OPTIONS="1:127.0.0.1:10443,1:127.0.0.1:5222"
unset ALIBABA_CLOUD_ACCESS_KEY_ID ALIBABA_CLOUD_ACCESS_KEY_SECRET || true

if [[ "${TELLOMI_SMS_PROVIDER}" != "fixed" || "${TELLOMI_EMAIL_PROVIDER}" != "log" ]]; then
  echo "refusing to start: SMS or email provider is not the local fixed/log mode" | tee "${artifact_dir}/blocker.txt"
  exit 4
fi
{
  echo "sms_provider=${TELLOMI_SMS_PROVIDER}"
  echo "email_provider=${TELLOMI_EMAIL_PROVIDER}"
  echo "teamgram_pin=${pin}"
  echo "dc_options=${TELLOMI_DC_OPTIONS}"
} | tee "${artifact_dir}/stack.txt"

dest="${RUNNER_TEMP:-/tmp}/teamgram-server-${pin}"
if [[ ! -d "$dest/.git" ]]; then
  git clone --depth 1 https://github.com/tellomi/teamgram-server.git "$dest"
fi
got="$(git -C "$dest" rev-parse HEAD)"
if [[ "$got" != "$pin" ]]; then
  echo "teamgram checkout ${got} is not pin ${pin}; not starting it" | tee "${artifact_dir}/blocker.txt"
  exit 4
fi

cd "$dest"
docker compose \
  -f docker-compose-env.yaml \
  -f docker-compose.yaml \
  -f e2e/docker-compose.ci.yaml \
  up -d --build

ready=0
for _ in $(seq 1 120); do
  if docker compose \
    -f docker-compose-env.yaml \
    -f docker-compose.yaml \
    -f e2e/docker-compose.ci.yaml \
    exec -T teamgram bash -c 'echo >/dev/tcp/127.0.0.1/10443' >/dev/null 2>&1; then
    echo "gnetway is accepting connections inside the container" | tee -a "${artifact_dir}/stack.txt"
    ready=1
    break
  fi
  sleep 5
done
if [[ "$ready" != 1 ]]; then
  docker compose -f docker-compose-env.yaml -f docker-compose.yaml -f e2e/docker-compose.ci.yaml ps | tee "${artifact_dir}/stack-ps.txt"
  echo "local teamgram did not open 10443" | tee "${artifact_dir}/blocker.txt"
  exit 4
fi

python3 - <<'PY'
import socket
socket.create_connection(("127.0.0.1", 10443), 5).close()
print("host loopback 10443 is open")
PY
