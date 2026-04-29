//
//  iTermCommandLineBackgroundRenderer.m
//  iTerm2SharedARC
//
//  Tints the background of every executed command line.
//

#import "iTermCommandLineBackgroundRenderer.h"

@implementation iTermCommandLineBackgroundRendererTransientState
@end

@implementation iTermCommandLineBackgroundRenderer {
    iTermMetalRenderer *_solidColorRenderer;
    iTermMetalMixedSizeBufferPool *_colorsPool;
    iTermMetalMixedSizeBufferPool *_verticesPool;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _solidColorRenderer = [[iTermMetalRenderer alloc] initWithDevice:device
                                                      vertexFunctionName:@"iTermSolidColorVertexShader"
                                                    fragmentFunctionName:@"iTermSolidColorFragmentShader"
                                                                blending:[iTermMetalBlending compositeSourceOver]
                                                     transientStateClass:[iTermCommandLineBackgroundRendererTransientState class]];
        _colorsPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                   capacity:8
                                                                       name:@"command line bg colors"];
        _verticesPool = [[iTermMetalMixedSizeBufferPool alloc] initWithDevice:device
                                                                     capacity:8
                                                                         name:@"command line bg vertices"];
    }
    return self;
}

- (BOOL)rendererDisabled {
    return NO;
}

- (iTermMetalFrameDataStat)createTransientStateStat {
    // Reuses the offscreen-CL stat bucket to avoid adding a new enum.
    return iTermMetalFrameDataStatPqCreateOffscreenCommandLineTS;
}

