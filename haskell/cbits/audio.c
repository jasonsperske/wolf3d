/* Hardware boundary: Haskell validates/chooses resources and emits game events.
 * This callback owns OPL state, resampling, and mixing. No Haskell callbacks,
 * file IO, or allocations occur on the audio thread. OPL is replaceable .so. */
#include <SDL.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "../vendor/nuked-opl3/opl3.h"
#define RATE 44100
#define MAX_SOUNDS 100
static void *library;
static void (*opl_reset)(opl3_chip *, uint32_t);
static void (*opl_write)(opl3_chip *, uint16_t, uint8_t);
static void (*opl_sample)(opl3_chip *, int16_t *);
static opl3_chip music_chip, effect_chip;
static SDL_AudioDeviceID device;
static uint8_t *music, *pcm[MAX_SOUNDS], *adlib[MAX_SOUNDS];
static int music_size, music_pos, music_wait, pcm_size[MAX_SOUNDS], adlib_size[MAX_SOUNDS];
static int active_adlib = -1, adlib_pos, adlib_wait;
static struct { int sound; uint64_t frame; } voices[8];
static unsigned next_voice;
/* IDs are the original soundnames enum. Missing PCM falls back to AdLib. */
static int digital_index(int sound) {
    switch (sound) {
    case 21:return 0; case 41:return 1; case 19:return 2; case 18:return 3;
    case 26:return 4; case 24:return 5; case 11:return 6; case 51:return 7;
    case 55:return 8; case 50:return 9; case 59:return 10; case 60:return 11;
    case 29:return 12; case 22:case 25:return 13; case 16:return 14;
    case 46:return 15; case 58:return 21; default:return -1;
    }
}
static uint32_t u32(const uint8_t *p) { return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24); }
static void lock(void) { if(device) SDL_LockAudioDevice(device); }
static void unlock(void) { if(device) SDL_UnlockAudioDevice(device); }
void audio_close(void) {
    if(device) { SDL_CloseAudioDevice(device); device=0; }
    free(music); music=NULL; music_size=0;
    for(int i=0;i<MAX_SOUNDS;i++) {
        free(pcm[i]);pcm[i]=NULL;pcm_size[i]=0;
        free(adlib[i]);adlib[i]=NULL;adlib_size[i]=0;
    }
    if(library) { SDL_UnloadObject(library);library=NULL; }
}
int audio_prepare(const char *path) {
    audio_close();
    library=SDL_LoadObject(path);
    if(!library) return 0;
    opl_reset=(void(*)(opl3_chip*,uint32_t))SDL_LoadFunction(library,"OPL3_Reset");
    opl_write=(void(*)(opl3_chip*,uint16_t,uint8_t))SDL_LoadFunction(library,"OPL3_WriteReg");
    opl_sample=(void(*)(opl3_chip*,int16_t*))SDL_LoadFunction(library,"OPL3_GenerateResampled");
    if(!opl_reset || !opl_write || !opl_sample) { audio_close();return 0; }
    opl_reset(&music_chip,RATE);opl_reset(&effect_chip,RATE);
    opl_write(&music_chip,1,0x20);opl_write(&effect_chip,1,0x20);
    for(int i=0;i<8;i++) voices[i].sound=-1;
    next_voice=0;active_adlib=-1;music_pos=0;music_wait=0;
    return 1;
}
static int copy_data(uint8_t **target,int *length,const uint8_t *source,int size) {
    if(size<0 || size>1048576) return 0;
    uint8_t *copy=size?malloc((size_t)size):NULL;
    if(size && !copy) return 0;
    if(size) memcpy(copy,source,(size_t)size);
    lock();free(*target);*target=copy;*length=size;unlock();return 1;
}
int audio_music(const uint8_t *data,int size) {
    if(!library || size<=0 || size%4) return 0;
    if(!copy_data(&music,&music_size,data,size)) return 0;
    lock();music_pos=0;music_wait=0;opl_reset(&music_chip,RATE);opl_write(&music_chip,1,0x20);unlock();return 1;
}
int audio_pcm(int slot,const uint8_t *data,int size) {
    return slot>=0 && slot<MAX_SOUNDS && copy_data(&pcm[slot],&pcm_size[slot],data,size);
}
int audio_effect(int slot,const uint8_t *data,int size) {
    if(slot<0 || slot>=MAX_SOUNDS || (size && (size<23 || u32(data)>(uint32_t)(size-23)))) return 0;
    return copy_data(&adlib[slot],&adlib_size[slot],data,size);
}
void audio_play(int sound) {
    if(!library) return;
    lock();
    int digi=digital_index(sound);
    if(digi>=0 && pcm_size[digi]) {
        unsigned v=next_voice++%8;voices[v].sound=digi;voices[v].frame=0;
    } else if(sound>=0 && sound<MAX_SOUNDS && adlib_size[sound]>=23) {
        const uint8_t *instrument=adlib[sound]+6;
        static const int regs[5]={0x20,0x40,0x60,0x80,0xe0};
        opl_reset(&effect_chip,RATE);opl_write(&effect_chip,1,0x20);
        for(int i=0;i<5;i++) {
            opl_write(&effect_chip,(uint16_t)regs[i],instrument[i*2]);
            opl_write(&effect_chip,(uint16_t)(regs[i]+3),instrument[i*2+1]);
        }
        opl_write(&effect_chip,0xc0,instrument[10]);
        active_adlib=sound;adlib_pos=0;adlib_wait=0;
    }
    unlock();
}
/* Also used headlessly to export reproducible WAV previews. Only call manually
 * while the SDL device is stopped; the device callback otherwise owns state. */
