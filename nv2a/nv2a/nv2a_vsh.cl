/**
 * OpenCL kernel that emulates the vertex pipeline
 * of the NV2A.
 *
 * Joshua Horacsek, 2015
 */

#define VSH_TOKEN_SIZE 4

typedef enum {
    FLD_ILU = 0,
    FLD_MAC,
    FLD_CONST,
    FLD_V,
    
    // Input A
    FLD_A_NEG,
    FLD_A_SWZ_X,
    FLD_A_SWZ_Y,
    FLD_A_SWZ_Z,
    FLD_A_SWZ_W,
    FLD_A_R,
    FLD_A_MUX,
    
    // Input B
    FLD_B_NEG,
    FLD_B_SWZ_X,
    FLD_B_SWZ_Y,
    FLD_B_SWZ_Z,
    FLD_B_SWZ_W,
    FLD_B_R,
    FLD_B_MUX,
    
    // Input C
    FLD_C_NEG,
    FLD_C_SWZ_X,
    FLD_C_SWZ_Y,
    FLD_C_SWZ_Z,
    FLD_C_SWZ_W,
    FLD_C_R,
    FLD_C_MUX,
    
    // Output
    FLD_OUT_MAC_MASK,
    FLD_OUT_R,
    FLD_OUT_ILU_MASK,
    FLD_OUT_O_MASK,
    FLD_OUT_ORB,
    FLD_OUT_ADDRESS,
    FLD_OUT_MUX,
    
    // Relative addressing
    FLD_A0X,
    
    // Final instruction
    FLD_FINAL
} VshFieldName;

typedef enum {
    MAC_NOP,
    MAC_MOV,
    MAC_MUL,
    MAC_ADD,
    MAC_MAD,
    MAC_DP3,
    MAC_DPH,
    MAC_DP4,
    MAC_DST,
    MAC_MIN,
    MAC_MAX,
    MAC_SLT,
    MAC_SGE,
    MAC_ARL
} VshMAC;

typedef enum {
    ILU_NOP = 0,
    ILU_MOV,
    ILU_RCP,
    ILU_RCC,
    ILU_RSQ,
    ILU_EXP,
    ILU_LOG,
    ILU_LIT
} VshILU;

typedef enum {
    PARAM_UNKNOWN = 0,
    PARAM_R,
    PARAM_V,
    PARAM_C,
    PARAM_OUT
} VshParameterType;


typedef struct _VshFieldMap {
    uchar offset;
    uchar shift;
    ulong mask;
    bool sign_extend;
}VshFieldMap;

/* Note: OpenGL seems to be case-sensitive, and requires upper-case opcodes! */
__constant char mac_opcode[] = "NOP\0MOV\0MUL\0ADD\0MAD\0DP3\0DPH\0DP4\0DST\0MIN\0MAX\0SLT\0SGE\0ARL";
__constant char ilu_opcode[] = "NOP\0MOV\0RCP\0RCC\0RSQ\0EXP\0LOG\0LIT";

