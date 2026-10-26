# StageLock on an AWS-hosted Ethereum test chain

This deployment hosts an independent Ethereum-compatible test chain on EC2 and the website on S3 behind CloudFront. A public HTTPS RPC permits blockchain reads and wallet-signed transactions. It is not Sepolia or Ethereum mainnet, and its ETH has no monetary value. Network history is controlled by the AWS operator, not a public validator network.

## Deploy from AWS CloudShell

Sign in to account `014679146311`, open CloudShell, upload the deployment ZIP, then run:

```bash
unzip -o StageLock_Private_AWS.zip
cd StageLock
export AWS_REGION=ap-south-1
bash scripts/deploy-private-aws.sh
```

The region is an example (Mumbai); choose another supported AWS region if preferred. Node.js 22+, npm, AWS CLI v2, Python 3, tar, curl, and Bash must be available. The script checks these before provisioning. It verifies the AWS account, installs packages, runs tests, deploys infrastructure, creates the escrow contract, builds the frontend with its actual address, publishes assets, and verifies the hosted response. Initial provisioning can take 15–25 minutes. AWS IAM permissions may need adjustment if your identity cannot create the specified resources.

Resource footprint: one `t3.small` instance, 20 GB encrypted gp3 storage, one allocated public IPv4 address, a VPC with a public subnet and internet gateway, a restricted security group, an EC2 role/profile, two encrypted SSM parameters, a private S3 bucket, and CloudFront. These resources incur AWS usage charges; this is not a free-hosting promise. No NAT gateway or paid domain is required.

## Connect MetaMask

At completion the script prints the site URL, RPC URL, escrow contract address, and review wallet public addresses. Add a custom network to MetaMask:

- Network name: StageLock Private
- RPC URL: use the printed HTTPS `/rpc` URL
- Chain ID: `731337`
- Currency: `ETH`
- Block explorer: leave blank

To retrieve the four wallet import keys **inside your AWS terminal**, run:

```bash
AWS_REGION=ap-south-1 STACK_NAME=stagelock-private bash scripts/show-review-wallets.sh
```

Import the Client, Contractor, and Arbitrator keys into MetaMask as separate accounts. Each starts with 1,000 test ETH, less any transaction costs incurred afterward. The client wallet also deploys the contract. Do not paste keys into chat, publish them, or use these wallets on public networks. Keep browser wallets restricted to trusted reviewers.

Create an agreement from the Client account using the Contractor and Arbitrator public addresses. Switch to Contractor to submit evidence, Client to approve, and Contractor to withdraw. Use another milestone to exercise dispute allocation from the Arbitrator account.

## Access boundaries

- Ganache's raw RPC binds only to container loopback; it is not published as an EC2 port.
- EC2 port 8080 accepts CloudFront origin addresses only. An origin header token further restricts access to the configured distribution.
- The gateway blocks server signing, account unlocking, mining/admin controls, and development-state mutation. Even the server's internal accounts are locked.
- Browser requests can read records and broadcast signed transactions. The origin token and wallet keys are never bundled in frontend assets.
- The browser-to-CloudFront connection uses HTTPS. CloudFront-to-EC2 traffic uses HTTP on the restricted origin path; it is not end-to-end TLS.
- The gateway has request-size, batch-size, concurrent-request and per-IP rate limits. It is intended for controlled project reviews, not public financial service operation.

The chain uses Ganache as its development Ethereum engine. This is an independently hosted test network, not a distributed consensus deployment or a security certification. The application interface remains StageLock without seeded agreements.

## Persistence and maintenance

Blockchain data and the deployed contract are stored under `/opt/stagelock/data` on the encrypted root EBS volume. The Docker service restarts automatically; an ordinary reboot or container restart preserves state. Running the deployment script again with the same account, region, and stack name reuses wallet credentials and the existing instance state.

EC2 replacement is different from a reboot. The root volume is retained on termination, but a replacement instance does not automatically restore that disk. Snapshot the chain data and record the encrypted SSM parameters before replacing the instance. Restore the previous disk/data before accepting further writes; do not silently replace an established chain with an empty database. Keep the origin token consistent with the CloudFront stack configuration.

Use Systems Manager Session Manager for server administration; there is no SSH ingress. Container logs are available with `sudo docker logs stagelock-chain`; they do not intentionally print wallet keys. The SSM bootstrap command uses only parameter names and never includes private-key values.

Deleting the stack retains the S3 bucket and EC2 root disk; remove retained resources separately only after preserving anything needed. Encrypted SSM parameters are created outside CloudFormation and also remain. Stopping EC2 stops chain processing; keeping the website online does not make the stopped chain available. Deleting web infrastructure never settles outstanding escrow agreements automatically.
