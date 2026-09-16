#!/usr/bin/env node
/** MCP stdio adapter. No model runtime and no external network dependencies. */
import net from 'node:net';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const orderSchema = {
  type: 'object', additionalProperties: false,
  properties: { unit_id: { type: 'string' }, kind: { type: 'string', enum: ['move','attack','defend','rest','recon','reserve','retreat','engineer'] }, target: { type: 'array', items: { type: 'integer' }, minItems: 2, maxItems: 2 }, stance: { type: 'string', enum: ['cautious','balanced','aggressive'] } },
  required: ['unit_id','kind'],
};
const object = (properties, required = []) => ({ type: 'object', properties, required, additionalProperties: false });
export const TOOLS = [
  { name: 'game_observe', description: 'Read your assigned side’s current operational picture, own formations/orders, known enemy contacts, objectives and reports.', inputSchema: object({}), annotations: { readOnlyHint: true } },
  { name: 'game_rules', description: 'Read available orders, support kinds and turn procedure.', inputSchema: object({}), annotations: { readOnlyHint: true } },
  { name: 'game_orders', description: 'Atomically validate and apply a batch of orders for your side. Existing orders persist. Include the current turn; locked or stale turns are rejected.', inputSchema: object({ turn: { type: 'integer', minimum: 1 }, orders: { type: 'array', items: orderSchema, maxItems: 128 } }, ['turn','orders']), annotations: { readOnlyHint: false, destructiveHint: false } },
  { name: 'game_support', description: 'Allocate your turn’s operational support to a known map hex.', inputSchema: object({ turn: { type: 'integer', minimum: 1 }, kind: { type: 'string', enum: ['artillery','air','recon'] }, target: { type: 'array', items: { type: 'integer' }, minItems: 2, maxItems: 2 } }, ['turn','kind','target']), annotations: { readOnlyHint: false, destructiveHint: false } },
  { name: 'game_commit', description: 'Lock your orders for the current turn. Both sides must commit before resolution. This cannot be undone.', inputSchema: object({ turn: { type: 'integer', minimum: 1 } }, ['turn']), annotations: { readOnlyHint: false, destructiveHint: true } },
  { name: 'game_wait_turn', description: 'Wait up to 25 seconds for a later turn or game end. A timeout is normal: call again; do not resubmit a locked turn.', inputSchema: object({ after_turn: { type: 'integer', minimum: 0 }, timeout_ms: { type: 'integer', minimum: 0, maximum: 25000 } }, ['after_turn']), annotations: { readOnlyHint: true } },
  { name: 'game_clear_orders', description: 'Remove all of your unlocked orders for the current turn so you can replan. Locked turns are rejected.', inputSchema: object({ turn: { type: 'integer', minimum: 1 } }, ['turn']), annotations: { readOnlyHint: false, destructiveHint: true } },
];

export function connectionPath() {
  const index = process.argv.indexOf('--connection');
  return process.env.EWARGAME_CONNECTION || (index >= 0 ? process.argv[index + 1] : '') || path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'Godot', 'app_userdata', '战线 · 战役指挥', 'agent-connection.json');
}

export async function command(method, params = {}, signal) {
  let config;
  try { config = JSON.parse(await fs.readFile(connectionPath(), 'utf8')); }
  catch { throw new Error('Open the game in 本地 Agent mode first, or set EWARGAME_CONNECTION to its connection file.'); }
  if (!['127.0.0.1', 'localhost'].includes(config.host) || !Number.isInteger(config.port) || config.port < 1024 || config.port > 65535 || typeof config.token !== 'string' || config.token.length < 16) throw new Error('Invalid loopback connection configuration.');
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host: '127.0.0.1', port: config.port });
    let buffer = '', done = false;
    const finish = (error, result) => {
      if (done) return;
      done = true;
      socket.destroy();
      signal?.removeEventListener('abort', abort);
      error ? reject(error) : resolve(result);
    };
    const abort = () => finish(new Error('Request cancelled.'));
    if (signal?.aborted) return abort();
    signal?.addEventListener('abort', abort, { once: true });
    socket.setTimeout(10000, () => finish(new Error('Game response timed out.')));
    socket.on('error', () => finish(new Error('Cannot connect to game. Check that the Agent match is running.')));
    socket.on('end', () => finish(new Error('Game closed the connection.')));
    socket.on('connect', () => socket.write(JSON.stringify({ token: config.token, method, params }) + '\n'));
    socket.setEncoding('utf8');
    socket.on('data', data => {
      buffer += data;
      if (Buffer.byteLength(buffer) > 8 * 1024 * 1024) return finish(new Error('Game response exceeds size limit.'));
      const newline = buffer.indexOf('\n');
      if (newline >= 0) {
        try { finish(null, JSON.parse(buffer.slice(0, newline))); }
        catch { finish(new Error('Malformed game response.')); }
      }
    });
  });
}