__constant VshFieldMap field_map[] = {
    // Control
    { 0, 25, 0x07, 0 }, // FLD_ILU
    { 0, 21, 0x0F, 0 }, // FLD_MAC,
    { 0, 13, 0xFF, 1 }, // FLD_CONST
    { 0,  9, 0x0F, 0 }, // FLD_V
    
    // Input A
    { 0,  8, 0x01, 0 }, // FLD_A_NEG
    { 0,  6, 0x03, 0 }, // FLD_A_SWZ_X
    { 0,  4, 0x03, 0 }, // FLD_A_SWZ_Y
    { 0,  2, 0x03, 0 }, // FLD_A_SWZ_Z
    { 0,  0, 0x03, 0 }, // FLD_A_SWZ_W
    { 1, 60, 0x0F, 0 }, // FLD_A_R
    { 1, 58, 0x03, 0 }, // FLD_A_MUX
    
    // Input B
    { 1, 57, 0x01, 0 }, // FLD_B_NEG
    { 1, 55, 0x03, 0 }, // FLD_B_SWZ_X
    { 1, 53, 0x03, 0 }, // FLD_B_SWZ_Y
    { 1, 51, 0x03, 0 }, // FLD_B_SWZ_Z
    { 1, 49, 0x03, 0 }, // FLD_B_SWZ_W
    { 1, 45, 0x0F, 0 }, // FLD_B_R
    { 1, 43, 0x03, 0 }, // FLD_B_MUX
    
    // Input C
    { 1, 42, 0x01, 0 }, // FLD_C_NEG
    { 1, 40, 0x03, 0 }, // FLD_C_SWZ_X
    { 1, 38, 0x03, 0 }, // FLD_C_SWZ_Y
    { 1, 36, 0x03, 0 }, // FLD_C_SWZ_Z
    { 1, 34, 0x03, 0 }, // FLD_C_SWZ_W
    { 1, 30, 0x0F, 0 }, // FLD_C_R
    { 1, 28, 0x03, 0 }, // FLD_C_MUX
    
    // Output
    { 1, 24, 0x0F, 0 }, // FLD_OUT_MAC_MASK
    { 1, 20, 0x0F, 0 }, // FLD_OUT_R
    { 1, 16, 0x0F, 0 }, // FLD_OUT_ILU_MASK
    { 1, 12, 0x0F, 0 }, // FLD_OUT_O_MASK
    { 1, 11, 0x01, 0 }, // FLD_OUT_ORB
    { 1,  3, 0xFF, 0 }, // FLD_OUT_ADDRESS
    { 1,  2, 0x01, 0 }, // FLD_OUT_MUX
    
    // Other
    { 1,  1, 0x01, 0 }, // FLD_A0X
    { 1,  0, 0x01, 0 }, // FLD_FINAL
};

// (old, new)
// xyzw, xyzw
// 0123, 4567
__constant uint4 shuffle_mask[] = {
    (uint4)(0,1,2,3), // 0000 ____
    (uint4)(0,1,2,7), // 0001 ___w
    (uint4)(0,1,6,3), // 0010 __z_
    (uint4)(0,1,6,7), // 0011 __zw
    (uint4)(0,5,2,3), // 0100 _y__
    (uint4)(0,5,2,7), // 0101 _y_w
    (uint4)(0,5,6,3), // 0110 _yz_
    (uint4)(0,5,6,7), // 0111 _yzw
    (uint4)(4,1,2,3), // 1000 x___
    (uint4)(4,1,2,7), // 1001 x__w
    (uint4)(4,1,6,3), // 1010 x_z_
    (uint4)(4,1,6,7), // 1011 x_zw
    (uint4)(4,5,2,3), // 1100 xy__
    (uint4)(4,5,2,7), // 1101 xy_w
    (uint4)(4,5,6,3), // 1110 xyz_
    (uint4)(4,5,6,7)  // 1111 xyzw
};

inline float4 vsh_execute_mac_opcode(const VshMAC opcode,
                                     const float4 a,
                                     const float4 b,
                                     const float4 c);
inline float4 vsh_execute_ilu_opcode(const VshILU opcode,
                                     const float4 c);
/**
 * Rips out a feild from an instruction token
 */
uchar vsh_decode_feild(VshFieldName fld, ulong2 token) {
    ulong half_token = token[field_map[fld].offset];
    return (uchar)((half_token >> field_map[fld].shift) & field_map[fld].mask);
}

inline float4 vsh_fetch_reg(const VshFieldName neg,
                            const VshFieldName sx,
                            const VshFieldName sy,
                            const VshFieldName sz,
                            const VshFieldName sw,
                            const VshFieldName mx,
                            const VshFieldName rreg,
                            const uint v_idx,
                            const uint c_idx,
                            const float4 *R,
                            global const float4 *C,
                            const float4 *V,
                            const ulong2 token) {
    
    uchar   negate = vsh_decode_feild(neg, token),
    swiz_x = vsh_decode_feild(sx, token),
    swiz_y = vsh_decode_feild(sy, token),
    swiz_z = vsh_decode_feild(sz, token),
    swiz_w = vsh_decode_feild(sw, token),
    mux = vsh_decode_feild(mx, token),
    r = vsh_decode_feild(rreg, token);
    float4 reg;
    
    printf("FETCH (%d): ", mux);
    switch(mux){
        case PARAM_R:
            reg = R[r];
            
            printf("R%d \n", r);
            break;
        case PARAM_C:
            reg = C[c_idx];
            printf("C%d \n", c_idx);
            break;
        case PARAM_V:
            reg = V[v_idx];
            printf("V%d \n", v_idx);
            break;
        default:
            printf("UNKNOWN\n");
    }
    
    reg = (float4)(reg[swiz_x], reg[swiz_y],reg[swiz_z], reg[swiz_w]) * (negate ? -1 : 1);
    printf("(%f, %f, %f, %f)\n", reg.x, reg.y, reg.z, reg.w);
    return reg;
}


