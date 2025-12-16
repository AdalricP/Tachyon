#include "render_async.h"
#include <Accelerate/Accelerate.h>
#include <stdlib.h>
#include <string.h>

#define MAX_PENDING_REQUESTS 16
#define MAX_COMPLETED_RESULTS 8

static dispatch_queue_t render_queue = NULL;
static dispatch_queue_t result_queue = NULL;

static RenderRequest pending_requests[MAX_PENDING_REQUESTS];
static int pending_count = 0;
static dispatch_semaphore_t pending_lock = NULL;

static RenderResult* completed_results[MAX_COMPLETED_RESULTS];
static int completed_count = 0;
static dispatch_semaphore_t completed_lock = NULL;

static fz_context* render_ctx = NULL;
static fz_document* render_doc = NULL;
static AppState* shared_app = NULL;

static float* orig_widths_copy = NULL;
static float* orig_heights_copy = NULL;

void init_async_renderer(AppState* app) {
    shared_app = app;
    
    render_queue = dispatch_queue_create("com.tachyon.render", DISPATCH_QUEUE_CONCURRENT);
    result_queue = dispatch_queue_create("com.tachyon.results", DISPATCH_QUEUE_SERIAL);
    
    pending_lock = dispatch_semaphore_create(1);
    completed_lock = dispatch_semaphore_create(1);
    
    render_ctx = fz_clone_context(app->ctx);
    
    pending_count = 0;
    completed_count = 0;
    
    for (int i = 0; i < MAX_COMPLETED_RESULTS; i++) {
        completed_results[i] = NULL;
    }
}

void shutdown_async_renderer(void) {
    if (render_queue) {
        dispatch_sync(render_queue, ^{});
    }
    
    cancel_all_renders();
    
    dispatch_semaphore_wait(completed_lock, DISPATCH_TIME_FOREVER);
    for (int i = 0; i < MAX_COMPLETED_RESULTS; i++) {
        if (completed_results[i]) {
            free_render_result(completed_results[i]);
            completed_results[i] = NULL;
        }
    }
    completed_count = 0;
    dispatch_semaphore_signal(completed_lock);
    
    if (render_doc) {
        fz_drop_document(render_ctx, render_doc);
        render_doc = NULL;
    }
    if (render_ctx) {
        fz_drop_context(render_ctx);
        render_ctx = NULL;
    }
    
    if (orig_widths_copy) {
        free(orig_widths_copy);
        orig_widths_copy = NULL;
    }
    if (orig_heights_copy) {
        free(orig_heights_copy);
        orig_heights_copy = NULL;
    }
    
    shared_app = NULL;
}

static void invert_colors_accelerated(unsigned char* pixels, int width, int height, int stride, int components) {
    if (components == 3) {
        for (int y = 0; y < height; y++) {
            unsigned char* row = pixels + y * stride;
            vDSP_Length count = width * 3;
            
            float temp[count];
            float neg_one = -1.0f;
            float two_fifty_five = 255.0f;
            
            vDSP_vfltu8(row, 1, temp, 1, count);
            vDSP_vsmsa(temp, 1, &neg_one, &two_fifty_five, temp, 1, count);
            vDSP_vfixu8(temp, 1, row, 1, count);
        }
    } else {
        for (int y = 0; y < height; y++) {
            unsigned char* p = pixels + y * stride;
            for (int x = 0; x < width; x++) {
                p[0] = 255 - p[0];
                p[1] = 255 - p[1];
                p[2] = 255 - p[2];
                p += components;
            }
        }
    }
}

