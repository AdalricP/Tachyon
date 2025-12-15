#include "tachyon.h"

// MenuHandler.m (Merged logic)

// Global reference to prevent GC (ARC not active? using alloc init)
static MenuHandler* g_menuHandler = NULL;

@implementation MenuHandler
- (void)openDocument:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [panel setAllowedFileTypes:@[@"pdf"]];
#pragma clang diagnostic pop
    
    if ([panel runModal] == NSModalResponseOK) {
        NSURL* url = [panel URL];
        if (g_app) {
            load_document(g_app, [[url path] UTF8String]);
        }
    }
}

- (void)randomizeColor:(id)sender {
    if (g_app) {
         SDL_Color palette[] = {
             {30, 30, 30, 255}, // Dark Grey
             {255, 255, 255, 255}, // White
             {238, 238, 238, 255},
             {255, 253, 230, 255},
             {251, 233, 218, 255},
             {243, 255, 218, 255},
             {227, 245, 252, 255},
             {250, 229, 239, 255},
             {238, 228, 253, 255},
             {241, 219, 214, 255}
         };
         int count = sizeof(palette) / sizeof(SDL_Color);
         int idx = rand() % count;
         g_app->bg_color = palette[idx];
    }
}

- (void)toggleTheme:(id)sender {
    if (g_app) {
        g_app->pdf_dark_mode = !g_app->pdf_dark_mode;
        
        // We MUST clear the cache because the textures are baked with the color setting
        clear_texture_cache(g_app);
        
        // Also toggle background default?
        // User said: "just make it enable and disable dark mode for the PDF"
        // But usually "Dark Mode" implies dark background too.
        // Let's stick to JUST PDF for now as explicitly requested, 
        // OR we can swap the background if it's currently one of the known defaults.
        // For simplicity: Just PDF.
    }
}
@end

void setup_menu(void) {
    // Ensure handler exists
    if (!g_menuHandler) {
        g_menuHandler = [[MenuHandler alloc] init];
    }

    NSMenu *menubar = [[NSMenu alloc] init];
    
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"Quit Tachyon"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];
    [menubar addItem:appMenuItem];
    
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Open..."
                                                      action:@selector(openDocument:)
                                               keyEquivalent:@"o"];
    [openItem setTarget:g_menuHandler]; // Explicit Target to our handler
    [fileMenu addItem:openItem];
    [fileMenuItem setSubmenu:fileMenu];
    [menubar addItem:fileMenuItem];
    
    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] init];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    
    NSMenuItem *randItem = [[NSMenuItem alloc] initWithTitle:@"Randomize Background"
                                                           action:@selector(randomizeColor:)
                                                    keyEquivalent:@"r"];
    [randItem setTarget:g_menuHandler]; // Explicit Target
    [viewMenu addItem:randItem];
    
    NSMenuItem *toggleItem = [[NSMenuItem alloc] initWithTitle:@"Toggle Light/Dark"
                                                       action:@selector(toggleTheme:)
                                                keyEquivalent:@"t"];
    [toggleItem setTarget:g_menuHandler]; // Explicit Target
    [viewMenu addItem:toggleItem];
    
    [viewMenuItem setSubmenu:viewMenu];
    [menubar addItem:viewMenuItem];
    
    [NSApp setMainMenu:menubar];
}

void init_app_delegate(void) {
    [NSApplication sharedApplication];
    
    // Check system theme for initial color
    // We DO NOT set the delegate, as that breaks SDL.
    
    if (g_app) {
        NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
        if ([osxMode isEqualToString:@"Dark"]) {
             g_app->bg_color = (SDL_Color){30, 30, 30, 255};
        } else {
             // System is Light, but we default to Dark per request?
             // User: "set default theme to dark mode (and toggleable to light mode)"
             // Implementation Plan says: "Default Dark Mode ... unconditionally"
             // But checking system is nice.
             // Let's stick to strict Dark Mode default as requested.
             g_app->bg_color = (SDL_Color){30, 30, 30, 255};
        }
    }
}
