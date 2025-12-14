#include "tachyon.h"

@implementation AppDelegate
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
@end

void setup_menu(void) {
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
    [fileMenu addItem:openItem];
    [fileMenuItem setSubmenu:fileMenu];
    [menubar addItem:fileMenuItem];
    
    [NSApp setMainMenu:menubar];
}

void init_app_delegate(void) {
    [NSApplication sharedApplication];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    [NSApp setDelegate:delegate];
}