- (void)drawWithFrameData:(iTermMetalFrameData *)frameData
           transientState:(__kindof iTermMetalRendererTransientState *)transientState {
    iTermCommandLineBackgroundRendererTransientState *tState = transientState;
    if (!tState.shouldDraw || tState.rowIndices.count == 0) {
        return;
    }
    const CGFloat viewportHeight = tState.configuration.viewportSize.y;
    const CGFloat viewportWidth = tState.configuration.viewportSize.x;
    const CGFloat rowHeight = tState.rowHeight;
    // tState.topMargin is the full top inset (topBottomMargins*scale +
    // extraMargins.top) so row 0 sits where the cell renderers place it.
    const CGFloat topMargin = tState.topMargin;
    const CGFloat bottomMargin = tState.configuration.extraMargins.bottom;
    const CGFloat leftMargin = tState.leftMargin;
    const CGFloat cellWidth = tState.cellWidth;
    NSDictionary<NSNumber *, NSIndexSet *> *const selectedColumnsByRow = tState.selectedColumnsByRow;

    // Build per-row pixel-space x ranges of selected cells. Each entry is the
    // list of [start, end) pairs for a row that has any selected columns.
    // We compute these once up front so we can size the buffers correctly.
    NSMutableDictionary<NSNumber *, NSData *> *selectedXRangesByRow = [NSMutableDictionary dictionary];
    [selectedColumnsByRow enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSIndexSet *indexes, BOOL *stop) {
        if (indexes.count == 0) {
            return;
        }
        NSMutableData *data = [NSMutableData data];
        [indexes enumerateRangesUsingBlock:^(NSRange range, BOOL *innerStop) {
            const CGFloat start = leftMargin + (CGFloat)range.location * cellWidth;
            const CGFloat end = start + (CGFloat)range.length * cellWidth;
            const CGFloat clampedStart = MAX(0.0, MIN(viewportWidth, start));
            const CGFloat clampedEnd = MAX(0.0, MIN(viewportWidth, end));
            if (clampedEnd <= clampedStart) {
                return;
            }
            CGFloat pair[2] = { clampedStart, clampedEnd };
            [data appendBytes:pair length:sizeof(pair)];
        }];
        if (data.length > 0) {
            selectedXRangesByRow[key] = data;
        }
    }];

    // First pass: count quads. Off-screen rows still emit one (degenerate)
    // quad to keep buffer indexing balanced.
    NSIndexSet *const rowIndices = tState.rowIndices;
    __block NSUInteger numQuads = 0;
    [rowIndices enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        const CGFloat top = viewportHeight - topMargin - (CGFloat)row * rowHeight;
        const CGFloat bottom = top - rowHeight;
        const CGFloat minY = MAX(bottom, bottomMargin);
        const CGFloat maxY = MIN(top, viewportHeight - topMargin);
        if (maxY <= minY) {
            numQuads += 1;
            return;
        }
        NSData *ranges = selectedXRangesByRow[@(row)];
        if (!ranges) {
            numQuads += 1;
            return;
        }
        const NSUInteger count = ranges.length / (sizeof(CGFloat) * 2);
        const CGFloat *pairs = (const CGFloat *)ranges.bytes;
        NSUInteger gaps = 0;
        CGFloat cursor = 0;
        for (NSUInteger i = 0; i < count; i++) {
            const CGFloat rs = pairs[i * 2];
            const CGFloat re = pairs[i * 2 + 1];
            if (rs > cursor) {
                gaps++;
            }
            cursor = MAX(cursor, re);
        }
        if (cursor < viewportWidth) {
            gaps++;
        }
        if (gaps == 0) {
            // Selection covers the entire row width — still emit one
            // degenerate quad to keep bookkeeping simple.
            numQuads += 1;
        } else {
            numQuads += gaps;
        }
    }];

    NSMutableData *vertexData = [NSMutableData dataWithLength:sizeof(iTermVertex) * 6 * numQuads];
    iTermVertex *vertices = (iTermVertex *)vertexData.mutableBytes;

    NSMutableData *colorData = [NSMutableData dataWithLength:sizeof(vector_float4) * numQuads];
    vector_float4 *colors = (vector_float4 *)colorData.mutableBytes;

    // tintColor is already premultiplied by the per-frame state.
    const vector_float4 tint = tState.tintColor;

    void (^emitDegenerate)(NSUInteger) = ^(NSUInteger quadIndex) {
        for (int i = 0; i < 6; i++) {
            vertices[quadIndex * 6 + i] = (iTermVertex){ {0, 0}, {0, 0} };
        }
        colors[quadIndex] = (vector_float4){0, 0, 0, 0};
    };

    void (^emitQuad)(NSUInteger, CGRect) = ^(NSUInteger quadIndex, CGRect rect) {
        vertices[quadIndex * 6 + 0] = (iTermVertex){ { CGRectGetMaxX(rect), CGRectGetMinY(rect) }, { 1, 0 } };
        vertices[quadIndex * 6 + 1] = (iTermVertex){ { CGRectGetMinX(rect), CGRectGetMinY(rect) }, { 0, 0 } };
        vertices[quadIndex * 6 + 2] = (iTermVertex){ { CGRectGetMinX(rect), CGRectGetMaxY(rect) }, { 0, 1 } };

        vertices[quadIndex * 6 + 3] = (iTermVertex){ { CGRectGetMaxX(rect), CGRectGetMinY(rect) }, { 1, 0 } };
        vertices[quadIndex * 6 + 4] = (iTermVertex){ { CGRectGetMinX(rect), CGRectGetMaxY(rect) }, { 0, 1 } };
        vertices[quadIndex * 6 + 5] = (iTermVertex){ { CGRectGetMaxX(rect), CGRectGetMaxY(rect) }, { 1, 1 } };
        colors[quadIndex] = tint;
    };

    __block NSUInteger quadIndex = 0;
    [rowIndices enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        // Row 0 is the topmost visible row. The viewport origin is at the
        // bottom-left, so y decreases as row increases.
        const CGFloat top = viewportHeight - topMargin - (CGFloat)row * rowHeight;
        // Tint the full cell — rowHeight already includes inter-line spacing.
        const CGFloat bottom = top - rowHeight;
        const CGFloat minY = MAX(bottom, bottomMargin);
        const CGFloat maxY = MIN(top, viewportHeight - topMargin);
        if (maxY <= minY) {
            emitDegenerate(quadIndex);
            quadIndex++;
            return;
        }

        NSData *ranges = selectedXRangesByRow[@(row)];
        if (!ranges) {
            emitQuad(quadIndex, CGRectMake(0, minY, viewportWidth, maxY - minY));
            quadIndex++;
            return;
        }

        const NSUInteger count = ranges.length / (sizeof(CGFloat) * 2);
        const CGFloat *pairs = (const CGFloat *)ranges.bytes;
        NSUInteger emitted = 0;
        CGFloat cursor = 0;
        for (NSUInteger i = 0; i < count; i++) {
            const CGFloat rs = pairs[i * 2];
            const CGFloat re = pairs[i * 2 + 1];
            if (rs > cursor) {
                emitQuad(quadIndex, CGRectMake(cursor, minY, rs - cursor, maxY - minY));
                quadIndex++;
                emitted++;
            }
            cursor = MAX(cursor, re);
        }
        if (cursor < viewportWidth) {
            emitQuad(quadIndex, CGRectMake(cursor, minY, viewportWidth - cursor, maxY - minY));
            quadIndex++;
            emitted++;
        }
        if (emitted == 0) {
            // Selection covers the entire row width.
            emitDegenerate(quadIndex);
            quadIndex++;
        }
    }];

    tState.vertexBuffer = [_verticesPool requestBufferFromContext:tState.poolContext
                                                             size:vertexData.length
                                                            bytes:vertexData.mutableBytes];
    id<MTLBuffer> colorsBuffer = [_colorsPool requestBufferFromContext:tState.poolContext
                                                                  size:colorData.length
                                                                 bytes:colorData.mutableBytes];

    [_solidColorRenderer drawWithTransientState:tState
                                  renderEncoder:frameData.renderEncoder
                               numberOfVertices:6 * numQuads
                                   numberOfPIUs:0
                                  vertexBuffers:@{ @(iTermVertexInputIndexVertices): tState.vertexBuffer,
                                                   @(iTermVertexColorArray): colorsBuffer
                                                }
                                fragmentBuffers:@{}
                                       textures:@{}];
}

- (nullable __kindof iTermMetalRendererTransientState *)createTransientStateForConfiguration:(nonnull iTermRenderConfiguration *)configuration
                                                                               commandBuffer:(nonnull id<MTLCommandBuffer>)commandBuffer {
    iTermCommandLineBackgroundRendererTransientState *tState =
        [_solidColorRenderer createTransientStateForConfiguration:configuration
                                                    commandBuffer:commandBuffer];
    return tState;
}

@end
