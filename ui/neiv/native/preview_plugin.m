#import "app_host_plugin.h"
#import "generated/neiv_callbacks.h"
#import "preview_zoom_view.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGConvertColorDataWithFormat.h>
#import <math.h>
#import <CommonCrypto/CommonDigest.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

typedef NS_ENUM(NSInteger, LightceptProjectSchema) {
    LightceptProjectSchemaLight = 2,
    LightceptProjectSchemaColor = 3,
    LightceptProjectSchemaDetail = 4,
    LightceptProjectSchemaSaturation = 5,
    LightceptProjectSchemaTexture = 6,
    LightceptProjectSchemaGeometry = 7,
    LightceptProjectSchemaTransform = 8,
    LightceptProjectSchemaHSL = 9,
    LightceptProjectSchemaCurve = 10,
    LightceptProjectSchemaLumaCurve = 11,
    LightceptProjectSchemaGrading = 12,
    LightceptProjectSchemaPickedColor = 13,
};

typedef NS_ENUM(NSInteger, LightceptProjectSaveStatus) {
    LightceptProjectSaveSaved = 2,
    LightceptProjectSaveCancelled = 3,
    LightceptProjectSaveIOFailure = 4,
    LightceptProjectSaveChangedSource = 5,
};

typedef NS_ENUM(NSUInteger, LightceptProjectField) {
    LightceptProjectExposure = 0,
    LightceptProjectContrast = 1,
    LightceptProjectShadows = 2,
    LightceptProjectHighlights = 3,
    LightceptProjectBlacks = 4,
    LightceptProjectWhites = 5,
    LightceptProjectWarmth = 6,
    LightceptProjectTint = 7,
    LightceptProjectVibrance = 8,
    LightceptProjectSaturation = 9,
    LightceptProjectClarity = 10,
    LightceptProjectTexture = 11,
    LightceptProjectCropLeft = 12,
    LightceptProjectCropTop = 13,
    LightceptProjectCropWidth = 14,
    LightceptProjectCropHeight = 15,
    LightceptProjectStraighten = 16,
    LightceptProjectTransform = 17,
    LightceptProjectHSL = 18,
    LightceptProjectCurve = 42,
    LightceptProjectGrading = 54,
};

static NSUInteger projectEntryLength(LightceptProjectSchema schema) {
    switch (schema) {
        case LightceptProjectSchemaLight: return 6;
        case LightceptProjectSchemaColor: return 9;
        case LightceptProjectSchemaDetail: return 10;
        case LightceptProjectSchemaSaturation: return 11;
        case LightceptProjectSchemaTexture: return 12;
        case LightceptProjectSchemaGeometry: return 17;
        case LightceptProjectSchemaTransform: return 18;
        case LightceptProjectSchemaHSL: return 42;
        case LightceptProjectSchemaCurve: return 51;
        case LightceptProjectSchemaLumaCurve: return 54;
        case LightceptProjectSchemaGrading: return 67;
        case LightceptProjectSchemaPickedColor: return 74;
    }
    return 0;
}

// Older recipes omit later controls; schema 4 stores Clarity where schema 5
// stores Saturation. readProject validates entry lengths before this accessor.
static int projectValue(NSArray *entry, LightceptProjectSchema schema, LightceptProjectField field) {
    if (field == LightceptProjectTransform && schema < LightceptProjectSchemaTransform) return 1;
    if (field >= LightceptProjectCropLeft && schema < LightceptProjectSchemaGeometry) return 0;
    if (field >= LightceptProjectWarmth && schema < LightceptProjectSchemaColor) return 0;
    if (field == LightceptProjectSaturation && schema < LightceptProjectSchemaSaturation) return 0;
    if (field == LightceptProjectTexture && schema < LightceptProjectSchemaTexture) return 0;
    if (field == LightceptProjectClarity) {
        if (schema < LightceptProjectSchemaDetail) return 0;
        return [entry[schema == LightceptProjectSchemaDetail ? LightceptProjectSaturation : LightceptProjectClarity] intValue];
    }
    return [entry[field] intValue];
}

static void previewDimensions(long long window, unsigned int generation, unsigned int *width, unsigned int *height);
static NSString *previewDisplayName(long long window, unsigned int generation);
void lightcept_native_document_lock(void);
void lightcept_native_document_unlock(void);

// Serialization only: Cyna owns the workflow state and its transitions.
int lightcept_native_write_snapshot(char *out, int capacity, long long window, unsigned int documentID, unsigned int generation,
                                    unsigned int committed, unsigned int phase, int hasPhoto,
                                    unsigned int failure, int exposureTenths,
                                    int contrastPercent, int shadowsPercent, int highlightsPercent, int blacksPercent, int whitesPercent, int warmthPercent, int tintPercent, int vibrancePercent, int saturationPercent, int clarityPercent, int texturePercent,
                                    int exposureAvailable, unsigned int editRevision, int canUndo, int canRedo, unsigned int historyLength, unsigned int historyCursor, unsigned int projectStatus) {
    if (!out || capacity < 1 || capacity > 65536 || phase > 3 || failure > 11 || projectStatus > 5 || historyLength > 32 || (historyLength && historyCursor >= historyLength) ||
        (hasPhoto != 0 && hasPhoto != 1) || exposureTenths < -160 || exposureTenths > 160 || contrastPercent < -100 || contrastPercent > 100 ||
        shadowsPercent < -100 || shadowsPercent > 100 || highlightsPercent < -100 || highlightsPercent > 100 || blacksPercent < -100 || blacksPercent > 100 || whitesPercent < -100 || whitesPercent > 100 || warmthPercent < -100 || warmthPercent > 100 || tintPercent < -100 || tintPercent > 100 || vibrancePercent < -100 || vibrancePercent > 100 || saturationPercent < -100 || saturationPercent > 100 || clarityPercent < -100 || clarityPercent > 100 || texturePercent < -100 || texturePercent > 100 ||
        (exposureAvailable != 0 && exposureAvailable != 1) || (canUndo != 0 && canUndo != 1) || (canRedo != 0 && canRedo != 1)) return -1;
    unsigned int width = 0, height = 0;
    if (hasPhoto) previewDimensions(window, committed, &width, &height);
    NSString *displayName = hasPhoto ? previewDisplayName(window, committed) : @"";
    if (!displayName) displayName = @"";
    NSData *nameBytes = [displayName dataUsingEncoding:NSUTF8StringEncoding];
    if (nameBytes.length > 255) displayName = @"";
    NSData *encodedName = [NSJSONSerialization dataWithJSONObject:@[displayName] options:0 error:nil];
    NSString *nameArray = [[NSString alloc] initWithData:encodedName encoding:NSUTF8StringEncoding];
    NSString *nameJSON = nameArray.length >= 2 ? [nameArray substringWithRange:NSMakeRange(1, nameArray.length - 2)] : @"\"\"";
    int count = snprintf(out, (size_t)capacity,
        "{\"documentId\":%u,\"generation\":%u,\"committedGeneration\":%u,\"previewWidth\":%u,\"previewHeight\":%u,\"phase\":%u,\"hasPhoto\":%s,\"sourceName\":%s,\"failureCode\":%u,\"exposureTenths\":%d,\"contrastPercent\":%d,\"shadowsPercent\":%d,\"highlightsPercent\":%d,\"blacksPercent\":%d,\"whitesPercent\":%d,\"warmthPercent\":%d,\"tintPercent\":%d,\"vibrancePercent\":%d,\"saturationPercent\":%d,\"clarityPercent\":%d,\"texturePercent\":%d,\"exposureAvailable\":%s,\"editRevision\":%u,\"canUndo\":%s,\"canRedo\":%s,\"historyLength\":%u,\"historyCursor\":%u,\"projectStatus\":%u}",
        documentID, generation, committed, width, height, phase, hasPhoto ? "true" : "false", nameJSON.UTF8String, failure,
        exposureTenths, contrastPercent, shadowsPercent, highlightsPercent, blacksPercent, whitesPercent, warmthPercent, tintPercent, vibrancePercent, saturationPercent, clarityPercent, texturePercent, exposureAvailable ? "true" : "false", editRevision, canUndo ? "true" : "false", canRedo ? "true" : "false", historyLength, historyCursor, projectStatus);
    if (count < 0 || count >= capacity) return -1;
    return count;
}

extern int neiv_dialog_capability(int save);
extern long long neiv_window_current_handle(void);
extern long long neiv_surface_create_native(long long window, const char *slot, const char *kind, const char *options);
extern int neiv_publish_event(const char *topic, const char *payloadJson, long long targetHandle);

@interface LightceptFrame : NSObject
@property(nonatomic, strong) NSData *pixels;
@property(nonatomic) size_t width;
@property(nonatomic) size_t height;
@property(nonatomic) size_t sourceWidth;
@property(nonatomic) size_t sourceHeight;
@property(nonatomic) size_t sourceCanvasWidth;
@property(nonatomic) size_t sourceCanvasHeight;
@property(nonatomic) unsigned int generation;
@property(nonatomic, copy) NSString *sourcePath;
@property(nonatomic, strong) NSData *sourceDigest;
@property(nonatomic, strong) NSData *workingDigest;
@property(nonatomic, strong) NSData *baselineDigest;
@property(nonatomic, strong) NSData *previewDigest;
@property(nonatomic, copy) NSString *routeID;
@property(nonatomic) BOOL editable;
@property(nonatomic, strong) NSData *preparedWorking;
@property(nonatomic, strong) NSData *preparedBaseline;
@property(nonatomic, strong) NSData *neutralPixels;
@property(nonatomic, strong) NSData *editValues;
@end
@implementation LightceptFrame
@end

@interface LightceptHistogramView : NSView
@property(nonatomic, strong) LightceptFrame *sourceFrame;
@end
@implementation LightceptHistogramView
- (void)setSourceFrame:(LightceptFrame *)sourceFrame {
    _sourceFrame = sourceFrame;
    [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedRed:0.063 green:0.082 blue:0.071 alpha:1] setFill];
    NSRectFill(self.bounds);
    if (!_sourceFrame || _sourceFrame.pixels.length != _sourceFrame.width * _sourceFrame.height * 4) return;
    unsigned int bins[4][128] = {{0}};
    const unsigned char *pixels = _sourceFrame.pixels.bytes;
    size_t count = _sourceFrame.width * _sourceFrame.height;
    size_t step = count > 200000 ? count / 200000 : 1;
    for (size_t i = 0; i < count; i += step) {
        const unsigned char *p = pixels + i * 4;
        unsigned int luminance = (54u * p[0] + 183u * p[1] + 19u * p[2]) >> 8;
        bins[0][luminance >> 1]++;
        for (size_t channel = 0; channel < 3; channel++) bins[channel + 1][p[channel] >> 1]++;
    }
    unsigned int peak = 1;
    for (size_t channel = 0; channel < 4; channel++)
        for (size_t i = 2; i < 126; i++) if (bins[channel][i] > peak) peak = bins[channel][i];
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    [[NSColor colorWithCalibratedRed:0.24 green:0.31 blue:0.27 alpha:0.65] setStroke];
    NSBezierPath *grid = [NSBezierPath bezierPath];
    grid.lineWidth = 0.5;
    for (int i = 1; i < 4; i++) {
        CGFloat x = floor(width * i / 4.0) + 0.5;
        [grid moveToPoint:NSMakePoint(x, 0)];
        [grid lineToPoint:NSMakePoint(x, height)];
    }
    [grid moveToPoint:NSMakePoint(0, floor(height / 2.0) + 0.5)];
    [grid lineToPoint:NSMakePoint(width, floor(height / 2.0) + 0.5)];
    [grid stroke];
    NSColor *colors[4] = {
        [NSColor colorWithCalibratedRed:0.82 green:0.89 blue:0.82 alpha:0.9],
        [NSColor colorWithCalibratedRed:0.90 green:0.38 blue:0.36 alpha:0.30],
        [NSColor colorWithCalibratedRed:0.43 green:0.75 blue:0.49 alpha:0.30],
        [NSColor colorWithCalibratedRed:0.40 green:0.61 blue:0.88 alpha:0.30]
    };
    for (size_t channel = 1; channel < 4; channel++) {
        NSBezierPath *area = [NSBezierPath bezierPath];
        [area moveToPoint:NSMakePoint(0, 0)];
        for (size_t i = 0; i < 128; i++) {
            unsigned int smooth = bins[channel][i];
            if (i > 0) smooth += bins[channel][i - 1];
            if (i < 127) smooth += bins[channel][i + 1];
            CGFloat y = (height - 2) * sqrt(MIN(1.0, (double)smooth / (3.0 * peak)));
            [area lineToPoint:NSMakePoint(width * i / 127.0, y)];
        }
        [area lineToPoint:NSMakePoint(width, 0)];
        [area closePath];
        [colors[channel] setFill];
        [area fill];
    }
    NSBezierPath *luminance = [NSBezierPath bezierPath];
    luminance.lineWidth = 1.2;
    for (size_t i = 0; i < 128; i++) {
        unsigned int smooth = bins[0][i];
        if (i > 0) smooth += bins[0][i - 1];
        if (i < 127) smooth += bins[0][i + 1];
        CGFloat y = (height - 2) * sqrt(MIN(1.0, (double)smooth / (3.0 * peak)));
        NSPoint point = NSMakePoint(width * i / 127.0, y);
        if (i == 0) [luminance moveToPoint:point]; else [luminance lineToPoint:point];
    }
    [colors[0] setStroke];
    [luminance stroke];
}
@end

@interface LightceptPendingPicker : NSObject <NSOpenSavePanelDelegate>
@property(nonatomic, strong) NSOpenPanel *panel;
@property(nonatomic) unsigned int generation;
@property(nonatomic) BOOL projectOnly;
@end
@implementation LightceptPendingPicker
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
    (void)sender;
    if (!self.projectOnly) return YES;
    NSNumber *directory = nil;
    [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:NULL];
    return directory.boolValue || [url.pathExtension caseInsensitiveCompare:@"lightcept"] == NSOrderedSame;
}
@end

@interface LightceptPendingSave : NSObject
@property(nonatomic, strong) NSSavePanel *panel;
@property(nonatomic) unsigned int generation;
@end
@implementation LightceptPendingSave
@end

@interface LightceptPendingExport : NSObject
@property(nonatomic, strong) NSSavePanel *panel;
@property(atomic, strong) NSTask *task;
@property(atomic) NSInteger status;
@property(atomic) BOOL cancelled;
@end
@implementation LightceptPendingExport
@end

@interface LightceptSource : NSObject
@property(nonatomic, copy) NSString *path;
@property(nonatomic) unsigned int generation;
@property(nonatomic, strong) NSData *digest;
@property(nonatomic, strong) NSData *expectedDigest;
@property(nonatomic, strong) NSData *expectedWorkingDigest;
@property(nonatomic, strong) NSData *expectedBaselineDigest;
@property(nonatomic, strong) NSData *expectedPreviewDigest;
@property(nonatomic, copy) NSString *routeID;
@property(nonatomic) size_t expectedWidth;
@property(nonatomic) size_t expectedHeight;
@property(nonatomic, strong) NSData *editValues;
@end
@implementation LightceptSource
@end

