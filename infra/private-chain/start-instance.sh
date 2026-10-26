#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${AWS_REGION:?}"
: "${BOOTSTRAP_BUCKET:?}"
: "${ACCOUNTS_PARAMETER:?}"
: "${ORIGIN_PARAMETER:?}"
install -d -m 700 /opt/stagelock/secrets
install -d -m 755 /opt/stagelock/app
install -d -m 700 /opt/stagelock/data
aws ssm get-parameter --region "$AWS_REGION" --name "$ACCOUNTS_PARAMETER" --with-decryption --query Parameter.Value --output text > /opt/stagelock/secrets/accounts.json
aws ssm get-parameter --region "$AWS_REGION" --name "$ORIGIN_PARAMETER" --with-decryption --query Parameter.Value --output text > /opt/stagelock/secrets/origin-token
aws s3 cp "s3://$BOOTSTRAP_BUCKET/private-chain/runtime.tar.gz" /opt/stagelock/runtime.tar.gz --region "$AWS_REGION"
tar -xzf /opt/stagelock/runtime.tar.gz -C /opt/stagelock/app
chown -R 1000:1000 /opt/stagelock/data /opt/stagelock/secrets
for attempt in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 5; done
docker info >/dev/null
cd /opt/stagelock/app
docker build -f infra/private-chain/Dockerfile -t stagelock-chain:1 .
if docker inspect stagelock-chain >/dev/null 2>&1; then docker stop -t 60 stagelock-chain; docker rm stagelock-chain; fi
docker run -d --name stagelock-chain --restart unless-stopped --stop-timeout 60 --read-only --tmpfs /tmp:size=128m --cap-drop ALL --security-opt no-new-privileges --memory 1500m --cpus 1.5 -p 8080:8080 -v /opt/stagelock/data:/data -v /opt/stagelock/secrets:/run/stagelock:ro stagelock-chain:1
printf 'Private-chain service started.\n'
