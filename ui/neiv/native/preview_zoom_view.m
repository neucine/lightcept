#import "preview_zoom_view.h"
#import "generated/neiv_callbacks.h"
#import <math.h>
#import <string.h>
#import <stdio.h>

extern int neiv_publish_event(const char *topic, const char *payloadJson, long long targetHandle);

@interface LightceptZoomView ()
@property(nonatomic) NSRect composedAfterRect;
@property(nonatomic) NSRect composedBeforeRect;
@end

@implementation LightceptZoomView
- (BOOL)isFlipped { return YES; }
- (void)clearSourceDetail {
    self.detailRects = nil;
    self.detailImages = nil;
    self.detailBeforeImages = nil;
    self.composedAfterRect = NSZeroRect;
    self.composedBeforeRect = NSZeroRect;
    [self setNeedsDisplay:YES];
}
- (void)setImage:(NSImage *)image {
    BOOL changedGeometry = !self.image || !image || !NSEqualSizes(self.image.size, image.size);
    [super setImage:image];
    if (changedGeometry) self.pan = NSZeroPoint;
    self.cropSelection = NSZeroRect;
    self.cropHasUserSelection = NO;
    [self clearSourceDetail];
    [self refreshPickedMask];
    if (self.viewportChanged) self.viewportChanged();
}
- (void)refreshPickedMask {
    self.pickedMaskImage = nil;
    if (!self.pickedMaskVisible || self.pickWidth == 0 || self.pickHeight == 0 ||
        self.pickWorking.length != self.pickWidth * self.pickHeight * 3 * sizeof(double)) {
        [self setNeedsDisplay:YES];
        return;
    }
    NSInteger width = MIN((NSInteger)self.pickWidth, 512), height = MIN((NSInteger)self.pickHeight, 512);
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4
        hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    if (!bitmap || !bitmap.bitmapData) return;
    if (bitmap.bytesPerRow != width * 4 ||
        neiv_callback_render_picked_mask(self.pickWorking.bytes, self.pickWorking.length,
            bitmap.bitmapData, bitmap.bytesPerRow * height, self.pickWidth, self.pickHeight,
            width, height, (int)self.pickedHue, (int)self.pickedWidth,
            (int)self.pickedSoftness) != 0) return;
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [image addRepresentation:bitmap];
    self.pickedMaskImage = image;
    [self setNeedsDisplay:YES];
}
- (void)setCropMode:(BOOL)cropMode {
    _cropMode = cropMode;
    self.draggingCrop = NO;
    self.cropSelection = cropMode && self.sourceWidth > 1 && self.sourceHeight > 1 ?
        NSMakeRect(0, 0, self.sourceWidth, self.sourceHeight) : NSZeroRect;
    self.cropHasUserSelection = NO;
    [self setNeedsDisplay:YES];
    [self.window invalidateCursorRectsForView:self];
    if (cropMode) [self publishCropSelection];
}
- (CGFloat)selectedAspectRatio {
    switch (self.cropAspectPreset) {
        case 1: return 1;
        case 2: return 4.0 / 3.0;
        case 3: return 3.0 / 2.0;
        case 4: return 16.0 / 9.0;
        default: return 0;
    }
}
- (NSSize)integerAspectExtentWithinWidth:(CGFloat)width height:(CGFloat)height {
    NSInteger numerator = 0, denominator = 1;
    switch (self.cropAspectPreset) {
        case 1: numerator = 1; break;
        case 2: numerator = 4; denominator = 3; break;
        case 3: numerator = 3; denominator = 2; break;
        case 4: numerator = 16; denominator = 9; break;
        default: return NSMakeSize(floor(width), floor(height));
    }
    NSInteger units = (NSInteger)floor(MIN(width / numerator, height / denominator));
    return NSMakeSize(units * numerator, units * denominator);
}
- (void)publishCropSelection {
    NSRect selected = self.cropSelection;
    if (selected.size.width < 2 || selected.size.height < 2) return;
    char payload[192];
    snprintf(payload, sizeof(payload),
        "{\"left\":%ld,\"top\":%ld,\"width\":%ld,\"height\":%ld,\"angleMillidegrees\":%ld}",
        (long)(self.cropOriginLeft + (NSInteger)selected.origin.x),
        (long)(self.cropOriginTop + (NSInteger)selected.origin.y),
        (long)selected.size.width, (long)selected.size.height,
        (long)self.straightenMillidegrees);
    neiv_publish_event("lightcept.crop", payload, self.windowHandle);
}
- (void)setCropAspectPreset:(NSInteger)preset {
    if (preset < 0 || preset > 4) return;
    NSInteger previousPreset = _cropAspectPreset;
    _cropAspectPreset = preset;
    CGFloat ratio = [self selectedAspectRatio];
    if (!self.cropMode || ratio == 0 || NSIsEmptyRect(self.cropSelection)) return;
    NSRect old = self.cropSelection;
    NSSize extent = [self integerAspectExtentWithinWidth:old.size.width height:old.size.height];
    if (extent.width < 2 || extent.height < 2) {
        NSInteger minimumWidth[] = {0, 2, 4, 3, 16};
        NSInteger minimumHeight[] = {0, 2, 3, 2, 9};
        extent = NSMakeSize(minimumWidth[preset], minimumHeight[preset]);
    }
    if (extent.width > self.sourceWidth || extent.height > self.sourceHeight) {
        _cropAspectPreset = previousPreset;
        return;
    }
    NSInteger left = (NSInteger)floor(NSMidX(old) - extent.width / 2);
    NSInteger top = (NSInteger)floor(NSMidY(old) - extent.height / 2);
    NSInteger roundedWidth = (NSInteger)extent.width;
    NSInteger roundedHeight = (NSInteger)extent.height;
    left = MIN((NSInteger)self.sourceWidth - roundedWidth, MAX(0, left));
    top = MIN((NSInteger)self.sourceHeight - roundedHeight, MAX(0, top));
    self.cropSelection = NSMakeRect(left, top, roundedWidth, roundedHeight);
    self.cropHasUserSelection = YES;
    [self setNeedsDisplay:YES];
    [self publishCropSelection];
}
- (NSRect)selectionFromAnchor:(NSPoint)anchor toPoint:(NSPoint)end {
    CGFloat dx = end.x - anchor.x, dy = end.y - anchor.y;
    CGFloat width = fabs(dx), height = fabs(dy);
    CGFloat ratio = [self selectedAspectRatio];
    if (ratio > 0) {
        NSSize extent = [self integerAspectExtentWithinWidth:width height:height];
        width = extent.width;
        height = extent.height;
        NSInteger roundedAnchorX = (NSInteger)round(anchor.x);
        NSInteger roundedAnchorY = (NSInteger)round(anchor.y);
        NSInteger x0 = dx < 0 ? roundedAnchorX - (NSInteger)width : roundedAnchorX;
        NSInteger y0 = dy < 0 ? roundedAnchorY - (NSInteger)height : roundedAnchorY;
        return NSMakeRect(x0, y0, width, height);
    }
    CGFloat left = dx < 0 ? anchor.x - width : anchor.x;
    CGFloat top = dy < 0 ? anchor.y - height : anchor.y;
    NSInteger x0 = MAX(0, (NSInteger)floor(left));
    NSInteger y0 = MAX(0, (NSInteger)floor(top));
    NSInteger x1 = MIN((NSInteger)self.sourceWidth, (NSInteger)ceil(left + width));
    NSInteger y1 = MIN((NSInteger)self.sourceHeight, (NSInteger)ceil(top + height));
    return NSMakeRect(x0, y0, MAX(0, x1 - x0), MAX(0, y1 - y0));
}
- (NSPoint)sourcePointForViewPoint:(NSPoint)point {
    NSRect target = [self imageRect];
    CGFloat scale = target.size.width / self.sourceWidth;
    return NSMakePoint(MIN(self.sourceWidth, MAX(0, (point.x - target.origin.x) / scale)),
        MIN(self.sourceHeight, MAX(0, (point.y - target.origin.y) / scale)));
}
- (void)setZoomPercent:(NSInteger)zoomPercent {
    _zoomPercent = zoomPercent;
    if (zoomPercent == 0) self.pan = NSZeroPoint;
    [self clearSourceDetail];
    [self.window invalidateCursorRectsForView:self];
    if (self.viewportChanged) self.viewportChanged();
}
- (void)setComparisonMode:(NSInteger)comparisonMode {
    _comparisonMode = comparisonMode;
    [self setNeedsDisplay:YES];
    [self.window invalidateCursorRectsForView:self];
}
- (NSRect)imageRect {
    NSImage *image = self.image;
    if (!image || image.size.width <= 0 || image.size.height <= 0) return NSZeroRect;
    CGFloat sourceWidth = self.sourceWidth > 0 ? self.sourceWidth : image.size.width;
    CGFloat sourceHeight = self.sourceHeight > 0 ? self.sourceHeight : image.size.height;
    NSSize bounds = self.bounds.size;
    CGFloat fit = MIN(bounds.width / sourceWidth, bounds.height / sourceHeight);
    CGFloat backing = self.window.backingScaleFactor > 0 ? self.window.backingScaleFactor : 1.0;
    CGFloat scale = self.zoomPercent == 0 ? fit : self.zoomPercent / (100.0 * backing);
    CGFloat width = sourceWidth * scale;
    CGFloat height = sourceHeight * scale;
    CGFloat maxX = MAX(0, (width - bounds.width) / 2);
    CGFloat maxY = MAX(0, (height - bounds.height) / 2);
    self.pan = NSMakePoint(MIN(maxX, MAX(-maxX, self.pan.x)), MIN(maxY, MAX(-maxY, self.pan.y)));
    CGFloat x = (bounds.width - width) / 2 + self.pan.x;
    CGFloat y = (bounds.height - height) / 2 + self.pan.y;
    if (self.zoomPercent > 0) {
        x = round(x * backing) / backing;
        y = round(y * backing) / backing;
    }
    return NSMakeRect(x, y, width, height);
}