static NSData *editValues(int exposure, int contrast, int shadows, int highlights,
    int blacks, int whites, int warmth, int tint, int vibrance, int saturation,
    int clarity, int texture) {
    // The last field is the identity user transform.
    const int values[18] = {exposure, contrast, shadows, highlights, blacks, whites,
        warmth, tint, vibrance, saturation, clarity, texture, 0, 0, 0, 0, 0, 1};
    return [NSData dataWithBytes:values length:sizeof(values)];
}

static BOOL nonneutralGeometry(NSData *values) {
    if (values.length != 18 * sizeof(int) && values.length != 42 * sizeof(int) &&
        values.length != 51 * sizeof(int) && values.length != 54 * sizeof(int) &&
        values.length != 67 * sizeof(int) && values.length != 74 * sizeof(int)) return NO;
    const int *edits = values.bytes;
    for (NSUInteger index = 12; index < 17; index++) if (edits[index]) return YES;
    return edits[17] != 1;
}

static BOOL hasHSL(NSData *values) {
    return values.length == 42 * sizeof(int) || values.length == 51 * sizeof(int) ||
        values.length == 54 * sizeof(int) || values.length == 67 * sizeof(int) || values.length == 74 * sizeof(int);
}

static BOOL hasCurve(NSData *values) { return values.length == 54 * sizeof(int) || values.length == 67 * sizeof(int) || values.length == 74 * sizeof(int); }
static BOOL hasGrading(NSData *values) { return values.length == 67 * sizeof(int) || values.length == 74 * sizeof(int); }
static BOOL hasPickedColor(NSData *values) { return values.length == 74 * sizeof(int); }

static BOOL validGrading(NSData *values) {
    if (!hasGrading(values)) return NO;
    const int *edits = values.bytes;
    for (NSUInteger wheel = 0; wheel < 4; wheel++) {
        NSUInteger index = 54 + wheel * 3;
        if (edits[index] < 0 || edits[index] >= 360 ||
            edits[index + 1] < 0 || edits[index + 1] > 100 ||
            edits[index + 2] < -100 || edits[index + 2] > 100) return NO;
    }
    return edits[66] >= -100 && edits[66] <= 100;
}

static BOOL validPickedColor(NSData *values) {
    if (!hasPickedColor(values)) return NO;
    const int *edits = values.bytes;
    return edits[67] >= 0 && edits[67] < 360 &&
        edits[68] >= 0 && edits[68] <= 90 &&
        edits[69] >= 0 && edits[69] <= 100 &&
        edits[70] >= -100 && edits[70] <= 100 &&
        edits[71] >= -100 && edits[71] <= 100 &&
        edits[72] >= -100 && edits[72] <= 100 &&
        edits[73] >= 0 && edits[73] <= 1;
}

static BOOL validCurve(NSData *values) {
    if (!hasCurve(values)) return NO;
    const int *edits = values.bytes;
    for (NSUInteger channel = 0; channel < 4; channel++) {
        NSUInteger i = 42 + channel * 3;
        if (edits[i] < 0 || edits[i] > edits[i + 1] ||
            edits[i + 1] > edits[i + 2] || edits[i + 2] > 1000) return NO;
    }
    return YES;
}

static BOOL validHSL(NSData *values) {
    if (!hasHSL(values)) return NO;
    const int *edits = values.bytes;
    for (NSUInteger index = 18; index < 42; index++)
        if (edits[index] < -100 || edits[index] > 100) return NO;
    return YES;
}

static NSData *editValuesWithGeometry(NSData *controls, NSArray *entry, LightceptProjectSchema schema) {
    if (controls.length != 18 * sizeof(int) || entry.count != projectEntryLength(schema)) return nil;
    int values[18];
    memcpy(values, controls.bytes, sizeof(values));
    for (NSUInteger index = 12; index < 17; index++) values[index] = [entry[index] intValue];
    values[17] = projectValue(entry, schema, LightceptProjectTransform);
    NSMutableData *result = [NSMutableData dataWithBytes:values length:sizeof(values)];
    if (schema >= LightceptProjectSchemaHSL) {
        int hsl[24];
        for (NSUInteger index = 0; index < 24; index++) hsl[index] = [entry[18 + index] intValue];
        [result appendBytes:hsl length:sizeof(hsl)];
    }
    if (schema >= LightceptProjectSchemaCurve) {
        int curve[12];
        for (NSUInteger index = 0; index < 12; index++) curve[index] =
            schema >= LightceptProjectSchemaLumaCurve || index < 9 ? [entry[42 + index] intValue] : (int[]){250, 500, 750}[index % 3];
        [result appendBytes:curve length:sizeof(curve)];
    }
    if (schema >= LightceptProjectSchemaGrading) {
        int grade[13];
        for (NSUInteger index = 0; index < 13; index++) grade[index] = [entry[54 + index] intValue];
        [result appendBytes:grade length:sizeof(grade)];
    }
    if (schema >= LightceptProjectSchemaPickedColor) {
        int picked[7];
        for (NSUInteger index = 0; index < 7; index++) picked[index] = [entry[67 + index] intValue];
        [result appendBytes:picked length:sizeof(picked)];
    }
    return result;
}

static _Thread_local unsigned int requestedGeneration;
static _Thread_local long long requestedWindow;
static _Thread_local int requestedExposureTenths;
static _Thread_local int requestedContrastPercent;
static _Thread_local int requestedShadowsPercent;
static _Thread_local int requestedHighlightsPercent;
static _Thread_local int requestedBlacksPercent;
static _Thread_local int requestedWhitesPercent;
static _Thread_local int requestedWarmthPercent;
static _Thread_local int requestedTintPercent;
static _Thread_local int requestedVibrancePercent;
static _Thread_local int requestedSaturationPercent;
static _Thread_local int requestedClarityPercent;
static _Thread_local int requestedTexturePercent;
static NSRecursiveLock *documentLock(void) {
    static NSRecursiveLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSRecursiveLock new]; });
    return lock;
}
static NSMutableDictionary<NSNumber *, LightceptFrame *> *committedFrames(void) {
    static NSMutableDictionary *frames;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ frames = [NSMutableDictionary new]; });
    return frames;
}
static void previewDimensions(long long window, unsigned int generation, unsigned int *width, unsigned int *height) {
    *width = 0;
    *height = 0;
    lightcept_native_document_lock();
    LightceptFrame *frame = committedFrames()[@(window)];
    if (frame && frame.generation == generation && frame.width <= 2048 && frame.height <= 2048) {
        *width = (unsigned int)frame.width;
        *height = (unsigned int)frame.height;
    }
    lightcept_native_document_unlock();
}
static NSString *previewDisplayName(long long window, unsigned int generation) {
    lightcept_native_document_lock();
    LightceptFrame *frame = committedFrames()[@(window)];
    NSString *name = frame && frame.generation == generation ? [frame.sourcePath.lastPathComponent copy] : nil;
    lightcept_native_document_unlock();
    return name;
}
static NSMutableDictionary<NSNumber *, LightceptFrame *> *candidateFrames(void) {
    static NSMutableDictionary *frames;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ frames = [NSMutableDictionary new]; });
    return frames;
}
// AppKit views are accessed only on the main thread. The document registry owns
// frames; this table only identifies the currently attached presentation view.
static NSMutableDictionary<NSNumber *, LightceptZoomView *> *previewViews(void) {
    static NSMutableDictionary *views;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ views = [NSMutableDictionary new]; });
    return views;
}
static NSMutableDictionary<NSNumber *, NSNumber *> *zoomLevels(void) {
    static NSMutableDictionary *levels;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ levels = [NSMutableDictionary new]; });
    return levels;
}
static NSMutableDictionary<NSNumber *, NSString *> *regionTokens(void) {
    static NSMutableDictionary *tokens;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tokens = [NSMutableDictionary new]; });
    return tokens;
}
static NSMutableDictionary<NSNumber *, NSTask *> *regionTasks(void) {
    static NSMutableDictionary *tasks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tasks = [NSMutableDictionary new]; });
    return tasks;
}
// Protected by the document lock. A newer edit stops the previous fitted RAW
// worker for this window; its generation still guards publication.
static NSMutableDictionary<NSNumber *, NSTask *> *fittedPreviewTasks(void) {
    static NSMutableDictionary *tasks;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ tasks = [NSMutableDictionary new]; });
    return tasks;
}
static dispatch_queue_t regionQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("dev.neucine.lightcept.source-region", DISPATCH_QUEUE_SERIAL); });
    return queue;
}
static NSMutableDictionary<NSNumber *, NSNumber *> *comparisonModes(void) {
    static NSMutableDictionary *modes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ modes = [NSMutableDictionary new]; });
    return modes;
}
static NSMutableDictionary<NSNumber *, NSNumber *> *proofProfiles(void) {
    static NSMutableDictionary *profiles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ profiles = [NSMutableDictionary new]; });
    return profiles;
}
static NSMutableDictionary<NSNumber *, NSImageView *> *navigatorViews(void) {
    static NSMutableDictionary *views;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ views = [NSMutableDictionary new]; });
    return views;
}
static NSMutableDictionary<NSNumber *, NSImageView *> *filmstripViews(void) {
    static NSMutableDictionary *views;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ views = [NSMutableDictionary new]; });
    return views;
}
static NSMutableDictionary<NSNumber *, LightceptHistogramView *> *histogramViews(void) {
    static NSMutableDictionary *views;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ views = [NSMutableDictionary new]; });
    return views;
}
static CGColorSpaceRef profileSpace(NSInteger kind, NSScreen *screen) {
    if (kind == 1) {
        NSURL *url = [NSBundle.mainBundle URLForResource:@"sRGB2014" withExtension:@"icc"];
        NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
        return data ? CGColorSpaceCreateWithICCData((__bridge CFDataRef)data) : NULL;
    }
    if (kind == 2) return CGColorSpaceCreateWithName(kCGColorSpaceAdobeRGB1998);
    if (kind == 3) {
        NSNumber *display = screen.deviceDescription[@"NSScreenNumber"];
        return display ? CGDisplayCopyColorSpace((CGDirectDisplayID)display.unsignedIntValue) : NULL;
    }
    return CGColorSpaceCreateDeviceRGB();
}

static NSImage *imageForFrameWithProof(LightceptFrame *frame, NSInteger proof, NSScreen *screen) {
    if (!frame || !frame.pixels || frame.width == 0 || frame.height == 0 ||
        frame.width > 10000 || frame.height > 10000 || frame.width > 4194304 / frame.height ||
        frame.pixels.length != frame.width * frame.height * 4) return nil;
    CGColorSpaceRef space = profileSpace(proof, screen);
    if (!space || CGColorSpaceGetNumberOfComponents(space) != 3) {
        if (space) CGColorSpaceRelease(space);
        return nil;
    }
    NSData *pixels = frame.pixels;
    if (proof >= 2) {
        CGColorSpaceRef source = profileSpace(1, screen);
        NSMutableData *converted = [NSMutableData dataWithLength:frame.pixels.length];
        CGColorDataFormat input = {0, source, kCGImageAlphaLast | kCGBitmapByteOrderDefault,
            8, frame.width * 4, kCGRenderingIntentRelativeColorimetric, NULL};
        CGColorDataFormat output = {0, space, kCGImageAlphaLast | kCGBitmapByteOrderDefault,
            8, frame.width * 4, kCGRenderingIntentRelativeColorimetric, NULL};
        BOOL success = source && converted && CGConvertColorDataWithFormat(frame.width, frame.height,
            converted.mutableBytes, output, (void *)frame.pixels.bytes, input, NULL);
        if (source) CGColorSpaceRelease(source);
        if (!success) { CGColorSpaceRelease(space); return nil; }
        pixels = converted;
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    if (!provider) { CGColorSpaceRelease(space); return nil; }
    CGImageRef image = CGImageCreate(frame.width, frame.height, 8, 32, frame.width * 4,
        space, kCGImageAlphaLast | kCGBitmapByteOrderDefault, provider, NULL, false,
        kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    if (!image) return nil;
    NSImage *result = [[NSImage alloc] initWithCGImage:image size:NSMakeSize(frame.width, frame.height)];
    CGImageRelease(image);
    return result;
}
static NSImage *imageForFrame(LightceptFrame *frame) {
    return imageForFrameWithProof(frame, 0, nil);
}
static void scheduleSourceRegion(long long window);
static void updatePreviewView(LightceptZoomView *view, LightceptFrame *frame, long long window) {
    if (!view || !frame) return;
    NSInteger proof = [proofProfiles()[@(window)] integerValue];
    NSScreen *screen = view.window.screen ?: NSScreen.mainScreen;
    NSImage *after = imageForFrameWithProof(frame, proof, screen);
    if (!after) return;
    NSImage *before = nil;
    if (frame.neutralPixels.length == frame.pixels.length) {
        LightceptFrame *neutral = [LightceptFrame new];
        neutral.pixels = frame.neutralPixels;
        neutral.width = frame.width;
        neutral.height = frame.height;
        before = imageForFrameWithProof(neutral, proof, screen);
    }
    view.sourceWidth = frame.sourceWidth;
    view.sourceHeight = frame.sourceHeight;
    const int *edits = frame.editValues.length >= 18 * sizeof(int) ? frame.editValues.bytes : NULL;
    view.cropOriginLeft = edits ? edits[12] : 0;
    view.cropOriginTop = edits ? edits[13] : 0;
    view.straightenMillidegrees = edits ? edits[16] : 0;
    view.pickWorking = frame.preparedWorking;
    view.pickWidth = frame.width;
    view.pickHeight = frame.height;
    view.image = after;
    view.beforeImage = before;
    view.comparisonMode = [comparisonModes()[@(window)] integerValue];
    [view setNeedsDisplay:YES];
}

int lightcept_native_set_crop_mode(long long window, int enabled) {
    if (window <= 0 || (enabled != 0 && enabled != 1)) return 0;
    void (^apply)(void) = ^{
        LightceptZoomView *view = previewViews()[@(window)];
        if (view) view.cropMode = enabled != 0;
    };
    if ([NSThread isMainThread]) apply();
    else dispatch_sync(dispatch_get_main_queue(), apply);
    return 1;
}

int lightcept_native_set_color_pick_mode(long long window, int enabled) {
    if (window <= 0 || (enabled != 0 && enabled != 1)) return 0;
    void (^apply)(void) = ^{
        LightceptZoomView *view = previewViews()[@(window)];
        if (view) view.pickColorMode = enabled != 0;
    };
    if ([NSThread isMainThread]) apply();
    else dispatch_sync(dispatch_get_main_queue(), apply);
    return 1;
}

int lightcept_native_show_color_selection(long long window, int enabled, int hue, int width, int softness) {
    if (window <= 0 || (enabled != 0 && enabled != 1) || hue < 0 || hue >= 360 ||
        width < 2 || width > 90 || softness < 1 || softness > 100) return 0;
    void (^apply)(void) = ^{
        LightceptZoomView *view = previewViews()[@(window)];
        if (!view) return;
        view.pickedMaskVisible = enabled != 0;
        view.pickedHue = hue;
        view.pickedWidth = width;
        view.pickedSoftness = softness;
        [view refreshPickedMask];
    };
    if ([NSThread isMainThread]) apply();
    else dispatch_sync(dispatch_get_main_queue(), apply);
    return 1;
}

int lightcept_native_set_crop_aspect(long long window, int preset) {
    if (window <= 0 || preset < 0 || preset > 4) return 0;
    void (^apply)(void) = ^{
        LightceptZoomView *view = previewViews()[@(window)];
        if (view) view.cropAspectPreset = preset;
    };
    if ([NSThread isMainThread]) apply();
    else dispatch_sync(dispatch_get_main_queue(), apply);
    return 1;
}

int lightcept_native_set_comparison(long long window, int mode, int proof) {
    if (window <= 0 || mode < 0 || mode > 2 || proof < 0 || proof > 3) return 0;
    __block int applied = 0;
    void (^apply)(void) = ^{
        LightceptZoomView *view = previewViews()[@(window)];
        lightcept_native_document_lock();
        LightceptFrame *frame = committedFrames()[@(window)];
        lightcept_native_document_unlock();
        if (!view || !frame) return;
        NSScreen *screen = view.window.screen ?: NSScreen.mainScreen;
        NSImage *after = imageForFrameWithProof(frame, proof, screen);
        if (!after) return;
        NSImage *before = nil;
        if (frame.neutralPixels.length == frame.pixels.length) {
            LightceptFrame *neutral = [LightceptFrame new];
            neutral.pixels = frame.neutralPixels;
            neutral.width = frame.width;
            neutral.height = frame.height;
            before = imageForFrameWithProof(neutral, proof, screen);
            if (!before) return;
        }
        comparisonModes()[@(window)] = @(mode);
        proofProfiles()[@(window)] = @(proof);
        view.image = after;
        view.beforeImage = before;
        view.comparisonMode = mode;
        [view setNeedsDisplay:YES];
        applied = 1;
    };
    if (NSThread.isMainThread) apply();
    else dispatch_sync(dispatch_get_main_queue(), apply);
    return applied;
}

int lightcept_native_set_zoom(long long window, int percent) {
    if (window <= 0 || (percent != 0 && (percent < 25 || percent > 400 || percent % 5 != 0))) return 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        zoomLevels()[@(window)] = @(percent);
        LightceptZoomView *view = previewViews()[@(window)];
        if (view) view.zoomPercent = percent;
    });
    return 1;
}
static NSMutableDictionary<NSNumber *, LightceptSource *> *candidateSources(void) {
    static NSMutableDictionary *sources;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sources = [NSMutableDictionary new]; });
    return sources;
}
static NSData *digestData(NSData *data) {
    if (!data || data.length > 512ULL * 1024ULL * 1024ULL) return nil;
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, bytes);
    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

