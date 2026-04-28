//
//  iTermCommandLineBackgroundRenderer.h
//  iTerm2SharedARC
//
//  Tints the background of every executed command line.
//

#import "iTermMetalRenderer.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermCommandLineBackgroundRendererTransientState : iTermMetalRendererTransientState

@property (nonatomic) BOOL shouldDraw;

// Viewport-local row indices (0 = topmost visible row). Recomputed each frame
// from the absolute-line indexset, so the tint follows scrolling.
@property (nonatomic, copy, nullable) NSIndexSet *rowIndices;

// Tint color (premultiplied alpha will be applied internally).
@property (nonatomic) vector_float4 tintColor;

@property (nonatomic) CGFloat rowHeight;  // pixels

@end

@interface iTermCommandLineBackgroundRenderer : NSObject<iTermMetalRenderer>
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
