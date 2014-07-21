#import "ViewController.h"
#import <Metal/Metal.h>

#include <iostream>

#import "MetalView.h"

#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>
#include <glm/ext.hpp>

#include "Geometry.hpp"
#include "MyShaderTypes.hpp"

namespace {
    simd::float3 bridge(const glm::vec3& v) {
        return simd::float3{v.x, v.y, v.z};
    }
    simd::float4 bridge(const glm::vec4& v) {
        return simd::float4{v.x, v.y, v.z, v.w};
    }
    simd::float3x3 bridge(const glm::mat3& m) {
        return simd::float3x3(bridge(m[0]), bridge(m[1]), bridge(m[2]));
    }
    simd::float4x4 bridge(const glm::mat4& m) {
        return simd::float4x4(bridge(m[0]), bridge(m[1]), bridge(m[2]), bridge(m[3]));
    }
    
    float remap(float value, float inputMin, float inputMax, float outputMin, float outputMax)
    {
        return (value - inputMin) * ((outputMax - outputMin) / (inputMax - inputMin)) + outputMin;
    }
    
    // Object Count
    // kObjectCount x kObjectCount => All Object Count
    const int kObjectCount = 8;
    
    // MSAA, must be 1 or 2 or 4.
    const int kSampleCount = 4;
}