function validate(value, schema) {
  if (schema.type === 'object') {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
    if ((schema.required || []).some(key => !(key in value))) return false;
    if (schema.additionalProperties === false && Object.keys(value).some(key => !(key in schema.properties))) return false;
    return Object.entries(value).every(([key, item]) => !schema.properties[key] || validate(item, schema.properties[key]));
  }
  if (schema.type === 'array') return Array.isArray(value) && value.length >= (schema.minItems || 0) && value.length <= (schema.maxItems ?? Infinity) && value.every(item => validate(item, schema.items));
  if (schema.type === 'integer') return Number.isSafeInteger(value) && value >= (schema.minimum ?? -Infinity) && value <= (schema.maximum ?? Infinity);
  if (schema.type === 'string') return typeof value === 'string' && value.length <= 256 && (!schema.enum || schema.enum.includes(value));
  return false;
}

const sleep = (ms, signal) => new Promise((resolve, reject) => {
  const timer = setTimeout(() => { signal?.removeEventListener('abort', abort); resolve(); }, ms);
  const abort = () => { clearTimeout(timer); reject(new Error('Request cancelled.')); };
  if (signal?.aborted) abort(); else signal?.addEventListener('abort', abort, { once: true });
});

export async function callTool(name, args, signal) {
  const tool = TOOLS.find(item => item.name === name);
  if (!tool || !validate(args, tool.inputSchema)) throw new Error('Unknown tool or invalid arguments.');
  if (name === 'game_wait_turn') {
    const deadline = Date.now() + (args.timeout_ms ?? 25000);
    for (;;) {
      const result = await command('observe', {}, signal);
      if (!result.ok || result.data.turn > args.after_turn || result.data.phase === 'finished') return result;
      if (Date.now() >= deadline) return { ...result, timed_out: true };
      await sleep(Math.min(500, deadline - Date.now()), signal);
    }
  }
  return command(name.slice(5), args, signal);
}

export function startStdio() {
  let buffer = '', initialized = false;
  const pending = new Map();
  const send = data => process.stdout.write(JSON.stringify(data) + '\n');
  const error = (id, code, message) => send({ jsonrpc: '2.0', id, error: { code, message } });
  async function handle(message) {
    if (!message || Array.isArray(message) || message.jsonrpc !== '2.0' || typeof message.method !== 'string') return error(message?.id ?? null, -32600, 'Invalid request');
    const id = message.id;
    if (message.method === 'notifications/cancelled') { pending.get(message.params?.requestId)?.abort(); return; }
    if (id === undefined) return;
    if (!(typeof id === 'string' || (typeof id === 'number' && Number.isFinite(id)))) return error(null, -32600, 'Invalid request id');
    if (pending.has(id)) return error(id, -32600, 'Duplicate active request id');
    const controller = new AbortController();
    pending.set(id, controller);
    try {
      let result;
      switch (message.method) {
        case 'initialize': {
          if (!message.params || typeof message.params.protocolVersion !== 'string') return error(id, -32602, 'Missing protocol version');
          const supported = ['2025-11-25', '2025-06-18', '2024-11-05'];
          initialized = true;
          result = { protocolVersion: supported.includes(message.params.protocolVersion) ? message.params.protocolVersion : supported[0], capabilities: { tools: {} }, serverInfo: { name: 'ewargame', version: '0.1.0' }, instructions: 'Play your assigned side using its observation. Read rules, place orders, commit, and wait for the next turn. Game adjudication is authoritative.' };
          break;
        }
        case 'ping': result = {}; break;
        case 'tools/list':
          if (!initialized) return error(id, -32002, 'Initialize first');
          result = { tools: TOOLS }; break;
        case 'tools/call': {
          if (!initialized) return error(id, -32002, 'Initialize first');
          try {
            const data = await callTool(message.params?.name, message.params?.arguments || {}, controller.signal);
            result = { content: [{ type: 'text', text: JSON.stringify(data) }], structuredContent: data, isError: data.ok === false };
          } catch (exception) { result = { content: [{ type: 'text', text: exception.message }], isError: true }; }
          break;
        }
        default: return error(id, -32601, 'Method not found');
      }
      send({ jsonrpc: '2.0', id, result });
    } finally { pending.delete(id); }
  }
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', data => {
    buffer += data;
    if (Buffer.byteLength(buffer) > 1024 * 1024) { error(null, -32600, 'Input too large'); process.exitCode = 1; process.stdin.destroy(); return; }
    for (;;) {
      const newline = buffer.indexOf('\n');
      if (newline < 0) break;
      const line = buffer.slice(0, newline).trim(); buffer = buffer.slice(newline + 1);
      if (!line) continue;
      let message;
      try { message = JSON.parse(line); } catch { error(null, -32700, 'Parse error'); continue; }
      handle(message).catch(() => error(message?.id ?? null, -32603, 'Internal error'));
    }
  });
  process.stdin.on('end', () => { for (const controller of pending.values()) controller.abort(); });
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) startStdio();
