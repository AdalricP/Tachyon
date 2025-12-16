#include "ocr.h"
#include <CoreImage/CoreImage.h>
#include <Vision/Vision.h>

void init_ocr(AppState* app) {
    if (!app->ocr_cache && app->page_count > 0) {
        app->ocr_cache = (OCRPage**)calloc(app->page_count, sizeof(OCRPage*));
    }
}

void cleanup_ocr(AppState* app) {
    if (app->ocr_cache) {
        for (int i = 0; i < app->page_count; i++) {
            if (app->ocr_cache[i]) {
                for (int w = 0; w < app->ocr_cache[i]->word_count; w++) {
                    free(app->ocr_cache[i]->words[w].text);
                }
                free(app->ocr_cache[i]->words);
                free(app->ocr_cache[i]);
            }
        }
        free(app->ocr_cache);
        app->ocr_cache = NULL;
    }
}

void perform_ocr_if_needed(AppState* app, int page_num) {
    if (!app->ocr_cache) init_ocr(app);
    if (app->ocr_cache[page_num] && app->ocr_cache[page_num]->is_processed) return;

    float zoom = 2.0f;
    fz_matrix transform = fz_scale(zoom, zoom);
    fz_page* page = fz_load_page(app->ctx, app->doc, page_num);
    fz_pixmap* pix = fz_new_pixmap_from_page_number(app->ctx, app->doc, page_num, transform, fz_device_rgb(app->ctx), 0);
    
    int width = fz_pixmap_width(app->ctx, pix);
    int height = fz_pixmap_height(app->ctx, pix);
    int stride = fz_pixmap_stride(app->ctx, pix);
    unsigned char* samples = fz_pixmap_samples(app->ctx, pix);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(samples, width, height, 8, stride, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaNoneSkipLast);
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    fz_drop_pixmap(app->ctx, pix);
    fz_drop_page(app->ctx, page);

    if (!cgImage) {
        printf("Failed to create CGImage for OCR on page %d\n", page_num);
        return;
    }

    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:NULL];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = YES;
    
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
    
    NSError *error = nil;
    [handler performRequests:@[request] error:&error];
    
    CGImageRelease(cgImage);
    
    if (error) {
        printf("OCR Error page %d: %s\n", page_num, [[error localizedDescription] UTF8String]);
        return;
    }
    
    NSArray *results = request.results;
    if (results.count > 0) {
        OCRPage* ocrPage = (OCRPage*)malloc(sizeof(OCRPage));
        ocrPage->word_count = 0;
        ocrPage->is_processed = true;
        
        ocrPage->word_count = (int)results.count;
        ocrPage->words = (OCRWord*)calloc(ocrPage->word_count, sizeof(OCRWord));
        
        for (int i = 0; i < results.count; i++) {
            VNRecognizedTextObservation *observation = results[i];
            VNRecognizedText *bestText = [observation topCandidates:1].firstObject;
            
            ocrPage->words[i].text = strdup([bestText.string UTF8String]);
            
            CGRect box = observation.boundingBox;
            
            ocrPage->words[i].bbox = CGRectMake(
                box.origin.x, 
                1.0f - (box.origin.y + box.size.height), 
                box.size.width, 
                box.size.height
            );
        }
        
        app->ocr_cache[page_num] = ocrPage;
        printf("OCR completed for page %d: %d blocks found\n", page_num, ocrPage->word_count);
    } else {
         OCRPage* ocrPage = (OCRPage*)malloc(sizeof(OCRPage));
         ocrPage->word_count = 0;
         ocrPage->words = NULL;
         ocrPage->is_processed = true;
         app->ocr_cache[page_num] = ocrPage;
    }
}
