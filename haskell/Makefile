GHC ?= ghc
SDL_CFLAGS ?= $(shell sdl2-config --cflags)
SDL_LIBS ?= $(shell sdl2-config --libs)
GHCFLAGS ?= -O2 -Wall -Wcompat -rtsopts
SOURCES := $(wildcard src/Wolf/*.hs)

.PHONY: all test test-assets snapshot smoke clean
ASSET_DIR ?= ../wolf3dsw
all: build/wolf-haskell
build/wolf-haskell: app/Main.hs $(SOURCES) cbits/platform.c
	mkdir -p build/game
	$(GHC) $(GHCFLAGS) -isrc -outputdir build/game app/Main.hs cbits/platform.c $(SDL_CFLAGS) $(SDL_LIBS) -o $@
build/tests: test/Main.hs $(SOURCES)
	mkdir -p build/test
	$(GHC) $(GHCFLAGS) -isrc -outputdir build/test test/Main.hs -o $@
build/asset-tests: test/AssetMain.hs $(SOURCES)
	mkdir -p build/asset-test
	$(GHC) $(GHCFLAGS) -isrc -outputdir build/asset-test test/AssetMain.hs -o $@
test: build/tests build/asset-tests
	./build/tests
	./build/asset-tests
test-assets: build/asset-tests
	./build/asset-tests "$(ASSET_DIR)"
snapshot: build/wolf-haskell
	./build/wolf-haskell --snapshot build/demo.ppm
smoke: build/wolf-haskell
	SDL_VIDEODRIVER=dummy ./build/wolf-haskell --smoke
clean:
	rm -rf build
