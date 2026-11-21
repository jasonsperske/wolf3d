GHC ?= ghc
SDL_CFLAGS ?= $(shell sdl2-config --cflags)
SDL_LIBS ?= $(shell sdl2-config --libs)
GHCFLAGS ?= -O2 -Wall -Wcompat -rtsopts
SOURCES := $(wildcard src/Wolf/*.hs)

.PHONY: all test test-assets snapshot smoke clean
ASSET_DIR ?= $(if $(wildcard ../assets/registered),../assets/registered,../assets/shareware)
all: build/wolf-haskell build/libwolfopl.so
build/wolf-haskell: app/Main.hs $(SOURCES) cbits/platform.c cbits/audio.c vendor/nuked-opl3/opl3.h
	mkdir -p build/game
	$(GHC) $(GHCFLAGS) -isrc -outputdir build/game app/Main.hs cbits/platform.c cbits/audio.c $(SDL_CFLAGS) $(SDL_LIBS) -o $@
build/libwolfopl.so: vendor/nuked-opl3/opl3.c vendor/nuked-opl3/opl3.h
	mkdir -p build
	$(CC) -O2 -fPIC -shared vendor/nuked-opl3/opl3.c -o $@
build/tests: test/Main.hs $(SOURCES)
	mkdir -p build/test
	$(GHC) $(GHCFLAGS) -isrc -outputdir build/test test/Main.hs -o $@
build/asset-tests: test/AssetMain.hs $(SOURCES)
	mkdir -p build/asset-test
	$(GHC) $(GHCFLAGS) -isrc -outputdir build/asset-test test/AssetMain.hs -o $@
build/media-tests: test/MediaMain.hs $(SOURCES)
	mkdir -p build/media-test
	$(GHC) $(GHCFLAGS) -isrc -outputdir build/media-test test/MediaMain.hs -o $@
test: build/tests build/asset-tests build/media-tests
	./build/tests
	./build/asset-tests
	./build/media-tests
test-assets: build/asset-tests build/media-tests
	./build/asset-tests "$(ASSET_DIR)"
	./build/media-tests "$(ASSET_DIR)"
snapshot: build/wolf-haskell
	./build/wolf-haskell --demo --snapshot build/demo.ppm
smoke: all
	SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./build/wolf-haskell --smoke
clean:
	rm -rf build
