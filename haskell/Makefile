GHC ?= ghc
SDL_CFLAGS ?= $(shell sdl2-config --cflags)
SDL_LIBS ?= $(shell sdl2-config --libs)
GHCFLAGS ?= -O2 -Wall -Wcompat -rtsopts
SOURCES := $(wildcard src/Wolf/*.hs)

.PHONY: all test snapshot smoke clean
all: build/wolf-haskell
build/wolf-haskell: app/Main.hs $(SOURCES) cbits/platform.c
	mkdir -p build/game
	$(GHC) $(GHCFLAGS) -isrc -outputdir build/game app/Main.hs cbits/platform.c $(SDL_CFLAGS) $(SDL_LIBS) -o $@
build/tests: test/Main.hs $(SOURCES)
	mkdir -p build/test
	$(GHC) $(GHCFLAGS) -isrc -outputdir build/test test/Main.hs -o $@
test: build/tests
	./build/tests
snapshot: build/wolf-haskell
	./build/wolf-haskell --snapshot build/demo.ppm
smoke: build/wolf-haskell
	SDL_VIDEODRIVER=dummy ./build/wolf-haskell --smoke
clean:
	rm -rf build
