#include "text_selection.h"
#include "render/render.h"
#include "ocr/ocr.h"
#include <SDL.h>

void init_text_selection(AppState* app) {
    if (!app->page_text_cache && app->page_count > 0) {
        app->page_text_cache = (fz_stext_page**)calloc(app->page_count, sizeof(fz_stext_page*));
    }
    app->is_selecting = false;
    app->sel_start_page = -1;
    app->sel_end_page = -1;
    init_ocr(app);
}

void cleanup_text_selection(AppState* app) {
    if (app->page_text_cache) {
        for (int i = 0; i < app->page_count; i++) {
            if (app->page_text_cache[i]) {
                fz_drop_stext_page(app->ctx, app->page_text_cache[i]);
            }
        }
        free(app->page_text_cache);
        app->page_text_cache = NULL;
    }
    cleanup_ocr(app);
}

static void ensure_stext_page(AppState* app, int page_num) {
    if (!app->page_text_cache[page_num]) {
        fz_page* page = fz_load_page(app->ctx, app->doc, page_num);
        app->page_text_cache[page_num] = fz_new_stext_page(app->ctx, fz_bound_page(app->ctx, page));
        fz_device* dev = fz_new_stext_device(app->ctx, app->page_text_cache[page_num], NULL);
        fz_run_page(app->ctx, page, dev, fz_identity, NULL);
        fz_close_device(app->ctx, dev);
        fz_drop_device(app->ctx, dev);
        fz_drop_page(app->ctx, page);
        
        fz_stext_page* sp = app->page_text_cache[page_num];
        if (!sp->first_block) {
             perform_ocr_if_needed(app, page_num);
        }
    }
}

static bool map_window_to_page(AppState* app, int win_x, int win_y, int* page_out, fz_point* pt_out) {
    int win_w, win_h;
    SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
    
    int log_w, log_h;
    SDL_Window* window = SDL_RenderGetWindow(app->renderer);
    SDL_GetWindowSize(window, &log_w, &log_h);
    
    float dpi_scale_x = (float)win_w / (float)log_w;
    float dpi_scale_y = (float)win_h / (float)log_h;
    
    float phys_x = win_x * dpi_scale_x;
    float phys_y = win_y * dpi_scale_y;
    
    float current_y = 0.0f;
    float view_top = app->scroll_y;
    
    for (int i = 0; i < app->page_count; i++) {
        int page_h_pixels = app->page_heights[i];
        float page_w_points = app->orig_widths[i];
        
        float base_scale = (float)(win_w - 40) / page_w_points;
        float final_scale = base_scale * app->zoom;
        int page_w_pixels = (int)(page_w_points * final_scale);

        float page_start_y = current_y - view_top;
        float page_end_y = page_start_y + page_h_pixels;

        if (phys_y >= page_start_y && phys_y <= page_end_y) {
            float x_pos;
            if (page_w_pixels < win_w) {
                x_pos = (float)((win_w - page_w_pixels) / 2);
            } else {
                x_pos = (float)((win_w - page_w_pixels) / 2) - app->scroll_x;
            }

            if (phys_x >= x_pos && phys_x <= x_pos + page_w_pixels) {
                *page_out = i;
                pt_out->x = (phys_x - x_pos) / final_scale + app->page_offsets_x[i];
                pt_out->y = (phys_y - page_start_y) / final_scale + app->page_offsets_y[i];
                return true;
            }
        }
        
        current_y += page_h_pixels + PAGE_GAP;
    }
    return false;
}

void handle_mouse_down(AppState* app, int x, int y) {
    int page;
    fz_point pt;
    if (map_window_to_page(app, x, y, &page, &pt)) {
        app->is_selecting = true;
        app->sel_start_page = page;
        app->sel_end_page = page;
        app->drag_start = pt;
        app->drag_end = pt;
        
        ensure_stext_page(app, page);
    } else {
        app->is_selecting = false;
        app->sel_start_page = -1;
    }
}

void handle_mouse_drag(AppState* app, int x, int y) {
    if (!app->is_selecting) return;
    
    int page;
    fz_point pt;
    if (map_window_to_page(app, x, y, &page, &pt)) {
        app->sel_end_page = page;
        app->drag_end = pt;
        ensure_stext_page(app, page);
    }
}

void handle_mouse_up(AppState* app, int x, int y) {
    (void)x; (void)y;
}

