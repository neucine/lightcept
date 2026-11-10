#import <AppKit/AppKit.h>
#import "../ui/neiv/native/preview_zoom_view.h"
#import <string.h>

int neiv_publish_event(const char *topic, const char *payloadJson, long long targetHandle) {
    (void)topic; (void)payloadJson; (void)targetHandle;
    return 0;
}

static NSImage *pixelImage(NSUInteger width, NSUInteger height, NSUInteger redColumns) {
    NSBitmapImageRep *pixels = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8
        samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    for (NSUInteger y = 0; y < height; y++) for (NSUInteger x = 0; x < width; x++) {
        unsigned char *rgba = pixels.bitmapData + y * pixels.bytesPerRow + x * 4;
        rgba[0] = x < redColumns ? 255 : 0;
        rgba[1] = x < redColumns ? 0 : 255;
        rgba[2] = 0;
        rgba[3] = 255;
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image addRepresentation:pixels];
    return image;
}

static NSImage *proofImage(NSUInteger width, NSUInteger height, NSUInteger redColumns) {
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
    unsigned char *bytes = pixels.mutableBytes;
    for (NSUInteger y = 0; y < height; y++) for (NSUInteger x = 0; x < width; x++) {
        NSUInteger offset = (y * width + x) * 4;
        bytes[offset] = x < redColumns ? 255 : 0;
        bytes[offset + 1] = x < redColumns ? 0 : 255;
        bytes[offset + 2] = 0;
        bytes[offset + 3] = 255;
    }
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceAdobeRGB1998);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGImageRef image = CGImageCreate(width, height, 8, 32, width * 4, space,
        kCGImageAlphaLast | kCGBitmapByteOrderDefault, provider, NULL, false,
        kCGRenderingIntentDefault);
    NSImage *result = [[NSImage alloc] initWithCGImage:image size:NSMakeSize(width, height)];
    CGImageRelease(image);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(space);
    return result;
}

static NSBitmapImageRep *render(LightceptZoomView *view) {
    NSInteger width = (NSInteger)view.bounds.size.width;
    NSInteger height = (NSInteger)view.bounds.size.height;
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8
        samplesPerPixel:4 hasAlpha:YES isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;
    [view drawRect:view.bounds];
    [context flushGraphics];
    [NSGraphicsContext restoreGraphicsState];
    return bitmap;
}

