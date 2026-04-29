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

    const NSUInteger numQuads = tState.rowIndices.count;
    NSMutableData *vertexData = [NSMutableData dataWithLength:sizeof(iTermVertex) * 6 * numQuads];
    iTermVertex *vertices = (iTermVertex *)vertexData.mutableBytes;

    NSMutableData *colorData = [NSMutableData dataWithLength:sizeof(vector_float4) * numQuads];
    vector_float4 *colors = (vector_float4 *)colorData.mutableBytes;

    // tintColor is already premultiplied by the per-frame state.
    const vector_float4 tint = tState.tintColor;

    NSIndexSet *const rowIndices = tState.rowIndices;
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
            // Off-screen; emit a degenerate quad.
            for (int i = 0; i < 6; i++) {
                vertices[quadIndex * 6 + i] = (iTermVertex){ {0, 0}, {0, 0} };
            }
            colors[quadIndex] = (vector_float4){0, 0, 0, 0};
            quadIndex++;
            return;
        }

        const CGRect rect = CGRectMake(0, minY, viewportWidth, maxY - minY);
        vertices[quadIndex * 6 + 0] = (iTermVertex){ { CGRectGetMaxX(rect), CGRectGetMinY(rect) }, { 1, 0 } };
        vertices[quadIndex * 6 + 1] = (iTermVertex){ { CGRectGetMinX(rect), CGRectGetMinY(rect) }, { 0, 0 } };
        vertices[quadIndex * 6 + 2] = (iTermVertex){ { CGRectGetMinX(rect), CGRectGetMaxY(rect) }, { 0, 1 } };

        vertices[quadIndex * 6 + 3] = (iTermVertex){ { CGRectGetMaxX(rect), CGRectGetMinY(rect) }, { 1, 0 } };
        vertices[quadIndex * 6 + 4] = (iTermVertex){ { CGRectGetMinX(rect), CGRectGetMaxY(rect) }, { 0, 1 } };
        vertices[quadIndex * 6 + 5] = (iTermVertex){ { CGRectGetMaxX(rect), CGRectGetMaxY(rect) }, { 1, 1 } };
        colors[quadIndex] = tint;
        quadIndex++;
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
