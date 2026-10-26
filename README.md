# StageLock

Milestone escrow for client–contractor agreements. Clients fund an agreement upfront; contractors submit delivery evidence; clients approve each payment. An independent arbitrator can split a disputed milestone between both parties.

## Run locally

Requires Node.js 22 or newer and an Ethereum browser wallet.

```sh
npm install
cp .env.example .env
npm run chain
```

In another terminal:

```sh
npm run deploy
```

Copy the returned `VITE_CONTRACT_ADDRESS` into `.env`, then run `npm run dev`. Add the local network to your wallet with RPC `http://127.0.0.1:8545`, chain ID `31337`, and currency `ETH`. Import accounts printed by the local chain for client, contractor and arbitrator. These accounts are exclusively for local use. Restart Vite after changing environment variables.

## Workflow

1. Connect the client wallet. Create an agreement with distinct contractor and arbitrator wallets, a delivery deadline, and up to twelve milestones. The full amount is escrowed at creation.
2. Connect the contractor wallet and submit work for a milestone before the deadline.
3. Connect the client wallet to approve payment or raise a dispute. Either party may dispute submitted work.
4. The arbitrator resolves a dispute by allocating an amount to the contractor; the remainder belongs to the client.
5. Recipients withdraw their credited ETH. After the delivery deadline, the client may reclaim unsubmitted milestones.

Titles and delivery evidence are public on-chain. Keep private documents outside the blockchain and share only appropriate references. Currency is native ETH; this version does not support tokens or fiat. Wallets pay network fees. Submitted work cannot be automatically refunded or released: an inactive client requires arbitration, and an inactive arbitrator can leave disputed funds locked. Agree on an available arbitrator before funding.

## Verification

```sh
npm test
npm run compile
npm run build
npx playwright install chromium
npm run test:browser
```

Tests use an isolated in-process Ethereum chain. They cover funding validation, authorization, delivery, settlement, withdrawals, replay protection, dispute allocations and expiry refunds.

## Configuration

| Variable | Purpose |
| --- | --- |
| `VITE_CHAIN_ID` | Expected wallet chain |
| `VITE_CONTRACT_ADDRESS` | Deployed StageLock contract |
| `VITE_RPC_URL` | Browser-accessible HTTPS RPC in hosted environments |
| `RPC_URL` | Deployment RPC |
| `DEPLOYER_PRIVATE_KEY` | Server-side deployment key for remote networks |

`VITE_` variables are public build inputs. Never place secrets in them. Deployment scripts read process environment variables; use `node --env-file=.env scripts/deploy.mjs` if loading deployment settings from a file.

## Hosting on AWS

The frontend is a static Vite build. Build with the intended chain and contract configuration, then serve `dist/` through an HTTPS static host such as S3 behind CloudFront. An Ethereum RPC and deployed contract are separate from web hosting. Local RPC addresses cannot serve remote visitors. Do not expose Ganache publicly. A contract change requires a new deployment; existing agreements remain in the old contract.

The contract has no owner withdrawal, upgrade controls, or platform fees. It uses pull payments and checks-effects-interactions for withdrawals. Independent security review is required before accepting valuable funds.

### Deploy the AWS hosting stack

`infra/hosting.yaml` creates an encrypted private S3 bucket, CloudFront origin access control, HTTPS delivery, and security response headers. The bucket is retained if the stack is deleted. CloudFront and S3 usage are billed to the selected AWS account.

After installing dependencies, attaching an authorized AWS identity, and deploying the escrow contract to the selected Ethereum network, export `AWS_REGION`, `VITE_CHAIN_ID`, `VITE_CONTRACT_ADDRESS`, and `VITE_RPC_URL`. The RPC must be browser-accessible over HTTPS. Use `STACK_NAME` to select the dedicated hosting stack; it defaults to `stagelock-web`.

```sh
bash scripts/deploy-aws.sh
```

The script verifies the chain and contract, runs contract tests, builds the frontend, deploys the CloudFormation stack, uploads the assets, invalidates the entry page, and checks the HTTPS response. Build configuration contains no private keys. Keep the AWS identity and contract deployer credentials outside the repository.

### AWS-hosted private review network

To deploy the website and an independent Ethereum test chain together, follow [the private-network deployment guide](infra/PRIVATE_NETWORK.md). This option supplies four funded review wallets and does not require Sepolia faucet ETH. Run `scripts/deploy-private-aws.sh` from an authenticated AWS terminal. The chain has no monetary-value currency and remains under the AWS operator's control.
