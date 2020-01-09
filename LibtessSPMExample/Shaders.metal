
#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;
#import "Common.h"

struct Vertex {
    float3 position [[ attribute(0) ]];
    float3 normal   [[ attribute(1) ]];
    float2 texCoord [[ attribute(2) ]];
};

struct VertexOut {
    float4 position [[ position ]];
    float3 eyeNormal;
    float2 texCoord;
};

vertex VertexOut vertex_main(Vertex in [[ stage_in ]],
                             constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]])
{
    VertexOut out;
    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;
    out.eyeNormal = (uniforms.modelViewMatrix * float4(in.normal, 0)).xyz;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> texture [[texture(0)]])
{
    constexpr sampler linearSampler(filter::linear);
    float4 baseColor = texture.sample(linearSampler, in.texCoord);
    
    float3 L = normalize(float3(0, 0, 1)); // light direction in view space
    float3 N = normalize(in.eyeNormal);
    float diffuse = saturate(dot(N, L));
    float3 color = diffuse * baseColor.rgb;
    return float4(color, baseColor.a);
}
