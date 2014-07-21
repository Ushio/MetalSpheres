#import <simd/simd.h>

namespace MyShaderTypes {
    struct ConstantInput {
        simd::float3 eye;
    };
    
    struct InstanceInput {
        simd::float4x4 mMatrix;
        simd::float3x3 nMatrix;
        simd::float4x4 mvpMatrix;
        
        simd::float3 color;
        float power;
    };
    
    struct VertexInput {
        simd::float3 position;
        simd::float3 normal;
    };
}
