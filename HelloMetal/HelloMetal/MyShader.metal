#include <metal_stdlib>
using namespace metal;

#include "MyShaderTypes.hpp"

// constants
#define M_PI  3.14159265358979323846264338327950288
constant float kPi = float(M_PI);

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    
    float3 color;
    float3 v;
    float power;
};

vertex VertexOut myVertexShader(const device MyShaderTypes::VertexInput *vertices [[ buffer(0) ]],
                                const constant MyShaderTypes::InstanceInput *instanceInput [[ buffer(1) ]],
                                const constant MyShaderTypes::ConstantInput *constantInput [[ buffer(2) ]],
                                unsigned int vid [[vertex_id]],
                                unsigned int iid [[instance_id]])
{
    float4 positionInWorld = instanceInput[iid].mMatrix * float4(vertices[vid].position, 1.0);
    
    VertexOut out;
    out.position = instanceInput[iid].mvpMatrix * float4(vertices[vid].position, 1.0);
    out.normal = instanceInput[iid].nMatrix * vertices[vid].normal;
    
    out.color = instanceInput[iid].color;
    out.v = normalize(constantInput->eye - positionInWorld.xyz);
    out.power = instanceInput[iid].power;
    
    return out;
}

fragment float4 myFragmentShader(VertexOut interpolated [[stage_in]])
{
    // ambient
    float ambient = 0.03f;
    
    // normalized lambert shading
    float3 L = normalize(float3(1.0f, 1.0f, 1.0f));
    float3 N = normalize(interpolated.normal);
    float lambert = max(dot(N, L), 0.0f) / kPi;
    
    // normalized phong shading
    float3 V = normalize(interpolated.v);
    float3 R = reflect(-L, N);
    float power = interpolated.power;
    float phongNormalize = ( power + 1.0f ) / ( 2.0f * kPi );
    float phong = 0.6f * max(pow(dot(R, V), 5.0f), 0.0f) * phongNormalize;
    
    // result
    float intencity = ambient + mix(lambert, phong, 0.8f);
    
    return float4(interpolated.color * intencity, 1.0f);
}

