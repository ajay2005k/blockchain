#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${AWS_REGION:?Set AWS_REGION to the target AWS region}"
: "${VITE_CHAIN_ID:?Set VITE_CHAIN_ID to the deployed contract network}"
: "${VITE_CONTRACT_ADDRESS:?Set VITE_CONTRACT_ADDRESS}"
: "${VITE_RPC_URL:?Set VITE_RPC_URL to a browser-accessible HTTPS Ethereum RPC}"
STACK_NAME="${STACK_NAME:-stagelock-web}"
command -v aws >/dev/null
command -v npm >/dev/null
node --input-type=module <<'JS'
import {isAddress,JsonRpcProvider,Contract} from 'ethers';
import {ABI} from './src/abi.js';
const {VITE_CHAIN_ID:chain,VITE_CONTRACT_ADDRESS:address,VITE_RPC_URL:rpc}=process.env;
if(!isAddress(address))throw Error('Invalid escrow contract address');
const url=new URL(rpc);
if(url.protocol!=='https:'||['localhost','127.0.0.1','0.0.0.0','[::1]'].includes(url.hostname))throw Error('Hosting requires a remote HTTPS RPC');
if(!/^\d+$/.test(chain)||Number(chain)<=0)throw Error('Invalid chain ID');
const provider=new JsonRpcProvider(rpc);
try {
 if((await provider.getNetwork()).chainId!==BigInt(chain))throw Error('RPC and configured chain do not match');
 if(await provider.getCode(address)==='0x')throw Error('No contract at configured address');
 await new Contract(address,ABI,provider).count();
 console.log('Escrow network and contract verified');
} finally { await provider.destroy(); }
JS
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output json
npm test
npm run build
aws cloudformation validate-template --template-body file://infra/hosting.yaml --region "$AWS_REGION" >/dev/null
aws cloudformation deploy --template-file infra/hosting.yaml --stack-name "$STACK_NAME" --region "$AWS_REGION" --no-fail-on-empty-changeset
BUCKET_NAME="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query 'Stacks[0].Outputs[?OutputKey==`BucketName`].OutputValue' --output text)"
DISTRIBUTION_ID="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query 'Stacks[0].Outputs[?OutputKey==`DistributionId`].OutputValue' --output text)"
aws s3 sync dist/ "s3://$BUCKET_NAME/" --region "$AWS_REGION" --cache-control 'public,max-age=31536000,immutable' --exclude index.html
aws s3 cp dist/index.html "s3://$BUCKET_NAME/index.html" --region "$AWS_REGION" --content-type text/html --cache-control 'no-cache,no-store,must-revalidate'
INVALIDATION_ID="$(aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths /index.html / --query Invalidation.Id --output text)"
aws cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"
SITE_URL="$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query 'Stacks[0].Outputs[?OutputKey==`SiteURL`].OutputValue' --output text)"
curl --fail --silent --show-error "$SITE_URL" -o /tmp/stagelock-hosted-index.html
node --input-type=module <<'JS'
import fs from 'node:fs';
const html=fs.readFileSync('/tmp/stagelock-hosted-index.html','utf8');
if(!html.includes('StageLock')||!html.includes('/assets/'))throw Error('Hosted app response verification failed');
JS
printf 'StageLock is available at %s\n' "$SITE_URL"
