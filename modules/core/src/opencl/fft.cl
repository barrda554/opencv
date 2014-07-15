#define SQRT_2 0.707106781188f
#define sin_120 0.866025403784f
#define fft5_2  0.559016994374f
#define fft5_3 -0.951056516295f
#define fft5_4 -1.538841768587f
#define fft5_5  0.363271264002f

__attribute__((always_inline))
float2 mul_float2(float2 a, float2 b) { 
    return (float2)(fma(a.x, b.x, -a.y * b.y), fma(a.x, b.y, a.y * b.x)); 
}

__attribute__((always_inline))
float2 twiddle(float2 a) { 
    return (float2)(a.y, -a.x); 
}

__attribute__((always_inline))
void fft_radix2(__local float2* smem, __constant const float2* twiddles, const int x, const int block_size, const int t)     
{
    const int k = x & (block_size - 1);
    float2 a0, a1;

    if (x < t)
    {
        a0 = smem[x];
        a1 = mul_float2(twiddles[k],smem[x+t]);
    }

    barrier(CLK_LOCAL_MEM_FENCE);

    if (x < t)
    {
        const int dst_ind = (x << 1) - k;
    
        smem[dst_ind] = a0 + a1;
        smem[dst_ind+block_size] = a0 - a1;
    }

    barrier(CLK_LOCAL_MEM_FENCE);
}

__attribute__((always_inline))
void fft_radix2_B2(__local float2* smem, __constant const float2* twiddles, const int x, const int block_size, const int t)     
{
    const int k1 = x & (block_size - 1);
    const int x2 = x + (t+1)/2;
    const int k2 = x2 & (block_size - 1);
    float2 a0, a1, a2, a3;

    if (x < (t+1)/2)
    {
        a0 = smem[x];
        a1 = mul_float2(twiddles[k1],smem[x+t]);
        a2 = smem[x2];
        a3 = mul_float2(twiddles[k2],smem[x2+t]);
    }

    barrier(CLK_LOCAL_MEM_FENCE);

    if (x < (t+1)/2)
    {
        int dst_ind = (x << 1) - k1;
        smem[dst_ind] = a0 + a1;
        smem[dst_ind+block_size] = a0 - a1;

        dst_ind = (x2 << 1) - k2;
        smem[dst_ind] = a2 + a3;
        smem[dst_ind+block_size] = a2 - a3;
    }

    barrier(CLK_LOCAL_MEM_FENCE);
}

__attribute__((always_inline))
void fft_radix4(__local float2* smem, __constant const float2* twiddles, const int x, const int block_size, const int t)
{
    const int k = x & (block_size - 1);
    float2 a0, a1, a2, a3;

    if (x < t)
    {
        const int twiddle_block = block_size / 4;
        a0 = smem[x];
        a1 = mul_float2(twiddles[k],smem[x+t]);
        a2 = mul_float2(twiddles[k + block_size],smem[x+2*t]);
        a3 = mul_float2(twiddles[k + 2*block_size],smem[x+3*t]);
    }

    barrier(CLK_LOCAL_MEM_FENCE);

    if (x < t)
    {
        const int dst_ind = ((x - k) << 2) + k;

        float2 b0 = a0 + a2;
        a2 = a0 - a2;
        float2 b1 = a1 + a3;
        a3 = twiddle(a1 - a3);

        smem[dst_ind]                = b0 + b1;
        smem[dst_ind + block_size]   = a2 + a3;
        smem[dst_ind + 2*block_size] = b0 - b1;
        smem[dst_ind + 3*block_size] = a2 - a3;
    }

    barrier(CLK_LOCAL_MEM_FENCE);
}

