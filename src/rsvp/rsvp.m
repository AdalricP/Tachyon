#include "rsvp.h"
#include "../core/constants.h"
#include "../text_selection.h"
#include "../physics/physics.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

static const SDL_Color HIGHLIGHT_COLORS[] = {
    {255, 220, 50, 150},   // Yellow
    {100, 200, 255, 150},  // Blue
    {100, 255, 150, 150},  // Green
    {255, 150, 200, 150},  // Pink
    {200, 150, 255, 150},  // Purple
    {255, 180, 100, 150},  // Orange
};
#define NUM_HIGHLIGHT_COLORS 6

static const char* CHAPTER_PATTERNS[] = {
    "chapter", "introduction", "prologue", "part one", "part 1",
    NULL
};

static bool is_noise_word(const char* word) {
    if (!word || strlen(word) == 0 || strlen(word) > 40) return true;
    if (word[0] == '[' && word[strlen(word)-1] == ']') return true;
    if (strncasecmp(word, "http", 4) == 0 || strncasecmp(word, "www.", 4) == 0) return true;
    int digits = 0, total = 0;
    for (const char* p = word; *p; p++) {
        if (isdigit(*p)) digits++;
        if (isalnum(*p)) total++;
    }
    if (total > 0 && (float)digits / total > 0.8f && total > 3) return true;
    return false;
}

static bool line_is_chapter_start(const char* line) {
    if (!line || strlen(line) < 4) return false;
    char lower[256];
    strncpy(lower, line, 255);
    lower[255] = '\0';
    for (char* p = lower; *p; p++) *p = tolower(*p);
    for (int i = 0; CHAPTER_PATTERNS[i] != NULL; i++) {
        if (strstr(lower, CHAPTER_PATTERNS[i]) != NULL) return true;
    }
    return false;
}

typedef struct {
    char** words;
    int* pages;
    fz_point* starts;
    fz_point* ends;
    int count;
    int capacity;
} WordList;

static void add_word_with_points(WordList* list, const char* word, int page, fz_point start, fz_point end) {
    if (!word || strlen(word) == 0 || is_noise_word(word)) return;
    if (list->count >= list->capacity - 1) {
        list->capacity *= 2;
        list->words = realloc(list->words, list->capacity * sizeof(char*));
        list->pages = realloc(list->pages, list->capacity * sizeof(int));
        list->starts = realloc(list->starts, list->capacity * sizeof(fz_point));
        list->ends = realloc(list->ends, list->capacity * sizeof(fz_point));
    }
    char* w = strdup(word);
    size_t wlen = strlen(w);
    while (wlen > 1 && ispunct(w[wlen-1]) && w[wlen-1] != '.' && w[wlen-1] != ',') {
        w[wlen-1] = '\0';
        wlen--;
    }
    if (strlen(w) > 0) {
        list->words[list->count] = w;
        list->pages[list->count] = page;
        list->starts[list->count] = start;
        list->ends[list->count] = end;
        list->count++;
    } else {
        free(w);
    }
}