- (NSRect)visibleSourceRect {
    if (!self.image || self.sourceWidth == 0 || self.sourceHeight == 0 || self.zoomPercent == 0) return NSZeroRect;
    NSRect target = [self imageRect];
    NSRect visible = NSIntersectionRect(target, self.bounds);
    if (NSIsEmptyRect(visible)) return NSZeroRect;
    CGFloat scale = target.size.width / self.sourceWidth;
    NSInteger left = MAX(0, (NSInteger)floor((NSMinX(visible) - NSMinX(target)) / scale));
    NSInteger top = MAX(0, (NSInteger)floor((NSMinY(visible) - NSMinY(target)) / scale));
    NSInteger right = MIN((NSInteger)self.sourceWidth, (NSInteger)ceil((NSMaxX(visible) - NSMinX(target)) / scale));
    NSInteger bottom = MIN((NSInteger)self.sourceHeight, (NSInteger)ceil((NSMaxY(visible) - NSMinY(target)) / scale));
    return NSMakeRect(left, top, MAX(0, right - left), MAX(0, bottom - top));
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    if (self.viewportChanged) self.viewportChanged();
}

- (void)viewDidChangeBackingProperties {
    [super viewDidChangeBackingProperties];
    [self clearSourceDetail];
    if (self.viewportChanged) self.viewportChanged();
}