__attribute__((always_inline))
void fft_radix8(__local float2* smem, __constant const float2* twiddles, const int x, const int block_size, const int t)
{
    const int k = x % block_size;
    float2 a0, a1, a2, a3, a4, a5, a6, a7;

    if (x < t)
    {
        int tw_ind = block_size / 8;

        a0 = smem[x];
        a1 = mul_float2(twiddles[k], smem[x + t]);
        a2 = mul_float2(twiddles[k + block_size],smem[x+2*t]);
        a3 = mul_float2(twiddles[k+2*block_size],smem[x+3*t]);
        a4 = mul_float2(twiddles[k+3*block_size],smem[x+4*t]);
        a5 = mul_float2(twiddles[k+4*block_size],smem[x+5*t]);
        a6 = mul_float2(twiddles[k+5*block_size],smem[x+6*t]);
        a7 = mul_float2(twiddles[k+6*block_size],smem[x+7*t]);

        float2 b0, b1, b6, b7;
        
        b0 = a0 + a4;
        a4 = a0 - a4;
        b1 = a1 + a5;
        a5 = a1 - a5;
        a5 = (float2)(SQRT_2) * (float2)(a5.x + a5.y, -a5.x + a5.y);
        b6 = twiddle(a2 - a6);
        a2 = a2 + a6;
        b7 = a3 - a7;
        b7 = (float2)(SQRT_2) * (float2)(-b7.x + b7.y, -b7.x - b7.y); 
        a3 = a3 + a7;

        a0 = b0 + a2;
        a2 = b0 - a2;
        a1 = b1 + a3;
        a3 = twiddle(b1 - a3);
        a6 = a4 - b6;
        a4 = a4 + b6;
        a7 = twiddle(a5 - b7);
        a5 = a5 + b7;

    }

    barrier(CLK_LOCAL_MEM_FENCE);

    if (x < t)
    {
        const int dst_ind = ((x - k) << 3) + k;
        __local float2* dst = smem + dst_ind;

        dst[0] = a0 + a1;
        dst[block_size] = a4 + a5;
        dst[2 * block_size] = a2 + a3;
        dst[3 * block_size] = a6 + a7;
        dst[4 * block_size] = a0 - a1;
        dst[5 * block_size] = a4 - a5;
        dst[6 * block_size] = a2 - a3;
        dst[7 * block_size] = a6 - a7;
    }

    barrier(CLK_LOCAL_MEM_FENCE);
}

__attribute__((always_inline))
void fft_radix3(__local float2* smem, __constant const float2* twiddles, const int x, const int block_size, const int t)
{
    const int k = x % block_size;
    float2 a0, a1, a2;

    if (x < t)
    {
        a0 = smem[x];
        a1 = mul_float2(twiddles[k], smem[x+t]);
        a2 = mul_float2(twiddles[k+block_size], smem[x+2*t]);
    }

    barrier(CLK_LOCAL_MEM_FENCE);

    if (x < t)
    {
        const int dst_ind = ((x - k) * 3) + k;

        float2 b1 = a1 + a2;
        a2 = twiddle(sin_120*(a1 - a2));
        float2 b0 = a0 - (float2)(0.5f)*b1;

        smem[dst_ind] = a0 + b1;
        smem[dst_ind + block_size] = b0 + a2;
        smem[dst_ind + 2*block_size] = b0 - a2;
    }

    barrier(CLK_LOCAL_MEM_FENCE);
}

__attribute__((always_inline))
void fft_radix3_B2(__local float2* smem, __constant const float2* twiddles, const int x, const int block_size, const int t)
{
    const int k = x % block_size;
    const int x2 = x + (t+1)/2;
    const int k2 = x2 % block_size;
    float2 a0, a1, a2, a3, a4, a5;

    if (x < (t+1)/2)
    {
        a0 = smem[x];
        a1 = mul_float2(twiddles[k], smem[x+t]);
        a2 = mul_float2(twiddles[k+block_size], smem[x+2*t]);

        a3 = smem[x2];
        a4 = mul_float2(twiddles[k2], smem[x2+t]);
        a5 = mul_float2(twiddles[k2+block_size], smem[x2+2*t]);
    }

    barrier(CLK_LOCAL_MEM_FENCE);

    if (x < (t+1)/2)
    {
        int dst_ind = ((x - k) * 3) + k;

        float2 b1 = a1 + a2;
        a2 = twiddle(sin_120*(a1 - a2));
        float2 b0 = a0 - (float2)(0.5f)*b1;

        smem[dst_ind] = a0 + b1;
        smem[dst_ind + block_size] = b0 + a2;
        smem[dst_ind + 2*block_size] = b0 - a2;

        dst_ind = ((x2 - k2) * 3) + k2;

        b1 = a4 + a5;
        a5 = twiddle(sin_120*(a4 - a5));
        b0 = a3 - (float2)(0.5f)*b1;

        smem[dst_ind] = a3 + b1;
        smem[dst_ind + block_size] = b0 + a5;
        smem[dst_ind + 2*block_size] = b0 - a5;
    }

    barrier(CLK_LOCAL_MEM_FENCE);
}

