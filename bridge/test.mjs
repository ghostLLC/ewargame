import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { TOOLS, callTool } from './server.mjs';

test('tool schemas expose orders and turn gates, no hidden-state tools', () => {
  assert.equal(TOOLS.length, 6);
  assert.ok(TOOLS.find(t => t.name === 'game_orders').inputSchema.required.includes('turn'));
  assert.ok(!TOOLS.some(t => /debug|cheat|save|seed/.test(t.name)));
});

test('reject malformed and unbounded inputs before any socket', async () => {
  await assert.rejects(callTool('game_orders', { turn: 1, orders: new Array(129).fill({}) }), /invalid arguments/);
  await assert.rejects(callTool('game_commit', { turn: -1 }), /invalid arguments/);
  await assert.rejects(callTool('game_observe', { side: 0 }), /invalid arguments/);
  await assert.rejects(callTool('game_wait_turn', { after_turn: 1, timeout_ms: 60000 }), /invalid arguments/);
});

test('stdio negotiation, tool discovery, invalid JSON and unknown methods', async () => {
  const child = spawn(process.execPath, [new URL('./server.mjs', import.meta.url).pathname.replace(/^\/(\w:)/, '$1')], { stdio: ['pipe','pipe','pipe'] });
  let output = '';
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', data => { output += data; });
  child.stdin.end([
    '{broken',
    JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test', version: '1' } } }),
    JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }),
    JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }),
    JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'unknown' }),
  ].join('\n') + '\n');
  const [code] = await once(child, 'exit');
  assert.equal(code, 0);
  const messages = output.trim().split('\n').map(line => JSON.parse(line));
  assert.equal(messages.find(m => m.id === null).error.code, -32700);
  assert.equal(messages.find(m => m.id === 1).result.protocolVersion, '2025-11-25');
  assert.equal(messages.find(m => m.id === 2).result.tools.length, 6);
  assert.equal(messages.find(m => m.id === 3).error.code, -32601);
});