// All table and view access is on the main thread. The serial worker queue
// prevents rapid zoom and pan changes from starting overlapping RAW decodes.
static void scheduleSourceRegion(long long window) {
    NSNumber *key = @(window);
    NSTask *oldTask = regionTasks()[key];
    if (oldTask.isRunning) [oldTask terminate];
    [regionTasks() removeObjectForKey:key];
    NSString *token = NSUUID.UUID.UUIDString;
    regionTokens()[key] = token;
    neiv_publish_event("lightcept.detail", "{\"ready\":false}", window);
    LightceptZoomView *view = previewViews()[key];
    [view clearSourceDetail];
    if (!view || view.zoomPercent == 0) return;
    NSRect rect = [view visibleSourceRect];
    if (NSIsEmptyRect(rect) || rect.size.width > INT32_MAX || rect.size.height > INT32_MAX ||
        rect.origin.x > INT32_MAX || rect.origin.y > INT32_MAX) return;
    lightcept_native_document_lock();
    LightceptFrame *frame = committedFrames()[key];
    lightcept_native_document_unlock();
    if (!frame.editable || frame.sourceWidth == 0 || frame.sourceHeight == 0 ||
        (frame.editValues.length != 12 * sizeof(int) && frame.editValues.length != 18 * sizeof(int) &&
         frame.editValues.length != 42 * sizeof(int) && frame.editValues.length != 54 * sizeof(int)) ||
        (hasHSL(frame.editValues) && !validHSL(frame.editValues)) ||
        (hasCurve(frame.editValues) && !validCurve(frame.editValues)) ||
        (hasGrading(frame.editValues) && !validGrading(frame.editValues)) ||
        (hasPickedColor(frame.editValues) && !validPickedColor(frame.editValues)) ||
        frame.sourceDigest.length != CC_SHA256_DIGEST_LENGTH) return;
    const int *committedEdits = frame.editValues.bytes;
    BOOL hasGeometry = frame.editValues.length >= 18 * sizeof(int) &&
        (committedEdits[12] || committedEdits[13] || committedEdits[14] ||
         committedEdits[15] || committedEdits[16] || committedEdits[17] != 1);
    if (hasHSL(frame.editValues)) hasGeometry = YES;
    BOOL explicitCrop = committedEdits[14] != 0 || committedEdits[15] != 0;
    if (hasGeometry && (committedEdits[12] < 0 || committedEdits[13] < 0 ||
        (explicitCrop && (committedEdits[14] <= 0 || committedEdits[15] <= 0)) ||
        (!explicitCrop && (committedEdits[12] || committedEdits[13])) ||
        committedEdits[16] < -17000 || committedEdits[16] > 17000 ||
        committedEdits[17] < 1 || committedEdits[17] > 8 ||
        (explicitCrop && ((size_t)committedEdits[14] != frame.sourceWidth ||
                          (size_t)committedEdits[15] != frame.sourceHeight)))) return;
    NSString *extension = frame.sourcePath.pathExtension.lowercaseString;
    int format = [extension isEqualToString:@"dng"] ? 1 : [extension isEqualToString:@"nef"] ? 2 : 0;
    if (!format) return;
    NSString *worker = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"lightcept-source-region"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:worker]) return;
    NSInteger proof = [proofProfiles()[key] integerValue];
    NSInteger comparison = [comparisonModes()[key] integerValue];
    NSInteger percent = view.zoomPercent;
    NSString *path = [frame.sourcePath copy];
    NSData *digest = [frame.sourceDigest copy];
    NSData *values = [frame.editValues copy];
    // Every worker request stays below the headless component's 4,194,304 pixel limit.
    // Fixed source-sized tiles also bound each image allocation during proof conversion.
    // A rotated 1536-square tile has a source window below the 4,194,304
    // pixel cap at the supported 17 degree limit, including the detail halo.
    const size_t tileEdge = hasGeometry && committedEdits[16] ? 1536 : 2040;
    size_t width = (size_t)rect.size.width, height = (size_t)rect.size.height;
    dispatch_async(regionQueue(), ^{
        @autoreleasepool {
            __block BOOL current = NO;
            dispatch_sync(dispatch_get_main_queue(), ^{ current = [regionTokens()[key] isEqualToString:token]; });
            if (!current) return;
            NSFileManager *manager = NSFileManager.defaultManager;
            NSDictionary *attributes = [manager attributesOfItemAtPath:path error:NULL];
            unsigned long long length = [attributes[NSFileSize] unsignedLongLongValue];
            NSData *source = length >= 8 && length <= 512ULL * 1024ULL * 1024ULL
                ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL] : nil;
            if (!source || ![digestData(source) isEqualToData:digest]) return;
            NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [@"lightcept-region-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            if (![manager createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:nil error:NULL]) return;
            @try {
                NSString *sourcePath = [directory stringByAppendingPathComponent:@"source.raw"];
                if (![source writeToFile:sourcePath atomically:NO]) return;
                NSString *requestPath = [directory stringByAppendingPathComponent:@"request.bin"];
                NSString *outputPath = [directory stringByAppendingPathComponent:@"region.rgba"];
                NSData *(^render)(BOOL, NSRect) = ^NSData *(BOOL neutral, NSRect tileRect) {
                    int32_t fields[80] = {0};
                    NSUInteger count = hasPickedColor(values) ? 80 : hasGrading(values) ? 73 : hasCurve(values) ? 60 : hasHSL(values) ? 48 : hasGeometry ? 24 : 17;
                    NSUInteger offset = hasGeometry ? 1 : 0;
                    if (hasGeometry) fields[0] = hasPickedColor(values) ? 8 : hasGrading(values) ? 7 : hasCurve(values) ? 6 : hasHSL(values) ? 4 : 3;
                    fields[offset] = format;
                    const int *edits = values.bytes;
                    for (NSUInteger index = 0; index < 12; index++)
                        fields[offset + index + 1] = neutral ? 0 : edits[index];
                    fields[offset + 13] = (int32_t)tileRect.origin.x;
                    fields[offset + 14] = (int32_t)tileRect.origin.y;
                    fields[offset + 15] = (int32_t)tileRect.size.width;
                    fields[offset + 16] = (int32_t)tileRect.size.height;
                    if (hasGeometry) for (NSUInteger index = 0; index < 5; index++)
                        fields[18 + index] = edits[12 + index];
                    if (hasGeometry) fields[23] = edits[17];
                    if (hasHSL(values)) for (NSUInteger index = 0; index < 24; index++)
                        fields[24 + index] = neutral ? 0 : edits[18 + index];
                    if (hasCurve(values)) for (NSUInteger index = 0; index < 12; index++)
                        fields[48 + index] = neutral ? (int32_t[]){250, 500, 750}[index % 3] : edits[42 + index];
                    if (hasGrading(values)) for (NSUInteger index = 0; index < 13; index++)
                        fields[60 + index] = neutral ? 0 : edits[54 + index];
                    if (hasPickedColor(values)) for (NSUInteger index = 0; index < 7; index++)
                        fields[73 + index] = neutral ? 0 : edits[67 + index];
                    for (NSUInteger index = 0; index < count; index++)
                        fields[index] = (int32_t)CFSwapInt32HostToLittle((uint32_t)fields[index]);
                    if (![[NSData dataWithBytes:fields length:count * sizeof(int32_t)] writeToFile:requestPath atomically:YES]) return nil;
                    [manager removeItemAtPath:outputPath error:NULL];
                    NSTask *task = [NSTask new];
                    task.executableURL = [NSURL fileURLWithPath:worker];
                    task.arguments = @[sourcePath, requestPath, outputPath];
                    __block BOOL stillCurrent = NO;
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        stillCurrent = [regionTokens()[key] isEqualToString:token];
                        if (stillCurrent) regionTasks()[key] = task;
                    });
                    if (!stillCurrent || ![task launchAndReturnError:NULL]) return nil;
                    // A newer viewport can invalidate this task between the
                    // main-thread registration above and the actual launch.
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        if (![regionTokens()[key] isEqualToString:token] && task.isRunning)
                            [task terminate];
                    });
                    [task waitUntilExit];
                    if (task.terminationStatus != 0) return nil;
                    NSData *pixels = [NSData dataWithContentsOfFile:outputPath];
                    return pixels.length == (size_t)tileRect.size.width * (size_t)tileRect.size.height * 4 ? pixels : nil;
                };
                NSMutableArray<NSValue *> *tileRects = [NSMutableArray new];
                NSMutableArray<NSData *> *afterTiles = [NSMutableArray new];
                NSMutableArray<NSData *> *beforeTiles = [NSMutableArray new];
                for (size_t y = 0; y < height; y += tileEdge) {
                    for (size_t x = 0; x < width; x += tileEdge) {
                        __block BOOL stillCurrent = NO;
                        dispatch_sync(dispatch_get_main_queue(), ^{ stillCurrent = [regionTokens()[key] isEqualToString:token]; });
                        if (!stillCurrent) return;
                        NSRect tileRect = NSMakeRect(rect.origin.x + x, rect.origin.y + y,
                            MIN(tileEdge, width - x), MIN(tileEdge, height - y));
                        NSData *after = render(NO, tileRect);
                        if (!after) return;
                        NSData *before = comparison == 0 ? nil : render(YES, tileRect);
                        if (comparison != 0 && !before) return;
                        [tileRects addObject:[NSValue valueWithRect:tileRect]];
                        [afterTiles addObject:after];
                        if (before) [beforeTiles addObject:before];
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (![regionTokens()[key] isEqualToString:token]) return;
                    lightcept_native_document_lock();
                    BOOL sameFrame = committedFrames()[key] == frame;
                    lightcept_native_document_unlock();
                    LightceptZoomView *currentView = previewViews()[key];
                    if (!sameFrame || !currentView || currentView.zoomPercent != percent ||
                        !NSEqualRects([currentView visibleSourceRect], rect) ||
                        [proofProfiles()[key] integerValue] != proof ||
                        [comparisonModes()[key] integerValue] != comparison) return;
                    NSScreen *screen = currentView.window.screen ?: NSScreen.mainScreen;
                    NSMutableArray<NSImage *> *afterImages = [NSMutableArray new];
                    NSMutableArray<NSImage *> *beforeImages = [NSMutableArray new];
                    for (NSUInteger index = 0; index < tileRects.count; index++) {
                        NSRect tileRect = tileRects[index].rectValue;
                        LightceptFrame *tile = [LightceptFrame new];
                        tile.width = (size_t)tileRect.size.width;
                        tile.height = (size_t)tileRect.size.height;
                        tile.pixels = afterTiles[index];
                        NSImage *afterImage = imageForFrameWithProof(tile, proof, screen);
                        if (!afterImage) return;
                        [afterImages addObject:afterImage];
                        if (comparison != 0) {
                            tile.pixels = beforeTiles[index];
                            NSImage *beforeImage = imageForFrameWithProof(tile, proof, screen);
                            if (!beforeImage) return;
                            [beforeImages addObject:beforeImage];
                        }
                    }
                    currentView.detailRects = tileRects;
                    currentView.detailImages = afterImages;
                    currentView.detailBeforeImages = beforeImages;
                    [currentView setNeedsDisplay:YES];
                    neiv_publish_event("lightcept.detail", "{\"ready\":true}", window);
                    if (regionTasks()[key]) [regionTasks() removeObjectForKey:key];
                });
            } @finally {
                [manager removeItemAtPath:directory error:NULL];
            }
        }
    });
}

static NSString *digestHex(NSData *digest) {
    if (digest.length != CC_SHA256_DIGEST_LENGTH) return nil;
    const unsigned char *bytes = digest.bytes;
    char text[CC_SHA256_DIGEST_LENGTH * 2 + 1];
    for (size_t i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) snprintf(text + i * 2, 3, "%02x", bytes[i]);
    return [NSString stringWithUTF8String:text];
}
static NSData *digestFromHex(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length != CC_SHA256_DIGEST_LENGTH * 2) return nil;
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    for (size_t i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        unichar a = [text characterAtIndex:i * 2], b = [text characterAtIndex:i * 2 + 1];
        int high = a >= '0' && a <= '9' ? a - '0' : a >= 'a' && a <= 'f' ? a - 'a' + 10 : -1;
        int low = b >= '0' && b <= '9' ? b - '0' : b >= 'a' && b <= 'f' ? b - 'a' + 10 : -1;
        if (high < 0 || low < 0) return nil;
        bytes[i] = (unsigned char)(high * 16 + low);
    }
    return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}
