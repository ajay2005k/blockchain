import fs from 'node:fs';
import solc from 'solc';
export function compile() {
 const output=JSON.parse(solc.compile(JSON.stringify({language:'Solidity',sources:{'StageLock.sol':{content:fs.readFileSync(new URL('../contracts/StageLock.sol',import.meta.url),'utf8')}},settings:{viaIR:true,optimizer:{enabled:true,runs:200},evmVersion:'shanghai',outputSelection:{'*':{'*':['abi','evm.bytecode.object']}}}})));
 for(const e of output.errors||[]) if(e.severity==='error') throw Error(e.formattedMessage);
 const c=output.contracts['StageLock.sol'].StageLock; return {abi:c.abi,bytecode:'0x'+c.evm.bytecode.object};
}
if(process.argv[1]===new URL(import.meta.url).pathname) { fs.mkdirSync('artifacts',{recursive:true}); fs.writeFileSync('artifacts/StageLock.json',JSON.stringify(compile(),null,2)); console.log('StageLock compiled'); }
