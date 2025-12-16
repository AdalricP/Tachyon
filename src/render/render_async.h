#ifndef RENDER_ASYNC_H
#define RENDER_ASYNC_H

#include "../core/types.h"
#include <dispatch/dispatch.h>

typedef struct {
    int page_num;
    float zoom;
    float base_scale;
    bool pdf_dark_mode;
    bool cancelled;
} RenderRequest;

typedef struct {
    int page_num;
    unsigned char* pixels;
    int width;
    int height;
    int stride;
    bool ready;
} RenderResult;

void init_async_renderer(AppState* app);
void shutdown_async_renderer(void);
void request_page_render(AppState* app, int page_num, float base_scale);
void cancel_page_render(int page_num);
void cancel_all_renders(void);
RenderResult* poll_completed_render(void);
void free_render_result(RenderResult* result);
bool is_page_render_pending(int page_num);

#endif