// Accessed only on the main thread where AppKit owns the panels.
static NSMutableDictionary<NSNumber *, LightceptPendingPicker *> *pendingPickers(void) {
    static NSMutableDictionary *pickers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pickers = [NSMutableDictionary new]; });
    return pickers;
}
static NSMutableDictionary<NSNumber *, LightceptPendingSave *> *pendingSaves(void) {
    static NSMutableDictionary *saves;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ saves = [NSMutableDictionary new]; });
    return saves;
}
static NSMutableDictionary<NSNumber *, LightceptPendingExport *> *pendingExports(void) {
    static NSMutableDictionary *exports;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ exports = [NSMutableDictionary new]; });
    return exports;
}
void lightcept_native_document_lock(void) { [documentLock() lock]; }
void lightcept_native_document_unlock(void) { [documentLock() unlock]; }
unsigned int lightcept_native_open_generation(void) { return requestedGeneration; }
int lightcept_native_open_exposure_tenths(void) { return requestedExposureTenths; }
int lightcept_native_open_contrast_percent(void) { return requestedContrastPercent; }
int lightcept_native_open_shadows_percent(void) { return requestedShadowsPercent; }
int lightcept_native_open_highlights_percent(void) { return requestedHighlightsPercent; }
int lightcept_native_open_blacks_percent(void) { return requestedBlacksPercent; }
int lightcept_native_open_whites_percent(void) { return requestedWhitesPercent; }
int lightcept_native_open_warmth_percent(void) { return requestedWarmthPercent; }
int lightcept_native_open_tint_percent(void) { return requestedTintPercent; }
int lightcept_native_open_vibrance_percent(void) { return requestedVibrancePercent; }
int lightcept_native_open_saturation_percent(void) { return requestedSaturationPercent; }
int lightcept_native_open_clarity_percent(void) { return requestedClarityPercent; }
int lightcept_native_open_texture_percent(void) { return requestedTexturePercent; }
int lightcept_native_should_cancel(void) {
    if (requestedWindow <= 0 || requestedGeneration == 0) return 1;
    return !neiv_callback_is_open_generation(requestedWindow, requestedGeneration);
}

int lightcept_native_commit_frame(long long window, unsigned int generation) {
    lightcept_native_document_lock();
    LightceptFrame *candidate = candidateFrames()[@(window)];
    if (!candidate || candidate.generation != generation) {
        lightcept_native_document_unlock();
        return 7;
    }
    committedFrames()[@(window)] = candidate;
    [candidateFrames() removeObjectForKey:@(window)];
    [candidateSources() removeObjectForKey:@(window)];
    lightcept_native_document_unlock();
    dispatch_async(dispatch_get_main_queue(), ^{
        lightcept_native_document_lock();
        BOOL current = committedFrames()[@(window)] == candidate;
        lightcept_native_document_unlock();
        if (current) {
            updatePreviewView(previewViews()[@(window)], candidate, window);
            NSImageView *navigator = navigatorViews()[@(window)];
            if (navigator) navigator.image = imageForFrame(candidate);
            NSImageView *filmstrip = filmstripViews()[@(window)];
            if (filmstrip) filmstrip.image = imageForFrame(candidate);
            LightceptHistogramView *histogram = histogramViews()[@(window)];
            if (histogram) histogram.sourceFrame = candidate;
        }
    });
    return candidate.editable ? 0 : 1;
}
void lightcept_native_discard_candidate(long long window, unsigned int generation) {
    lightcept_native_document_lock();
    NSTask *cancelledTask = nil;
    if (candidateFrames()[@(window)].generation == generation)
        [candidateFrames() removeObjectForKey:@(window)];
    if (candidateSources()[@(window)].generation == generation) {
        [candidateSources() removeObjectForKey:@(window)];
        cancelledTask = fittedPreviewTasks()[@(window)];
        [fittedPreviewTasks() removeObjectForKey:@(window)];
    }
    lightcept_native_document_unlock();
    if (cancelledTask.isRunning) [cancelledTask terminate];
}
long long lightcept_native_create_preview(long long window) {
    char options[64];
    int count = snprintf(options, sizeof(options), "{\"window\":%lld}", window);
    if (window <= 0 || count < 0 || count >= (int)sizeof(options)) return 0;
    return neiv_surface_create_native(window, "photo_preview", "lightcept.preview", options);
}
long long lightcept_native_create_navigator_preview(long long window) {
    char options[96];
    int count = snprintf(options, sizeof(options), "{\"window\":%lld,\"role\":\"navigator\"}", window);
    if (window <= 0 || count < 0 || count >= (int)sizeof(options)) return 0;
    return neiv_surface_create_native(window, "navigator_preview", "lightcept.preview", options);
}
long long lightcept_native_create_filmstrip_preview(long long window) {
    char options[96];
    int count = snprintf(options, sizeof(options), "{\"window\":%lld,\"role\":\"filmstrip\"}", window);
    if (window <= 0 || count < 0 || count >= (int)sizeof(options)) return 0;
    return neiv_surface_create_native(window, "filmstrip_preview", "lightcept.preview", options);
}
long long lightcept_native_create_histogram(long long window) {
    char options[96];
    int count = snprintf(options, sizeof(options), "{\"window\":%lld,\"role\":\"histogram\"}", window);
    if (window <= 0 || count < 0 || count >= (int)sizeof(options)) return 0;
    return neiv_surface_create_native(window, "histogram_preview", "lightcept.preview", options);
}

size_t lightcept_native_file_size(const char *filePath) {
    if (!filePath) return 0;
    NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:filePath length:strlen(filePath)];
    if (!path || ![@[@"dng", @"nef"] containsObject:[path.pathExtension lowercaseString]]) return 0;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) return 0;
    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    if (size < 8 || size > 512ULL * 1024ULL * 1024ULL) return 0;
    return (size_t)size;
}

int lightcept_native_read_file(const char *filePath, unsigned char *output, size_t length) {
    if (!output || lightcept_native_file_size(filePath) != length) return 1;
    NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:filePath length:strlen(filePath)];
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return 1;
    NSData *source = nil;
    @try { source = [handle readDataOfLength:length + 1]; }
    @catch (NSException *exception) { (void)exception; }
    @finally { [handle closeFile]; }
    if (source.length != length) return 1;
    NSData *digest = digestData(source);
    if (!digest) return 1;
    lightcept_native_document_lock();
    LightceptSource *candidate = candidateSources()[@(requestedWindow)];
    if (!candidate || candidate.generation != requestedGeneration ||
        (candidate.expectedDigest && ![candidate.expectedDigest isEqualToData:digest])) {
        lightcept_native_document_unlock();
        return 1;
    }
    candidate.digest = digest;
    lightcept_native_document_unlock();
    memcpy(output, source.bytes, length);
    return 0;
}

int lightcept_native_publish_frame(const unsigned char *pixels, size_t length, size_t width, size_t height, unsigned int generation) {
    if (!pixels || width == 0 || height == 0 || width > 2048 || height > 2048 || length != width * height * 4) return 4;
    long long window = requestedWindow;
    if (window <= 0 || generation != requestedGeneration) return 7;
    NSData *completed = [NSData dataWithBytes:pixels length:length];
    if (!completed) return 3;
    NSData *previewDigest = digestData(completed);
    if (!previewDigest) return 3;
    lightcept_native_document_lock();
    if (!neiv_callback_is_open_generation(window, generation)) {
        lightcept_native_document_unlock();
        return 7;
    }
    LightceptFrame *frame = [LightceptFrame new];
    frame.pixels = completed;
    frame.width = width;
    frame.height = height;
    frame.generation = generation;
    LightceptSource *source = candidateSources()[@(window)];
    if (!source || source.generation != generation) {
        lightcept_native_document_unlock();
        return 7;
    }
    frame.sourcePath = source.path;
    frame.sourceDigest = source.digest;
    frame.editValues = source.editValues;
    frame.routeID = source.routeID;
    frame.previewDigest = previewDigest;
    frame.editable = YES;
    if (!frame.sourceDigest || (source.expectedWidth && (source.expectedWidth != width || source.expectedHeight != height))) {
        lightcept_native_document_unlock();
        return 4;
    }
    if (source.expectedPreviewDigest && ![source.expectedPreviewDigest isEqualToData:previewDigest]) {
        lightcept_native_document_unlock();
        return 11;
    }
    candidateFrames()[@(window)] = frame;
    lightcept_native_document_unlock();
    return 0;
}

int lightcept_native_publish_prepared(const void *working, size_t workingLength, const void *baseline, size_t width, size_t height, size_t sourceWidth, size_t sourceHeight, unsigned int generation) {
    if (!working || !baseline || width == 0 || height == 0 || width > 2048 || height > 2048 || height > 4194304 / width || workingLength != width * height * 3 || sourceWidth == 0 || sourceHeight == 0 || sourceWidth > 10000 || sourceHeight > 10000 || sourceWidth > 50000000 / sourceHeight || width > sourceWidth || height > sourceHeight || generation != requestedGeneration) return 4;
    NSData *workingCopy = [NSData dataWithBytes:working length:workingLength * sizeof(double)];
    NSData *baselineCopy = [NSData dataWithBytes:baseline length:sizeof(double)];
    if (!workingCopy || !baselineCopy) return 3;
    NSData *workingDigest = digestData(workingCopy);
    NSData *baselineDigest = digestData(baselineCopy);
    if (!workingDigest || !baselineDigest) return 3;
    lightcept_native_document_lock();
    LightceptFrame *frame = candidateFrames()[@(requestedWindow)];
    if (!frame || frame.generation != generation || !neiv_callback_is_open_generation(requestedWindow, generation)) {
        lightcept_native_document_unlock();
        return 7;
    }
    LightceptSource *source = candidateSources()[@(requestedWindow)];
    if (!source || source.generation != generation) {
        lightcept_native_document_unlock();
        return 7;
    }
    if ((source.expectedWorkingDigest && ![source.expectedWorkingDigest isEqualToData:workingDigest]) ||
        (source.expectedBaselineDigest && ![source.expectedBaselineDigest isEqualToData:baselineDigest])) {
        lightcept_native_document_unlock();
        return 11;
    }
    frame.preparedWorking = workingCopy;
    frame.preparedBaseline = baselineCopy;
    frame.sourceWidth = sourceWidth;
    frame.sourceHeight = sourceHeight;
    frame.sourceCanvasWidth = sourceWidth;
    frame.sourceCanvasHeight = sourceHeight;
    frame.workingDigest = workingDigest;
    frame.baselineDigest = baselineDigest;
    lightcept_native_document_unlock();
    NSMutableData *neutral = [NSMutableData dataWithLength:width * height * 4];
    if (!neutral || neiv_callback_render_prepared_dng(workingCopy.bytes, workingCopy.length,
        baselineCopy.bytes, baselineCopy.length, neutral.mutableBytes, neutral.length,
        width, height, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) != 0) return 3;
    frame.neutralPixels = neutral;
    return 0;
}

static BOOL openDirectDng(const char *filePath) {
    if (lightcept_native_should_cancel()) return NO;
    NSString *path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:filePath length:strlen(filePath)];
    if (!path || ![[path.pathExtension lowercaseString] isEqualToString:@"dng"]) return NO;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) return NO;
    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    if (size < 8 || size > 512ULL * 1024ULL * 1024ULL) return NO;
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return NO;
    NSData *source = nil;
    @try {
        source = [handle readDataOfLength:(NSUInteger)size + 1];
    } @catch (NSException *exception) {
        (void)exception;
    } @finally {
        [handle closeFile];
    }
    if (source.length != (NSUInteger)size) return NO;
    if (lightcept_native_should_cancel()) return NO;
    unsigned int sourceWidth = 0, sourceHeight = 0;
    if (neiv_callback_dng_info(source.bytes, source.length, &sourceWidth, &sourceHeight) != 0 || sourceWidth == 0 || sourceHeight == 0) return NO;
    size_t width = sourceWidth, height = sourceHeight;
    if (width > 2048 || height > 2048) {
        if (width >= height) {
            height = MAX((size_t)1, height * 2048 / width);
            width = 2048;
        } else {
            width = MAX((size_t)1, width * 2048 / height);
            height = 2048;
        }
    }
    if (width == 0 || height == 0 || width > 2048 || height > 2048) return NO;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
    if (!pixels || neiv_callback_render_dng(source.bytes, source.length, pixels.mutableBytes, pixels.length, width, height) != 0) return NO;
    long long window = requestedWindow;
    lightcept_native_document_lock();
    if (window <= 0 || !neiv_callback_is_open_generation(window, requestedGeneration)) {
        lightcept_native_document_unlock();
        return NO;
    }
    LightceptFrame *frame = [LightceptFrame new];
    frame.pixels = pixels;
    frame.width = width;
    frame.height = height;
    frame.generation = requestedGeneration;
    frame.sourcePath = path;
    frame.sourceDigest = digestData(source);
    frame.routeID = @"dng_uncompressed_view_v1";
    frame.editable = NO;
    candidateFrames()[@(window)] = frame;
    lightcept_native_document_unlock();
    return YES;
}

static NSString *detailRouteForPath(NSString *source) {
    NSString *extension = [source.pathExtension lowercaseString];
    if ([extension isEqualToString:@"dng"]) return @"dng_spatial_preview_detail_v3";
    if ([extension isEqualToString:@"nef"]) return @"nef_z8_lossless_preview_detail_v3";
    return nil;
}

static NSString *saturationRouteForPath(NSString *source) {
    NSString *extension = [source.pathExtension lowercaseString];
    if ([extension isEqualToString:@"dng"]) return @"dng_spatial_preview_saturation_v4";
    if ([extension isEqualToString:@"nef"]) return @"nef_z8_lossless_preview_saturation_v4";
    return nil;
}

static NSString *routeForPath(NSString *source) {
    NSString *extension = [source.pathExtension lowercaseString];
    if ([extension isEqualToString:@"dng"]) return @"dng_spatial_preview_texture_v5";
    if ([extension isEqualToString:@"nef"]) return @"nef_z8_lossless_preview_texture_v5";
    return nil;
}

