#ifndef RENDER_H
#define RENDER_H

#include "../core/types.h"
#include "../core/constants.h"

void render(AppState* app);
void calculate_layout(AppState* app);
void clear_texture_cache(AppState* app);
void show_overlay(AppState* app, const char* text);

#endif
