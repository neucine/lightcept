#import <AppKit/AppKit.h>
#import "../ui/neiv/native/preview_zoom_view.h"

int neiv_publish_event(const char *topic, const char *payloadJson, long long targetHandle) {
    (void)topic; (void)payloadJson; (void)targetHandle;
    return 0;
}

@interface LightceptZoomView (CropRatioCheck)
- (NSRect)selectionFromAnchor:(NSPoint)anchor toPoint:(NSPoint)end;
@end

int main(void) {
    @autoreleasepool {
        LightceptZoomView *view = [[LightceptZoomView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
        view.sourceWidth = 6000;
        view.sourceHeight = 4000;
        const NSInteger numerators[] = {1, 4, 3, 16};
        const NSInteger denominators[] = {1, 3, 2, 9};
        const CGFloat positionsX[] = {0.1, 0.6, 19.4, 3000.4, 5999.4, 5999.9};
        const CGFloat positionsY[] = {0.1, 0.6, 19.4, 2000.6, 3999.4, 3999.9};
        for (NSInteger preset = 1; preset <= 4; preset++) {
            view.cropAspectPreset = preset;
            for (NSInteger x = 0; x < 6; x++) {
                for (NSInteger y = 0; y < 6; y++) {
                    NSPoint anchor = NSMakePoint(positionsX[x], positionsY[y]);
                    NSPoint end = NSMakePoint(positionsX[5 - x], positionsY[5 - y]);
                    NSRect rect = [view selectionFromAnchor:anchor toPoint:end];
                    if (rect.size.width * denominators[preset - 1] !=
                            rect.size.height * numerators[preset - 1] ||
                        NSMinX(rect) < 0 || NSMinY(rect) < 0 ||
                        NSMaxX(rect) > view.sourceWidth || NSMaxY(rect) > view.sourceHeight) {
                        NSLog(@"Invalid preset %ld rectangle %@", (long)preset, NSStringFromRect(rect));
                        return 1;
                    }
                }
            }
            view.cropMode = YES;
            view.cropSelection = NSMakeRect(83, 47, 739, 527);
            [view setCropAspectPreset:preset];
            NSRect adjusted = view.cropSelection;
            if (adjusted.size.width * denominators[preset - 1] !=
                    adjusted.size.height * numerators[preset - 1]) {
                NSLog(@"Invalid preset change %ld rectangle %@", (long)preset,
                    NSStringFromRect(adjusted));
                return 1;
            }
            view.cropSelection = NSMakeRect(83, 47, 2, 2);
            [view setCropAspectPreset:preset];
            adjusted = view.cropSelection;
            if (adjusted.size.width * denominators[preset - 1] !=
                    adjusted.size.height * numerators[preset - 1] ||
                adjusted.size.width < 2 || adjusted.size.height < 2) {
                NSLog(@"Invalid small preset change %ld rectangle %@", (long)preset,
                    NSStringFromRect(adjusted));
                return 1;
            }
        }
    }
    return 0;
}