static SDL_Cursor* g_cursor_arrow = NULL;
static SDL_Cursor* g_cursor_ibeam = NULL;

void update_cursor_for_position(AppState* app, int x, int y) {
    if (!g_cursor_arrow) {
        g_cursor_arrow = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_ARROW);
        g_cursor_ibeam = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_IBEAM);
    }
    
    int page;
    fz_point pt;
    if (map_window_to_page(app, x, y, &page, &pt)) {
        SDL_SetCursor(g_cursor_ibeam);
    } else {
        SDL_SetCursor(g_cursor_arrow);
    }
}

void draw_selection_overlay(AppState* app) {
    if (!app->is_selecting || app->sel_start_page == -1) return;
    
    int start = app->sel_start_page < app->sel_end_page ? app->sel_start_page : app->sel_end_page;
    int end = app->sel_start_page > app->sel_end_page ? app->sel_start_page : app->sel_end_page;
    
    fz_point p_start = app->drag_start;
    fz_point p_end = app->drag_end;
    (void)p_start; (void)p_end;
    
    if (app->sel_start_page > app->sel_end_page) {
        p_start = app->drag_end;
        p_end = app->drag_start;
    }

    int win_w, win_h;
    SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
    SDL_SetRenderDrawBlendMode(app->renderer, SDL_BLENDMODE_BLEND);
    SDL_SetRenderDrawColor(app->renderer, 0, 100, 255, 100);

    float current_y = 0;
    float view_top = app->scroll_y;

    for (int i = 0; i < app->page_count; i++) {
        int page_h_pixels = app->page_heights[i];
        float page_w_points = app->orig_widths[i];
        
        float base_scale = (float)(win_w - 40) / page_w_points;
        float final_scale = base_scale * app->zoom;
        int page_w_pixels = (int)(page_w_points * final_scale);
        
        float page_start_y = current_y - view_top;
        float x_pos;
        if (page_w_pixels < win_w) {
            x_pos = (float)((win_w - page_w_pixels) / 2);
        } else {
            x_pos = (float)((win_w - page_w_pixels) / 2) - app->scroll_x;
        }

        if (i >= start && i <= end) {
            if (ensure_stext_page(app, i), app->page_text_cache[i]) {
                fz_point a = {0, 0}; 
                fz_point b = {99999, 99999};

                if (i == app->sel_start_page && i == app->sel_end_page) {
                     a = app->drag_start;
                     b = app->drag_end;
                } else if (i == start) {
                     if (app->sel_start_page == start) a = app->drag_start;
                     else a = app->drag_end; 
                } else if (i == end) {
                     if (app->sel_end_page == end) b = app->drag_end;
                     else b = app->drag_start;
                     a.x = 0; a.y = 0;
                }

                OCRPage* ocr = (app->ocr_cache && i < app->page_count) ? app->ocr_cache[i] : NULL;
                bool use_ocr = (ocr && ocr->word_count > 0);
                
                if (use_ocr) {
                    float x0 = a.x < b.x ? a.x : b.x;
                    float y0 = a.y < b.y ? a.y : b.y;
                    float x1 = a.x > b.x ? a.x : b.x;
                    float y1 = a.y > b.y ? a.y : b.y;
                    
                    for (int w = 0; w < ocr->word_count; w++) {
                        OCRWord word = ocr->words[w];
                        
                        float wx = word.bbox.origin.x * page_w_points;
                        float wy = word.bbox.origin.y * (app->orig_heights[i]);
                        float ww = word.bbox.size.width * page_w_points;
                        float wh = word.bbox.size.height * (app->orig_heights[i]);
                        
                        if (wx + ww > x0 && wx < x1 && wy + wh > y0 && wy < y1) {
                             SDL_Rect sdl_r;
                             sdl_r.x = (int)(x_pos + wx * final_scale);
                             sdl_r.y = (int)(page_start_y + wy * final_scale);
                             sdl_r.w = (int)(ww * final_scale);
                             sdl_r.h = (int)(wh * final_scale);
                             SDL_RenderFillRect(app->renderer, &sdl_r);
                        }
                    }
                } else {
                    fz_quad quads[1000];
                    int n_quads = 0;
                    
                    if (start != end) {
                        if (i == start) {
                             n_quads = fz_highlight_selection(app->ctx, app->page_text_cache[i], a, (fz_point){9999,9999}, quads, 1000);
                        } else if (i == end) {
                             n_quads = fz_highlight_selection(app->ctx, app->page_text_cache[i], (fz_point){0,0}, b, quads, 1000);
                        } else {
                             n_quads = fz_highlight_selection(app->ctx, app->page_text_cache[i], (fz_point){0,0}, (fz_point){9999,9999}, quads, 1000);
                        }
                    } else {
                        n_quads = fz_highlight_selection(app->ctx, app->page_text_cache[i], a, b, quads, 1000);
                    }
    
                    for (int q = 0; q < n_quads; q++) {
                        fz_rect r = fz_rect_from_quad(quads[q]);
                        SDL_Rect sdl_r;
                        sdl_r.x = (int)(x_pos + r.x0 * final_scale);
                        sdl_r.y = (int)(page_start_y + r.y0 * final_scale);
                        sdl_r.w = (int)((r.x1 - r.x0) * final_scale);
                        sdl_r.h = (int)((r.y1 - r.y0) * final_scale);
                        SDL_RenderFillRect(app->renderer, &sdl_r);
                    }
                }
            }
        }

        current_y += page_h_pixels + PAGE_GAP;
    }
}

