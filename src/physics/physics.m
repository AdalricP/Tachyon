#include "physics.h"
#include "../render/render.h"
#include "../render/render_async.h"
#include <math.h>
#include <stdio.h>

void set_zoom(AppState* app, float new_zoom, int center_x, int center_y) {
    if (new_zoom < ZOOM_MIN) new_zoom = ZOOM_MIN;
    if (new_zoom > ZOOM_MAX) new_zoom = ZOOM_MAX;
    
    if (fabsf(new_zoom - app->zoom) < 0.001f) return;
    
    float old_zoom = app->zoom;
    app->zoom = new_zoom;
    
    float zoom_ratio = new_zoom / old_zoom;
    float center_view_y = (float)center_y; 
    float doc_y = app->scroll_y + center_view_y;
    float new_doc_y = doc_y * zoom_ratio;
    app->scroll_y = new_doc_y - center_view_y;
    
    app->scroll_x *= zoom_ratio;
    
    cancel_all_renders();
    
    calculate_layout(app);
    
    char buf[32];
    snprintf(buf, 32, "Zoom: %d%%", (int)(app->zoom * 100));
    show_overlay(app, buf);
}

void update_physics(AppState* app, float dt) {
    if (!app->doc) return;
    
    int win_w, win_h;
    SDL_GetRendererOutputSize(app->renderer, &win_w, &win_h);
    
    if (fabsf(app->velocity_y) > 0.1f) {
        app->scroll_y += app->velocity_y * dt;
        
        if (app->velocity_y > 0) {
            app->velocity_y -= app->velocity_y * FRICTION_DAMPING * dt;
            if (app->velocity_y < 0) app->velocity_y = 0;
        } else {
            app->velocity_y -= app->velocity_y * FRICTION_DAMPING * dt; 
            if (app->velocity_y > 0) app->velocity_y = 0;
        }
        
        if (fabsf(app->velocity_y) < 1.0f) app->velocity_y = 0;
        if (app->velocity_y > 10000.0f) app->velocity_y = 10000.0f;
        if (app->velocity_y < -10000.0f) app->velocity_y = -10000.0f;
    }
    
    if (fabsf(app->velocity_x) > 0.1f) {
        app->scroll_x += app->velocity_x * dt;
        
        if (app->velocity_x > 0) {
            app->velocity_x -= app->velocity_x * FRICTION_DAMPING * dt;
            if (app->velocity_x < 0) app->velocity_x = 0;
        } else {
            app->velocity_x -= app->velocity_x * FRICTION_DAMPING * dt; 
            if (app->velocity_x > 0) app->velocity_x = 0;
        }
        
        if (fabsf(app->velocity_x) < 1.0f) app->velocity_x = 0;
    }
    
    if (fabsf(app->zoom_velocity) > 0.01f) {
        float new_zoom = app->zoom + app->zoom_velocity * dt;
        
        if (new_zoom < ZOOM_MIN) {
            new_zoom = ZOOM_MIN;
            app->zoom_velocity = 0;
        }
        if (new_zoom > ZOOM_MAX) {
            new_zoom = ZOOM_MAX;
            app->zoom_velocity = 0;
        }
        
        set_zoom(app, new_zoom, win_w / 2, win_h / 2);
        
        if (app->zoom_velocity > 0) {
            app->zoom_velocity -= app->zoom_velocity * FRICTION_DAMPING * dt;
            if (app->zoom_velocity < 0) app->zoom_velocity = 0;
        } else {
            app->zoom_velocity -= app->zoom_velocity * FRICTION_DAMPING * dt;
            if (app->zoom_velocity > 0) app->zoom_velocity = 0;
        }
        
        if (fabsf(app->zoom_velocity) < 0.1f) app->zoom_velocity = 0;
    }

    int max_scroll_y = app->total_height - win_h;
    if (max_scroll_y < 0) max_scroll_y = 0;
    
    if (app->scroll_y < 0) {
        app->scroll_y = 0;
        app->velocity_y = 0;
    }
    if (app->scroll_y > max_scroll_y) {
        app->scroll_y = max_scroll_y;
        app->velocity_y = 0;
    }
    
    if (app->max_width <= win_w) {
        app->scroll_x = 0;
        app->velocity_x = 0;
    } else {
        int overflow = app->max_width - win_w;
        
        int limit = overflow / 2;
        if (app->scroll_x < -limit) {
            app->scroll_x = -limit;
            app->velocity_x = 0;
        }
        if (app->scroll_x > limit) {
            app->scroll_x = limit;
            app->velocity_x = 0;
        }
    }
    
    if (app->overlay_timer > 0) {
        app->overlay_timer -= dt;
        if (app->overlay_timer < 0) app->overlay_timer = 0;
    }
    
    if (fabsf(app->velocity_y) > 0.1f || fabsf(app->velocity_x) > 0.1f) {
        app->scrollbar_alpha = 1.0f;
    } else {
        app->scrollbar_alpha -= 2.0f * dt;
        if (app->scrollbar_alpha < 0) app->scrollbar_alpha = 0;
    }
}