- (void)drawDetailImages:(NSArray<NSImage *> *)images inImageRect:(NSRect)target {
    if (images.count == 0 || self.sourceWidth == 0) return;
    CGFloat scale = target.size.width / self.sourceWidth;
    CGFloat backing = self.window.backingScaleFactor > 0 ? self.window.backingScaleFactor : 1.0;
    NSRect composed = images == self.detailImages ? self.composedAfterRect :
        images == self.detailBeforeImages ? self.composedBeforeRect : NSZeroRect;
    if (!NSIsEmptyRect(composed) && images.count == 1) {
        NSRect destination = NSMakeRect(target.origin.x + composed.origin.x * scale,
            target.origin.y + composed.origin.y * scale,
            composed.size.width * scale, composed.size.height * scale);
        [images[0] drawInRect:destination fromRect:NSZeroRect
            operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES hints:nil];
        return;
    }
    if (images.count != self.detailRects.count) return;
    if (images.count > 1 && scale * backing < 1.0) {
        NSRect extent = NSZeroRect;
        for (NSValue *value in self.detailRects)
            extent = NSIsEmptyRect(extent) ? value.rectValue : NSUnionRect(extent, value.rectValue);
        size_t width = (size_t)extent.size.width, height = (size_t)extent.size.height;
        if (width > 0 && height > 0 && width <= INT32_MAX &&
            height <= 50000000 / width && height <= INT32_MAX) {
            NSMutableData *joined = [NSMutableData dataWithLength:width * height * 4];
            CGImageRef first = NULL;
            BOOL valid = joined != nil;
            for (NSUInteger index = 0; valid && index < images.count; index++) {
                NSRect tile = self.detailRects[index].rectValue;
                CGImageRef source = [images[index] CGImageForProposedRect:NULL context:nil hints:nil];
                CGDataProviderRef provider = source ? CGImageGetDataProvider(source) : NULL;
                CFDataRef bytes = provider ? CGDataProviderCopyData(provider) : NULL;
                size_t tileWidth = (size_t)tile.size.width, tileHeight = (size_t)tile.size.height;
                size_t stride = source ? CGImageGetBytesPerRow(source) : 0;
                valid = source && bytes && CGImageGetWidth(source) == tileWidth &&
                    CGImageGetHeight(source) == tileHeight && stride >= tileWidth * 4 &&
                    CFDataGetLength(bytes) >= stride * tileHeight &&
                    CGImageGetBitsPerPixel(source) == 32 &&
                    CGImageGetBitsPerComponent(source) == 8 &&
                    CGColorSpaceGetNumberOfComponents(CGImageGetColorSpace(source)) == 3 &&
                    tile.origin.x >= extent.origin.x && tile.origin.y >= extent.origin.y &&
                    NSMaxX(tile) <= NSMaxX(extent) && NSMaxY(tile) <= NSMaxY(extent);
                if (valid) {
                    if (!first) first = source;
                    valid = CGImageGetBitmapInfo(source) == CGImageGetBitmapInfo(first) &&
                        CFEqual(CGImageGetColorSpace(source), CGImageGetColorSpace(first));
                }
                if (valid) {
                    size_t left = (size_t)(tile.origin.x - extent.origin.x);
                    size_t top = (size_t)(tile.origin.y - extent.origin.y);
                    const UInt8 *input = CFDataGetBytePtr(bytes);
                    UInt8 *output = joined.mutableBytes;
                    for (size_t row = 0; row < tileHeight; row++)
                        memcpy(output + ((top + row) * width + left) * 4,
                            input + row * stride, tileWidth * 4);
                }
                if (bytes) CFRelease(bytes);
            }
            if (valid && first) {
                CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)joined);
                CGImageRef combined = provider ? CGImageCreate(width, height, 8, 32, width * 4,
                    CGImageGetColorSpace(first), CGImageGetBitmapInfo(first), provider,
                    NULL, CGImageGetShouldInterpolate(first), CGImageGetRenderingIntent(first)) : NULL;
                if (provider) CGDataProviderRelease(provider);
                if (combined) {
                    NSImage *image = [[NSImage alloc] initWithCGImage:combined
                        size:NSMakeSize(width, height)];
                    CGImageRelease(combined);
                    if (images == self.detailImages) {
                        self.detailImages = @[image];
                        self.composedAfterRect = extent;
                    } else if (images == self.detailBeforeImages) {
                        self.detailBeforeImages = @[image];
                        self.composedBeforeRect = extent;
                    }
                    NSRect destination = NSMakeRect(target.origin.x + extent.origin.x * scale,
                        target.origin.y + extent.origin.y * scale, width * scale, height * scale);
                    [image drawInRect:destination fromRect:NSZeroRect
                        operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES hints:nil];
                    return;
                }
            }
        }
    }
    [NSGraphicsContext saveGraphicsState];
    if (scale * backing >= 1.0)
        NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationNone;
    for (NSUInteger index = 0; index < images.count; index++) {
        NSRect rect = self.detailRects[index].rectValue;
        NSRect destination = NSMakeRect(target.origin.x + rect.origin.x * scale,
            target.origin.y + rect.origin.y * scale, rect.size.width * scale, rect.size.height * scale);
        [images[index] drawInRect:destination fromRect:NSZeroRect operation:NSCompositingOperationCopy
            fraction:1 respectFlipped:YES hints:nil];
    }
    [NSGraphicsContext restoreGraphicsState];
}
- (CGFloat)dividerXForImageRect:(NSRect)target {
    return target.origin.x + target.size.width * self.splitFraction;
}
- (void)drawDividerAtX:(CGFloat)divider inImageRect:(NSRect)target {
    CGFloat top = MAX(0, target.origin.y);
    CGFloat bottom = MIN(self.bounds.size.height, NSMaxY(target));
    if (divider < 0 || divider >= self.bounds.size.width || bottom <= top) return;
    [[NSColor colorWithCalibratedWhite:0.92 alpha:0.9] setFill];
    NSRectFill(NSMakeRect(divider - 1, top, 2, bottom - top));
    CGFloat centerY = (top + bottom) / 2;
    NSRect handle = NSMakeRect(divider - 19, centerY - 30, 38, 60);
    NSBezierPath *shadow = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(handle, -2, -2) xRadius:20 yRadius:20];
    [[NSColor colorWithCalibratedWhite:0 alpha:0.36] setFill];
    [shadow fill];
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:handle xRadius:18 yRadius:18];
    [[NSColor colorWithCalibratedRed:0.17 green:0.23 blue:0.18 alpha:0.96] setFill];
    [pill fill];
    [[NSColor colorWithCalibratedWhite:0.94 alpha:0.95] setStroke];
    pill.lineWidth = 1.5;
    [pill stroke];
    [[NSColor colorWithCalibratedWhite:0.95 alpha:1] setStroke];
    NSBezierPath *grip = [NSBezierPath bezierPath];
    grip.lineWidth = 2;
    [grip moveToPoint:NSMakePoint(divider - 8, centerY)];
    [grip lineToPoint:NSMakePoint(divider - 3, centerY - 5)];
    [grip moveToPoint:NSMakePoint(divider - 8, centerY)];
    [grip lineToPoint:NSMakePoint(divider - 3, centerY + 5)];
    [grip moveToPoint:NSMakePoint(divider + 8, centerY)];
    [grip lineToPoint:NSMakePoint(divider + 3, centerY - 5)];
    [grip moveToPoint:NSMakePoint(divider + 8, centerY)];
    [grip lineToPoint:NSMakePoint(divider + 3, centerY + 5)];
    [grip stroke];
}
- (void)drawSplitInRect:(NSRect)target {
    CGFloat divider = [self dividerXForImageRect:target];
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(NSMakeRect(0, 0, MAX(0, divider), self.bounds.size.height));
    [self.beforeImage drawInRect:target fromRect:NSZeroRect operation:NSCompositingOperationCopy
        fraction:1 respectFlipped:YES hints:nil];
    [self drawDetailImages:self.detailBeforeImages inImageRect:target];
    [NSGraphicsContext restoreGraphicsState];
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(NSMakeRect(divider, 0, MAX(0, self.bounds.size.width - divider), self.bounds.size.height));
    [self.image drawInRect:target fromRect:NSZeroRect operation:NSCompositingOperationCopy
        fraction:1 respectFlipped:YES hints:nil];
    [self drawDetailImages:self.detailImages inImageRect:target];
    [NSGraphicsContext restoreGraphicsState];
    [self drawDividerAtX:divider inImageRect:target];
}
- (void)drawRect:(NSRect)dirtyRect {
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(self.bounds);
    [[NSColor colorWithCalibratedRed:0.059 green:0.075 blue:0.063 alpha:1] setFill];
    NSRectFill(dirtyRect);
    NSImage *image = self.image;
    NSRect target = [self imageRect];
    if (!image || NSIsEmptyRect(target)) {
        [NSGraphicsContext restoreGraphicsState];
        return;
    }
    if (self.comparisonMode == 1 && self.beforeImage) image = self.beforeImage;
    if (self.comparisonMode == 2 && self.beforeImage) [self drawSplitInRect:target];
    else {
        [image drawInRect:target fromRect:NSZeroRect operation:NSCompositingOperationCopy
            fraction:1 respectFlipped:YES hints:nil];
        [self drawDetailImages:self.comparisonMode == 1 ? self.detailBeforeImages : self.detailImages
            inImageRect:target];
    }
    if (self.pickedMaskVisible && self.pickedMaskImage)
        [self.pickedMaskImage drawInRect:target fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver fraction:1
            respectFlipped:YES hints:nil];
    if (self.cropMode && !NSIsEmptyRect(self.cropSelection) && self.sourceWidth > 0) {
        CGFloat scale = target.size.width / self.sourceWidth;
        NSRect selected = NSMakeRect(target.origin.x + self.cropSelection.origin.x * scale,
            target.origin.y + self.cropSelection.origin.y * scale,
            self.cropSelection.size.width * scale, self.cropSelection.size.height * scale);
        [[NSColor colorWithCalibratedRed:0.93 green:0.77 blue:0.42 alpha:1] setStroke];
        NSBezierPath *outline = [NSBezierPath bezierPathWithRect:selected];
        outline.lineWidth = 2;
        [outline stroke];
        NSBezierPath *guides = [NSBezierPath bezierPath];
        guides.lineWidth = 1;
        for (int part = 1; part <= 2; part++) {
            CGFloat x = NSMinX(selected) + selected.size.width * part / 3;
            CGFloat y = NSMinY(selected) + selected.size.height * part / 3;
            [guides moveToPoint:NSMakePoint(x, NSMinY(selected))];
            [guides lineToPoint:NSMakePoint(x, NSMaxY(selected))];
            [guides moveToPoint:NSMakePoint(NSMinX(selected), y)];
            [guides lineToPoint:NSMakePoint(NSMaxX(selected), y)];
        }
        [guides stroke];
        CGFloat handleSize = 8;
        NSPoint corners[4] = {
            NSMakePoint(NSMinX(selected), NSMinY(selected)),
            NSMakePoint(NSMaxX(selected), NSMinY(selected)),
            NSMakePoint(NSMinX(selected), NSMaxY(selected)),
            NSMakePoint(NSMaxX(selected), NSMaxY(selected))
        };
        [[NSColor colorWithCalibratedRed:0.98 green:0.86 blue:0.62 alpha:1] setFill];
        for (int index = 0; index < 4; index++)
            NSRectFill(NSMakeRect(corners[index].x - handleSize / 2,
                corners[index].y - handleSize / 2, handleSize, handleSize));
    }
    [NSGraphicsContext restoreGraphicsState];
}
- (void)resetCursorRects {
    [super resetCursorRects];
    if (self.comparisonMode != 2 || !self.beforeImage || !self.image) return;
    NSRect target = [self imageRect];
    CGFloat divider = target.origin.x + target.size.width * self.splitFraction;
    NSRect grip = NSIntersectionRect(NSMakeRect(divider - 24, target.origin.y, 48, target.size.height), self.bounds);
    if (!NSIsEmptyRect(grip)) [self addCursorRect:grip cursor:NSCursor.openHandCursor];
}
- (void)updateTrackingAreas {
    if (self.cursorTrackingArea) [self removeTrackingArea:self.cursorTrackingArea];
    self.cursorTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
            NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:self.cursorTrackingArea];
    [super updateTrackingAreas];
}
- (void)updateComparisonCursor:(NSEvent *)event {
    if (self.cropMode) { [NSCursor.crosshairCursor set]; return; }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect target = [self imageRect];
    CGFloat divider = target.origin.x + target.size.width * self.splitFraction;
    if (self.comparisonMode == 2 && NSPointInRect(point, target) && fabs(point.x - divider) <= 24)
        [NSCursor.openHandCursor set];
    else [NSCursor.arrowCursor set];
}
- (void)mouseMoved:(NSEvent *)event { [self updateComparisonCursor:event]; }
- (void)mouseEntered:(NSEvent *)event { [self updateComparisonCursor:event]; }
- (void)mouseExited:(NSEvent *)event { (void)event; [NSCursor.arrowCursor set]; }
- (void)mouseDown:(NSEvent *)event {
    self.dragStart = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect target = [self imageRect];
    if (self.pickColorMode && self.pickWorking.length == self.pickWidth * self.pickHeight * 3 * sizeof(double) &&
        self.pickWidth > 0 && self.pickHeight > 0 && NSPointInRect(self.dragStart, target)) {
        size_t x = MIN(self.pickWidth - 1, (size_t)MAX(0, (NSInteger)((self.dragStart.x - target.origin.x) * self.pickWidth / target.size.width)));
        size_t y = MIN(self.pickHeight - 1, (size_t)MAX(0, (NSInteger)((self.dragStart.y - target.origin.y) * self.pickHeight / target.size.height)));
        const double *pixels = self.pickWorking.bytes;
        size_t index = (y * self.pickWidth + x) * 3;
        int hue = neiv_callback_sample_picked_hue(pixels + index, 3 * sizeof(double));
        char payload[64];
        snprintf(payload, sizeof(payload), "{\"hue\":%d}", hue);
        neiv_publish_event("lightcept.color_pick", payload, self.windowHandle);
        self.pickColorMode = NO;
        [self.window invalidateCursorRectsForView:self];
        return;
    }
    if (self.cropMode && self.image && self.sourceWidth > 0 && NSPointInRect(self.dragStart, target)) {
        self.draggingCrop = YES;
        self.cropStart = [self sourcePointForViewPoint:self.dragStart];
        self.cropDragOriginal = self.cropSelection;
        self.cropDragKind = 0;
        if (self.cropHasUserSelection && !NSIsEmptyRect(self.cropSelection)) {
            NSRect selected = self.cropSelection;
            CGFloat tolerance = 12 * self.sourceWidth / target.size.width;
            NSPoint corners[4] = {
                NSMakePoint(NSMinX(selected), NSMinY(selected)),
                NSMakePoint(NSMaxX(selected), NSMinY(selected)),
                NSMakePoint(NSMinX(selected), NSMaxY(selected)),
                NSMakePoint(NSMaxX(selected), NSMaxY(selected))
            };
            for (int index = 0; index < 4; index++) {
                if (fabs(self.cropStart.x - corners[index].x) <= tolerance &&
                    fabs(self.cropStart.y - corners[index].y) <= tolerance) {
                    self.cropDragKind = index + 2;
                    break;
                }
            }
            if (self.cropDragKind == 0 && NSPointInRect(self.cropStart, selected))
                self.cropDragKind = 1;
        }
        if (self.cropDragKind == 0) self.cropSelection = NSZeroRect;
        return;
    }
    CGFloat divider = target.origin.x + target.size.width * self.splitFraction;
    self.draggingDivider = self.comparisonMode == 2 && NSPointInRect(self.dragStart, target)
        && fabs(self.dragStart.x - divider) <= 24;
    if (self.draggingDivider) [NSCursor.closedHandCursor set];
}
- (void)mouseDragged:(NSEvent *)event {
    NSPoint current = [self convertPoint:event.locationInWindow fromView:nil];
    if (self.draggingCrop) {
        NSPoint end = [self sourcePointForViewPoint:current];
        if (self.cropDragKind == 1) {
            NSRect original = self.cropDragOriginal;
            NSInteger left = (NSInteger)lround(original.origin.x + end.x - self.cropStart.x);
            NSInteger top = (NSInteger)lround(original.origin.y + end.y - self.cropStart.y);
            left = MIN((NSInteger)self.sourceWidth - (NSInteger)original.size.width, MAX(0, left));
            top = MIN((NSInteger)self.sourceHeight - (NSInteger)original.size.height, MAX(0, top));
            self.cropSelection = NSMakeRect(left, top, original.size.width, original.size.height);
        } else {
            NSPoint anchor = self.cropStart;
            NSRect original = self.cropDragOriginal;
            if (self.cropDragKind == 2) anchor = NSMakePoint(NSMaxX(original), NSMaxY(original));
            if (self.cropDragKind == 3) anchor = NSMakePoint(NSMinX(original), NSMaxY(original));
            if (self.cropDragKind == 4) anchor = NSMakePoint(NSMaxX(original), NSMinY(original));
            if (self.cropDragKind == 5) anchor = NSMakePoint(NSMinX(original), NSMinY(original));
            self.cropSelection = [self selectionFromAnchor:anchor toPoint:end];
        }
        [self setNeedsDisplay:YES];
        return;
    }
    if (self.draggingDivider) {
        NSRect target = [self imageRect];
        self.splitFraction = MIN(0.95, MAX(0.05, (current.x - target.origin.x) / target.size.width));
    } else {
        if (self.detailRects.count > 0) {
            [self clearSourceDetail];
            neiv_publish_event("lightcept.detail", "{\"ready\":false}", self.windowHandle);
        }
        self.pan = NSMakePoint(self.pan.x + current.x - self.dragStart.x,
            self.pan.y + current.y - self.dragStart.y);
    }
    self.dragStart = current;
    [self setNeedsDisplay:YES];
}
- (void)mouseUp:(NSEvent *)event {
    if (self.draggingCrop) {
        self.draggingCrop = NO;
        if (self.cropSelection.size.width < 2 || self.cropSelection.size.height < 2)
            self.cropSelection = self.cropDragOriginal;
        else self.cropHasUserSelection = YES;
        [self setNeedsDisplay:YES];
        [self publishCropSelection];
        return;
    }
    self.draggingDivider = NO;
    [self.window invalidateCursorRectsForView:self];
    [self updateComparisonCursor:event];
    if (self.viewportChanged) self.viewportChanged();
}
- (void)scrollWheel:(NSEvent *)event {
    if (!(event.modifierFlags & NSEventModifierFlagCommand) || !self.image) {
        [super scrollWheel:event];
        return;
    }
    CGFloat sourceWidth = self.sourceWidth > 0 ? self.sourceWidth : self.image.size.width;
    CGFloat sourceHeight = self.sourceHeight > 0 ? self.sourceHeight : self.image.size.height;
    CGFloat fit = MIN(self.bounds.size.width / sourceWidth,
        self.bounds.size.height / sourceHeight);
    CGFloat backing = self.window.backingScaleFactor > 0 ? self.window.backingScaleFactor : 1.0;
    NSInteger current = self.zoomPercent == 0 ? (NSInteger)lround(fit * backing * 100) : self.zoomPercent;
    CGFloat delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.5 : 10.0);
    NSInteger change = (NSInteger)lround(delta / 5.0) * 5;
    if (change == 0) change = delta > 0 ? 5 : -5;
    NSInteger next = MIN(400, MAX(25, current + change));
    self.zoomPercent = next;
    char payload[48];
    snprintf(payload, sizeof(payload), "{\"percent\":%ld}", (long)next);
    neiv_publish_event("lightcept.zoom", payload, self.windowHandle);
}
@end
