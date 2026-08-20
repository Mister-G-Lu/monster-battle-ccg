.PHONY: verify static campaign-data lua-campaign web-ui

verify: static lua-campaign web-ui

static:
	python3 tests/static_checks.py

campaign-data:
	python3 scripts/refresh_campaign_data.py --verify

lua-campaign:
	@if command -v luajit >/dev/null 2>&1; then LUA=luajit; \
	elif command -v lua >/dev/null 2>&1; then LUA=lua; \
	else echo "SKIP lua campaign tests (no lua/luajit)"; exit 0; fi; \
	$$LUA tests/campaign_test.lua && $$LUA tests/campaign_balance_diag.lua && \
	$$LUA tests/level_w1_test.lua && $$LUA tests/campaign_service_test.lua && \
	$$LUA tests/campaign_battle_test.lua && $$LUA tests/web_bridge_test.lua

web-ui:
	@if command -v node >/dev/null 2>&1; then \
		node --test web/tests/lua_list.test.mjs web/tests/ui.test.mjs && \
		(cd web && node tests/bridge_recruit.mjs); \
	else echo "SKIP web UI tests (no node)"; fi
