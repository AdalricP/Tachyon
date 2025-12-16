#ifndef TYPES_H
#define TYPES_H

#import <Cocoa/Cocoa.h>
#include <SDL.h>
#include <SDL_ttf.h>
#include <SDL_ttf.h>
#include <mupdf/fitz.h>
#include <stdbool.h>
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>

typedef struct {
    CGRect bbox; // Normalized 0..1
    char* text; 
} OCRWord;

typedef struct {
    OCRWord* words;
    int word_count;
    bool is_processed;
} OCRPage;

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
    float* texture_zoom;  // Zoom level each texture was rendered at
    int* page_heights;
    float* orig_widths;
    float* orig_heights;
    float* page_offsets_x;
    float* page_offsets_y;
    
    Uint32 last_time;

    // Text Selection
    fz_stext_page** page_text_cache; // Array of pointers, lazy loaded
    
    OCRPage** ocr_cache; // Array of pointers to OCRPage

    bool is_selecting;
    fz_point drag_start;
    fz_point drag_end;
    int sel_start_page;
    int sel_end_page;
} AppState;

extern AppState* g_app;

#endif