void extract_text_for_rsvp(AppState* app) {
    if (!app->doc || !app->ctx) return;
    if (app->rsvp && app->rsvp->words) return;
    
    if (!app->rsvp) {
        app->rsvp = calloc(1, sizeof(*app->rsvp));
        app->rsvp->wpm = RSVP_DEFAULT_WPM;
        app->rsvp->chunk_size = 1;
        app->rsvp->paused = true;
    }
    
    WordList list = {
        .words = malloc(16384 * sizeof(char*)),
        .pages = malloc(16384 * sizeof(int)),
        .starts = malloc(16384 * sizeof(fz_point)),
        .ends = malloc(16384 * sizeof(fz_point)),
        .count = 0,
        .capacity = 16384
    };
    
    int first_chapter_idx = 0;
    bool found_chapter = false;
    
    for (int p = 0; p < app->page_count; p++) {
        fz_try(app->ctx) {
            fz_page* page = fz_load_page(app->ctx, app->doc, p);
            fz_stext_page* stext = fz_new_stext_page_from_page(app->ctx, page, NULL);
            fz_drop_page(app->ctx, page);
            
            for (fz_stext_block* block = stext->first_block; block; block = block->next) {
                if (block->type != FZ_STEXT_BLOCK_TEXT) continue;
                
                for (fz_stext_line* line = block->u.t.first_line; line; line = line->next) {
                    char word_buf[128] = "";
                    int word_pos = 0;
                    fz_point word_start = {0, 0};
                    fz_point word_end = {0, 0};
                    bool in_word = false;
                    
                    for (fz_stext_char* ch = line->first_char; ch; ch = ch->next) {
                        int c = ch->c;
                        bool is_space = (c == ' ' || c == '\t' || c == '\n' || c == '\r');
                        
                        if (is_space) {
                            if (in_word && word_pos > 0) {
                                word_buf[word_pos] = '\0';
                                if (!found_chapter && line_is_chapter_start(word_buf)) {
                                    first_chapter_idx = list.count;
                                    found_chapter = true;
                                    app->rsvp->first_content_page = p;
                                }
                                add_word_with_points(&list, word_buf, p, word_start, word_end);
                                word_pos = 0;
                                in_word = false;
                            }
                        } else {
                            if (!in_word) {
                                word_start = ch->origin;
                                in_word = true;
                            }
                            word_end.x = ch->origin.x + (ch->quad.lr.x - ch->quad.ll.x);
                            word_end.y = ch->origin.y;
                            if (word_pos < 126) {
                                if (c < 128 && c > 31) word_buf[word_pos++] = (char)c;
                                else if (c == 0x2019 || c == 0x2018) word_buf[word_pos++] = '\'';
                            }
                        }
                    }
                    
                    if (in_word && word_pos > 0) {
                        word_buf[word_pos] = '\0';
                        if (!found_chapter && line_is_chapter_start(word_buf)) {
                            first_chapter_idx = list.count;
                            found_chapter = true;
                            app->rsvp->first_content_page = p;
                        }
                        add_word_with_points(&list, word_buf, p, word_start, word_end);
                    }
                }
            }
            fz_drop_stext_page(app->ctx, stext);
        } fz_catch(app->ctx) { continue; }
    }
    
    app->rsvp->words = list.words;
    app->rsvp->word_pages = list.pages;
    app->rsvp->word_start = list.starts;
    app->rsvp->word_end = list.ends;
    app->rsvp->word_count = list.count;
    app->rsvp->current_index = first_chapter_idx;
    
    printf("RSVP: Extracted %d words, starting at %d\n", list.count, first_chapter_idx);
}

void init_rsvp(AppState* app) {
    if (app->rsvp) return;
    app->rsvp = calloc(1, sizeof(*app->rsvp));
    app->rsvp->wpm = RSVP_DEFAULT_WPM;
    app->rsvp->chunk_size = 1;
    app->rsvp->paused = true;
    app->rsvp->highlight_color_index = 0;
    app->rsvp->overlay_alpha = 160;
}

void cleanup_rsvp(AppState* app) {
    if (!app->rsvp) return;
    if (app->rsvp->words) {
        for (int i = 0; i < app->rsvp->word_count; i++) free(app->rsvp->words[i]);
        free(app->rsvp->words);
    }
    if (app->rsvp->word_pages) free(app->rsvp->word_pages);
    if (app->rsvp->word_start) free(app->rsvp->word_start);
    if (app->rsvp->word_end) free(app->rsvp->word_end);
    free(app->rsvp);
    app->rsvp = NULL;
}

void toggle_rsvp_mode(AppState* app) {
    if (!app->rsvp) init_rsvp(app);
    
    if (app->rsvp->active) {
        app->rsvp->active = false;
    } else {
        app->rsvp->active = true;
        if (!app->rsvp->words) extract_text_for_rsvp(app);
        
        int win_w, win_h;
        SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
        set_zoom(app, 0.99f, win_w / 2, win_h / 2);
        
        float accum = 0;
        int visible_page = 0;
        for (int i = 0; i < app->page_count; i++) {
            if (accum + app->page_heights[i] > app->scroll_y) {
                visible_page = i;
                break;
            }
            accum += app->page_heights[i] + PAGE_GAP;
        }
        
        for (int i = 0; i < app->rsvp->word_count; i++) {
            if (app->rsvp->word_pages[i] >= visible_page) {
                app->rsvp->current_index = i;
                break;
            }
        }
        
        app->rsvp->paused = false;
        app->rsvp->last_advance_time = SDL_GetTicks();
    }
}

