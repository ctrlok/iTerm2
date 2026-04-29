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

// Top margin in pixels — distance from the top edge of the viewport down
// to the top edge of row 0. This must include both the standard
// topBottomMargins (in pixels) and the per-pane extraMargins.top, matching
// the effective top margin used by the cell renderers.
@property (nonatomic) CGFloat topMargin;

// Left margin in pixels — distance from the left edge of the viewport in
// to the left edge of column 0. This includes the standard sideMargins (in
// pixels) and the per-pane extraMargins.left.
@property (nonatomic) CGFloat leftMargin;

// Cell width in pixels.
@property (nonatomic) CGFloat cellWidth;

// Maps @(row) -> NSIndexSet of selected visual cell columns on that row.
// Rows missing from the dictionary (or with an empty index set) are tinted
// at full width. Selected cells are punched out of the tint so the user’s
// text selection remains visible.
@property (nonatomic, copy, nullable) NSDictionary<NSNumber *, NSIndexSet *> *selectedColumnsByRow;

@end

@interface iTermCommandLineBackgroundRenderer : NSObject<iTermMetalRenderer>
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
