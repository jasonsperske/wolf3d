# Nuked-OPL3

Unmodified upstream files from https://github.com/nukeykt/Nuked-OPL3
at commit `765ec962e473aeb767e4cba74ffdc8f588ffbfe8`.

`opl3.c`, `opl3.h`, and `LICENSE` are vendored so normal builds need no network.
The code retains its upstream copyright and LGPL-2.1-or-later notices.

The Make build produces a replaceable `libwolfopl.so`; the game loads its public
OPL3 API through SDL_LoadObject. The bundle includes this exact source and its
license alongside the shared library. This library is used in OPL2-compatible
mode for Wolfenstein's original AdLib register streams.
