#!/usr/bin/env bash
set -euo pipefail
export AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-south-1}}"
export AWS_PAGER=''
STACK_NAME="${STACK_NAME:-stagelock-private}"
printf 'These are private-network review wallets. Never fund them on a public network or share their keys.\n'
aws ssm get-parameter --name "/$STACK_NAME/accounts" --with-decryption --query Parameter.Value --output text
