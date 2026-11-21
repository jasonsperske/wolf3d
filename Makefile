# Root entry points; source and compiler output stay under haskell/.
.PHONY: all test test-assets bundle test-bundle clean
ASSET_DIR ?= $(if $(wildcard assets/registered),assets/registered,assets/shareware)
all test clean:
	$(MAKE) -C haskell $@
test-assets:
	$(MAKE) -C haskell test-assets ASSET_DIR="$(abspath $(ASSET_DIR))"
bundle: all
	python3 haskell/tools/bundle.py "$(ASSET_DIR)" dist/wolf-haskell

test-bundle: all
	python3 haskell/test/bundle_test.py "$(ASSET_DIR)"
