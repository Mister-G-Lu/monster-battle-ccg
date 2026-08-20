// Coerce a wasmoon Lua table (1-indexed) or a JS array into a dense JS array.
// Sequential Lua tables sometimes arrive as real arrays, sometimes as objects
// with numeric keys; the UI/engine should not care which.
export function luaList(v) {
  if (v == null) return [];
  if (Array.isArray(v)) return v.filter((x) => x != null);
  const out = [];
  for (let i = 1; v[i] != null; i++) out.push(v[i]);
  return out;
}
