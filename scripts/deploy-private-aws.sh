#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-south-1}}"
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_PAGER=''
STACK_NAME="${STACK_NAME:-stagelock-private}"
EXPECTED_AWS_ACCOUNT="${EXPECTED_AWS_ACCOUNT:-014679146311}"
[[ "$STACK_NAME" =~ ^[a-zA-Z][a-zA-Z0-9-]{0,100}$ ]] || { echo 'Invalid stack name'; exit 1; }
for tool in aws node npm python3 tar curl; do command -v "$tool" >/dev/null; done
node -e 'if(Number(process.versions.node.split(".")[0])<22)throw Error("Node.js 22 or newer is required")'
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
[[ "$ACCOUNT_ID" == "$EXPECTED_AWS_ACCOUNT" ]] || { echo 'AWS account differs from EXPECTED_AWS_ACCOUNT; stopping'; exit 1; }
printf 'Deploying StageLock to AWS account %s in %s. Stack: %s\n' "$ACCOUNT_ID" "$AWS_REGION" "$STACK_NAME"
printf 'Resources: t3.small EC2, 20 GB encrypted disk, public IPv4, private S3, CloudFront HTTPS. AWS usage is billed.\n'
npm install --no-audit --no-fund
npm test
PRIVATE_DIR="$(pwd)/.private-aws/$STACK_NAME"
mkdir -p "$PRIVATE_DIR"
ACCOUNTS_PARAMETER="/$STACK_NAME/accounts"
ORIGIN_PARAMETER="/$STACK_NAME/origin-token"
ensure_parameter() {
  local parameter="$1" target="$2" kind="$3" found
  found="$(aws ssm describe-parameters --parameter-filters "Key=Name,Option=Equals,Values=$parameter" --query 'Parameters[0].Name' --output text)"
  if [[ "$found" == "$parameter" ]]; then
    aws ssm get-parameter --name "$parameter" --with-decryption --query Parameter.Value --output text > "$target"
  else
    node --input-type=module - "$kind" "$target" <<'JS'
import fs from 'node:fs';import {randomBytes} from 'node:crypto';import {Wallet} from 'ethers';
const [kind,path]=process.argv.slice(2);
const value=kind==='wallets'?JSON.stringify(['Client','Contractor','Arbitrator','Reserve'].map(role=>{const w=Wallet.createRandom();return {role,address:w.address,privateKey:w.privateKey};})):randomBytes(32).toString('hex');
fs.writeFileSync(path,value,{mode:0o600});
JS
    aws ssm put-parameter --name "$parameter" --type SecureString --value "file://$target" >/dev/null
  fi
  chmod 600 "$target"
}
ensure_parameter "$ACCOUNTS_PARAMETER" "$PRIVATE_DIR/accounts.json" wallets
ensure_parameter "$ORIGIN_PARAMETER" "$PRIVATE_DIR/origin-token" token
PREFIX_LIST="$(aws ec2 describe-managed-prefix-lists --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing --query 'PrefixLists[0].PrefixListId' --output text)"
[[ "$PREFIX_LIST" == pl-* ]] || { echo 'CloudFront origin prefix list unavailable in selected region'; exit 1; }
python3 - "$PRIVATE_DIR" "$PREFIX_LIST" "$ACCOUNTS_PARAMETER" "$ORIGIN_PARAMETER" <<'PY'
import json,sys,pathlib
p=pathlib.Path(sys.argv[1]);token=(p/'origin-token').read_text().strip()
params=[{'ParameterKey':k,'ParameterValue':v} for k,v in [('CloudFrontPrefixList',sys.argv[2]),('AccountsParameter',sys.argv[3]),('OriginParameter',sys.argv[4]),('OriginToken',token)]]
(p/'parameters.json').write_text(json.dumps(params))
PY
aws cloudformation validate-template --template-body file://infra/private-hosting.json >/dev/null
aws cloudformation deploy --stack-name "$STACK_NAME" --template-file infra/private-hosting.json --capabilities CAPABILITY_IAM --parameter-overrides "file://$PRIVATE_DIR/parameters.json" --no-fail-on-empty-changeset
output() { aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }
BUCKET_NAME="$(output BucketName)"
INSTANCE_ID="$(output InstanceId)"
SITE_URL="$(output SiteURL)"
RPC_URL="$(output RpcURL)"
DISTRIBUTION_ID="$(output DistributionId)"
tar -czf "$PRIVATE_DIR/runtime.tar.gz" contracts/StageLock.sol scripts/compile.mjs infra/private-chain/
aws s3 cp "$PRIVATE_DIR/runtime.tar.gz" "s3://$BUCKET_NAME/private-chain/runtime.tar.gz" --only-show-errors
aws s3 cp infra/private-chain/start-instance.sh "s3://$BUCKET_NAME/private-chain/start-instance.sh" --only-show-errors
printf 'Waiting for the instance management agent…\n'
SSM_READY=''
for attempt in $(seq 1 90); do
  ping="$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$INSTANCE_ID" --query 'InstanceInformationList[0].PingStatus' --output text)"
  if [[ "$ping" == Online ]]; then SSM_READY=yes; break; fi
  sleep 10