void rsvp_update(AppState* app, float dt) {
    if (!app->rsvp || !app->rsvp->active) return;
    if (!app->rsvp->words || app->rsvp->word_count == 0) return;
    
    int win_w, win_h;
    SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
    
    int idx = app->rsvp->current_index;
    int end_idx = idx + app->rsvp->chunk_size - 1;
    if (end_idx >= app->rsvp->word_count) end_idx = app->rsvp->word_count - 1;
    
    int page = app->rsvp->word_pages[idx];
    float y_start = app->rsvp->word_start[idx].y;
    float x_start = app->rsvp->word_start[idx].x;
    float x_end = app->rsvp->word_end[end_idx].x;
    
    float page_w = app->orig_widths[page];
    float base_scale = (float)(win_w - 40) / page_w;
    float final_scale = base_scale * app->zoom;
    int page_w_pixels = (int)(page_w * final_scale);
    
    float word_center_x_on_page = (x_start + x_end) / 2.0f * final_scale;
    float page_x_offset = (float)(win_w - page_w_pixels) / 2;
    float word_screen_x = page_x_offset + word_center_x_on_page;
    float target_scroll_x = word_screen_x - (float)win_w / 2;
    
    float target_scroll_y = 0;
    for (int i = 0; i < page; i++) {
        target_scroll_y += app->page_heights[i] + PAGE_GAP;
    }
    target_scroll_y += y_start * final_scale - win_h / 2;
    
    app->scroll_y = target_scroll_y;
    app->scroll_x = target_scroll_x;
    app->velocity_y = 0;
    app->velocity_x = 0;
    
    if (app->rsvp->paused) return;
    
    Uint32 now = SDL_GetTicks();
    float ms = (60.0f * 1000.0f) / app->rsvp->wpm * app->rsvp->chunk_size;
    if (now - app->rsvp->last_advance_time >= (Uint32)ms) {
        app->rsvp->current_index += app->rsvp->chunk_size;
        if (app->rsvp->current_index >= app->rsvp->word_count) {
            app->rsvp->current_index = app->rsvp->word_count - 1;
            app->rsvp->paused = true;
        }
        app->rsvp->last_advance_time = now;
    }
}

void rsvp_render(AppState* app) {
    if (!app->rsvp || !app->rsvp->active) return;
    if (!app->rsvp->words || app->rsvp->word_count == 0) return;
    
    int win_w, win_h;
    SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
    SDL_SetRenderDrawBlendMode(app->renderer, SDL_BLENDMODE_BLEND);
    
    int idx = app->rsvp->current_index;
    int end_idx = idx + app->rsvp->chunk_size - 1;
    if (end_idx >= app->rsvp->word_count) end_idx = app->rsvp->word_count - 1;
    
    int page = app->rsvp->word_pages[idx];
    fz_point start = app->rsvp->word_start[idx];
    fz_point end = app->rsvp->word_end[end_idx];
    
    float page_w = app->orig_widths[page];
    float base_scale = (float)(win_w - 40) / page_w;
    float final_scale = base_scale * app->zoom;
    int page_w_pixels = (int)(page_w * final_scale);
    
    float x_pos = (float)((win_w - page_w_pixels) / 2) - app->scroll_x;
    
    float page_start_y = 0;
    for (int i = 0; i < page; i++) {
        page_start_y += app->page_heights[i] + PAGE_GAP;
    }
    page_start_y -= app->scroll_y;
    
    float text_height = 14 * final_scale;
    float highlight_x = x_pos + start.x * final_scale - 4;
    float highlight_y = page_start_y + start.y * final_scale - text_height;
    float highlight_w = (end.x - start.x) * final_scale + 8;
    float highlight_h = text_height + 6;
    
    if (app->pdf_dark_mode) {
        SDL_SetRenderDrawColor(app->renderer, 0, 0, 0, app->rsvp->overlay_alpha);
    } else {
        SDL_SetRenderDrawColor(app->renderer, 255, 255, 255, app->rsvp->overlay_alpha);
    }
    SDL_Rect top_overlay = {0, 0, win_w, (int)highlight_y};
    SDL_Rect bot_overlay = {0, (int)(highlight_y + highlight_h), win_w, win_h - (int)(highlight_y + highlight_h)};
    SDL_Rect left_overlay = {0, (int)highlight_y, (int)highlight_x, (int)highlight_h};
    SDL_Rect right_overlay = {(int)(highlight_x + highlight_w), (int)highlight_y, win_w - (int)(highlight_x + highlight_w), (int)highlight_h};
    SDL_RenderFillRect(app->renderer, &top_overlay);
    SDL_RenderFillRect(app->renderer, &bot_overlay);
    SDL_RenderFillRect(app->renderer, &left_overlay);
    SDL_RenderFillRect(app->renderer, &right_overlay);
    
    SDL_Color col;
    if (app->pdf_dark_mode) {
        col = (SDL_Color){255, 220, 50, 120};
    } else {
        col = (SDL_Color){255, 220, 50, 120};
    }
    SDL_SetRenderDrawColor(app->renderer, col.r, col.g, col.b, col.a);
    SDL_Rect highlight = {(int)highlight_x, (int)highlight_y, (int)highlight_w, (int)highlight_h};
    SDL_RenderFillRect(app->renderer, &highlight);
    
    SDL_SetRenderDrawColor(app->renderer, 0, 0, 0, 200);
    SDL_Rect bar = {0, win_h - 40, win_w, 40};
    SDL_RenderFillRect(app->renderer, &bar);
    
    if (app->font) {
        TTF_SetFontSize(app->font, 13);
        char status[256];
        snprintf(status, 256, "%d WPM | %d word%s | Page %d | %s | IJKL | Arrows | N:top | Cmd+H:color",
            app->rsvp->wpm, app->rsvp->chunk_size, app->rsvp->chunk_size > 1 ? "s" : "",
            page + 1, app->rsvp->paused ? "PAUSED" : "READING");
        SDL_Color white = {200, 200, 200, 255};
        SDL_Surface* surf = TTF_RenderText_Blended(app->font, status, white);
        if (surf) {
            SDL_Texture* tex = SDL_CreateTextureFromSurface(app->renderer, surf);
            SDL_Rect dst = {(win_w - surf->w) / 2, win_h - 28, surf->w, surf->h};
            SDL_RenderCopy(app->renderer, tex, NULL, &dst);
            SDL_DestroyTexture(tex);
            SDL_FreeSurface(surf);
        }
        TTF_SetFontSize(app->font, 24);
    }
}

