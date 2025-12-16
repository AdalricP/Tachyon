#ifndef RSVP_H
#define RSVP_H

#include "../core/types.h"

#define RSVP_DEFAULT_WPM 300
#define RSVP_MIN_WPM 100
#define RSVP_MAX_WPM 1000
#define RSVP_WPM_STEP 20
#define RSVP_MIN_CHUNK 1
#define RSVP_MAX_CHUNK 5

void init_rsvp(AppState* app);
void cleanup_rsvp(AppState* app);
void toggle_rsvp_mode(AppState* app);
void rsvp_update(AppState* app, float dt);
void rsvp_render(AppState* app);
void rsvp_handle_key(AppState* app, SDL_Keycode key, bool cmd);
void extract_text_for_rsvp(AppState* app);

#endif
