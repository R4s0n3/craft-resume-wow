LUA ?= luajit

.PHONY: test package
test:
	$(LUA) tests/run.lua
	$(LUA) tests/ui.lua
	$(LUA) -e 'for _, f in ipairs({"Model", "Core", "Tracker", "Export", "UI"}) do assert(loadfile("CraftResume/" .. f .. ".lua")) end'

package: test
	python3 scripts/package.py
