#include "ui.h"

void draw_circle(SDL_Renderer* renderer, int cx, int cy, int radius) {
    for (int w = 0; w < radius * 2; w++) {
        for (int h = 0; h < radius * 2; h++) {
            int dx = radius - w; 
            int dy = radius - h; 
            if ((dx*dx + dy*dy) <= (radius * radius)) {
                SDL_RenderDrawPoint(renderer, cx + dx, cy + dy);
            }
        }
    }
}

void draw_pill(SDL_Renderer* renderer, int x, int y, int w, int h) {
    if (h > w) {
        int r = w / 2;
        if (h < w) h = w; 
        
        SDL_Rect body = { x, y + r, w, h - 2*r };
        SDL_RenderFillRect(renderer, &body);
        
        int r2 = r*r;
        for (int dy = -r; dy <= r; dy++) {
            for (int dx = -r; dx <= r; dx++) {
                if (dx*dx + dy*dy <= r2) {
                     SDL_RenderDrawPoint(renderer, x + r + dx, y + r + dy); 
                     SDL_RenderDrawPoint(renderer, x + r + dx, y + h - r + dy); 
                }
            }
        }
    } else {
        int r = h / 2;
        if (w < h) w = h;
        
        SDL_Rect body = { x + r, y, w - 2*r, h };
        SDL_RenderFillRect(renderer, &body);
        
        int r2 = r*r;
        for (int dy = -r; dy <= r; dy++) {
            for (int dx = -r; dx <= r; dx++) {
                if (dx*dx + dy*dy <= r2) {
                     SDL_RenderDrawPoint(renderer, x + r + dx, y + r + dy); 
                     SDL_RenderDrawPoint(renderer, x + w - r + dx, y + r + dy); 
                }
            }
        }
    }
}

void draw_scrollbar(AppState* app) {
    if (app->scrollbar_alpha <= 0.0f) return;
    
    int win_w, win_h;
    SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
    
    int alpha = (int)(app->scrollbar_alpha * 255.0f);
    if (alpha > 255) alpha = 255;
    if (alpha <= 0) return;
    
    SDL_SetRenderDrawBlendMode(app->renderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(app->renderer, 100, 100, 100, alpha); 
    
    int thick = 12; 
    int margin = 4; 
    
    if (app->total_height > win_h) {
        float content_h = (float)app->total_height;
        float view_h = (float)win_h;
        float scroll_y = app->scroll_y;
        
        float thumb_h = (view_h / content_h) * view_h;
        if (thumb_h < 50) thumb_h = 50; 
        
        float max_scroll = content_h - view_h;
        float scroll_ratio = scroll_y / max_scroll;
        if (scroll_ratio < 0) scroll_ratio = 0;
        if (scroll_ratio > 1) scroll_ratio = 1;
        
        float thumb_y = scroll_ratio * (view_h - thumb_h);
        
        draw_pill(app->renderer, win_w - (thick + margin), (int)thumb_y, thick, (int)thumb_h);
    }
    
    if (app->max_width > win_w) {
         float content_w = (float)app->max_width;
         float view_w = (float)win_w;
         
         float overflow = content_w - view_w;
         float limit = overflow / 2.0f;
         
         float scroll_ratio = (app->scroll_x + limit) / overflow;
         if (scroll_ratio < 0) scroll_ratio = 0;
         if (scroll_ratio > 1) scroll_ratio = 1;
         
         float thumb_w = (view_w / content_w) * view_w;
         if (thumb_w < 50) thumb_w = 50;
         
         float thumb_x = scroll_ratio * (view_w - thumb_w);
         
         draw_pill(app->renderer, (int)thumb_x, win_h - (thick + margin), (int)thumb_w, thick);
    }
}
