/**
 * OpenCL kernel that emulates register combiners
 * for rudimentary pixel shaders.
 *
 * Joshua Horacsek, 2015
 */

#define STAGES 8

typedef struct _CombinerShader{
    
}CombinerShader;

kernel void psh_execute_shader(global ulong *shaders) {
    float4 R[10]; //
    
    for(int stage = 0; stage < STAGES - 1; stage++){
        /* Fetch Register */
        
        /* Do input mask */
        
        /* Perform operation */
        
        /* Bias output */
        
        /* Write registers */
    }
}


float3 identity(float3 x) { return x; }
float3 unsigned_identity(float3 x) { return max(x, 0); }
float3 expand_normal(float3 x) { return 2.*max(x, 0) - 1.; }
float3 half_bias_normal(float3 x) { return max(x, 0) - 0.5; }

float3 negate(float3 x) { return -x; }
float3 unsigned_invert(float3 x) { return 1-min(max(x, 0),1); }
float3 expand_negate(float3 x) { return -2*max(x, 0) + 1; }