static void perform_render(int page_num, float base_scale, float zoom, bool dark_mode) {
    if (!shared_app || !shared_app->doc || !shared_app->ctx) return;
    
    fz_context* ctx = shared_app->ctx;
    
    fz_try(ctx) {
        float final_scale = base_scale * zoom;
        fz_matrix transform = fz_scale(final_scale, final_scale);
        
        fz_pixmap* pix = fz_new_pixmap_from_page_number(ctx, shared_app->doc, page_num, transform, fz_device_rgb(ctx), 0);
        
        int w = fz_pixmap_width(ctx, pix);
        int h = fz_pixmap_height(ctx, pix);
        int stride = fz_pixmap_stride(ctx, pix);
        int components = fz_pixmap_components(ctx, pix);
        
        unsigned char* pixels = (unsigned char*)malloc(h * stride);
        memcpy(pixels, fz_pixmap_samples(ctx, pix), h * stride);
        
        fz_drop_pixmap(ctx, pix);
        
        if (dark_mode) {
            invert_colors_accelerated(pixels, w, h, stride, components);
        }
        
        RenderResult* result = (RenderResult*)malloc(sizeof(RenderResult));
        result->page_num = page_num;
        result->pixels = pixels;
        result->width = w;
        result->height = h;
        result->stride = stride;
        result->ready = true;
        
        dispatch_semaphore_wait(completed_lock, DISPATCH_TIME_FOREVER);
        if (completed_count < MAX_COMPLETED_RESULTS) {
            completed_results[completed_count++] = result;
        } else {
            free(result->pixels);
            free(result);
        }
        dispatch_semaphore_signal(completed_lock);
        
    } fz_catch(ctx) {
        printf("Async render failed for page %d\n", page_num);
    }
    
    dispatch_semaphore_wait(pending_lock, DISPATCH_TIME_FOREVER);
    for (int i = 0; i < pending_count; i++) {
        if (pending_requests[i].page_num == page_num) {
            for (int j = i; j < pending_count - 1; j++) {
                pending_requests[j] = pending_requests[j + 1];
            }
            pending_count--;
            break;
        }
    }
    dispatch_semaphore_signal(pending_lock);
}

void request_page_render(AppState* app, int page_num, float base_scale) {
    if (!render_queue || page_num < 0 || page_num >= app->page_count) return;
    
    dispatch_semaphore_wait(pending_lock, DISPATCH_TIME_FOREVER);
    
    for (int i = 0; i < pending_count; i++) {
        if (pending_requests[i].page_num == page_num) {
            dispatch_semaphore_signal(pending_lock);
            return;
        }
    }
    
    if (pending_count >= MAX_PENDING_REQUESTS) {
        dispatch_semaphore_signal(pending_lock);
        return;
    }
    
    RenderRequest req = {
        .page_num = page_num,
        .zoom = app->zoom,
        .base_scale = base_scale,
        .pdf_dark_mode = app->pdf_dark_mode,
        .cancelled = false
    };
    pending_requests[pending_count++] = req;
    
    float zoom = req.zoom;
    bool dark_mode = req.pdf_dark_mode;
    
    dispatch_semaphore_signal(pending_lock);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        perform_render(page_num, base_scale, zoom, dark_mode);
    });
}

void cancel_page_render(int page_num) {
    dispatch_semaphore_wait(pending_lock, DISPATCH_TIME_FOREVER);
    for (int i = 0; i < pending_count; i++) {
        if (pending_requests[i].page_num == page_num) {
            pending_requests[i].cancelled = true;
            break;
        }
    }
    dispatch_semaphore_signal(pending_lock);
}

void cancel_all_renders(void) {
    dispatch_semaphore_wait(pending_lock, DISPATCH_TIME_FOREVER);
    for (int i = 0; i < pending_count; i++) {
        pending_requests[i].cancelled = true;
    }
    dispatch_semaphore_signal(pending_lock);
}

RenderResult* poll_completed_render(void) {
    RenderResult* result = NULL;
    
    dispatch_semaphore_wait(completed_lock, DISPATCH_TIME_FOREVER);
    if (completed_count > 0) {
        result = completed_results[0];
        for (int i = 0; i < completed_count - 1; i++) {
            completed_results[i] = completed_results[i + 1];
        }
        completed_results[completed_count - 1] = NULL;
        completed_count--;
    }
    dispatch_semaphore_signal(completed_lock);
    
    return result;
}

void free_render_result(RenderResult* result) {
    if (result) {
        if (result->pixels) {
            free(result->pixels);
        }
        free(result);
    }
}

bool is_page_render_pending(int page_num) {
    bool pending = false;
    
    dispatch_semaphore_wait(pending_lock, DISPATCH_TIME_FOREVER);
    for (int i = 0; i < pending_count; i++) {
        if (pending_requests[i].page_num == page_num && !pending_requests[i].cancelled) {
            pending = true;
            break;
        }
    }
    dispatch_semaphore_signal(pending_lock);
    
    return pending;
}
