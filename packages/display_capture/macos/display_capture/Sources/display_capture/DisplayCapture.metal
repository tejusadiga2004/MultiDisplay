#include <metal_stdlib>
using namespace metal;

struct VertexOut {
  float4 position [[position]];
  float2 uv;
};

vertex VertexOut dc_vertex(uint id [[vertex_id]]) {
  constexpr float2 positions[3] = {
    float2(-1, -1),
    float2(3, -1),
    float2(-1, 3)
  };
  constexpr float2 coordinates[3] = {
    float2(0, 1),
    float2(2, 1),
    float2(0, -1)
  };
  return { float4(positions[id], 0, 1), coordinates[id] };
}

fragment half4 dc_fragment(
  VertexOut in [[stage_in]],
  texture2d<half> source [[texture(0)]],
  sampler linearSampler [[sampler(0)]]
) {
  return source.sample(linearSampler, in.uv);
}
