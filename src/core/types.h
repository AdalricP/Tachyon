#ifndef TYPES_H
#define TYPES_H

#import <Cocoa/Cocoa.h>
#include <SDL.h>
#include <SDL_ttf.h>
#include <mupdf/fitz.h>
#include <stdbool.h>

typedef struct {
    fz_context* ctx;
    fz_document* doc;
    int page_count;
    
    SDL_Color bg_color;
    bool pdf_dark_mode;
    
    float scroll_y;
    float scroll_x;       
    float velocity_y;
    float velocity_x;     
    int total_height;
    int max_width;        
    
    
    float zoom;
    float zoom_velocity;
    
    
    float overlay_timer;
    char overlay_text[64];
    float scrollbar_alpha;
    TTF_Font* font;
    SDL_Texture* overlay_texture;
    int overlay_w, overlay_h;

    
    SDL_Renderer* renderer;
    SDL_Texture** page_textures;
    int* page_heights;
    float* orig_widths;
    float* orig_heights;
    
    Uint32 last_time;
} AppState;

extern AppState* g_app;

#endif
