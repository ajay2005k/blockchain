import http from 'node:http';
import {timingSafeEqual} from 'node:crypto';
const allowed = new Set([
  'eth_chainId', 'eth_blockNumber', 'eth_getBalance', 'eth_getCode',
  'eth_getTransactionCount', 'eth_estimateGas', 'eth_gasPrice',
  'eth_maxPriorityFeePerGas', 'eth_feeHistory', 'eth_call', 'eth_getLogs',
  'eth_getTransactionByHash', 'eth_getTransactionReceipt',
  'eth_getBlockByNumber', 'eth_getBlockByHash', 'eth_sendRawTransaction',
  'net_version', 'web3_clientVersion', 'eth_accounts'
]);
export function createGateway({token, request, metadata, maxPerMinute = 300}) {
  if (!token || token.length < 32) throw Error('A strong origin token is required');
  let inFlight = 0;
  const clients = new Map();
  const expected = Buffer.from(token);
  function reply(res, status, value) {
    res.writeHead(status, {'Content-Type':'application/json', 'Cache-Control':'no-store',
      'Access-Control-Allow-Origin':'*', 'Access-Control-Allow-Headers':'Content-Type',
      'Access-Control-Allow-Methods':'POST, GET, OPTIONS', 'X-Content-Type-Options':'nosniff'});
    res.end(JSON.stringify(value));
  }
  return http.createServer(async (req, res) => {
    const supplied = Buffer.from(String(req.headers['x-stagelock-origin'] || ''));
    if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return reply(res, 403, {error:'Forbidden'});
    if (req.url?.split('?')[0] !== '/rpc') return reply(res, 404, {error:'Not found'});
    if (req.method === 'OPTIONS') return reply(res, 204, null);
    if (req.method === 'GET') return reply(res, 200, metadata());
    if (req.method !== 'POST') return reply(res, 405, {error:'Method not allowed'});
    const ip = String(req.headers['x-forwarded-for'] || req.socket.remoteAddress).split(',').at(-1).trim();
    const now = Date.now();
    for (const [key, entry] of clients) if (now > entry.expires) clients.delete(key);
    const entry = clients.get(ip) || {count:0, expires:now+60000};
    if (++entry.count > maxPerMinute || inFlight >= 24 || clients.size > 10000) return reply(res, 429, {error:'Rate limit reached'});
    clients.set(ip, entry); inFlight++;
    try {
      let size = 0; const chunks = [];
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 65536) { reply(res, 413, {error:'Request too large'}); return; }
        chunks.push(chunk);
      }
      let body;
      try { body = JSON.parse(Buffer.concat(chunks).toString()); }
      catch { return reply(res, 400, {error:'Invalid JSON'}); }
      const batch = Array.isArray(body) ? body : [body];
      if (!batch.length || batch.length > 20) return reply(res, 400, {error:'Batch limit exceeded'});
      const results = [];
      for (const call of batch) {
        const id = typeof call?.id === 'string' || typeof call?.id === 'number' ? call.id : null;
        if (!call || call.jsonrpc !== '2.0' || !Array.isArray(call.params ?? [])) {
          results.push({jsonrpc:'2.0',id,error:{code:-32600,message:'Invalid request'}}); continue;
        }
        if (!allowed.has(call.method)) {
          results.push({jsonrpc:'2.0',id,error:{code:-32601,message:'RPC method is not available'}}); continue;
        }
        try {
          const result = call.method === 'eth_accounts' ? [] : await request({method:call.method,params:call.params || []});
          results.push({jsonrpc:'2.0',id,result});
        } catch (e) {
          results.push({jsonrpc:'2.0',id,error:{code:Number.isInteger(e.code)?e.code:-32000,message:String(e.message || 'RPC request failed').slice(0,500)}});
        }
      }
      reply(res, 200, Array.isArray(body) ? results : results[0]);
    } catch { if (!res.headersSent) reply(res, 400, {error:'Request failed'}); }
    finally { inFlight--; }
  });
}