// Replace a prepared candidate only after both geometry renders and all
// persisted identities have been checked. The worker owns the crop and
// straighten mathematics; this boundary owns document publication.
static int renderGeometryCandidate(NSString *source, long long window, unsigned int generation,
    NSData *values, NSData *expectedWorking, NSData *expectedPreview,
    size_t width, size_t height) {
    if ((!nonneutralGeometry(values) && !hasHSL(values)) ||
        (hasHSL(values) && !validHSL(values)) ||
        (hasCurve(values) && !validCurve(values)) ||
        (hasGrading(values) && !validGrading(values)) ||
        (hasPickedColor(values) && !validPickedColor(values)) || !width || !height || width > 2048 ||
        height > 2048 || width > 4194304 / height) return 4;
    NSString *extension = source.pathExtension.lowercaseString;
    int format = [extension isEqualToString:@"dng"] ? 1 : [extension isEqualToString:@"nef"] ? 2 : 0;
    NSString *worker = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"lightcept-fitted-preview"];
    if (!format || ![[NSFileManager defaultManager] isExecutableFileAtPath:worker]) return 6;
    lightcept_native_document_lock();
    LightceptFrame *candidate = candidateFrames()[@(window)];
    BOOL current = candidate && candidate.generation == generation &&
        neiv_callback_is_open_generation(window, generation);
    NSData *sourceDigest = current ? candidate.sourceDigest : nil;
    lightcept_native_document_unlock();
    if (!current || sourceDigest.length != CC_SHA256_DIGEST_LENGTH) return 7;
    NSData *sourceBytes = [NSData dataWithContentsOfFile:source options:NSDataReadingMappedIfSafe error:NULL];
    if (!sourceBytes || ![digestData(sourceBytes) isEqualToData:sourceDigest]) return 8;
    const int *edits = values.bytes;
    size_t cropWidth = edits[14] ? (size_t)edits[14] :
        (edits[17] >= 5 ? candidate.sourceHeight : candidate.sourceWidth);
    size_t cropHeight = edits[15] ? (size_t)edits[15] :
        (edits[17] >= 5 ? candidate.sourceWidth : candidate.sourceHeight);
    if (edits[12] < 0 || edits[13] < 0 || !cropWidth || !cropHeight ||
        width > cropWidth || height > cropHeight ||
        edits[16] < -17000 || edits[16] > 17000 || edits[17] < 1 || edits[17] > 8) return 4;
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [@"lightcept-fitted-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![manager createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:nil error:NULL]) return 3;
    int result = 3;
    @try {
        NSString *requestPath = [directory stringByAppendingPathComponent:@"request.bin"];
        NSString *outputPath = [directory stringByAppendingPathComponent:@"preview.rgba"];
        NSString *workingPath = [directory stringByAppendingPathComponent:@"working.f64"];
        NSMutableArray<NSData *> *renders = [NSMutableArray arrayWithCapacity:2];
        NSData *working = nil;
        for (NSUInteger pass = 0; pass < 2; pass++) {
            if (!neiv_callback_is_open_generation(window, generation)) return 7;
            int32_t fields[78] = {0};
            fields[0] = hasPickedColor(values) ? 8 : hasGrading(values) ? 7 : hasCurve(values) ? 6 : hasHSL(values) ? 4 : 3;
            fields[1] = format;
            for (NSUInteger index = 0; index < 12; index++) fields[2 + index] = pass ? 0 : edits[index];
            fields[14] = (int32_t)width;
            fields[15] = (int32_t)height;
            for (NSUInteger index = 0; index < 5; index++) fields[16 + index] = edits[12 + index];
            fields[21] = edits[17];
            if (hasHSL(values)) for (NSUInteger index = 0; index < 24; index++)
                fields[22 + index] = pass ? 0 : edits[18 + index];
            if (hasCurve(values)) for (NSUInteger index = 0; index < 12; index++)
                fields[46 + index] = pass ? (int32_t[]){250, 500, 750}[index % 3] : edits[42 + index];
            if (hasGrading(values)) for (NSUInteger index = 0; index < 13; index++)
                fields[58 + index] = pass ? 0 : edits[54 + index];
            if (hasPickedColor(values)) for (NSUInteger index = 0; index < 7; index++)
                fields[71 + index] = pass ? 0 : edits[67 + index];
            NSUInteger fieldCount = hasPickedColor(values) ? 78 : hasGrading(values) ? 71 : hasCurve(values) ? 58 : hasHSL(values) ? 46 : 22;
            for (NSUInteger index = 0; index < fieldCount; index++)
                fields[index] = (int32_t)CFSwapInt32HostToLittle((uint32_t)fields[index]);
            if (![[NSData dataWithBytes:fields length:fieldCount * sizeof(int32_t)] writeToFile:requestPath atomically:YES]) return 3;
            [manager removeItemAtPath:outputPath error:NULL];
            [manager removeItemAtPath:workingPath error:NULL];
            NSTask *task = [NSTask new];
            task.executableURL = [NSURL fileURLWithPath:worker];
            task.arguments = @[source, requestPath, outputPath, workingPath];
            lightcept_native_document_lock();
            BOOL stillCurrent = neiv_callback_is_open_generation(window, generation);
            if (stillCurrent) fittedPreviewTasks()[@(window)] = task;
            lightcept_native_document_unlock();
            if (!stillCurrent) return 7;
            if (![task launchAndReturnError:NULL]) {
                lightcept_native_document_lock();
                if (fittedPreviewTasks()[@(window)] == task) [fittedPreviewTasks() removeObjectForKey:@(window)];
                lightcept_native_document_unlock();
                return 3;
            }
            if (!neiv_callback_is_open_generation(window, generation) && task.isRunning) [task terminate];
            [task waitUntilExit];
            lightcept_native_document_lock();
            if (fittedPreviewTasks()[@(window)] == task) [fittedPreviewTasks() removeObjectForKey:@(window)];
            lightcept_native_document_unlock();
            if (!neiv_callback_is_open_generation(window, generation)) return 7;
            if (task.terminationStatus != 0) return 5;
            NSData *pixels = [NSData dataWithContentsOfFile:outputPath];
            if (pixels.length != width * height * 4) return 5;
            [renders addObject:pixels];
            if (pass == 0) {
                working = [NSData dataWithContentsOfFile:workingPath];
                if (working.length != width * height * 3 * sizeof(double)) return 5;
            }
        }
        NSData *previewDigest = digestData(renders[0]);
        NSData *workingDigest = digestData(working);
        if ((expectedPreview && ![expectedPreview isEqualToData:previewDigest]) ||
            (expectedWorking && ![expectedWorking isEqualToData:workingDigest]) ||
            ![digestData([NSData dataWithContentsOfFile:source options:NSDataReadingMappedIfSafe error:NULL]) isEqualToData:sourceDigest]) return 11;
        lightcept_native_document_lock();
        BOOL sameCandidate = candidateFrames()[@(window)] == candidate &&
            neiv_callback_is_open_generation(window, generation);
        if (sameCandidate) {
            candidate.pixels = renders[0];
            candidate.neutralPixels = renders[1];
            candidate.preparedWorking = working;
            candidate.width = width;
            candidate.height = height;
            candidate.sourceWidth = cropWidth;
            candidate.sourceHeight = cropHeight;
            candidate.editValues = values;
            candidate.previewDigest = previewDigest;
            candidate.workingDigest = workingDigest;
        }
        lightcept_native_document_unlock();
        result = sameCandidate ? 0 : 7;
    } @finally {
        [manager removeItemAtPath:directory error:NULL];
    }
    return result;
}

static BOOL scheduleOpen(NSString *source, long long window, unsigned int generation, int exposureTenths, int contrastPercent, int shadowsPercent, int highlightsPercent, int blacksPercent, int whitesPercent, int warmthPercent, int tintPercent, int vibrancePercent, int saturationPercent, int clarityPercent, int texturePercent, NSData *geometryValues, NSData *expectedDigest, NSData *expectedWorkingDigest, NSData *expectedBaselineDigest, NSData *expectedPreviewDigest, size_t expectedWidth, size_t expectedHeight) {
    lightcept_native_document_lock();
    if (!neiv_callback_is_open_generation(window, generation)) {
        lightcept_native_document_unlock();
        return NO;
    }
    LightceptSource *candidate = [LightceptSource new];
    candidate.path = source;
    candidate.generation = generation;
    candidate.expectedDigest = expectedDigest;
    BOOL geometry = nonneutralGeometry(geometryValues) || hasHSL(geometryValues);
    if ((hasHSL(geometryValues) && !validHSL(geometryValues)) ||
        (hasCurve(geometryValues) && !validCurve(geometryValues)) ||
        (hasGrading(geometryValues) && !validGrading(geometryValues)) ||
        (hasPickedColor(geometryValues) && !validPickedColor(geometryValues))) {
        lightcept_native_document_unlock();
        return NO;
    }
    NSData *controlValues = editValues(exposureTenths, contrastPercent, shadowsPercent,
        highlightsPercent, blacksPercent, whitesPercent, warmthPercent, tintPercent,
        vibrancePercent, saturationPercent, clarityPercent, texturePercent);
    NSMutableData *renderValues = [controlValues mutableCopy];
    if (geometry) memcpy((int *)renderValues.mutableBytes + 12,
        (const int *)geometryValues.bytes + 12, 6 * sizeof(int));
    if (hasHSL(geometryValues)) [renderValues appendBytes:(const int *)geometryValues.bytes + 18
        length:(hasPickedColor(geometryValues) ? 56 : hasGrading(geometryValues) ? 49 : hasCurve(geometryValues) ? 36 : 24) * sizeof(int)];
    candidate.expectedWorkingDigest = geometry ? nil : expectedWorkingDigest;
    candidate.expectedBaselineDigest = expectedBaselineDigest;
    candidate.expectedPreviewDigest = geometry ? nil : expectedPreviewDigest;
    candidate.routeID = routeForPath(source);
    candidate.editValues = renderValues;
    candidate.expectedWidth = geometry ? 0 : expectedWidth;
    candidate.expectedHeight = geometry ? 0 : expectedHeight;
    candidateSources()[@(window)] = candidate;
    NSTask *supersededTask = fittedPreviewTasks()[@(window)];
    [fittedPreviewTasks() removeObjectForKey:@(window)];
    lightcept_native_document_unlock();
    if (supersededTask.isRunning) [supersededTask terminate];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            requestedWindow = window;
            requestedGeneration = generation;
            requestedExposureTenths = exposureTenths;
            requestedContrastPercent = contrastPercent;
            requestedShadowsPercent = shadowsPercent;
            requestedHighlightsPercent = highlightsPercent;
            requestedBlacksPercent = blacksPercent;
            requestedWhitesPercent = whitesPercent;
            requestedWarmthPercent = warmthPercent;
            requestedTintPercent = tintPercent;
            requestedVibrancePercent = vibrancePercent;
            requestedSaturationPercent = saturationPercent;
            requestedClarityPercent = clarityPercent;
            requestedTexturePercent = texturePercent;
            NSString *extension = [source.pathExtension lowercaseString];
            int status = [extension isEqualToString:@"dng"]
                ? neiv_callback_open_camera_dng(source.fileSystemRepresentation)
                : ([extension isEqualToString:@"nef"] ? neiv_callback_open_camera_nef(source.fileSystemRepresentation) : 6);
            if (status == 0 && geometry)
                status = renderGeometryCandidate(source, window, generation, renderValues,
                    expectedWorkingDigest, expectedPreviewDigest, expectedWidth, expectedHeight);
            if (expectedDigest && status == 1) status = 8;
            if (!expectedDigest && status != 0 && exposureTenths == 0 && contrastPercent == 0 && shadowsPercent == 0 && highlightsPercent == 0 && blacksPercent == 0 && whitesPercent == 0 && warmthPercent == 0 && tintPercent == 0 && vibrancePercent == 0 && saturationPercent == 0 && clarityPercent == 0 && texturePercent == 0 && !lightcept_native_should_cancel() && openDirectDng(source.fileSystemRepresentation)) status = 0;
            neiv_callback_complete_open(window, generation, status);
            requestedWindow = 0;
            requestedGeneration = 0;
            requestedExposureTenths = 0;
            requestedContrastPercent = 0;
            requestedShadowsPercent = 0;
            requestedHighlightsPercent = 0;
            requestedBlacksPercent = 0;
            requestedWhitesPercent = 0;
            requestedWarmthPercent = 0;
            requestedTintPercent = 0;
            requestedVibrancePercent = 0;
            requestedSaturationPercent = 0;
            requestedClarityPercent = 0;
            requestedTexturePercent = 0;
        }
    });
    return YES;
}

void lightcept_native_cancel_picker(long long window, unsigned int generation) {
    dispatch_async(dispatch_get_main_queue(), ^{
        LightceptPendingPicker *pending = pendingPickers()[@(window)];
        if (!pending || (generation != 0 && pending.generation != generation)) return;
        [pendingPickers() removeObjectForKey:@(window)];
        [pending.panel cancel:nil];
    });
}

static NSNumber *projectInteger(id value, long long minimum, long long maximum) {
    if (!value || CFGetTypeID((__bridge CFTypeRef)value) != CFNumberGetTypeID()) return nil;
    double number = [value doubleValue];
    long long integer = [value longLongValue];
    if (!isfinite(number) || number != (double)integer || integer < minimum || integer > maximum) return nil;
    return value;
}

// Validate the entire bounded schema before any Cyna document transition.
static NSString *colorRouteForPath(NSString *source) {
    NSString *extension = [source.pathExtension lowercaseString];
    if ([extension isEqualToString:@"dng"]) return @"dng_spatial_preview_color_v2";
    if ([extension isEqualToString:@"nef"]) return @"nef_z8_lossless_preview_color_v2";
    return nil;
}

static NSString *legacyRouteForPath(NSString *source) {
    NSString *extension = [source.pathExtension lowercaseString];
    if ([extension isEqualToString:@"dng"]) return @"dng_spatial_preview_v1";
    if ([extension isEqualToString:@"nef"]) return @"nef_z8_lossless_preview_v1";
    return nil;
}

