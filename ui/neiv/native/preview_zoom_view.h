#import <AppKit/AppKit.h>

@interface LightceptZoomView : NSImageView
@property(nonatomic) NSInteger zoomPercent; // 0 means fit; otherwise image pixels per view point.
@property(nonatomic) NSPoint pan;
@property(nonatomic) NSPoint dragStart;
@property(nonatomic, strong) NSImage *beforeImage;
@property(nonatomic) NSInteger comparisonMode; // 0 after, 1 before, 2 adjustable split.
@property(nonatomic) CGFloat splitFraction;
@property(nonatomic) BOOL draggingDivider;
@property(nonatomic, strong) NSTrackingArea *cursorTrackingArea;
@property(nonatomic) long long windowHandle;
@property(nonatomic) size_t sourceWidth;
@property(nonatomic) size_t sourceHeight;
@property(nonatomic) BOOL cropMode;
@property(nonatomic) BOOL pickColorMode;
@property(nonatomic, strong) NSData *pickWorking;
@property(nonatomic) size_t pickWidth;
@property(nonatomic) size_t pickHeight;
@property(nonatomic) BOOL pickedMaskVisible;
@property(nonatomic) NSInteger pickedHue;
@property(nonatomic) NSInteger pickedWidth;
@property(nonatomic) NSInteger pickedSoftness;
@property(nonatomic, strong) NSImage *pickedMaskImage;
- (void)refreshPickedMask;
@property(nonatomic) BOOL draggingCrop;
@property(nonatomic) NSPoint cropStart;
@property(nonatomic) NSRect cropSelection; // Current image source pixels.
@property(nonatomic) NSRect cropDragOriginal;
@property(nonatomic) NSInteger cropDragKind; // 0 new, 1 move, 2-5 corner resize.
@property(nonatomic) BOOL cropHasUserSelection;
@property(nonatomic) NSInteger cropAspectPreset; // 0 free, 1 square, 2 4:3, 3 3:2, 4 16:9.
@property(nonatomic) NSInteger cropOriginLeft;
@property(nonatomic) NSInteger cropOriginTop;
@property(nonatomic) NSInteger straightenMillidegrees;
@property(nonatomic, copy) NSArray<NSValue *> *detailRects; // Upright source pixel coordinates.
@property(nonatomic, copy) NSArray<NSImage *> *detailImages;
@property(nonatomic, copy) NSArray<NSImage *> *detailBeforeImages;
@property(nonatomic, copy) void (^viewportChanged)(void);
- (NSRect)visibleSourceRect;
- (void)clearSourceDetail;
- (void)setCropAspectPreset:(NSInteger)preset;
@end
