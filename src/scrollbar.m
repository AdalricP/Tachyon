#include "tachyon.h"

// Helper to draw rounded rect
// Since SDL2 doesn't have native rounded rects, we can approximation it or use a library.
// For simplicity and speed, we will draw a main rect and 4 smaller rects, or just a normal rect if "perfect" rounding is too complex without textures.
// User asked for "border radius".
// We can use the SDL_RenderGeometry method to draw a perfect rounded rect if we wanted, but that's verbose.
// Let's stick to a clean rect for now, or maybe a simple "pill" shape (rect + 2 circles).
// Actually, let's keep it simple: RenderFillRect is fine, but maybe 2px padding.

// Helper to draw a filled circle (for rounded ends)
void draw_circle(SDL_Renderer* renderer, int cx, int cy, int radius) {
    for (int w = 0; w < radius * 2; w++) {
        for (int h = 0; h < radius * 2; h++) {
            int dx = radius - w; // horizontal offset
            int dy = radius - h; // vertical offset
            if ((dx*dx + dy*dy) <= (radius * radius)) {
                SDL_RenderDrawPoint(renderer, cx + dx, cy + dy);
            }
        }
    }
}

// Draw a pill (capsule) shape
// w is width, h is height.
// If vertical (h > w), radius is w/2.
// If horizontal (w > h), radius is h/2.
void draw_pill(SDL_Renderer* renderer, int x, int y, int w, int h) {
    if (h > w) {
        // Vertical Pill
        int r = w / 2;
        if (h < w) h = w; // Clamp
        
        // Top Circle
        // draw_circle is slow pixel-by-pixel, but for 12px radius perfectly fine
        // Actually, let's just use a cross-approximation for 'rounding' if pixel is too slow?
        // No, pixel drawing for r=6 (total ~100 pixels) is instant.
        
        // Body
        SDL_Rect body = { x, y + r, w, h - 2*r };
        SDL_RenderFillRect(renderer, &body);
        
        // Caps
        // We can optimize circle drawing or just use a small texture. 
        // Let's use the SDL_RenderGeometry approach for a "Circle" to be cleaner/faster?
        // Actually, at this size (12px), pure rect approximation is easiest for smooth look without anti-aliasing issues of manual points.
        // Let's compromise: "Beveled" look (3 rects) looks decent at small sizes.
        //   [XX]
        // [XXXXXX]
        // [XXXXXX]
        //   [XX]
        
        // Detailed approach:
        int r2 = r*r;
        for (int dy = -r; dy <= r; dy++) {
            for (int dx = -r; dx <= r; dx++) {
                if (dx*dx + dy*dy <= r2) {
                     SDL_RenderDrawPoint(renderer, x + r + dx, y + r + dy); // Top Cap center
                     SDL_RenderDrawPoint(renderer, x + r + dx, y + h - r + dy); // Bot Cap center
                }
            }
        }
    } else {
        // Horizontal Pill
        int r = h / 2;
        if (w < h) w = h;
        
        SDL_Rect body = { x + r, y, w - 2*r, h };
        SDL_RenderFillRect(renderer, &body);
        
        int r2 = r*r;
        for (int dy = -r; dy <= r; dy++) {
            for (int dx = -r; dx <= r; dx++) {
                if (dx*dx + dy*dy <= r2) {
                     SDL_RenderDrawPoint(renderer, x + r + dx, y + r + dy); // Left Cap
                     SDL_RenderDrawPoint(renderer, x + w - r + dx, y + r + dy); // Right Cap
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
    SDL_SetRenderDrawColor(app->renderer, 100, 100, 100, alpha); // Greyish thumb
    
    // Thickness
    int thick = 12; // Slightly thicker than 8
    int margin = 4; // Gap from edge
    
    // --- Vertical Scrollbar ---
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
        
        // Draw Thumb
        draw_pill(app->renderer, win_w - (thick + margin), (int)thumb_y, thick, (int)thumb_h);
    }
    
    // --- Horizontal Scrollbar ---
    if (app->max_width > win_w) {
         float content_w = (float)app->max_width;
         float view_w = (float)win_w;
         
         float overflow = content_w - view_w;
         float limit = overflow / 2.0f;
         
         // Physics uses range [-limit, +limit]
         // Map to [0, 1]
         float scroll_ratio = (app->scroll_x + limit) / overflow;
         if (scroll_ratio < 0) scroll_ratio = 0;
         if (scroll_ratio > 1) scroll_ratio = 1;
         
         float thumb_w = (view_w / content_w) * view_w;
         if (thumb_w < 50) thumb_w = 50;
         
         float thumb_x = scroll_ratio * (view_w - thumb_w);
         
         draw_pill(app->renderer, (int)thumb_x, win_h - (thick + margin), (int)thumb_w, thick);
    }
}
