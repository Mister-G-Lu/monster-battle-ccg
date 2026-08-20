.PHONY: verify campaign-data static lua-campaign app-shell web

verify: static app-shell lua-campaign

static:
	python3 tests/static_checks.py

app-shell:
	@if command -v node >/dev/null 2>&1; then node tests/app_shell_test.js; \
	else echo "SKIP app shell test (no node)"; fi

web:
	@echo "Serving the app at http://localhost:8000/ (Ctrl-C to stop)"
	python3 -m http.server 8000

campaign-data:
	python3 scripts/refresh_campaign_data.py --verify

lua-campaign:
	@if command -v luajit >/dev/null 2>&1; then LUA=luajit; \
	elif command -v lua >/dev/null 2>&1; then LUA=lua; \
	else echo "SKIP lua campaign tests (no lua/luajit)"; exit 0; fi; \
	$$LUA tests/campaign_test.lua && $$LUA tests/campaign_balance_diag.lua && \
	$$LUA tests/level_w1_test.lua && $$LUA tests/campaign_service_test.lua
