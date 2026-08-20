.PHONY: verify campaign-data static lua-campaign

verify: static lua-campaign

static:
	python3 tests/static_checks.py

campaign-data:
	python3 scripts/refresh_campaign_data.py --verify

lua-campaign:
	@if command -v luajit >/dev/null 2>&1; then LUA=luajit; \
	elif command -v lua >/dev/null 2>&1; then LUA=lua; \
	else echo "SKIP lua campaign tests (no lua/luajit)"; exit 0; fi; \
	$$LUA tests/campaign_test.lua && $$LUA tests/campaign_balance_diag.lua && $$LUA tests/level_w1_test.lua