static NSDictionary *readProject(NSData *data) {
    if (!data || data.length == 0 || data.length > 16384) return nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![parsed isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *project = parsed;
    NSNumber *schema = projectInteger(project[@"schema"], LightceptProjectSchemaLight, LightceptProjectSchemaPickedColor);
    if (!schema) return nil;
    NSString *source = project[@"sourcePath"];
    NSString *route = project[@"routeID"];
    NSString *digest = project[@"sourceSHA256"];
    if (![source isKindOfClass:[NSString class]] || source.length == 0 || source.length > 4096 || !source.isAbsolutePath ||
        ![route isKindOfClass:[NSString class]] || !([route isEqualToString:routeForPath(source)] && (schema.intValue == LightceptProjectSchemaTexture || schema.intValue == LightceptProjectSchemaGeometry || schema.intValue == LightceptProjectSchemaTransform || schema.intValue == LightceptProjectSchemaHSL || schema.intValue == LightceptProjectSchemaCurve || schema.intValue == LightceptProjectSchemaLumaCurve || schema.intValue == LightceptProjectSchemaGrading || schema.intValue == LightceptProjectSchemaPickedColor)) && !([route isEqualToString:saturationRouteForPath(source)] && schema.intValue == LightceptProjectSchemaSaturation) && !([route isEqualToString:detailRouteForPath(source)] && schema.intValue == LightceptProjectSchemaDetail) && !([route isEqualToString:colorRouteForPath(source)] && schema.intValue == LightceptProjectSchemaColor) && !([route isEqualToString:legacyRouteForPath(source)] && schema.intValue == LightceptProjectSchemaLight) ||
        !digestFromHex(digest) || !digestFromHex(project[@"workingSHA256"]) ||
        !digestFromHex(project[@"baselineSHA256"]) || !digestFromHex(project[@"previewSHA256"])) return nil;
    NSNumber *width = projectInteger(project[@"previewWidth"], 1, 2048);
    NSNumber *height = projectInteger(project[@"previewHeight"], 1, 2048);
    NSNumber *revision = projectInteger(project[@"editRevision"], 0, UINT32_MAX);
    NSArray *history = project[@"history"];
    if (!width || !height || width.unsignedLongLongValue * height.unsignedLongLongValue > 4194304 || !revision ||
        ![history isKindOfClass:[NSArray class]] || history.count == 0 || history.count > 32 ||
        !projectInteger(project[@"cursor"], 0, (long long)history.count - 1)) return nil;
    if (revision.unsignedIntValue < [project[@"cursor"] unsignedIntValue]) return nil;
    for (id entry in history) {
        if (![entry isKindOfClass:[NSArray class]] || [entry count] != projectEntryLength((LightceptProjectSchema)schema.integerValue)) return nil;
        NSArray *values = entry;
        if (!projectInteger(values[0], -40, 40)) return nil;
        for (NSUInteger i = 1; i < MIN((NSUInteger)12, projectEntryLength((LightceptProjectSchema)schema.integerValue)); i++) if (!projectInteger(values[i], -100, 100)) return nil;
        if (schema.integerValue >= LightceptProjectSchemaHSL)
            for (NSUInteger i = 18; i < 42; i++) if (!projectInteger(values[i], -100, 100)) return nil;
        if (schema.integerValue >= LightceptProjectSchemaCurve) {
            for (NSUInteger channel = 0; channel < (schema.integerValue >= LightceptProjectSchemaLumaCurve ? 4 : 3); channel++) {
                NSUInteger i = 42 + channel * 3;
                NSNumber *a = projectInteger(values[i], 0, 1000);
                NSNumber *b = projectInteger(values[i + 1], 0, 1000);
                NSNumber *c = projectInteger(values[i + 2], 0, 1000);
                if (!a || !b || !c || a.intValue > b.intValue || b.intValue > c.intValue) return nil;
            }
        }
        if (schema.integerValue >= LightceptProjectSchemaGrading) {
            for (NSUInteger wheel = 0; wheel < 4; wheel++) {
                NSUInteger field = 54 + wheel * 3;
                if (!projectInteger(values[field], 0, 359) ||
                    !projectInteger(values[field + 1], 0, 100) ||
                    !projectInteger(values[field + 2], -100, 100)) return nil;
            }
            if (!projectInteger(values[66], -100, 100)) return nil;
        }
        if (schema.integerValue >= LightceptProjectSchemaPickedColor) {
            if (!projectInteger(values[67], 0, 359) ||
                !projectInteger(values[68], 0, 90) ||
                !projectInteger(values[69], 0, 100) ||
                !projectInteger(values[70], -100, 100) ||
                !projectInteger(values[71], -100, 100) ||
                !projectInteger(values[72], -100, 100) ||
                !projectInteger(values[73], 0, 1)) return nil;
        }
        if (schema.integerValue >= LightceptProjectSchemaGeometry) {
            for (NSUInteger i = LightceptProjectCropLeft; i <= LightceptProjectCropHeight; i++) if (!projectInteger(values[i], 0, 10000)) return nil;
            if (!projectInteger(values[LightceptProjectStraighten], -17000, 17000)) return nil;
            if (schema.integerValue >= LightceptProjectSchemaTransform &&
                !projectInteger(values[LightceptProjectTransform], 1, 8)) return nil;
            int left = [values[LightceptProjectCropLeft] intValue], top = [values[LightceptProjectCropTop] intValue];
            int width = [values[LightceptProjectCropWidth] intValue], height = [values[LightceptProjectCropHeight] intValue];
            if ((!width || !height) ? (left || top || width || height) :
                (left > 10000 - width || top > 10000 - height)) return nil;
        }
    }
    NSArray *neutral = history[0];
    for (NSUInteger i = 0; i < neutral.count; i++)
        if ([neutral[i] intValue] != (i == LightceptProjectTransform ? 1 :
            i >= LightceptProjectCurve && i < LightceptProjectGrading ?
                (int[]){250, 500, 750}[(i - LightceptProjectCurve) % 3] : 0)) return nil;
    return project;
}

static BOOL projectRouteUnavailable(NSData *data) {
    if (!data || data.length == 0 || data.length > 16384) return NO;
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![parsed isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *project = parsed;
    NSNumber *schema = projectInteger(project[@"schema"], 0, UINT32_MAX);
    if (schema && schema.unsignedIntValue != LightceptProjectSchemaLight && schema.unsignedIntValue != LightceptProjectSchemaColor && schema.unsignedIntValue != LightceptProjectSchemaDetail && schema.unsignedIntValue != LightceptProjectSchemaSaturation && schema.unsignedIntValue != LightceptProjectSchemaTexture && schema.unsignedIntValue != LightceptProjectSchemaGeometry && schema.unsignedIntValue != LightceptProjectSchemaTransform && schema.unsignedIntValue != LightceptProjectSchemaHSL && schema.unsignedIntValue != LightceptProjectSchemaCurve && schema.unsignedIntValue != LightceptProjectSchemaLumaCurve && schema.unsignedIntValue != LightceptProjectSchemaGrading && schema.unsignedIntValue != LightceptProjectSchemaPickedColor) return YES;
    NSString *source = project[@"sourcePath"], *route = project[@"routeID"];
    return [source isKindOfClass:[NSString class]] && [route isKindOfClass:[NSString class]] &&
        !([route isEqualToString:routeForPath(source)] && (schema.unsignedIntValue == LightceptProjectSchemaTexture || schema.unsignedIntValue == LightceptProjectSchemaGeometry || schema.unsignedIntValue == LightceptProjectSchemaTransform || schema.unsignedIntValue == LightceptProjectSchemaHSL || schema.unsignedIntValue == LightceptProjectSchemaCurve || schema.unsignedIntValue == LightceptProjectSchemaLumaCurve || schema.unsignedIntValue == LightceptProjectSchemaGrading || schema.unsignedIntValue == LightceptProjectSchemaPickedColor)) && !([route isEqualToString:saturationRouteForPath(source)] && schema.unsignedIntValue == LightceptProjectSchemaSaturation) && !([route isEqualToString:detailRouteForPath(source)] && schema.unsignedIntValue == LightceptProjectSchemaDetail) && !([route isEqualToString:colorRouteForPath(source)] && schema.unsignedIntValue == LightceptProjectSchemaColor) && !([route isEqualToString:legacyRouteForPath(source)] && schema.unsignedIntValue == LightceptProjectSchemaLight);
}

int lightcept_native_save_project(long long window, unsigned int generation, const int *values,
                                  unsigned int length, unsigned int cursor, unsigned int revision) {
    if (window <= 0 || generation == 0 || !values || length == 0 || length > 32 || cursor >= length || neiv_dialog_capability(1) != 1) return 1;
    NSMutableArray *history = [NSMutableArray arrayWithCapacity:length];
    for (unsigned int i = 0; i < length; i++) {
        NSUInteger entryLength = projectEntryLength(LightceptProjectSchemaPickedColor);
        NSMutableArray *entry = [NSMutableArray arrayWithCapacity:entryLength];
        for (NSUInteger j = 0; j < entryLength; j++) [entry addObject:@(values[i * entryLength + j])];
        [history addObject:entry];
    }
    lightcept_native_document_lock();
    LightceptFrame *frame = committedFrames()[@(window)];
    BOOL valid = frame && frame.generation == generation && frame.editable &&
        (frame.editValues.length == 18 * sizeof(int) || validHSL(frame.editValues)) &&
        (!hasCurve(frame.editValues) || validCurve(frame.editValues)) &&
        (!hasGrading(frame.editValues) || validGrading(frame.editValues)) &&
        (!hasPickedColor(frame.editValues) || validPickedColor(frame.editValues)) &&
        frame.sourceDigest.length == CC_SHA256_DIGEST_LENGTH &&
        frame.workingDigest.length == CC_SHA256_DIGEST_LENGTH && frame.baselineDigest.length == CC_SHA256_DIGEST_LENGTH &&
        frame.previewDigest.length == CC_SHA256_DIGEST_LENGTH &&
        frame.sourcePath.isAbsolutePath && frame.routeID && [frame.routeID isEqualToString:routeForPath(frame.sourcePath)];
    NSString *source = valid ? [frame.sourcePath copy] : nil;
    NSData *digest = valid ? [frame.sourceDigest copy] : nil;
    NSData *workingDigest = valid ? [frame.workingDigest copy] : nil;
    NSData *baselineDigest = valid ? [frame.baselineDigest copy] : nil;
    NSData *previewDigest = valid ? [frame.previewDigest copy] : nil;
    NSString *route = valid ? [frame.routeID copy] : nil;
    size_t width = valid ? frame.width : 0, height = valid ? frame.height : 0;
    if (valid) {
        const int *committed = frame.editValues.bytes;
        for (NSUInteger field = 0; field < 74; field++) {
            int actual = field < 18 || (field < 42 && hasHSL(frame.editValues)) ||
                (field >= 42 && field < 54 && hasCurve(frame.editValues)) ||
                (field >= 54 && field < 67 && hasGrading(frame.editValues)) ||
                (field >= 67 && hasPickedColor(frame.editValues)) ? committed[field] :
                field >= 42 && field < 54 ? (int[]){250, 500, 750}[((field - 42) % 3)] : 0;
            if (actual != values[cursor * 74 + field]) valid = NO;
        }
        if (nonneutralGeometry(frame.editValues) && values[cursor * 74 + 14] &&
            (frame.sourceWidth != (size_t)values[cursor * 74 + 14] ||
             frame.sourceHeight != (size_t)values[cursor * 74 + 15])) valid = NO;
    }
    lightcept_native_document_unlock();
    if (!valid || width == 0 || height == 0 || width > 2048 || height > 2048) return 1;
    NSDictionary *project = @{@"schema": @(LightceptProjectSchemaPickedColor), @"sourcePath": source, @"sourceSHA256": digestHex(digest),
        @"workingSHA256": digestHex(workingDigest), @"baselineSHA256": digestHex(baselineDigest),
        @"previewSHA256": digestHex(previewDigest),
        @"routeID": route, @"previewWidth": @(width), @"previewHeight": @(height),
        @"editRevision": @(revision), @"cursor": @(cursor), @"history": history};
    NSData *document = [NSJSONSerialization dataWithJSONObject:project options:NSJSONWritingPrettyPrinted error:NULL];
    if (!readProject(document)) return 1;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (pendingSaves()[@(window)]) { neiv_callback_complete_project_save(window, generation, LightceptProjectSaveIOFailure); return; }
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"lightcept"]];
        panel.nameFieldStringValue = [[source.lastPathComponent stringByDeletingPathExtension] stringByAppendingPathExtension:@"lightcept"];
        LightceptPendingSave *pending = [LightceptPendingSave new];
        pending.panel = panel;
        pending.generation = generation;
        pendingSaves()[@(window)] = pending;
        [panel beginWithCompletionHandler:^(NSModalResponse response) {
            if (pendingSaves()[@(window)] != pending) return;
            [pendingSaves() removeObjectForKey:@(window)];
            if (response != NSModalResponseOK || !panel.URL) {
                neiv_callback_complete_project_save(window, generation, LightceptProjectSaveCancelled);
                return;
            }
            NSURL *destination = panel.URL;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                @autoreleasepool {
                    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:source error:NULL];
                    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
                    NSData *sourceBytes = size >= 8 && size <= 512ULL * 1024ULL * 1024ULL
                        ? [NSData dataWithContentsOfFile:source options:NSDataReadingMappedIfSafe error:NULL] : nil;
                    if (!sourceBytes || ![digestData(sourceBytes) isEqualToData:digest]) {
                        neiv_callback_complete_project_save(window, generation, LightceptProjectSaveChangedSource);
                        return;
                    }
                    lightcept_native_document_lock();
                    BOOL active = neiv_callback_can_save_project(window, generation) != 0;
                    BOOL written = active && [document writeToURL:destination options:NSDataWritingAtomic error:NULL];
                    lightcept_native_document_unlock();
                    neiv_callback_complete_project_save(window, generation, written ? LightceptProjectSaveSaved : LightceptProjectSaveIOFailure);
                }
            });
        }];
    });
    return 0;
}

// Status: idle, choosing path, saved, cancelled, failed, changed source, rendering.
int lightcept_native_export_status(long long window) {
    @synchronized (pendingExports()) {
        return (int)pendingExports()[@(window)].status;
    }
}

void lightcept_native_cancel_export(long long window) {
    dispatch_async(dispatch_get_main_queue(), ^{
        LightceptPendingExport *pending;
        @synchronized (pendingExports()) {
            pending = pendingExports()[@(window)];
            if (!pending || (pending.status != 1 && pending.status != 6)) return;
            pending.cancelled = YES;
            pending.status = 3;
        }
        [pending.panel cancel:nil];
        if (pending.task.isRunning) [pending.task terminate];
    });
}

