#ifndef TACHYON_H
#define TACHYON_H

#import <Cocoa/Cocoa.h>
#include <SDL.h>
#include <SDL_ttf.h>
#include <mupdf/fitz.h>
#include <stdbool.h>

#define SCREEN_WIDTH 1280
#define SCREEN_HEIGHT 720
#define PAGE_GAP 20
#define FRICTION_DAMPING 10.0f
#define SCROLL_SENSITIVITY 120.0f
#define ZOOM_MIN 0.25f
#define ZOOM_MAX 4.0f
#define ZOOM_SENSITIVITY 0.05f

typedef struct {
    fz_context* ctx;
    fz_document* doc;
    int page_count;
    
    
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


@interface AppDelegate : NSObject <NSApplicationDelegate>
@end


void setup_menu(void);
void init_app_delegate(void); 
void load_document(AppState* app, const char* path);
void render(AppState* app);
void calculate_layout(AppState* app);
void clear_cache(AppState* app);
void set_zoom(AppState* app, float new_zoom, int center_x, int center_y);
void show_overlay(AppState* app, const char* text);
void update_physics(AppState* app, float dt);

#endif
