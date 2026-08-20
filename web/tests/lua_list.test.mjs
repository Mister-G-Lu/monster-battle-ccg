import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { luaList } from '../src/lua_list.js';

describe('luaList', () => {
  it('returns [] for nullish', () => {
    assert.deepEqual(luaList(null), []);
    assert.deepEqual(luaList(undefined), []);
  });

  it('passes JS arrays through, dropping holes/nulls', () => {
    assert.deepEqual(luaList(['a', 'b']), ['a', 'b']);
    assert.deepEqual(luaList(['a', null, 'c']), ['a', 'c']);
  });

  it('reads 1-indexed Lua tables (wasmoon object form)', () => {
    assert.deepEqual(luaList({ 1: 'oak', 2: 'vine', 3: 'bark' }), ['oak', 'vine', 'bark']);
  });

  it('stops at the first hole in a Lua table', () => {
    assert.deepEqual(luaList({ 1: 'oak', 3: 'bark' }), ['oak']);
  });
});