int lightcept_native_export_tiff(long long window, unsigned int generation, const int *values) {
    if (window <= 0 || generation == 0 || !values || neiv_dialog_capability(1) != 1) return 1;
    if (values[0] < -40 || values[0] > 40) return 1;
    for (NSUInteger i = 1; i < 12; i++) if (values[i] < -100 || values[i] > 100) return 1;
    if (values[12] < 0 || values[13] < 0 || values[14] < 0 || values[15] < 0 ||
        values[12] > 10000 || values[13] > 10000 || values[14] > 10000 || values[15] > 10000 ||
        values[16] < -17000 || values[16] > 17000 || values[17] < 1 || values[17] > 8 ||
        ((values[14] == 0 || values[15] == 0) &&
         (values[12] != 0 || values[13] != 0 || values[14] != 0 || values[15] != 0)) ||
        (values[14] && (values[12] > 10000 - values[14] || values[13] > 10000 - values[15]))) return 1;
    lightcept_native_document_lock();
    LightceptFrame *frame = committedFrames()[@(window)];
    BOOL valid = frame && frame.generation == generation && frame.editable &&
        frame.sourcePath.isAbsolutePath && frame.sourceDigest.length == CC_SHA256_DIGEST_LENGTH &&
        [frame.routeID isEqualToString:routeForPath(frame.sourcePath)];
    NSData *hslValues = valid && hasHSL(frame.editValues) ? [frame.editValues copy] : nil;
    if (hslValues && !validHSL(hslValues)) valid = NO;
    if (hslValues && hasCurve(hslValues) && !validCurve(hslValues)) valid = NO;
    if (hslValues && hasGrading(hslValues) && !validGrading(hslValues)) valid = NO;
    if (hslValues && hasPickedColor(hslValues) && !validPickedColor(hslValues)) valid = NO;
    if (hslValues) {
        const int *committed = hslValues.bytes;
        for (NSUInteger index = 0; index < 18; index++)
            if (committed[index] != values[index]) valid = NO;
    }
    NSString *source = valid ? [frame.sourcePath copy] : nil;
    NSData *digest = valid ? [frame.sourceDigest copy] : nil;
    lightcept_native_document_unlock();
    if (!valid) return 1;
    NSString *extension = source.pathExtension.lowercaseString;
    int format = [extension isEqualToString:@"dng"] ? 1 : [extension isEqualToString:@"nef"] ? 2 : 0;
    if (!format) return 1;
    NSString *resources = NSBundle.mainBundle.resourcePath;
    NSString *exporter = [resources stringByAppendingPathComponent:@"lightcept-export-tiff"];
    NSString *icc = [resources stringByAppendingPathComponent:@"sRGB2014.icc"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:exporter] ||
        ![[NSFileManager defaultManager] fileExistsAtPath:icc]) return 1;
    BOOL hasGeometry = values[12] || values[13] || values[14] || values[15] || values[16] || values[17] != 1 || hslValues;
    NSMutableData *request = [NSMutableData dataWithCapacity:hslValues ? (hasPickedColor(hslValues) ? 304 : hasGrading(hslValues) ? 276 : hasCurve(hslValues) ? 224 : 176) : hasGeometry ? 80 : 52];
    NSUInteger fieldCount = hslValues ? (hasPickedColor(hslValues) ? 76 : hasGrading(hslValues) ? 69 : hasCurve(hslValues) ? 56 : 44) : hasGeometry ? 20 : 13;
    for (NSUInteger i = 0; i < fieldCount; i++) {
        uint32_t encoded = CFSwapInt32HostToLittle((uint32_t)(hasGeometry ?
            (i == 0 ? (hasPickedColor(hslValues) ? 8 : hasGrading(hslValues) ? 7 : hasCurve(hslValues) ? 6 : hslValues ? 4 : 3) : i == 1 ? format :
             i < 20 ? values[i - 2] : ((const int *)hslValues.bytes)[i - 2]) :
            (i == 0 ? format : values[i - 1])));
        [request appendBytes:&encoded length:sizeof(encoded)];
    }
    LightceptPendingExport *pending = [LightceptPendingExport new];
    pending.status = 1;
    @synchronized (pendingExports()) {
        if (pendingExports()[@(window)].status == 1 || pendingExports()[@(window)].status == 6) return 1;
        pendingExports()[@(window)] = pending;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (pending.cancelled) return;
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.allowedContentTypes = @[UTTypeTIFF];
        panel.nameFieldStringValue = [[source.lastPathComponent stringByDeletingPathExtension] stringByAppendingPathExtension:@"tiff"];
        pending.panel = panel;
        [panel beginWithCompletionHandler:^(NSModalResponse response) {
            if (pending.cancelled) return;
            if (response != NSModalResponseOK || !panel.URL) { pending.status = 3; return; }
            NSURL *destination = panel.URL;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                @autoreleasepool {
                    NSFileManager *manager = NSFileManager.defaultManager;
                    NSDictionary *attributes = [manager attributesOfItemAtPath:source error:NULL];
                    unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
                    NSData *sourceBytes = size >= 8 && size <= 512ULL * 1024ULL * 1024ULL
                        ? [NSData dataWithContentsOfFile:source options:NSDataReadingMappedIfSafe error:NULL] : nil;
                    if (!sourceBytes || ![digestData(sourceBytes) isEqualToData:digest]) {
                        if (!pending.cancelled) pending.status = 5;
                        return;
                    }
                    if (pending.cancelled) return;
                    if ([manager fileExistsAtPath:destination.path]) { pending.status = 4; return; }
                    NSString *directory = [destination.path.stringByDeletingLastPathComponent stringByAppendingPathComponent:
                        [@".lightcept-export-" stringByAppendingString:NSUUID.UUID.UUIDString]];
                    if (![manager createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:nil error:NULL]) {
                        pending.status = 4; return;
                    }
                    @try {
                        NSString *requestPath = [directory stringByAppendingPathComponent:@"request.bin"];
                        NSString *sourcePath = [directory stringByAppendingPathComponent:@"source.raw"];
                        NSString *outputPath = [directory stringByAppendingPathComponent:@"output.tiff"];
                        if (![request writeToFile:requestPath atomically:YES] ||
                            ![sourceBytes writeToFile:sourcePath atomically:NO]) { pending.status = 4; return; }
                        if (pending.cancelled) return;
                        pending.status = 6;
                        NSTask *task = [NSTask new];
                        task.executableURL = [NSURL fileURLWithPath:exporter];
                        task.arguments = @[sourcePath, icc, requestPath, outputPath];
                        pending.task = task;
                        NSError *error = nil;
                        if (![task launchAndReturnError:&error]) { pending.status = 4; return; }
                        if (pending.cancelled) [task terminate];
                        [task waitUntilExit];
                        NSDictionary *outputAttributes = [manager attributesOfItemAtPath:outputPath error:NULL];
                        @synchronized (pendingExports()) {
                            if (pending.cancelled) return;
                            if (task.terminationStatus != 0 || [outputAttributes[NSFileSize] unsignedLongLongValue] < 3188 ||
                                ![manager linkItemAtPath:outputPath toPath:destination.path error:NULL]) {
                                pending.status = 4; return;
                            }
                            pending.status = 2;
                        }
                    } @finally {
                        [manager removeItemAtPath:directory error:NULL];
                    }
                }
            });
        }];
    });
    return 0;
}

int lightcept_native_select_project(long long window, unsigned int generation) {
    if (window <= 0 || generation == 0 || neiv_dialog_capability(0) != 1) return 1;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!neiv_callback_is_open_generation(window, generation)) return;
        LightceptPendingPicker *previous = pendingPickers()[@(window)];
        if (previous) {
            [pendingPickers() removeObjectForKey:@(window)];
            [previous.panel cancel:nil];
        }
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        LightceptPendingPicker *pending = [LightceptPendingPicker new];
        pending.panel = panel;
        pending.generation = generation;
        pending.projectOnly = YES;
        panel.delegate = pending;
        pendingPickers()[@(window)] = pending;
        [panel beginWithCompletionHandler:^(NSModalResponse response) {
            if (pendingPickers()[@(window)] != pending) return;
            [pendingPickers() removeObjectForKey:@(window)];
            if (!neiv_callback_is_open_generation(window, generation)) return;
            if (response != NSModalResponseOK || !panel.URL) {
                neiv_callback_complete_open(window, generation, 7);
                return;
            }
            NSURL *projectURL = panel.URL;
            if ([projectURL.pathExtension caseInsensitiveCompare:@"lightcept"] != NSOrderedSame) {
                neiv_callback_complete_open(window, generation, 9);
                return;
            }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                @autoreleasepool {
                    NSData *data = [NSData dataWithContentsOfURL:projectURL options:0 error:NULL];
                    if (!data) { neiv_callback_complete_open(window, generation, 10); return; }
                    NSDictionary *project = readProject(data);
                    if (!project) { neiv_callback_complete_open(window, generation, projectRouteUnavailable(data) ? 11 : 9); return; }
                    NSArray *history = project[@"history"];
                    LightceptProjectSchema schema = (LightceptProjectSchema)[project[@"schema"] integerValue];
                    for (NSUInteger i = 0; i < history.count; i++) {
                        NSArray *entry = history[i];
                        if (!neiv_callback_stage_project_entry(window, generation, (unsigned int)i,
                            projectValue(entry, schema, LightceptProjectExposure), projectValue(entry, schema, LightceptProjectContrast),
                            projectValue(entry, schema, LightceptProjectShadows), projectValue(entry, schema, LightceptProjectHighlights),
                            projectValue(entry, schema, LightceptProjectBlacks), projectValue(entry, schema, LightceptProjectWhites),
                            projectValue(entry, schema, LightceptProjectWarmth), projectValue(entry, schema, LightceptProjectTint),
                            projectValue(entry, schema, LightceptProjectVibrance), projectValue(entry, schema, LightceptProjectSaturation),
                            projectValue(entry, schema, LightceptProjectClarity), projectValue(entry, schema, LightceptProjectTexture),
                            projectValue(entry, schema, LightceptProjectCropLeft), projectValue(entry, schema, LightceptProjectCropTop),
                            projectValue(entry, schema, LightceptProjectCropWidth), projectValue(entry, schema, LightceptProjectCropHeight),
                            projectValue(entry, schema, LightceptProjectStraighten),
                            projectValue(entry, schema, LightceptProjectTransform))) {
                            neiv_callback_complete_open(window, generation, 9);
                            return;
                        }
                        if (schema >= LightceptProjectSchemaHSL) {
                            for (NSUInteger band = 0; band < 8; band++) {
                                if (!neiv_callback_stage_project_hsl(window, generation,
                                    (unsigned int)i, (unsigned int)band,
                                    [entry[18 + band] intValue],
                                    [entry[26 + band] intValue],
                                    [entry[34 + band] intValue])) {
                                    neiv_callback_complete_open(window, generation, 9);
                                    return;
                                }
                            }
                        }
                        if (schema >= LightceptProjectSchemaCurve) {
                            for (NSUInteger channel = 0; channel < (schema >= LightceptProjectSchemaLumaCurve ? 4 : 3); channel++) {
                                NSUInteger first = 42 + channel * 3;
                                if (!neiv_callback_stage_project_curve(window, generation,
                                    (unsigned int)i, (unsigned int)channel,
                                    [entry[first] intValue], [entry[first + 1] intValue],
                                    [entry[first + 2] intValue])) {
                                    neiv_callback_complete_open(window, generation, 9);
                                    return;
                                }
                            }
                        }
                        if (schema >= LightceptProjectSchemaGrading) {
                            for (NSUInteger field = 0; field < (schema >= LightceptProjectSchemaPickedColor ? 20 : 13); field++) {
                                if (!neiv_callback_stage_grade(window, generation,
                                    (unsigned int)i, (unsigned int)field,
                                    [entry[54 + field] intValue])) {
                                    neiv_callback_complete_open(window, generation, 9);
                                    return;
                                }
                            }
                        }
                    }
                    unsigned int cursor = [project[@"cursor"] unsignedIntValue];
                    if (!neiv_callback_finish_project_entries(window, generation, (unsigned int)history.count,
                        cursor, [project[@"editRevision"] unsignedIntValue])) {
                        neiv_callback_complete_open(window, generation, 9);
                        return;
                    }
                    NSArray *selected = history[cursor];
                    NSString *source = project[@"sourcePath"];
                    NSData *selectedValues = nil;
                    if (schema >= LightceptProjectSchemaGeometry) {
                        NSData *controls = editValues(
                            projectValue(selected, schema, LightceptProjectExposure), projectValue(selected, schema, LightceptProjectContrast),
                            projectValue(selected, schema, LightceptProjectShadows), projectValue(selected, schema, LightceptProjectHighlights),
                            projectValue(selected, schema, LightceptProjectBlacks), projectValue(selected, schema, LightceptProjectWhites),
                            projectValue(selected, schema, LightceptProjectWarmth), projectValue(selected, schema, LightceptProjectTint),
                            projectValue(selected, schema, LightceptProjectVibrance), projectValue(selected, schema, LightceptProjectSaturation),
                            projectValue(selected, schema, LightceptProjectClarity), projectValue(selected, schema, LightceptProjectTexture));
                        selectedValues = editValuesWithGeometry(controls, selected, schema);
                    }
                    if (!scheduleOpen(source, window, generation,
                        projectValue(selected, schema, LightceptProjectExposure), projectValue(selected, schema, LightceptProjectContrast),
                        projectValue(selected, schema, LightceptProjectShadows), projectValue(selected, schema, LightceptProjectHighlights),
                        projectValue(selected, schema, LightceptProjectBlacks), projectValue(selected, schema, LightceptProjectWhites),
                        projectValue(selected, schema, LightceptProjectWarmth), projectValue(selected, schema, LightceptProjectTint),
                        projectValue(selected, schema, LightceptProjectVibrance), projectValue(selected, schema, LightceptProjectSaturation),
                        projectValue(selected, schema, LightceptProjectClarity), projectValue(selected, schema, LightceptProjectTexture), selectedValues,
                        digestFromHex(project[@"sourceSHA256"]), digestFromHex(project[@"workingSHA256"]),
                        digestFromHex(project[@"baselineSHA256"]),
                        // Schema 10 stored a preview rendered with straight RGB segments.
                        // Schema 11 remaps those values with a smooth curve on replay.
                        schema == LightceptProjectSchemaCurve ? nil : digestFromHex(project[@"previewSHA256"]),
                        [project[@"previewWidth"] unsignedLongLongValue],
                        [project[@"previewHeight"] unsignedLongLongValue]))
                        neiv_callback_complete_open(window, generation, 7);
                }
            });
        }];
    });
    return 0;
}

int lightcept_native_select_photo(long long window, unsigned int generation) {
    if (window <= 0 || generation == 0 || neiv_dialog_capability(0) != 1) return 5;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!neiv_callback_is_open_generation(window, generation)) return;
        LightceptPendingPicker *previous = pendingPickers()[@(window)];
        if (previous) {
            [pendingPickers() removeObjectForKey:@(window)];
            [previous.panel cancel:nil];
        }
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        LightceptPendingPicker *pending = [LightceptPendingPicker new];
        pending.panel = panel;
        pending.generation = generation;
        pendingPickers()[@(window)] = pending;
        [panel beginWithCompletionHandler:^(NSModalResponse response) {
            if (pendingPickers()[@(window)] != pending) return;
            [pendingPickers() removeObjectForKey:@(window)];
            if (!neiv_callback_is_open_generation(window, generation)) return;
            NSString *source = response == NSModalResponseOK ? panel.URL.path : nil;
            if (source.length > 0) scheduleOpen(source, window, generation, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, nil, nil, nil, nil, nil, 0, 0);
            else neiv_callback_complete_open(window, generation, 7);
        }];
    });
    return 0;
}

