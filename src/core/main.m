#include "types.h"
#include "constants.h"
#include "../render/render.h"
#include "../physics/physics.h"
#include "../ui/ui.h"
#include "../io/file.h"
#include <SDL_syswm.h>

AppState* g_app = NULL;

int main(int argc, char* args[]) {
    printf("Initializing SDL...\n");
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        printf("SDL Init Error: %s\n", SDL_GetError());
        return 1;
    }
    printf("Initializing TTF...\n");
    if (TTF_Init() < 0) {
         printf("TTF Init Error: %s\n", TTF_GetError());
         return 1;
    }
    
    printf("Creating Window...\n");
    SDL_Window* window = SDL_CreateWindow("Tachyon", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 
                                          SCREEN_WIDTH, SCREEN_HEIGHT, SDL_WINDOW_SHOWN | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_RESIZABLE);
    if (!window) return 1;
    
    printf("Force Dark Mode and Unified Title Bar...\n");
    
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    
    if (SDL_GetWindowWMInfo(window, &info)) {
        if (info.subsystem == SDL_SYSWM_COCOA) {
            NSWindow *nswindow = info.info.cocoa.window;
            if (nswindow) {
                printf("NSWindow found via WMInfo. Applying styles.\n");
                [nswindow setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
                
                NSUInteger mask = [nswindow styleMask];
                mask |= NSWindowStyleMaskTitled; 
                mask |= NSWindowStyleMaskFullSizeContentView;
                [nswindow setStyleMask:mask];
                
                [nswindow setTitlebarAppearsTransparent:YES];
                [nswindow setTitleVisibility:NSWindowTitleHidden];
            } else {
                 printf("ERROR: Cocoa Window is NULL.\n");
            }
        } else {
            printf("ERROR: Subsystem is not Cocoa.\n");
        }
    } else {
        printf("ERROR: SDL_GetWindowWMInfo failed: %s\n", SDL_GetError());
    }

    printf("Creating Renderer...\n");
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!renderer) {
        printf("Renderer Init Error: %s\n", SDL_GetError());
        return 1;
    }

    printf("Setup App State...\n");
    AppState app = {0};
    app.ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
    app.renderer = renderer;
    app.zoom = 1.0f;
    app.pdf_dark_mode = true; 
    
    printf("Loading Font...\n");
    app.font = TTF_OpenFont("/System/Library/Fonts/Helvetica.ttc", 24);
    if (!app.font) {
         printf("Failed to load font: %s\n", TTF_GetError());
    }
    
    fz_register_document_handlers(app.ctx);
    g_app = &app; 

    printf("Init App Delegate...\n");
    init_app_delegate();
    printf("Setup Menu...\n");
    setup_menu();
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];

    if (argc > 1) {
        printf("Loading Doc...\n");
        load_document(&app, args[1]);
    }

    bool quit = false;
    SDL_Event e;
    app.last_time = SDL_GetTicks();
    
    printf("First Render...\n");
    render(&app);

    printf("Entering Loop...\n");
    while (!quit) {
        Uint32 current_time = SDL_GetTicks();
        float dt = (current_time - app.last_time) / 1000.0f;
        
        if (dt > 0.1f) dt = 0.1f;
        
        app.last_time = current_time;
        
        int win_w, win_h;
        SDL_GetRendererOutputSize(app.renderer, &win_w, &win_h);
        
        while (SDL_PollEvent(&e) != 0) {
            if (e.type == SDL_QUIT) {
                quit = true;
            } else if (e.type == SDL_DROPFILE) {
                char* dropped_file = e.drop.file;
                load_document(&app, dropped_file);
                SDL_free(dropped_file);
            } else if (e.type == SDL_MOUSEWHEEL) {
                if (app.doc) {
                    bool cmd = (SDL_GetModState() & KMOD_GUI) != 0;
                    bool shift = (SDL_GetModState() & KMOD_SHIFT) != 0;
                    
                    if (cmd) {
                        app.zoom_velocity += e.wheel.y * ZOOM_SENSITIVITY * 20.0f;
                    } else {
                        app.velocity_y -= e.wheel.y * SCROLL_SENSITIVITY * 15.0f;
                        
                        if (shift || e.wheel.x != 0) {
                             if (e.wheel.x != 0) {
                                  app.velocity_x += e.wheel.x * SCROLL_SENSITIVITY * 15.0f; 
                             } else if (shift && e.wheel.y != 0) {
                                  app.velocity_x += e.wheel.y * SCROLL_SENSITIVITY * 15.0f;
                                  app.velocity_y += e.wheel.y * SCROLL_SENSITIVITY * 15.0f; 
                             }
                        }
                    } 
                }
            } else if (e.type == SDL_KEYDOWN) {
                bool cmd = (SDL_GetModState() & KMOD_GUI) != 0;
                
                switch(e.key.keysym.sym) {
                    case SDLK_UP: app.velocity_y -= 800.0f; break; 
                    case SDLK_DOWN: app.velocity_y += 800.0f; break;
                    case SDLK_LEFT: app.velocity_x -= 800.0f; break;
                    case SDLK_RIGHT: app.velocity_x += 800.0f; break;
                    case SDLK_ESCAPE: quit = true; break;
                    case SDLK_EQUALS: 
                    case SDLK_PLUS:
                        if (cmd) {
                            app.zoom_velocity += 2.0f; 
                        }
                        break;
                    case SDLK_MINUS: 
                        if (cmd) {
                            app.zoom_velocity -= 2.0f;
                        }
                        break;
                    case SDLK_0: 
                        if (cmd) {
                            app.zoom_velocity = 0;
                            set_zoom(&app, 1.0f, win_w / 2, win_h / 2);
                        }
                        break;
                }
            }
        }
        
        update_physics(&app, dt);
        render(&app);
    }
    
    clear_cache(&app);
    if (app.overlay_texture) SDL_DestroyTexture(app.overlay_texture);
    if (app.font) TTF_CloseFont(app.font);
    
    if (app.doc) fz_drop_document(app.ctx, app.doc);
    if (app.ctx) fz_drop_context(app.ctx);

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    TTF_Quit();
    SDL_Quit();

    return 0;
}