void audio_render(int16_t *output,int frames) {
    for(int i=0;i<frames;i++) {
        int left=0,right=0;int16_t sample[2];
        if(library && music_size) {
            while(music_wait==0) {
                const uint8_t *e=music+music_pos;
                opl_write(&music_chip,e[0],e[1]);
                music_wait=(e[2]|(e[3]<<8))*63; /* 700 Hz IMF ticks */
                music_pos=(music_pos+4)%music_size;
            }
            --music_wait;opl_sample(&music_chip,sample);
            left+=sample[0]/2;right+=sample[1]/2;
        }
        if(library && active_adlib>=0) {
            const uint8_t *effect=adlib[active_adlib];
            if(adlib_wait==0) {
                if(adlib_pos>=(int)u32(effect)) { opl_write(&effect_chip,0xb0,0);active_adlib=-1; }
                else {
                    uint8_t freq=effect[23+adlib_pos++];
                    opl_write(&effect_chip,0xa0,freq);
                    opl_write(&effect_chip,0xb0,freq?(uint8_t)(((effect[22]&7)<<2)|0x20):0);
                    adlib_wait=315; /* 140 Hz effect notes */
                }
            }
            if(adlib_wait) --adlib_wait;
            opl_sample(&effect_chip,sample);left+=sample[0];right+=sample[1];
        }
        for(int v=0;v<8;v++) if(voices[v].sound>=0) {
            int slot=voices[v].sound;
            uint64_t index=voices[v].frame++*7042/RATE;
            if(index>=(uint64_t)pcm_size[slot]) voices[v].sound=-1;
            else { int value=((int)pcm[slot][index]-128)*64;left+=value;right+=value; }
        }
        output[i*2]=(int16_t)(left>32767?32767:left< -32768?-32768:left);
        output[i*2+1]=(int16_t)(right>32767?32767:right< -32768?-32768:right);
    }
}
static void callback(void *unused,uint8_t *stream,int length) {
    (void)unused;audio_render((int16_t*)stream,length/4);
}
int audio_start(void) {
    if(!library || SDL_InitSubSystem(SDL_INIT_AUDIO)!=0) return 0;
    SDL_AudioSpec wanted;SDL_zero(wanted);
    wanted.freq=RATE;wanted.format=AUDIO_S16SYS;wanted.channels=2;wanted.samples=1024;wanted.callback=callback;
    device=SDL_OpenAudioDevice(NULL,0,&wanted,NULL,0);
    if(!device) return 0;
    SDL_PauseAudioDevice(device,0);return 1;
}