void rsvp_handle_key(AppState* app, SDL_Keycode key, bool cmd) {
    if (!app->rsvp || !app->rsvp->active) return;
    
    switch (key) {
        case SDLK_SPACE:
            app->rsvp->paused = !app->rsvp->paused;
            if (!app->rsvp->paused) app->rsvp->last_advance_time = SDL_GetTicks();
            break;
        
        case SDLK_j:
            app->rsvp->wpm -= RSVP_WPM_STEP;
            if (app->rsvp->wpm < RSVP_MIN_WPM) app->rsvp->wpm = RSVP_MIN_WPM;
            break;
        case SDLK_l:
            app->rsvp->wpm += RSVP_WPM_STEP;
            if (app->rsvp->wpm > RSVP_MAX_WPM) app->rsvp->wpm = RSVP_MAX_WPM;
            break;
        case SDLK_i:
            app->rsvp->chunk_size++;
            if (app->rsvp->chunk_size > RSVP_MAX_CHUNK) app->rsvp->chunk_size = RSVP_MAX_CHUNK;
            break;
        case SDLK_k:
            app->rsvp->chunk_size--;
            if (app->rsvp->chunk_size < RSVP_MIN_CHUNK) app->rsvp->chunk_size = RSVP_MIN_CHUNK;
            break;
        
        case SDLK_LEFT:
            app->rsvp->current_index--;
            if (app->rsvp->current_index < 0) app->rsvp->current_index = 0;
            break;
        case SDLK_RIGHT:
            app->rsvp->current_index++;
            if (app->rsvp->current_index >= app->rsvp->word_count) 
                app->rsvp->current_index = app->rsvp->word_count - 1;
            break;
        case SDLK_UP: {
            int cur_page = app->rsvp->word_pages[app->rsvp->current_index];
            if (cur_page > 0) {
                for (int i = app->rsvp->current_index - 1; i >= 0; i--) {
                    if (app->rsvp->word_pages[i] < cur_page) {
                        app->rsvp->current_index = i;
                        break;
                    }
                }
            }
            break;
        }
        case SDLK_DOWN: {
            int cur_page = app->rsvp->word_pages[app->rsvp->current_index];
            if (cur_page < app->page_count - 1) {
                for (int i = app->rsvp->current_index + 1; i < app->rsvp->word_count; i++) {
                    if (app->rsvp->word_pages[i] > cur_page) {
                        app->rsvp->current_index = i;
                        break;
                    }
                }
            }
            break;
        }
        
        case SDLK_r:
            app->rsvp->current_index = 0;
            app->rsvp->paused = true;
            break;
        
        case SDLK_n: {
            int cur_page = app->rsvp->word_pages[app->rsvp->current_index];
            for (int i = 0; i < app->rsvp->word_count; i++) {
                if (app->rsvp->word_pages[i] == cur_page) {
                    app->rsvp->current_index = i;
                    break;
                }
            }
            break;
        }
        
        case SDLK_h:
            if (cmd) {
                app->rsvp->highlight_color_index = (app->rsvp->highlight_color_index + 1) % NUM_HIGHLIGHT_COLORS;
            }
            break;
        
        case SDLK_LEFTBRACKET:
            app->rsvp->overlay_alpha -= 20;
            if (app->rsvp->overlay_alpha < 0) app->rsvp->overlay_alpha = 0;
            break;
        case SDLK_RIGHTBRACKET:
            app->rsvp->overlay_alpha += 20;
            if (app->rsvp->overlay_alpha > 255) app->rsvp->overlay_alpha = 255;
            break;
    }
}