__attribute__((always_inline))
void fft_radix5(__local float2* smem, __constant const float2* twiddles, const int x, const int block_size, const int t)
{
    const int k = x % block_size;
    float2 a0, a1, a2, a3, a4;

    if (x < t)
    {
        a0 = smem[x];
        a1 = mul_float2(twiddles[k], smem[x + t]);
        a2 = mul_float2(twiddles[k + block_size],smem[x+2*t]);
        a3 = mul_float2(twiddles[k+2*block_size],smem[x+3*t]);
        a4 = mul_float2(twiddles[k+3*block_size],smem[x+4*t]);
    }

    barrier(CLK_LOCAL_MEM_FENCE);

    if (x < t)
    {
        const int dst_ind = ((x - k) * 5) + k;
        __local float2* dst = smem + dst_ind;

        float2 b0, b1, b5;

        b1 = a1 + a4;
        a1 -= a4;

        a4 = a3 + a2;
        a3 -= a2;

        a2 = b1 + a4;
        b0 = a0 - (float2)0.25f * a2;

        b1 = fft5_2 * (b1 - a4);
        a4 = fft5_3 * (float2)(-a1.y - a3.y, a1.x + a3.x);
        b5 = (float2)(a4.x - fft5_5 * a1.y, a4.y + fft5_5 * a1.x);

        a4.x += fft5_4 * a3.y; 
        a4.y -= fft5_4 * a3.x;

        a1 = b0 + b1;
        b0 -= b1;

        dst[0] = a0 + a2;
        dst[block_size] = a1 + a4;
        dst[2 * block_size] = b0 + b5;
        dst[3 * block_size] = b0 - b5;
        dst[4 * block_size] = a1 - a4;
    }

    barrier(CLK_LOCAL_MEM_FENCE);
}

__kernel void fft_multi_radix_rows(__global const uchar* src_ptr, int src_step, int src_offset, int src_rows, int src_cols,
                                   __global uchar* dst_ptr, int dst_step, int dst_offset, int dst_rows, int dst_cols,
                                   __constant float2 * twiddles_ptr, const int t, const int nz)
{
    const int x = get_global_id(0);
    const int y = get_group_id(1);

    if (y < nz)
    {
        __local float2 smem[LOCAL_SIZE];
        __constant const float2* twiddles = (__constant float2*) twiddles_ptr;
        const int ind = x;
        const int block_size = LOCAL_SIZE/kercn;

#ifndef REAL_INPUT
        __global const float2* src = (__global const float2*)(src_ptr + mad24(y, src_step, mad24(x, (int)(sizeof(float)*2), src_offset)));
        #pragma unroll
        for (int i=0; i<kercn; i++)
            smem[x+i*block_size] = src[i*block_size];
#else
        __global const float* src = (__global const float*)(src_ptr + mad24(y, src_step, mad24(x, (int)sizeof(float), src_offset)));
        #pragma unroll
        for (int i=0; i<kercn; i++)
            smem[x+i*block_size] = (float2)(src[i*block_size], 0.f);
#endif
        barrier(CLK_LOCAL_MEM_FENCE);

        RADIX_PROCESS;

#ifndef CCS_OUTPUT
        __global float2* dst = (__global float2*)(dst_ptr + mad24(y, dst_step, mad24(x, (int)(sizeof(float)*2), dst_offset)));
        #pragma unroll
        for (int i=0; i<kercn; i++)
            dst[i*block_size] = smem[x + i*block_size];
#else
        // pack row to CCS
        __local float* smem_1cn = (__local float*) smem;
        __global float* dst = (__global float*)(dst_ptr + mad24(y, dst_step, dst_offset));
        for (int i=x; i<dst_cols-1; i+=block_size)
            dst[i+1] = smem_1cn[i+2];
        if (x == 0)
            dst[0] = smem_1cn[0];
#endif
    }
}

__kernel void fft_multi_radix_cols(__global const uchar* src_ptr, int src_step, int src_offset, int src_rows, int src_cols,
                                   __global uchar* dst_ptr, int dst_step, int dst_offset, int dst_rows, int dst_cols,
                                   __constant float2 * twiddles_ptr, const int t, const int nz)
{
    const int x = get_group_id(0);
    const int y = get_global_id(1);

    if (x < nz)
    {
        __local float2 smem[LOCAL_SIZE];
        __global const uchar* src = src_ptr + mad24(y, src_step, mad24(x, (int)(sizeof(float)*2), src_offset));
        __global uchar* dst = dst_ptr + mad24(y, dst_step, mad24(x, (int)(sizeof(float)*2), dst_offset));
        __constant const float2* twiddles = (__constant float2*) twiddles_ptr;
        const int ind = y;
        const int block_size = LOCAL_SIZE/kercn;
        #pragma unroll
        for (int i=0; i<kercn; i++)
            smem[y+i*block_size] = *((__global const float2*)(src + i*block_size*src_step));

        barrier(CLK_LOCAL_MEM_FENCE);

        RADIX_PROCESS;

        // copy data to dst
        #pragma unroll
        for (int i=0; i<kercn; i++)
            *((__global float2*)(dst + i*block_size*src_step)) = smem[y + i*block_size];
    }
}