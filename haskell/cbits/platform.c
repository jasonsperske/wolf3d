/* Platform mechanics only. All game rules, raycasting, and pixels are Haskell.
 * One owner and one cleanup path keep this deliberately small FFI auditable. */
#include <SDL.h>
#include <stdint.h>
static SDL_Window *window;
static SDL_Renderer *renderer;
static SDL_Texture *texture;
void platform_close(void) {
    SDL_DestroyTexture(texture); texture = NULL;
    SDL_DestroyRenderer(renderer); renderer = NULL;
    SDL_DestroyWindow(window); window = NULL;
    SDL_Quit();
}
const char *platform_error(void) { return SDL_GetError(); }
int platform_open(void) {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER) != 0) return 0;
    window = SDL_CreateWindow("Haskell Wolf | WASD move, arrows turn, E door, Space fire, R restart, Esc quit",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 960, 600, SDL_WINDOW_RESIZABLE);
    if (!window) return 0;
    renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer) renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
    if (!renderer) return 0;
    SDL_RenderSetLogicalSize(renderer, 320, 200);
    texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, 320, 200);
    return texture != NULL;
}
/* Stable bit layout avoids exposing SDL structs or enum values to Haskell. */
uint32_t platform_input(void) {
    SDL_Event event;
    uint32_t bits = 0;
    while (SDL_PollEvent(&event)) if (event.type == SDL_QUIT) bits |= 1;
    const uint8_t *k = SDL_GetKeyboardState(NULL);
    if (k[SDL_SCANCODE_ESCAPE]) bits |= 1;
    if (k[SDL_SCANCODE_W] || k[SDL_SCANCODE_UP]) bits |= 2;
    if (k[SDL_SCANCODE_S] || k[SDL_SCANCODE_DOWN]) bits |= 4;
    if (k[SDL_SCANCODE_A]) bits |= 8;
    if (k[SDL_SCANCODE_D]) bits |= 16;
    if (k[SDL_SCANCODE_LEFT]) bits |= 32;
    if (k[SDL_SCANCODE_RIGHT]) bits |= 64;
    if (k[SDL_SCANCODE_E]) bits |= 128;
    if (k[SDL_SCANCODE_SPACE]) bits |= 256;
    if (k[SDL_SCANCODE_R]) bits |= 512;
    return bits;
}
int platform_present(const uint32_t *pixels, int state, int hp, int remaining) {
    char title[256];
    SDL_snprintf(title, sizeof title, "Haskell Wolf | Health %d | Guards %d | %s | WASD / arrows / E / Space / R / Esc",
        hp, remaining, state == 1 ? "ESCAPED! R to restart" : state == 2 ? "DEFEATED - R to restart" : "Find green exit / E at elevator");
    SDL_SetWindowTitle(window, title);
    if (SDL_UpdateTexture(texture, NULL, pixels, 320 * sizeof(uint32_t)) != 0) return 0;
    if (SDL_RenderClear(renderer) != 0) return 0;
    if (SDL_RenderCopy(renderer, texture, NULL, NULL) != 0) return 0;
    SDL_RenderPresent(renderer);
    return 1;
}
double platform_time(void) { return (double)SDL_GetPerformanceCounter() / (double)SDL_GetPerformanceFrequency(); }
void platform_delay(void) { SDL_Delay(1); }