void copy_selected_text(AppState* app) {
    if (!app->is_selecting || app->sel_start_page == -1) return;
    
    int start = app->sel_start_page < app->sel_end_page ? app->sel_start_page : app->sel_end_page;
    int end = app->sel_start_page > app->sel_end_page ? app->sel_start_page : app->sel_end_page;
    
    fz_buffer *buf = fz_new_buffer(app->ctx, 1024);
    fz_output *out = fz_new_output_with_buffer(app->ctx, buf);
    
    fz_point p_start = app->drag_start;
    fz_point p_end = app->drag_end;
     if (app->sel_start_page > app->sel_end_page) {
        p_start = app->drag_end;
        p_end = app->drag_start;
    }
    
    for (int i = start; i <= end; i++) {
        ensure_stext_page(app, i);
        
        OCRPage* ocr = (app->ocr_cache && i < app->page_count) ? app->ocr_cache[i] : NULL;
        bool use_ocr = (ocr && ocr->word_count > 0);
        
        if (use_ocr) {
             float x0 = p_start.x < p_end.x ? p_start.x : p_end.x;
             float y0 = p_start.y < p_end.y ? p_start.y : p_end.y;
             float x1 = p_start.x > p_end.x ? p_start.x : p_end.x;
             float y1 = p_start.y > p_end.y ? p_start.y : p_end.y;
             
             if (start != end) {
                 x0 = 0; y0 = 0; x1 = 99999; y1 = 99999; 
             }
             
             for (int w = 0; w < ocr->word_count; w++) {
                OCRWord word = ocr->words[w];
                float wx = word.bbox.origin.x * (app->orig_widths[i]);
                float wy = word.bbox.origin.y * (app->orig_heights[i]);
                float ww = word.bbox.size.width * (app->orig_widths[i]);
                float wh = word.bbox.size.height * (app->orig_heights[i]);
                
                if (wx + ww > x0 && wx < x1 && wy + wh > y0 && wy < y1) {
                     fz_write_string(app->ctx, out, word.text);
                     fz_write_string(app->ctx, out, " ");
                }
             }
             fz_write_string(app->ctx, out, "\n");
             
        } else if (app->page_text_cache[i]) {
            fz_point a = {0,0}, b = {9999,9999};
             if (i == start && i == end) {
                 a = p_start; b = p_end;
             } else if (i == start) {
                 a = p_start;
             } else if (i == end) {
                 b = p_end;
             }
             
             char* text = fz_copy_selection(app->ctx, app->page_text_cache[i], a, b, 0);
             if (text) {
                 fz_write_string(app->ctx, out, text);
                 fz_write_string(app->ctx, out, "\n"); 
                 fz_free(app->ctx, text);
             }
        }
    }
    
    fz_close_output(app->ctx, out);
    fz_drop_output(app->ctx, out);
    
    unsigned char* res_data;
    size_t res_len = fz_buffer_storage(app->ctx, buf, &res_data);
    
    if (res_len > 0) {
        char* final_str = malloc(res_len + 1);
        memcpy(final_str, res_data, res_len);
        final_str[res_len] = '\0';
        SDL_SetClipboardText(final_str);
        free(final_str);
    }
    
    fz_drop_buffer(app->ctx, buf);
}
