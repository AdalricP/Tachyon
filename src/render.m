#include "tachyon.h"

void calculate_layout(AppState* app) {
    if (!app->doc) return;
    
    if (app->page_heights) free(app->page_heights);
    if (!app->page_textures) {
        app->page_textures = (SDL_Texture**)calloc(app->page_count, sizeof(SDL_Texture*));
    }
    app->page_heights = (int*)calloc(app->page_count, sizeof(int));
    
    int total = 0;
    int win_w, win_h;
    SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
    
    float max_w = 0;
    
    for (int i = 0; i < app->page_count; i++) {
        float page_w_points = app->orig_widths[i];
        float page_h_points = app->orig_heights[i];
        
        
        float base_scale = (float)(win_w - 40) / page_w_points;
        float final_scale = base_scale * app->zoom;
        
        int page_h = (int)(page_h_points * final_scale);
        int page_w = (int)(page_w_points * final_scale);
        
        if (page_w > max_w) max_w = page_w;
        
        app->page_heights[i] = page_h;
        total += page_h + PAGE_GAP;
    }
    app->total_height = total;
    app->max_width = (int)max_w;
}

void show_overlay(AppState* app, const char* text) {
    snprintf(app->overlay_text, sizeof(app->overlay_text), "%s", text);
    app->overlay_timer = 2.0f; 
    
    if (app->overlay_texture) {
        SDL_DestroyTexture(app->overlay_texture);
        app->overlay_texture = NULL;
    }
    
    if (app->font) {
        SDL_Color color = {255, 255, 255, 255};
        SDL_Surface* surf = TTF_RenderText_Blended(app->font, text, color);
        if (surf) {
            app->overlay_texture = SDL_CreateTextureFromSurface(app->renderer, surf);
            app->overlay_w = surf->w;
            app->overlay_h = surf->h;
            SDL_FreeSurface(surf);
        }
    }
}

SDL_Texture* render_page_to_texture(AppState* app, int page_num) {
    fz_page* page = fz_load_page(app->ctx, app->doc, page_num);
    
    int win_w, win_h;
    SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
    
    float page_w_points = app->orig_widths[page_num];
    float base_scale = (float)(win_w - 40) / page_w_points;
    float final_scale = base_scale * app->zoom;
    
    fz_matrix transform = fz_scale(final_scale, final_scale);
    fz_pixmap* pix = fz_new_pixmap_from_page_number(app->ctx, app->doc, page_num, transform, fz_device_rgb(app->ctx), 0);
    fz_drop_page(app->ctx, page);

    if (!pix) return NULL;
    
    SDL_Surface* surf = SDL_CreateRGBSurfaceFrom(
        fz_pixmap_samples(app->ctx, pix),
        fz_pixmap_width(app->ctx, pix),
        fz_pixmap_height(app->ctx, pix),
        24,
        fz_pixmap_stride(app->ctx, pix),
        0x000000FF, 0x0000FF00, 0x00FF0000, 0
    );
    
    SDL_Texture* texture = SDL_CreateTextureFromSurface(app->renderer, surf);
    SDL_FreeSurface(surf);
    fz_drop_pixmap(app->ctx, pix);
    
    return texture;
}

void render(AppState* app) {
    SDL_SetRenderDrawColor(app->renderer, 30, 30, 30, 255);
    SDL_RenderClear(app->renderer);

    if (!app->doc) {
        SDL_RenderPresent(app->renderer);
        return;
    }
    
    int win_w, win_h;
    SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
    
    float current_y = 0.0f; 
    
    int view_h = win_h;
    float view_top = app->scroll_y;
    
    
    
    
    
    
    
    int view_width = win_w;
    float view_left = app->scroll_x;
    
    int buffer_y = 2000; 
    
    
    int current_page_index = -1;
    
    for (int i = 0; i < app->page_count; i++) {
        int page_h = app->page_heights[i];
        
        bool visible_y = (current_y + page_h + PAGE_GAP > view_top - buffer_y && current_y < view_top + view_h + buffer_y);
        
        if (current_y <= view_top + view_h/2 && current_y + page_h >= view_top + view_h/2) {
             current_page_index = i + 1;
        }
        
        if (visible_y) {
            if (!app->page_textures[i]) {
                app->page_textures[i] = render_page_to_texture(app, i);
            }
            
            if (app->page_textures[i]) {
                int w, h;
                SDL_QueryTexture(app->page_textures[i], NULL, NULL, &w, &h);
                
                
                float x_pos;
                if (w < view_width) {
                    x_pos = (float)((view_width - w) / 2); 
                } else {
                    x_pos = -view_left; 
                    
                    
                    
                    
                    
                    
                    
                    
                    
                    
                    
                    x_pos = (float)((view_width - w) / 2) - view_left;
                }
                
                SDL_FRect dest;
                dest.x = x_pos;
                dest.y = current_y - view_top; 
                dest.w = (float)w;
                dest.h = (float)h;
                
                SDL_RenderCopyF(app->renderer, app->page_textures[i], NULL, &dest);
            }
        } else {
            if (app->page_textures[i]) {
                SDL_DestroyTexture(app->page_textures[i]);
                app->page_textures[i] = NULL;
            }
        }
        
        current_y += (float)(page_h + PAGE_GAP);
    }
    
    
    static int last_page = -1;
    if (current_page_index != -1 && current_page_index != last_page) {
        if (app->overlay_timer <= 0 || strncmp(app->overlay_text, "Zoom", 4) != 0) {
            char buf[64];
            snprintf(buf, 64, "Page %d / %d", current_page_index, app->page_count);
            show_overlay(app, buf);
        }
        last_page = current_page_index;
    }
    
    
    if (app->overlay_timer > 0 && app->overlay_texture) {
        int alpha = 255;
        if (app->overlay_timer < 0.5f) {
            alpha = (int)(255 * (app->overlay_timer / 0.5f));
        }
        SDL_SetTextureAlphaMod(app->overlay_texture, alpha);
        
        SDL_SetRenderDrawColor(app->renderer, 0, 0, 0, 150 * (alpha/255.0f));
        SDL_SetRenderDrawBlendMode(app->renderer, SDL_BLENDMODE_BLEND);
        
        int box_w = app->overlay_w + 40;
        int box_h = app->overlay_h + 20;
        SDL_Rect box = { (win_w - box_w)/2, win_h - 100, box_w, box_h };
        SDL_RenderFillRect(app->renderer, &box);
        
        SDL_Rect text_rect = { (win_w - app->overlay_w)/2, win_h - 100 + 10, app->overlay_w, app->overlay_h };
        SDL_RenderCopy(app->renderer, app->overlay_texture, NULL, &text_rect);
    }
    
    SDL_RenderPresent(app->renderer);
}