int main(void) {
    @autoreleasepool {
        LightceptZoomView *view = [[LightceptZoomView alloc] initWithFrame:NSMakeRect(0, 0, 4, 2)];
        view.sourceWidth = 4;
        view.sourceHeight = 2;
        view.image = pixelImage(4, 2, 4);
        view.detailRects = @[[NSValue valueWithRect:NSMakeRect(0, 0, 2, 2)],
            [NSValue valueWithRect:NSMakeRect(2, 0, 2, 2)]];
        view.detailImages = @[pixelImage(2, 2, 2), pixelImage(2, 2, 0)];
        const NSInteger zoomLevels[] = {50, 100, 200};
        for (NSInteger zoomIndex = 0; zoomIndex < 3; zoomIndex++) {
            NSInteger zoom = zoomLevels[zoomIndex];
            [view setFrameSize:NSMakeSize(4 * zoom / 100, 2 * zoom / 100)];
            view.zoomPercent = zoom;
            view.detailRects = @[[NSValue valueWithRect:NSMakeRect(0, 0, 2, 2)],
                [NSValue valueWithRect:NSMakeRect(2, 0, 2, 2)]];
            view.detailImages = @[pixelImage(2, 2, 2), pixelImage(2, 2, 0)];
            NSBitmapImageRep *bitmap = render(view);
            if (zoom == 50) {
                if (view.detailImages.count != 1) {
                    NSLog(@"Reduced tiles were retained after composition");
                    return 1;
                }
                NSBitmapImageRep *repeat = render(view);
                if (memcmp(bitmap.bitmapData, repeat.bitmapData,
                    bitmap.bytesPerRow * 2 * zoom / 100) != 0) {
                    NSLog(@"Composed viewport changed on redraw");
                    return 1;
                }
            }
            for (NSInteger y = 0; y < 2 * zoom / 100; y++) {
                for (NSInteger x = 0; x < 4 * zoom / 100; x++) {
                NSColor *sample = [[bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
                if ((x < 2 * zoom / 100 && (sample.redComponent < 0.9 || sample.greenComponent > 0.25)) ||
                    (x >= 2 * zoom / 100 && (sample.greenComponent < 0.75 || sample.redComponent > 0.25))) {
                    NSLog(@"Incorrect tile at (%ld,%ld): %@", (long)x, (long)y, sample);
                    return 1;
                }
                }
            }
            NSImage *whole = pixelImage(4, 2, 2);
            view.detailRects = @[[NSValue valueWithRect:NSMakeRect(0, 0, 4, 2)]];
            view.detailImages = @[whole];
            NSBitmapImageRep *reference = render(view);
            if (bitmap.bytesPerRow != reference.bytesPerRow ||
                memcmp(bitmap.bitmapData, reference.bitmapData,
                    bitmap.bytesPerRow * 2 * zoom / 100) != 0) {
                for (NSInteger y = 0; y < 2 * zoom / 100; y++)
                    for (NSInteger x = 0; x < 4 * zoom / 100; x++)
                        NSLog(@"(%ld,%ld) tiled %@ whole %@", (long)x, (long)y,
                            [bitmap colorAtX:x y:y], [reference colorAtX:x y:y]);
                NSLog(@"Tile seam differs from the untiled reference at %ld%%", (long)zoom);
                return 1;
            }
        }
        [view setFrameSize:NSMakeSize(2, 1)];
        view.sourceWidth = 8;
        view.sourceHeight = 4;
        view.image = pixelImage(8, 4, 4);
        view.zoomPercent = 50;
        view.detailRects = @[[NSValue valueWithRect:NSMakeRect(2, 1, 2, 2)],
            [NSValue valueWithRect:NSMakeRect(4, 1, 2, 2)]];
        view.detailImages = @[pixelImage(2, 2, 2), pixelImage(2, 2, 0)];
        NSBitmapImageRep *offsetTiles = render(view);
        view.detailRects = @[[NSValue valueWithRect:NSMakeRect(2, 1, 4, 2)]];
        view.detailImages = @[pixelImage(4, 2, 2)];
        NSBitmapImageRep *offsetReference = render(view);
        if (memcmp(offsetTiles.bitmapData, offsetReference.bitmapData,
            offsetTiles.bytesPerRow) != 0) {
            NSLog(@"Offset viewport tiles differ from untiled reference");
            return 1;
        }
        view.sourceWidth = 4;
        view.sourceHeight = 2;
        view.image = pixelImage(4, 2, 2);
        view.beforeImage = pixelImage(4, 2, 2);
        view.zoomPercent = 50;
        view.comparisonMode = 2;
        view.splitFraction = 0.5;
        view.detailRects = @[[NSValue valueWithRect:NSMakeRect(0, 0, 2, 2)],
            [NSValue valueWithRect:NSMakeRect(2, 0, 2, 2)]];
        view.detailImages = @[pixelImage(2, 2, 2), pixelImage(2, 2, 0)];
        view.detailBeforeImages = @[pixelImage(2, 2, 2), pixelImage(2, 2, 0)];
        (void)render(view);
        if (view.detailImages.count != 1 || view.detailBeforeImages.count != 1) {
            NSLog(@"Split view retained reduced tiles after composition");
            return 1;
        }
        view.comparisonMode = 0;
        view.beforeImage = nil;
        view.detailRects = @[[NSValue valueWithRect:NSMakeRect(0, 0, 2, 2)],
            [NSValue valueWithRect:NSMakeRect(2, 0, 2, 2)]];
        view.detailImages = @[proofImage(2, 2, 2), proofImage(2, 2, 0)];
        NSBitmapImageRep *proofTiles = render(view);
        view.detailRects = @[[NSValue valueWithRect:NSMakeRect(0, 0, 4, 2)]];
        view.detailImages = @[proofImage(4, 2, 2)];
        NSBitmapImageRep *proofReference = render(view);
        if (memcmp(proofTiles.bitmapData, proofReference.bitmapData,
            proofTiles.bytesPerRow) != 0) {
            NSLog(@"Adobe RGB tiles differ from untiled reference");
            return 1;
        }
    }
    return 0;
}