kernel void vsh_exec_shader(global ulong2 *shader,
                            global ulong *output,
                            global float4 *c_regs) {
    // Working registers
    float4 R[12], REG_A, REG_B, REG_C, V[16], ilu_out, mac_out, O[13];
    int A0 = 0;
    
    /* Initialize the local registers */
    for(uint i = 0; i < 12; i++) R[i] = (float4)(i,0,i,1);
    for(uint i = 0; i < 16; i++) V[i] = (float4)(0,0,i,1);
    
    
    V[0] = float4(1,2,3,1);
    
    /* Process each instruction in the stream */
    for(uint i = 0; i < 128; i++) {
        
        // I'd rather do the endian swap here every time, as opposed to some
        // conditional logic to deal with the split C_R field
        ulong2 token = (ulong2)((shader[i][0] >> 32) | ((shader[i][0] & 0xFFFFFFFF) << 32),
                                (shader[i][1] >> 32) | ((shader[i][1] & 0xFFFFFFFF) << 32));
        
        /* Decode the control fields */
        uchar mac = vsh_decode_feild(FLD_MAC, token);
        uchar ilu = vsh_decode_feild(FLD_ILU, token);
        char c_reg = vsh_decode_feild(FLD_CONST, token);
        uchar v_reg = vsh_decode_feild(FLD_V, token);
        
        c_reg += vsh_decode_feild(FLD_A0X, token) ? (char)A0 : 0;
        
        /* Fetch registers */
        REG_A = vsh_fetch_reg(FLD_A_NEG,   FLD_A_SWZ_X, FLD_A_SWZ_Y,
                              FLD_A_SWZ_Z, FLD_A_SWZ_W, FLD_A_MUX, FLD_A_R,
                              v_reg, c_reg, R, c_regs, V, token);
        
        REG_B = vsh_fetch_reg(FLD_B_NEG,   FLD_B_SWZ_X, FLD_B_SWZ_Y,
                              FLD_B_SWZ_Z, FLD_B_SWZ_W, FLD_B_MUX, FLD_B_R,
                              v_reg, c_reg, R, c_regs, V, token);
        
        REG_C = vsh_fetch_reg(FLD_C_NEG,   FLD_C_SWZ_X, FLD_C_SWZ_Y,
                              FLD_C_SWZ_Z, FLD_C_SWZ_W, FLD_C_MUX, FLD_C_R,
                              v_reg, c_reg, R, c_regs, V, token);
        
        /* Debugging */
        printf("\\* Slot: %d (0x%016lX) (0x%016lX) C=%d, V=%d *\\\n%s\n%s\n\n",
               i, token[0], token[1], c_reg, v_reg, &mac_opcode[mac*4], &ilu_opcode[ilu*4]);
        
        /* Execute the instruction */
        mac_out = vsh_execute_mac_opcode(mac, REG_A, REG_B, REG_C);
        ilu_out = vsh_execute_ilu_opcode(ilu, REG_C);
        
        /* Get output control */
        uchar out_reg  = vsh_decode_feild(FLD_OUT_R, token);
        uchar out_addr = vsh_decode_feild(FLD_OUT_ADDRESS, token);
        
        uchar mac_reg = out_reg;
        uchar ilu_reg = (mac != MAC_NOP) ? 1 : out_reg;
        
        /* Get output masks */
        uchar mac_mask = vsh_decode_feild(FLD_OUT_MAC_MASK, token);
        uchar ilu_mask = vsh_decode_feild(FLD_OUT_ILU_MASK, token);
        uchar o_mask = vsh_decode_feild(FLD_OUT_O_MASK, token);
        
        mac_mask = (mac == MAC_NOP) ? 0 : mac_mask;
        ilu_mask = (ilu == ILU_NOP) ? 0 : mac_mask;
        
        /* Write to register */
        R[mac_reg] = shuffle2(R[mac_reg], mac_out, shuffle_mask[mac_mask]);
        R[ilu_reg] = shuffle2(R[ilu_reg], ilu_out, shuffle_mask[ilu_mask]);
        
        /* */
        printf("MAC: R[%d] 0x%02X - (%f, %f, %f, %f)\n", mac_reg, mac_mask,
               mac_out[0], mac_out[1], mac_out[2], mac_out[3]);
        
        printf("ILU: R[%d] 0x%02X - (%f, %f, %f, %f)\n\n", ilu_reg, ilu_mask,
               ilu_out[0], ilu_out[1], ilu_out[2], ilu_out[3]);
        
        
        /* Multiplex that output to an output register (or writeable constant) */
        float4 mux_out = vsh_decode_feild(FLD_OUT_MUX, token) == 0 ? mac_out : ilu_out;
        
        if (vsh_decode_feild(FLD_OUT_MUX, token) == 0){
            uchar co_reg = vsh_decode_feild(FLD_OUT_ADDRESS, token);
            c_regs[co_reg] = shuffle2(c_regs[co_reg], mux_out, shuffle_mask[o_mask]);
        }else {
            uchar o_reg = vsh_decode_feild(FLD_OUT_ADDRESS, token) & 0xF;
            O[o_reg] = shuffle2(O[o_reg], mux_out, shuffle_mask[o_mask]);
        }
        
        /* Load A0 */
        A0 = ((int2)(A0, (int)mac_out.x))[mac == MAC_ARL];
        
        /* Shader program ends on the final token */
        if(vsh_decode_feild(FLD_FINAL, token)) {
            break;
        }
    }
}