// Render all controls from the source-neutral fitted frame while geometry and size stay fixed.
static BOOL scheduleCachedPreview(LightceptFrame *prepared, NSData *values, long long window, unsigned int generation) {
    if (!prepared.preparedWorking || prepared.preparedWorking.length != prepared.width * prepared.height * 3 * sizeof(double) ||
        prepared.preparedBaseline.length != sizeof(double) ||
        (hasHSL(values) && !validHSL(values)) ||
        (hasCurve(values) && !validCurve(values)) || (hasGrading(values) && !validGrading(values)) ||
        (hasPickedColor(values) && !validPickedColor(values)) ||
        memcmp((const int *)values.bytes + 12, (const int *)prepared.editValues.bytes + 12, 6 * sizeof(int))) return NO;
    lightcept_native_document_lock();
    BOOL current = committedFrames()[@(window)] == prepared && neiv_callback_is_open_generation(window, generation);
    NSTask *oldTask = fittedPreviewTasks()[@(window)];
    if (current) [fittedPreviewTasks() removeObjectForKey:@(window)];
    lightcept_native_document_unlock();
    if (!current) return NO;
    if (oldTask.isRunning) [oldTask terminate];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSFileManager *manager = NSFileManager.defaultManager;
            NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [@"lightcept-cached-" stringByAppendingString:NSUUID.UUID.UUIDString]];
            int status = 3;
            if ([manager createDirectoryAtPath:directory withIntermediateDirectories:NO attributes:nil error:NULL]) {
                @try { do {
                    NSString *workingPath = [directory stringByAppendingPathComponent:@"working.f64"];
                    NSString *baselinePath = [directory stringByAppendingPathComponent:@"baseline.f64"];
                    NSString *requestPath = [directory stringByAppendingPathComponent:@"request.bin"];
                    NSString *outputPath = [directory stringByAppendingPathComponent:@"preview.rgba"];
                    int32_t fields[78] = {0};
                    const int *edits = values.bytes;
                    fields[0] = 8;
                    fields[1] = 3;
                    for (NSUInteger i = 0; i < 12; i++) fields[2 + i] = edits[i];
                    fields[14] = (int32_t)prepared.width;
                    fields[15] = (int32_t)prepared.height;
                    for (NSUInteger i = 0; i < 5; i++) fields[16 + i] = edits[12 + i];
                    fields[21] = edits[17];
                    if (hasHSL(values)) for (NSUInteger i = 0; i < 24; i++) fields[22 + i] = edits[18 + i];
                    if (hasCurve(values)) for (NSUInteger i = 0; i < 12; i++) fields[46 + i] = edits[42 + i];
                    else for (NSUInteger i = 0; i < 12; i++) fields[46 + i] = (int32_t[]){250, 500, 750}[i % 3];
                    if (hasGrading(values)) for (NSUInteger i = 0; i < 13; i++) fields[58 + i] = edits[54 + i];
                    if (hasPickedColor(values)) for (NSUInteger i = 0; i < 7; i++) fields[71 + i] = edits[67 + i];
                    for (NSUInteger i = 0; i < 78; i++) fields[i] = (int32_t)CFSwapInt32HostToLittle((uint32_t)fields[i]);
                    if (![prepared.preparedWorking writeToFile:workingPath atomically:YES] ||
                        ![prepared.preparedBaseline writeToFile:baselinePath atomically:YES] ||
                        ![[NSData dataWithBytes:fields length:sizeof(fields)] writeToFile:requestPath atomically:YES]) break;
                    NSTask *task = [NSTask new];
                    task.executableURL = [NSURL fileURLWithPath:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"lightcept-fitted-preview"]];
                    task.arguments = @[workingPath, requestPath, outputPath, baselinePath];
                    lightcept_native_document_lock();
                    BOOL valid = committedFrames()[@(window)] == prepared && neiv_callback_is_open_generation(window, generation);
                    if (valid) fittedPreviewTasks()[@(window)] = task;
                    lightcept_native_document_unlock();
                    if (!valid) { status = 7; break; }
                    if (![task launchAndReturnError:NULL]) break;
                    [task waitUntilExit];
                    lightcept_native_document_lock();
                    if (fittedPreviewTasks()[@(window)] == task) [fittedPreviewTasks() removeObjectForKey:@(window)];
                    valid = committedFrames()[@(window)] == prepared && neiv_callback_is_open_generation(window, generation);
                    lightcept_native_document_unlock();
                    if (!valid) { status = 7; break; }
                    if (task.terminationStatus != 0) { status = 5; break; }
                    NSData *pixels = [NSData dataWithContentsOfFile:outputPath];
                    if (pixels.length != prepared.width * prepared.height * 4) { status = 5; break; }
                    LightceptFrame *frame = [LightceptFrame new];
                    frame.pixels = pixels;
                    frame.width = prepared.width;
                    frame.height = prepared.height;
                    frame.generation = generation;
                    frame.sourcePath = prepared.sourcePath;
                    frame.sourceDigest = prepared.sourceDigest;
                    frame.workingDigest = prepared.workingDigest;
                    frame.baselineDigest = prepared.baselineDigest;
                    frame.previewDigest = digestData(pixels);
                    frame.routeID = prepared.routeID;
                    frame.editable = YES;
                    frame.preparedWorking = prepared.preparedWorking;
                    frame.preparedBaseline = prepared.preparedBaseline;
                    frame.neutralPixels = prepared.neutralPixels;
                    frame.editValues = values;
                    frame.sourceWidth = prepared.sourceWidth;
                    frame.sourceHeight = prepared.sourceHeight;
                    frame.sourceCanvasWidth = prepared.sourceCanvasWidth;
                    frame.sourceCanvasHeight = prepared.sourceCanvasHeight;
                    lightcept_native_document_lock();
                    valid = committedFrames()[@(window)] == prepared && neiv_callback_is_open_generation(window, generation);
                    if (valid) candidateFrames()[@(window)] = frame;
                    lightcept_native_document_unlock();
                    status = valid ? 0 : 7;
                } while (0); } @finally {
                    [manager removeItemAtPath:directory error:NULL];
                }
            }
            neiv_callback_complete_open(window, generation, status);
        }
    });
    return YES;
}

int lightcept_native_rerender_history(long long window, unsigned int generation,
    const int *values, size_t length) {
    if (window <= 0 || generation == 0 || !values || (length != 18 && length != 42 && length != 54 && length != 67 && length != 74)) return 4;
    NSData *recipe = [NSData dataWithBytes:values length:length * sizeof(int)];
    if (length == 42 && !validHSL(recipe)) return 4;
    if ((length == 54 || length == 67 || length == 74) && (!validHSL(recipe) || !validCurve(recipe))) return 4;
    if ((length == 67 || length == 74) && !validGrading(recipe)) return 4;
    if (length == 74 && !validPickedColor(recipe)) return 4;
    lightcept_native_document_lock();
    LightceptFrame *frame = committedFrames()[@(window)];
    NSString *source = frame.editable ? [frame.sourcePath copy] : nil;
    NSData *digest = frame.sourceDigest;
    NSData *baseline = frame.baselineDigest;
    size_t sourceWidth = frame.sourceCanvasWidth, sourceHeight = frame.sourceCanvasHeight;
    lightcept_native_document_unlock();
    if (!source || !digest || !baseline || !sourceWidth || !sourceHeight) return 2;
    if (values[12] < 0 || values[13] < 0 || values[14] < 0 || values[15] < 0 ||
        values[16] < -17000 || values[16] > 17000 ||
        values[17] < 1 || values[17] > 8) return 4;
    size_t canvasWidth = values[17] >= 5 ? sourceHeight : sourceWidth;
    size_t canvasHeight = values[17] >= 5 ? sourceWidth : sourceHeight;
    if (values[14] || values[15]) {
        if (values[14] <= 0 || values[15] <= 0 ||
            (size_t)values[12] >= canvasWidth || (size_t)values[13] >= canvasHeight ||
            (size_t)values[14] > canvasWidth - (size_t)values[12] ||
            (size_t)values[15] > canvasHeight - (size_t)values[13]) return 4;
        canvasWidth = (size_t)values[14];
        canvasHeight = (size_t)values[15];
    } else if (values[12] || values[13]) return 4;
    size_t width = canvasWidth, height = canvasHeight;
    if (width > 2048 || height > 2048) {
        if (width >= height) { height = MAX((size_t)1, height * 2048 / width); width = 2048; }
        else { width = MAX((size_t)1, width * 2048 / height); height = 2048; }
    }
    if (width == frame.width && height == frame.height && scheduleCachedPreview(frame, recipe, window, generation)) return 0;
    return scheduleOpen(source, window, generation, values[0], values[1], values[2], values[3],
        values[4], values[5], values[6], values[7], values[8], values[9], values[10], values[11],
        recipe, digest, nil, baseline, nil, width, height) ? 0 : 7;
}

int lightcept_native_source_canvas_size(long long window, unsigned int generation,
    size_t *width, size_t *height) {
    if (window <= 0 || generation == 0 || !width || !height) return 0;
    lightcept_native_document_lock();
    LightceptFrame *frame = committedFrames()[@(window)];
    BOOL valid = frame && frame.generation == generation && frame.editable &&
        frame.sourceCanvasWidth > 0 && frame.sourceCanvasHeight > 0;
    if (valid) {
        *width = frame.sourceCanvasWidth;
        *height = frame.sourceCanvasHeight;
    }
    lightcept_native_document_unlock();
    return valid ? 1 : 0;
}

int lightcept_native_rerender_develop(long long window, unsigned int generation, int exposureTenths, int contrastPercent, int shadowsPercent, int highlightsPercent, int blacksPercent, int whitesPercent, int warmthPercent, int tintPercent, int vibrancePercent, int saturationPercent, int clarityPercent, int texturePercent) {
    if (window <= 0 || generation == 0 || exposureTenths < -160 || exposureTenths > 160 || contrastPercent < -100 || contrastPercent > 100 || shadowsPercent < -100 || shadowsPercent > 100 || highlightsPercent < -100 || highlightsPercent > 100) return 4;
    lightcept_native_document_lock();
    LightceptFrame *frame = committedFrames()[@(window)];
    NSString *source = frame.editable ? frame.sourcePath : nil;
    lightcept_native_document_unlock();
    if (source.length == 0) return 2;
    NSMutableData *recipe = [frame.editValues mutableCopy];
    int *controls = recipe.mutableBytes;
    const int updated[12] = {exposureTenths, contrastPercent, shadowsPercent, highlightsPercent,
        blacksPercent, whitesPercent, warmthPercent, tintPercent, vibrancePercent,
        saturationPercent, clarityPercent, texturePercent};
    memcpy(controls, updated, sizeof(updated));
    if (scheduleCachedPreview(frame, recipe, window, generation)) return 0;
    return scheduleOpen(source, window, generation, exposureTenths, contrastPercent, shadowsPercent,
        highlightsPercent, blacksPercent, whitesPercent, warmthPercent, tintPercent, vibrancePercent,
        saturationPercent, clarityPercent, texturePercent, frame.editValues, frame.sourceDigest,
        nonneutralGeometry(frame.editValues) ? nil : frame.workingDigest, frame.baselineDigest,
        nil, frame.width, frame.height) ? 0 : 7;
}

@interface LightceptPreviewPlugin : NSObject <CynaHostPlugin, CynaSurfaceProvider>
@property(nonatomic) long long windowHandle;
@end

@implementation LightceptPreviewPlugin
- (void)windowHandleAssigned:(long long)handle { self.windowHandle = handle; }
- (void)attachToRoot:(NSView *)root webview:(WKWebView *)webview slots:(CynaSlotHost *)slots {
    (void)root; (void)webview; (void)slots;
}
- (void)receiveMessage:(NSDictionary *)message { (void)message; }
- (void)navigationStarted {}
- (void)close {
    if (self.windowHandle <= 0) return;
    lightcept_native_cancel_picker(self.windowHandle, 0);
    lightcept_native_cancel_export(self.windowHandle);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNumber *key = @(self.windowHandle);
        NSTask *task = regionTasks()[key];
        if (task.isRunning) [task terminate];
        [regionTasks() removeObjectForKey:key];
        [regionTokens() removeObjectForKey:key];
        LightceptPendingSave *pending = pendingSaves()[@(self.windowHandle)];
        if (pending) {
            [pendingSaves() removeObjectForKey:@(self.windowHandle)];
            [pending.panel cancel:nil];
        }
    });
    lightcept_native_document_lock();
    NSTask *fittedTask = fittedPreviewTasks()[@(self.windowHandle)];
    [fittedPreviewTasks() removeObjectForKey:@(self.windowHandle)];
    neiv_callback_close_document(self.windowHandle);
    [committedFrames() removeObjectForKey:@(self.windowHandle)];
    [candidateFrames() removeObjectForKey:@(self.windowHandle)];
    [candidateSources() removeObjectForKey:@(self.windowHandle)];
    [comparisonModes() removeObjectForKey:@(self.windowHandle)];
    [proofProfiles() removeObjectForKey:@(self.windowHandle)];
    [zoomLevels() removeObjectForKey:@(self.windowHandle)];
    lightcept_native_document_unlock();
    if (fittedTask.isRunning) [fittedTask terminate];
    dispatch_async(dispatch_get_main_queue(), ^{
        [previewViews() removeObjectForKey:@(self.windowHandle)];
        [navigatorViews() removeObjectForKey:@(self.windowHandle)];
        [filmstripViews() removeObjectForKey:@(self.windowHandle)];
    [histogramViews() removeObjectForKey:@(self.windowHandle)];
    });
}
- (NSDictionary<NSString *, id<CynaSurfaceProvider>> *)surfaceProviders {
    return @{@"lightcept.preview": self};
}
- (NSView *)createSurfaceWithOptions:(NSDictionary *)options {
    BOOL navigator = [options[@"role"] isEqualToString:@"navigator"];
    BOOL filmstrip = [options[@"role"] isEqualToString:@"filmstrip"];
    BOOL histogram = [options[@"role"] isEqualToString:@"histogram"];
    if (!((options.count == 1 && !options[@"role"]) || (options.count == 2 && (navigator || filmstrip || histogram))) ||
        ![options[@"window"] isKindOfClass:NSNumber.class]) return nil;
    long long window = [options[@"window"] longLongValue];
    if (window <= 0) return nil;
    lightcept_native_document_lock();
    LightceptFrame *frame = committedFrames()[@(window)];
    lightcept_native_document_unlock();
    if (histogram) {
        LightceptHistogramView *view = [LightceptHistogramView new];
        view.sourceFrame = frame;
        view.accessibilityLabel = @"Developed preview luminance histogram";
        histogramViews()[@(window)] = view;
        return view;
    }
    NSImage *image = navigator || filmstrip ? imageForFrame(frame) : nil;
    if ((navigator || filmstrip) && !image) return nil;
    NSImageView *view = navigator || filmstrip ? [NSImageView new] : [LightceptZoomView new];
    if (navigator || filmstrip) view.image = image;
    else {
        LightceptZoomView *zoom = (LightceptZoomView *)view;
        zoom.windowHandle = window;
        zoom.splitFraction = 0.5;
        __weak LightceptZoomView *weakZoom = zoom;
        zoom.viewportChanged = ^{
            LightceptZoomView *currentZoom = weakZoom;
            if (!currentZoom) return;
            zoomLevels()[@(window)] = @(currentZoom.zoomPercent);
            scheduleSourceRegion(window);
        };
        updatePreviewView(zoom, frame, window);
        if (!zoom.image) return nil;
    }
    if (navigator || filmstrip) view.imageScaling = NSImageScaleProportionallyUpOrDown;
    else ((LightceptZoomView *)view).zoomPercent = [zoomLevels()[@(window)] integerValue];
    view.accessibilityLabel = navigator ? @"Navigator photograph" : filmstrip ? @"Filmstrip photograph" : @"Photograph preview";
    if (navigator) navigatorViews()[@(window)] = view;
    else if (filmstrip) filmstripViews()[@(window)] = view;
    else {
        previewViews()[@(window)] = (LightceptZoomView *)view;
        scheduleSourceRegion(window);
    }
    return view;
}
@end
