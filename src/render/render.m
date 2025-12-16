#include "render.h"
#include "render.h"
#include "render_async.h"
#include "../ui/ui.h"
#include "../text_selection.h"
#include <math.h>

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

    if (app->pdf_dark_mode) {
        unsigned char* samples = fz_pixmap_samples(app->ctx, pix);
        int w = fz_pixmap_width(app->ctx, pix);
        int h = fz_pixmap_height(app->ctx, pix);
        int n = fz_pixmap_components(app->ctx, pix); 
        int stride = fz_pixmap_stride(app->ctx, pix); 
        
        for (int y = 0; y < h; y++) {
            unsigned char* p = samples + y * stride;
            for (int x = 0; x < w; x++) {
                 p[0] = 255 - p[0]; 
                 p[1] = 255 - p[1]; 
                 p[2] = 255 - p[2]; 
                 p += n;
            }
        }
    }
    
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

void clear_texture_cache(AppState* app) {
    for (int i = 0; i < app->page_count; i++) {
        if (app->page_textures[i]) {
            SDL_DestroyTexture(app->page_textures[i]);
            app->page_textures[i] = NULL;
        }
    }
}

void render(AppState* app) {
    int win_w, win_h;
    SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
    
    SDL_Color top_col = app->bg_color;
    SDL_Color bot_col = app->bg_color;
    
    bool rsvp_active = (app->rsvp && app->rsvp->active);
    
    if (rsvp_active) {
        if (app->pdf_dark_mode) {
            top_col = (SDL_Color){0, 0, 0, 255};
            bot_col = (SDL_Color){0, 0, 0, 255};
        } else {
            top_col = (SDL_Color){255, 255, 255, 255};
            bot_col = (SDL_Color){255, 255, 255, 255};
        }
    } else {
        int brightness = (app->bg_color.r + app->bg_color.g + app->bg_color.b) / 3;
        float mix_factor = 0.4f; 
        
        if (brightness < 128) {
            top_col.r = (Uint8)((int)top_col.r * (1.0f - mix_factor) + 50 * mix_factor);
            top_col.g = (Uint8)((int)top_col.g * (1.0f - mix_factor) + 50 * mix_factor);
            top_col.b = (Uint8)((int)top_col.b * (1.0f - mix_factor) + 50 * mix_factor);
        } else {
            top_col.r = (Uint8)((int)top_col.r * (1.0f - mix_factor) + 255 * mix_factor);
            top_col.g = (Uint8)((int)top_col.g * (1.0f - mix_factor) + 255 * mix_factor);
            top_col.b = (Uint8)((int)top_col.b * (1.0f - mix_factor) + 255 * mix_factor);
        }
    }

    SDL_Vertex verts[4] = {
        { {0, 0}, top_col, {0, 0} },
        { {(float)win_w, 0}, top_col, {0, 0} },
        { {(float)win_w, (float)win_h}, bot_col, {0, 0} },
        { {0, (float)win_h}, bot_col, {0, 0} }
    };
    int indices[6] = {0, 1, 2, 2, 3, 0};
    
    SDL_RenderGeometry(app->renderer, NULL, verts, 4, indices, 6);

    if (!app->doc) {
        SDL_RenderPresent(app->renderer);
        return;
    }
    
    RenderResult* result;
    while ((result = poll_completed_render()) != NULL) {
        if (result->page_num >= 0 && result->page_num < app->page_count) {
            if (app->page_textures[result->page_num]) {
                SDL_DestroyTexture(app->page_textures[result->page_num]);
            }
            
            SDL_Surface* surf = SDL_CreateRGBSurfaceFrom(
                result->pixels,
                result->width,
                result->height,
                24,
                result->stride,
                0x000000FF, 0x0000FF00, 0x00FF0000, 0
            );
            
            app->page_textures[result->page_num] = SDL_CreateTextureFromSurface(app->renderer, surf);
            app->texture_zoom[result->page_num] = app->zoom;
            SDL_FreeSurface(surf);
        }
        free_render_result(result);
    }
    
    float current_y = 0.0f; 
    int view_h = win_h;
    float view_top = app->scroll_y;
    int view_width = win_w; 
    float view_left = app->scroll_x;
    int buffer_y = 2000; 

    int current_page_index = 0;
    float temp_y = 0;
    for (int i = 0; i < app->page_count; i++) {
        int page_h = app->page_heights[i];
        if (view_top + view_h/2 >= temp_y && view_top + view_h/2 <= temp_y + page_h + PAGE_GAP) {
            current_page_index = i;
            break;
        }
        temp_y += page_h + PAGE_GAP;
    }

    int buffer_range = 2;
    int load_start = current_page_index - buffer_range;
    int load_end = current_page_index + buffer_range;
    if (load_start < 0) load_start = 0;
    if (load_end >= app->page_count) load_end = app->page_count - 1;
    
    int renders_this_frame = 0;
    int max_renders_per_frame = 1;
    
    current_y = 0.0f; 
    for (int i = 0; i < app->page_count; i++) {
        int page_h = app->page_heights[i];
        float page_w_points = app->orig_widths[i];
        float base_scale = (float)(win_w - 40) / page_w_points;
        int expected_w = (int)(page_w_points * base_scale * app->zoom);
        
        bool visible_y = (current_y + page_h + PAGE_GAP > view_top - buffer_y && current_y < view_top + view_h + buffer_y);
        bool in_buffer = (i >= load_start && i <= load_end);
        bool should_load = in_buffer && renders_this_frame < max_renders_per_frame;
        
        bool has_texture = app->page_textures[i] != NULL;
        bool is_stale = has_texture && (fabsf(app->texture_zoom[i] - app->zoom) > 0.01f);
        bool needs_render = (!has_texture || is_stale) && !is_page_render_pending(i);
        
        if (should_load && needs_render) {
            request_page_render(app, i, base_scale);
            renders_this_frame++;
        }
        
        if (!in_buffer && !visible_y && has_texture) {
            SDL_DestroyTexture(app->page_textures[i]);
            app->page_textures[i] = NULL;
        }
        
        if (visible_y && has_texture) {
            SDL_FRect dest;
            dest.x = (float)((view_width - expected_w) / 2) - view_left;
            dest.y = current_y - view_top;
            dest.w = (float)expected_w;
            dest.h = (float)page_h;
            
            SDL_RenderCopyF(app->renderer, app->page_textures[i], NULL, &dest);
        }
        
        current_y += (float)(page_h + PAGE_GAP);
    }
    
    int fade_h = 100;
    
    SDL_DisplayMode dm;
    SDL_GetCurrentDisplayMode(0, &dm); 
    
    SDL_Vertex fade_top[4] = {
        { {0, 0}, top_col, {0, 0} },
        { {(float)win_w, 0}, top_col, {0, 0} },
        { {(float)win_w, (float)fade_h}, {top_col.r, top_col.g, top_col.b, 0}, {0, 0} },
        { {0, (float)fade_h}, {top_col.r, top_col.g, top_col.b, 0}, {0, 0} }
    };
    SDL_RenderGeometry(app->renderer, NULL, fade_top, 4, indices, 6);
    
    SDL_Vertex fade_bot[4] = {
        { {0, (float)win_h - fade_h}, {bot_col.r, bot_col.g, bot_col.b, 0}, {0, 0} },
        { {(float)win_w, (float)win_h - fade_h}, {bot_col.r, bot_col.g, bot_col.b, 0}, {0, 0} },
        { {(float)win_w, (float)win_h}, bot_col, {0, 0} },
        { {0, (float)win_h}, bot_col, {0, 0} }
    };
    SDL_RenderGeometry(app->renderer, NULL, fade_bot, 4, indices, 6);

    static int last_page = -1;
    
    draw_selection_overlay(app);
    
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
    
    draw_scrollbar(app);
}
