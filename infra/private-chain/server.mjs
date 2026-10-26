import fs from 'node:fs';
import ganache from 'ganache';
import {JsonRpcProvider,Wallet,ContractFactory,parseEther,toBeHex} from 'ethers';
import {compile} from '../../scripts/compile.mjs';
import {createGateway} from './gateway.mjs';
process.on('uncaughtException', e => { console.error('Private-chain startup failure:', e.message); process.exit(1); });
process.on('unhandledRejection', e => { console.error('Private-chain request failure:', e?.message || String(e)); process.exit(1); });
const data = process.env.CHAIN_DATA_DIR || '/data';
const secrets = process.env.CHAIN_SECRETS_DIR || '/run/stagelock';
const accounts = JSON.parse(fs.readFileSync(secrets+'/accounts.json','utf8'));
const token = fs.readFileSync(secrets+'/origin-token','utf8').trim();
if (accounts.length !== 4) throw Error('Four private review wallets required');
fs.mkdirSync(data,{recursive:true});
const chainId = 731337;
const chain = ganache.server({
  logging:{quiet:true},
  chain:{chainId,networkId:chainId,hardfork:'shanghai',vmErrorsOnRPCResponse:true},
  wallet:{lock:true,passphrase:token,accounts:accounts.map(a=>({secretKey:a.privateKey,balance:toBeHex(parseEther('1000'))})), unlockedAccounts:[]},
  database:{dbPath:data+'/chain'},miner:{blockGasLimit:15000000,defaultGasPrice:2000000000}
});
const internalPort = Number(process.env.CHAIN_INTERNAL_PORT || 8545);
await chain.listen(internalPort,'127.0.0.1');
const provider = new JsonRpcProvider('http://127.0.0.1:'+internalPort);
const deploymentFile = data+'/deployment.json';
let deployment;
if (fs.existsSync(deploymentFile)) {
  deployment = JSON.parse(fs.readFileSync(deploymentFile,'utf8'));
  if (await provider.getCode(deployment.contractAddress) === '0x') throw Error('Saved contract missing; refusing to replace the chain silently');
} else {
  const {abi,bytecode} = compile();
  const contract = await new ContractFactory(abi,bytecode,new Wallet(accounts[0].privateKey,provider)).deploy();
  await contract.waitForDeployment();
  deployment = {chainId,contractAddress:await contract.getAddress()};
  fs.writeFileSync(deploymentFile,JSON.stringify(deployment,null,2),{mode:0o600});
}
const gateway = createGateway({token,request:args=>chain.provider.request(args),metadata:()=>({...deployment,currency:'ETH',network:'StageLock Private',accounts:accounts.map(a=>({role:a.role,address:a.address}))})});
await new Promise(resolve=>gateway.listen(Number(process.env.CHAIN_GATEWAY_PORT || 8080),'0.0.0.0',resolve));
console.log('StageLock private chain ready. Chain ID:',chainId,'Contract:',deployment.contractAddress);
let shuttingDown=false;
async function shutdown(){if(shuttingDown)return;shuttingDown=true;await new Promise(resolve=>gateway.close(resolve));await provider.destroy();await chain.close();process.exit(0);}
process.on('SIGTERM',shutdown);process.on('SIGINT',shutdown);
