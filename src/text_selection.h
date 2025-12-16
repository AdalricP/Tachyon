#ifndef TEXT_SELECTION_H
#define TEXT_SELECTION_H

#include "core/types.h"

void init_text_selection(AppState* app);
void cleanup_text_selection(AppState* app);

void handle_mouse_down(AppState* app, int x, int y);
void handle_mouse_drag(AppState* app, int x, int y);
void handle_mouse_up(AppState* app, int x, int y);

void update_cursor_for_position(AppState* app, int x, int y);

void draw_selection_overlay(AppState* app);
void copy_selected_text(AppState* app);

#endif
