#ifndef UI_H
#define UI_H

#include "../core/types.h"
#include "../core/constants.h"

@interface MenuHandler : NSObject
@end

void setup_menu(void);
void init_app_delegate(void);
void draw_scrollbar(AppState* app);

#endif