@implementation ViewController
{
    MetalView *_metalView;
    
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLLibrary> _library;
    id<MTLRenderPipelineState> _renderPipelineState;
    
    // MSAA
    id<MTLTexture> _msaaTexture;
    
    // depth
    id<MTLTexture> _depthTexture;
    id<MTLDepthStencilState> _depthStencilState;
    
    // geometry buffers
    id<MTLBuffer> _vertexBuffer;
    int _indexCount;
    id<MTLBuffer> _indexBuffer;
    
    // instance buffers
    id<MTLBuffer> _instanceBuffer;
    int _instanceCount;
    
    // constant buffer
    id<MTLBuffer> _constantBuffer;
    
    // create rendering loop
    CADisplayLink *_displayLink;
    
    // camera control
    CGPoint _previousTranslation;
    glm::vec3 _pinchBaseCameraPosition;
    
    glm::vec3 _cameraPosition;
    glm::vec3 _cameraUp;
    
    // object control
    double _elapsed;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // create metal view dynamic
    _metalView = [[MetalView alloc] init];
    _metalView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_metalView];
    
    MetalView *metalView = _metalView;
    NSDictionary *views = NSDictionaryOfVariableBindings(metalView);
    NSArray *vConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-0-[metalView]-0-|"
                                                                    options:0
                                                                    metrics:nil
                                                                      views:views];
    [self.view addConstraints:vConstraints];
    NSArray *hConstraints = [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[metalView]-0-|"
                                                                    options:0
                                                                    metrics:nil
                                                                      views:views];
    [self.view addConstraints:hConstraints];
    
    [self.view layoutIfNeeded];
    
    // Intaraction
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(didPan:)];
    pan.minimumNumberOfTouches = 1;
    pan.maximumNumberOfTouches = 1;
    [_metalView addGestureRecognizer:pan];
    
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(didPinch:)];
    [_metalView addGestureRecognizer:pinch];
    
    // Metal Initialize
    _device = MTLCreateSystemDefaultDevice();
    
    metalView.metalLayer.device = _device;
    metalView.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    _metalView.metalLayer.framebufferOnly = YES;
    
    _commandQueue = [_device newCommandQueue];
    _library = [_device newDefaultLibrary];

    auto icoshpere = Geometry::createIcosphere(4);
    _vertexBuffer = [_device newBufferWithBytes:icoshpere.vertices.data()
                                         length:icoshpere.vertices.size() * sizeof(decltype(icoshpere.vertices)::value_type)
                                        options:0];
    _indexBuffer = [_device newBufferWithBytes:icoshpere.indices.data()
                                        length:icoshpere.indices.size() * sizeof(decltype(icoshpere.indices)::value_type)
                                       options:0];
    _indexCount = static_cast<int>(icoshpere.indices.size());
    
    _instanceCount = kObjectCount * kObjectCount;
    
    // this is dummy data
    std::vector<MyShaderTypes::InstanceInput> instanceBuffer(_instanceCount);
    _instanceBuffer = [_device newBufferWithBytes:instanceBuffer.data() length:sizeof(MyShaderTypes::InstanceInput) * _instanceCount options:0];
    
    // this is dummy data
    MyShaderTypes::ConstantInput constantInput;
    _constantBuffer = [_device newBufferWithBytes:&constantInput length:sizeof(constantInput) options:0];
    
    _renderPipelineState = ^{
        NSError *error;
        MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor alloc] init];
        desc.vertexFunction = [_library newFunctionWithName:@"myVertexShader"];
        desc.fragmentFunction = [_library newFunctionWithName:@"myFragmentShader"];
        desc.colorAttachments[0].pixelFormat = metalView.metalLayer.pixelFormat;
        desc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        desc.depthWriteEnabled = YES;
        desc.sampleCount = kSampleCount;
        return [_device newRenderPipelineStateWithDescriptor:desc error:&error];
    }();

    _depthStencilState = ^{
        MTLDepthStencilDescriptor *desc = [[MTLDepthStencilDescriptor alloc] init];
        desc.depthCompareFunction = MTLCompareFunctionLess;
        desc.depthWriteEnabled = YES;
        return [_device newDepthStencilStateWithDescriptor:desc];
    }();

    _displayLink = [CADisplayLink displayLinkWithTarget:self
                                               selector:@selector(update:)];
    _displayLink.frameInterval = 1;
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    
    // camera control
    _cameraPosition = glm::vec3(0.0f, 5.0f, 8.0f);
    _cameraUp = glm::vec3(0.0f, 1.0f, 0.0f);
}
- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    int width = _metalView.bounds.size.width * _metalView.contentScaleFactor;
    int height = _metalView.bounds.size.height * _metalView.contentScaleFactor;
    _metalView.metalLayer.drawableSize = CGSizeMake(width, height);
    
    if(kSampleCount != 1)
    {
        _msaaTexture = ^{
            MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:_metalView.metalLayer.pixelFormat
                                                                                            width:width
                                                                                           height:height
                                                                                        mipmapped:NO];
            
            desc.textureType = MTLTextureType2DMultisample;
            desc.sampleCount = kSampleCount;
            return [_device newTextureWithDescriptor:desc];
        }();
    }
    
    _depthTexture = ^{
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                                        width:width
                                                                                       height:height
                                                                                    mipmapped:NO];
        desc.textureType = kSampleCount == 1? MTLTextureType2D : MTLTextureType2DMultisample;
        desc.sampleCount = kSampleCount;
        return [_device newTextureWithDescriptor:desc];
    }();
}
- (void)didPan:(UIPanGestureRecognizer *)sender
{
    CGPoint translation = [sender translationInView:_metalView];
    
    float deltax = translation.x - _previousTranslation.x;
    float deltay = translation.y - _previousTranslation.y;
    _previousTranslation = translation;
    
    glm::vec3 forward = glm::normalize(-_cameraPosition);
    glm::vec3 right = glm::cross(forward, _cameraUp);
    _cameraUp = glm::normalize(glm::cross(right, forward));
    
    glm::quat yRot = glm::angleAxis(-deltax * 0.005f, _cameraUp);
    glm::quat xRot = glm::angleAxis(-deltay * 0.005f, right);
    glm::quat rot = xRot * yRot;
    _cameraPosition = rot * _cameraPosition;
    _cameraUp = rot * _cameraUp;

    if(sender.state == UIGestureRecognizerStateEnded)
    {
        _previousTranslation = CGPointZero;
    }
}
- (void)didPinch:(UIPinchGestureRecognizer *)sender
{
    if(sender.state == UIGestureRecognizerStateBegan)
    {
        _pinchBaseCameraPosition = _cameraPosition;
    }
    else
    {
        _cameraPosition = _pinchBaseCameraPosition * ((static_cast<float>(sender.scale) - 1.0f) * -1.0f + 1.0f);
    }
}
- (void)update:(id)sender
{
    _elapsed += 1.0 / 60.0;
    
    id<CAMetalDrawable> drawable = [_metalView.metalLayer nextDrawable];
    if(drawable == nil)
    {
        return;
    }
    
    float width = _metalView.metalLayer.drawableSize.width;
    float height = _metalView.metalLayer.drawableSize.height;
    
    // update constant buffer
    MyShaderTypes::ConstantInput *constantInput = (MyShaderTypes::ConstantInput *)[_constantBuffer contents];
    constantInput->eye = bridge(_cameraPosition);
    
    // update instance buffer
    glm::vec3 look(0.0f, 0.0f, 0.0f);
    glm::mat4 viewMatrix = glm::lookAt(_cameraPosition, look, _cameraUp);
    glm::mat4 projMatrix = glm::perspectiveFov(glm::radians(45.0f), width, height, 0.1f, 100.0f);
    
    MyShaderTypes::InstanceInput *instanceInputs = (MyShaderTypes::InstanceInput *)[_instanceBuffer contents];
    float size = 4.5f;
    for(int x = 0 ; x < kObjectCount ; ++x)
    {
        float xval = remap(x, 0, kObjectCount - 1, -size, size);
        for(int z = 0 ; z < kObjectCount ; ++z)
        {
            float zval = remap(z, 0, kObjectCount - 1, -size, size);
            
            glm::vec3 position = glm::vec3(xval, 0.0f, zval);
            
            float s = remap(x, 0, kObjectCount - 1, 0.0f, 2.0f);
            float twist = sinf(_elapsed * glm::pi<float>() * 0.1f + s * glm::pi<float>() * 2.0f) * glm::pi<float>() * 0.08f;
            glm::vec3 twisted = glm::rotate(position, twist, glm::vec3(1.0f, 0.0f, 0.0f));
            
            glm::mat4 modelMatrix;
            modelMatrix = glm::translate(modelMatrix, twisted);
            modelMatrix = glm::scale(modelMatrix, glm::vec3(0.5f, 0.5f, 0.5f));
            
            glm::mat3 nMatrix = glm::transpose(glm::inverse(glm::mat3(modelMatrix)));
            glm::mat4 mvpMatrix = projMatrix * viewMatrix * modelMatrix;
            
            int index = x * kObjectCount + z;
            instanceInputs[index].mMatrix = bridge(modelMatrix);
            instanceInputs[index].nMatrix = bridge(nMatrix);
            instanceInputs[index].mvpMatrix = bridge(mvpMatrix);
            
            float h = remap(index, 0, _instanceCount, 0.0f, 360.0f);
            glm::vec3 color = glm::rgbColor(glm::vec3(h, 1.0f, 1.0f));
            instanceInputs[index].color = bridge(color);
            instanceInputs[index].power = remap(index, 0, _instanceCount - 1, 1.0f, 12.0f);
        }
    }
    
    // render
    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    id <MTLRenderCommandEncoder> commandEncoder = ^{
        MTLRenderPassDescriptor *desc = [MTLRenderPassDescriptor renderPassDescriptor];
        
        if(kSampleCount == 1)
        {
            desc.colorAttachments[0].texture = [drawable texture];
            desc.colorAttachments[0].storeAction = MTLStoreActionStore;
        }
        else
        {
            // Multi Sampled Anti-Aliasing
            desc.colorAttachments[0].texture = _msaaTexture;
            desc.colorAttachments[0].resolveTexture = [drawable texture];
            desc.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
        }
        desc.colorAttachments[0].loadAction = MTLLoadActionClear;
        desc.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
        
        desc.depthAttachment.texture = _depthTexture;
        desc.depthAttachment.loadAction = MTLLoadActionClear;
        desc.depthAttachment.clearDepth = 1.0;
        
        return [commandBuffer renderCommandEncoderWithDescriptor:desc];
    }();
    

    [commandEncoder setRenderPipelineState:_renderPipelineState];
    [commandEncoder setDepthStencilState:_depthStencilState];
    
    [commandEncoder setTriangleFillMode:MTLTriangleFillModeFill];
    [commandEncoder setCullMode:MTLCullModeBack];
    [commandEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    [commandEncoder setVertexBuffer:_instanceBuffer offset:0 atIndex:1];
    [commandEncoder setVertexBuffer:_constantBuffer offset:0 atIndex:2];
    
    [commandEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                               indexCount:_indexCount
                                indexType:MTLIndexTypeUInt16
                              indexBuffer:_indexBuffer
                        indexBufferOffset:0
                            instanceCount:_instanceCount];

    [commandEncoder endEncoding];
    
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end
