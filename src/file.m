#include "tachyon.h"

void clear_cache(AppState* app) {
    if (app->page_textures) {
        for (int i = 0; i < app->page_count; i++) {
            if (app->page_textures[i]) {
                SDL_DestroyTexture(app->page_textures[i]);
                app->page_textures[i] = NULL;
            }
        }
        free(app->page_textures);
        app->page_textures = NULL;
    }
    if (app->page_heights) {
        free(app->page_heights);
        app->page_heights = NULL;
    }
    if (app->orig_widths) {
        free(app->orig_widths);
        app->orig_widths = NULL;
    }
    if (app->orig_heights) {
        free(app->orig_heights);
        app->orig_heights = NULL;
    }
}

void load_document(AppState* app, const char* path) {
    if (app->doc) {
        clear_cache(app);
        fz_drop_document(app->ctx, app->doc);
        app->doc = NULL;
    }
    
    if (path == NULL || path[0] == '\0') return;

    fz_try(app->ctx) {
        app->doc = fz_open_document(app->ctx, path);
        app->page_count = fz_count_pages(app->ctx, app->doc);
        app->scroll_y = 0;
        app->scroll_x = 0;
        app->velocity_y = 0;
        app->velocity_x = 0;
        app->zoom = 0.5f;
        app->zoom_velocity = 0;
        
        printf("Opened: %s (%d pages)\n", path, app->page_count);
        
        
        app->orig_widths = (float*)calloc(app->page_count, sizeof(float));
        app->orig_heights = (float*)calloc(app->page_count, sizeof(float));
        
        for (int i = 0; i < app->page_count; i++) {
            fz_page* page = fz_load_page(app->ctx, app->doc, i);
            fz_rect bounds = fz_bound_page(app->ctx, page);
            fz_drop_page(app->ctx, page);
            app->orig_widths[i] = bounds.x1 - bounds.x0;
            app->orig_heights[i] = bounds.y1 - bounds.y0;
        }
        
        calculate_layout(app);
        
        char buf[64];
        snprintf(buf, 64, "Page 1 / %d", app->page_count);
        show_overlay(app, buf);
        
    } fz_catch(app->ctx) {
        printf("Failed to open document: %s\n", path);
    }
}
