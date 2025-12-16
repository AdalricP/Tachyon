#ifndef OCR_H
#define OCR_H

#include "../core/types.h"

// Initializes OCR cache for the app
void init_ocr(AppState* app);

// Cleans up OCR cache
void cleanup_ocr(AppState* app);

// Performs OCR on the specified page if it hasn't been processed yet
// Returns true if OCR was performed or results available, false on error
void perform_ocr_if_needed(AppState* app, int page_num);

#endif
