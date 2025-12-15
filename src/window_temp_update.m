#include "tachyon.h"

// ... (MenuHandler logic)

- (void)toggleTheme:(id)sender {
    if (g_app) {
        g_app->pdf_dark_mode = !g_app->pdf_dark_mode;
        
        // We MUST clear the cache because the textures are baked with the color setting
        clear_cache(g_app);
    }
}
