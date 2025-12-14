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

    // Invert Colors only if Background is Dark
    // Calculate brightness of BG
    int bg_brightness = (app->bg_color.r + app->bg_color.g + app->bg_color.b) / 3;
    bool dark_mode = (bg_brightness < 128); // Threshold

    if (dark_mode) {
        unsigned char* samples = fz_pixmap_samples(app->ctx, pix);
        int w = fz_pixmap_width(app->ctx, pix);
        int h = fz_pixmap_height(app->ctx, pix);
        int n = fz_pixmap_components(app->ctx, pix); 
        int stride = fz_pixmap_stride(app->ctx, pix); 
        
        for (int y = 0; y < h; y++) {
            unsigned char* p = samples + y * stride;
            for (int x = 0; x < w; x++) {
                 p[0] = 255 - p[0]; // R
                 p[1] = 255 - p[1]; // G
                 p[2] = 255 - p[2]; // B
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

void render(AppState* app) {
    // --- Background Gradient ---
    int win_w, win_h;
    SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
    
    SDL_Color top_col = app->bg_color;
    SDL_Color bot_col = app->bg_color;
    
    // Extremely subtle gradient
    // If Dark: Top is slightly lighter
    // If Light: Top is slightly lighter (closer to white)
    // "Light & Desaturated on top"
    
    int brightness = (app->bg_color.r + app->bg_color.g + app->bg_color.b) / 3;
    float mix_factor = 0.4f; // 40% mix with target
    
    if (brightness < 128) {
        // Dark Mode: Mix with Lighter Grey {60,60,60}
        // Actually user said "light & desaturated on top" and "actual colour at bottom"
        // For dark mode, "lighter" means higher values.
        top_col.r = (Uint8)((int)top_col.r * (1.0f - mix_factor) + 50 * mix_factor);
        top_col.g = (Uint8)((int)top_col.g * (1.0f - mix_factor) + 50 * mix_factor);
        top_col.b = (Uint8)((int)top_col.b * (1.0f - mix_factor) + 50 * mix_factor);
    } else {
        // Light Mode: Mix with White {255,255,255}
        top_col.r = (Uint8)((int)top_col.r * (1.0f - mix_factor) + 255 * mix_factor);
        top_col.g = (Uint8)((int)top_col.g * (1.0f - mix_factor) + 255 * mix_factor);
        top_col.b = (Uint8)((int)top_col.b * (1.0f - mix_factor) + 255 * mix_factor);
    }

    SDL_Vertex verts[4] = {
        { {0, 0}, top_col, {0, 0} },
        { {(float)win_w, 0}, top_col, {0, 0} },
        { {(float)win_w, (float)win_h}, bot_col, {0, 0} },
        { {0, (float)win_h}, bot_col, {0, 0} }
    };
    int indices[6] = {0, 1, 2, 2, 3, 0};
    
    SDL_RenderGeometry(app->renderer, NULL, verts, 4, indices, 6);
    // No RenderClear needed as we cover screen

    if (!app->doc) {
        SDL_RenderPresent(app->renderer);
        return;
    }
    
    float current_y = 0.0f; 
    int view_h = win_h;
    float view_top = app->scroll_y;
    int view_width = win_w; // Unused variable warning fix? used in x_pos
    float view_left = app->scroll_x;
    int buffer_y = 2000; 

    // 1. Calculate Current Page Index (Center of View)
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

    // 2. Define Buffer Range
    int buffer_range = 3;
    int load_start = current_page_index - buffer_range;
    int load_end = current_page_index + buffer_range;

    // 3. Render Loop & Throttled Loading
    // Strategy:
    // - Always load visible pages immediately.
    // - Load AT MOST 1 buffer page per frame to prevent stutter.
    
    int pages_uploaded_this_frame = 0;
    int max_background_uploads = 1;
    
    current_y = 0.0f; // Reset for actual rendering
    for (int i = 0; i < app->page_count; i++) {
        int page_h = app->page_heights[i];
        
        bool visible_y = (current_y + page_h + PAGE_GAP > view_top - buffer_y && current_y < view_top + view_h + buffer_y);
        bool in_buffer = (i >= load_start && i <= load_end);

        // Logic:
        // 1. If visible and not loaded -> Load IMMEDIATELY (Priority)
        // 2. If in_buffer and not loaded -> Load ONLY if quota allows
        // 3. If !visible and !in_buffer -> Unload
        
        bool should_retain = (visible_y || in_buffer);
        
        if (should_retain) {
            if (!app->page_textures[i]) {
                // Determine if we should load now
                bool force_load = visible_y;
                bool background_load = in_buffer && !visible_y && (pages_uploaded_this_frame < max_background_uploads);
                
                if (force_load || background_load) {
                    app->page_textures[i] = render_page_to_texture(app, i);
                    if (!force_load) {
                        pages_uploaded_this_frame++;
                    }
                }
            }
            
            // Only draw if actually visible and loaded
            if (visible_y && app->page_textures[i]) {
                int w, h;
                SDL_QueryTexture(app->page_textures[i], NULL, NULL, &w, &h);
                
                float x_pos;
                if (w < view_width) {
                    x_pos = (float)((view_width - w) / 2); 
                } else {
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
            // Unload if NOT visible AND NOT in buffer
            if (app->page_textures[i]) {
                SDL_DestroyTexture(app->page_textures[i]);
                app->page_textures[i] = NULL;
            }
        }
        
        current_y += (float)(page_h + PAGE_GAP);
    }
    
    // --- Edge Fades ---
    int fade_h = 100;
    
    // Top Fade: Uses Top Gradient Color
    SDL_DisplayMode dm;
    SDL_GetCurrentDisplayMode(0, &dm); // Just to get struct, actually unused here
    
    // Top Rect: Starts at 0 with top_col, fades to transparent
    SDL_Vertex fade_top[4] = {
        { {0, 0}, top_col, {0, 0} },
        { {(float)win_w, 0}, top_col, {0, 0} },
        { {(float)win_w, (float)fade_h}, {top_col.r, top_col.g, top_col.b, 0}, {0, 0} },
        { {0, (float)fade_h}, {top_col.r, top_col.g, top_col.b, 0}, {0, 0} }
    };
    SDL_RenderGeometry(app->renderer, NULL, fade_top, 4, indices, 6);
    
    // Bottom Rect: Starts at H-fade_h with transparent, ends at H with bot_col
    SDL_Vertex fade_bot[4] = {
        { {0, (float)win_h - fade_h}, {bot_col.r, bot_col.g, bot_col.b, 0}, {0, 0} },
        { {(float)win_w, (float)win_h - fade_h}, {bot_col.r, bot_col.g, bot_col.b, 0}, {0, 0} },
        { {(float)win_w, (float)win_h}, bot_col, {0, 0} },
        { {0, (float)win_h}, bot_col, {0, 0} }
    };
    SDL_RenderGeometry(app->renderer, NULL, fade_bot, 4, indices, 6);

    
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
    
    draw_scrollbar(app);
    
    SDL_RenderPresent(app->renderer);
}
