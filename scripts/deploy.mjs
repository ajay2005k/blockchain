import {JsonRpcProvider,Wallet,ContractFactory} from 'ethers';
import {compile} from './compile.mjs';
const url=process.env.RPC_URL||'http://127.0.0.1:8545';
if(!process.env.DEPLOYER_PRIVATE_KEY&&!['127.0.0.1','localhost'].includes(new URL(url).hostname)) throw Error('Remote deployment requires DEPLOYER_PRIVATE_KEY');
const provider=new JsonRpcProvider(url);
const signer=process.env.DEPLOYER_PRIVATE_KEY?new Wallet(process.env.DEPLOYER_PRIVATE_KEY,provider):await provider.getSigner();
const {abi,bytecode}=compile(); const c=await new ContractFactory(abi,bytecode,signer).deploy(); await c.waitForDeployment();
console.log('VITE_CONTRACT_ADDRESS='+await c.getAddress()); console.log('VITE_CHAIN_ID='+(await provider.getNetwork()).chainId); 
