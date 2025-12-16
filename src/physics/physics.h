#ifndef PHYSICS_H
#define PHYSICS_H

#include "../core/types.h"
#include "../core/constants.h"

void update_physics(AppState* app, float dt);
void set_zoom(AppState* app, float new_zoom, int center_x, int center_y);

#endif
