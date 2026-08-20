# web-poc — browser feasibility spike

Proves the real Monster Battle Lua engine runs unmodified in WebAssembly
(via wasmoon). If it runs in Node's WASM, it runs in a browser's WASM.

## Run
    python3 ../scripts/setup_test_env.py   # from repo root: makes decrypted/ + csv_plain/
    npm install wasmoon
    node prove_engine.mjs

Expected: prints `nodes=19`, `cards_loaded=1595`, `OK engine booted in WASM`.

See ../docs/BROWSER_VERSION_RESEARCH.md for the architecture this validates.