inline float4 vsh_execute_mac_opcode(const VshMAC opcode,
                                     const float4 a,
                                     const float4 b,
                                     const float4 c) {
    float4 ret = 0;
    switch(opcode) {
        case MAC_NOP: break;
            
        case MAC_ARL:
            ret = floor(a);
            break;
            
        case MAC_MOV:
            ret = a;
            break;
            
        case MAC_MUL:
            ret = a * b;
            break;
            
        case MAC_ADD:
            ret = a + c;
            break;
            
        case MAC_MAD:
            ret = a*b + c;
            break;
            
        case MAC_DP3:
            ret = dot(a.xyz, b.xyz);
            break;
            
        case MAC_DPH:
            ret = dot(a.xyz, b.xyz) + a.w;
            break;
            
        case MAC_DP4:
            ret = dot(a.xyzw, b.xyzw);
            break;
            
        case MAC_DST:
            ret = (float4) (1, a.y*b.y, a.z, b.w);
            break;
            
        case MAC_MIN:
            ret = min(a,b);
            break;
            
        case MAC_MAX:
            ret = max(a,b);
            break;
            
        case MAC_SLT:
            ret = (float4)(a.x < b.x ? 1 : 0,
                           a.y < b.y ? 1 : 0,
                           a.z < b.z ? 1 : 0,
                           a.w < b.w ? 1 : 0);
            break;
            
        case MAC_SGE:
            ret = (float4)(a.x >= b.x ? 1 : 0,
                           a.y >= b.y ? 1 : 0,
                           a.z >= b.z ? 1 : 0,
                           a.w >= b.w ? 1 : 0);
            break;
    }
    
    return ret;
}


inline float4 vsh_execute_ilu_opcode(const VshILU opcode,
                                     const float4 c) {
    float4 ret = 0;
    float t = 0;
    switch(opcode) {
        case ILU_NOP: break;
        case ILU_MOV:
            ret = c;
            break;
            
        case ILU_RCP:
            ret = (1./c.x);
            break;
            
        case ILU_RCC:
            t = 1./c.x;
            ret = t > 0 ?
            clamp(t, (float)5.42101e-020, (float)1.884467e+019) :
            clamp(t, (float)-1.884467e+019, (float)-5.42101e-020);
            break;
            
        case ILU_RSQ:
            ret = rsqrt(c.x);
            break;
            
        case ILU_EXP:
            ret = exp2(c.x);
            break;
            
        case ILU_LOG:
            ret = log2(c.x);
            break;
            
        case ILU_LIT:
        {
            ret = (float4)(1,0,0,1);
            ret.yz = c.x > 0 ? (float2)(c.x,  c.y > 0 ? pow(c.y, c.w) : 0) : 0;
        }
            break;
    }
    return ret;
}
