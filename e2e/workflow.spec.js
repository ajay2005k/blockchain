import {test,expect} from '@playwright/test';
import ganache from 'ganache';
import {JsonRpcProvider,ContractFactory} from 'ethers';
import {spawn} from 'node:child_process';
import {compile} from '../scripts/compile.mjs';
let server,vite,accounts;
test.beforeAll(async()=>{
 server=ganache.server({logging:{quiet:true},chain:{chainId:31337,hardfork:'shanghai'}});await server.listen(18545);
 const p=new JsonRpcProvider('http://127.0.0.1:18545');accounts=(await p.listAccounts()).map(a=>a.address);
 const {abi,bytecode}=compile();const c=await new ContractFactory(abi,bytecode,await p.getSigner()).deploy();await c.waitForDeployment();
 vite=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port','15173','--strictPort'],{env:{...process.env,VITE_CONTRACT_ADDRESS:await c.getAddress(),VITE_RPC_URL:'http://127.0.0.1:18545',VITE_CHAIN_ID:'31337'},stdio:'pipe'});
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Vite startup timed out')),20000);vite.stdout.on('data',d=>{if(d.toString().includes('15173')){clearTimeout(timer);resolve();}});vite.on('error',reject);});await p.destroy();
});
test.afterAll(async()=>{vite?.kill();await server?.close();});
async function wallet(page,index){await page.evaluate(address=>{window.selectedAccount=address;window.walletListeners.accountsChanged?.forEach(fn=>fn([address]));},accounts[index]);await page.locator('#connect').click();}
test('client funds, contractor delivers, client approves, contractor withdraws',async({page})=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.addInitScript(({accounts})=>{window.selectedAccount=accounts[0];window.walletListeners={};window.ethereum={on:(event,fn)=>{(window.walletListeners[event]??=[]).push(fn);},request:async({method,params=[]})=>{if(['eth_requestAccounts','eth_accounts'].includes(method))return [window.selectedAccount];const r=await fetch('http://127.0.0.1:18545',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({jsonrpc:'2.0',id:1,method,params})});const data=await r.json();if(data.error)throw Object.assign(Error(data.error.message),data.error);return data.result;}};},{accounts});
 await page.goto('http://127.0.0.1:15173');await expect(page).toHaveTitle('StageLock — Milestone escrow');
 await page.locator('#connect').click();await page.locator('#new').click();
 await page.locator('[name=title]').fill('Identity system');await page.locator('[name=contractor]').fill(accounts[1]);await page.locator('[name=arbitrator]').fill(accounts[2]);await page.locator('[name=deadline]').fill(new Date(Date.now()+7*86400000).toISOString().slice(0,10));
 await page.getByRole('textbox',{name:'Milestone title',exact:true}).fill('Brand guidelines');await page.getByRole('textbox',{name:'Amount in ETH',exact:true}).fill('0.1');await page.getByRole('button',{name:'Create & fund agreement'}).click();await expect(page.locator('dialog')).not.toBeVisible({timeout:30000});
 await expect(page.getByRole('button',{name:/Identity system/}).first()).toBeVisible();
 await wallet(page,1);await page.getByRole('button',{name:/Identity system/}).first().click();await page.getByRole('textbox',{name:'Delivery evidence'}).fill('Guidelines delivered at ipfs://brand-guidelines');await page.getByRole('button',{name:'Submit work'}).click();await expect(page.locator('dialog').getByText('In review',{exact:true})).toBeVisible({timeout:30000});
 await page.getByRole('button',{name:'Close',exact:true}).click();await wallet(page,0);await page.getByRole('button',{name:/Identity system/}).first().click();await page.getByRole('button',{name:'Approve payment'}).click();await expect(page.locator('dialog').getByText('Paid',{exact:true})).toBeVisible({timeout:30000});
 await page.getByRole('button',{name:'Close',exact:true}).click();await wallet(page,1);await expect(page.locator('#withdraw')).toBeEnabled();await page.locator('#withdraw').click();await expect(page.locator('#withdraw')).toBeDisabled({timeout:30000});
 await page.setViewportSize({width:390,height:844});await expect(page.locator('#new')).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);expect(errors).toEqual([]);
});