done
[[ "$SSM_READY" == yes ]] || { echo 'Instance management agent did not become ready. Check EC2 instance status.'; exit 1; }
python3 - "$PRIVATE_DIR" "$AWS_REGION" "$BUCKET_NAME" "$ACCOUNTS_PARAMETER" "$ORIGIN_PARAMETER" <<'PY'
import json,sys,shlex,pathlib
p=pathlib.Path(sys.argv[1]);region,bucket,accounts,origin=sys.argv[2:]
commands=['set -eu','aws s3 cp '+shlex.quote('s3://'+bucket+'/private-chain/start-instance.sh')+' /tmp/stagelock-start.sh --region '+shlex.quote(region),
 'AWS_REGION='+shlex.quote(region)+' BOOTSTRAP_BUCKET='+shlex.quote(bucket)+' ACCOUNTS_PARAMETER='+shlex.quote(accounts)+' ORIGIN_PARAMETER='+shlex.quote(origin)+' bash /tmp/stagelock-start.sh']
(p/'ssm-command.json').write_text(json.dumps({'commands':commands,'executionTimeout':['1200']}))
PY
COMMAND_ID="$(aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name AWS-RunShellScript --parameters "file://$PRIVATE_DIR/ssm-command.json" --timeout-seconds 1200 --query Command.CommandId --output text)"
printf 'Installing the blockchain service. SSM command: %s\n' "$COMMAND_ID"
STATUS=''
for attempt in $(seq 1 180); do
  STATUS="$(aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" --query Status --output text 2>/dev/null || true)"
  case "$STATUS" in
    Success) break;;
    Failed|TimedOut|Cancelled|Cancelling) echo 'Service setup failed. Inspect the SSM command in the AWS console.'; exit 1;;
  esac
  sleep 10
done
[[ "$STATUS" == Success ]] || { echo 'Service setup is still running. Inspect SSM before retrying.'; exit 1; }
printf 'Waiting for the HTTPS RPC…\n'
READY=''
for attempt in $(seq 1 60); do
  if curl --fail --silent --show-error --max-time 15 "$RPC_URL" -o "$PRIVATE_DIR/network.json" 2>/dev/null && node --input-type=module - "$PRIVATE_DIR/network.json" <<'JS'
import fs from 'node:fs';import {isAddress} from 'ethers';const m=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));if(m.chainId!==731337||!isAddress(m.contractAddress))process.exit(1);
JS
  then READY=yes; break; fi
  sleep 10
done
[[ "$READY" == yes ]] || { echo 'HTTPS RPC did not become ready. Check the SSM service logs.'; exit 1; }
export VITE_CHAIN_ID=731337
export VITE_CONTRACT_ADDRESS="$(node --input-type=module -e 'import fs from "node:fs";console.log(JSON.parse(fs.readFileSync(process.argv[1],"utf8")).contractAddress)' "$PRIVATE_DIR/network.json")"
export VITE_RPC_URL="$RPC_URL"
npm run build
aws s3 sync dist/ "s3://$BUCKET_NAME/" --cache-control 'public,max-age=31536000,immutable' --exclude index.html --only-show-errors
aws s3 cp dist/index.html "s3://$BUCKET_NAME/index.html" --content-type text/html --cache-control 'no-cache,no-store,must-revalidate' --only-show-errors
INVALIDATION_ID="$(aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths / /index.html --query Invalidation.Id --output text)"
aws cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"
curl --fail --silent --show-error --retry 4 "$SITE_URL" -o "$PRIVATE_DIR/hosted-index.html"
node --input-type=module - "$PRIVATE_DIR/hosted-index.html" <<'JS'
import fs from 'node:fs';const html=fs.readFileSync(process.argv[2],'utf8');if(!html.includes('StageLock')||!html.includes('/assets/'))throw Error('Hosted frontend verification failed');
JS
printf '\nWebsite: %s\nWallet network: StageLock Private\nRPC: %s\nChain ID: 731337\nCurrency symbol: ETH\nContract: %s\n' "$SITE_URL" "$RPC_URL" "$VITE_CONTRACT_ADDRESS"
printf 'Review wallet public addresses:\n'
node --input-type=module - "$PRIVATE_DIR/accounts.json" <<'JS'
import fs from 'node:fs';for(const a of JSON.parse(fs.readFileSync(process.argv[2],'utf8')))console.log(a.role+': '+a.address);
JS
printf 'To display wallet import keys privately in your AWS terminal, run:\nAWS_REGION=%s STACK_NAME=%s bash scripts/show-review-wallets.sh\n' "$AWS_REGION" "$STACK_NAME"
