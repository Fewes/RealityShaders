
/*
	Depth-based functions
*/

#if !defined(REALITY_DEPTH)
	#define REALITY_DEPTH
	#undef INCLUDED_HEADERS
	#define INCLUDED_HEADERS

	static const float FarPlane = 10000.0;
	static const float FCoef = 1.0 / log2(FarPlane + 1.0);

	/*
		Gets slope-scaled shadow bias from depth
		---
		Source: https://download.nvidia.com/developer/presentations/2004/GPU_Jackpot/Shadow_Mapping.pdf
	*/
	float GetSlopedBasedBias(float Depth, uniform float SlopeScale = -0.001, uniform float Bias = -0.003)
	{
		float M = fwidth(Depth);
		return Depth + (M * SlopeScale) + Bias;
	}

	/*
		Converts linear depth to logarithmic depth in the pixel shader
		---
		Source: https://outerra.blogspot.com/2013/07/logarithmic-depth-buffer-optimizations.html
	*/
	float ApplyLogarithmicDepth(float Depth)
	{
		return saturate(log2(Depth) * FCoef);
	}

	/*
		Transforms the vertex position's depth from World/Object space to light space
		---
		NOTE: Make sure Pos and matrices are in same space!
	*/
	float4 GetMeshShadowProjection(float4 Pos, float4x4 LightTrapezMat, float4x4 LightMat)
	{
		float4 ShadowCoords = mul(Pos, LightTrapezMat);
		float4 LightCoords = mul(Pos, LightMat);
		// (L.z/L.w)*T.w == (L.z/L.w) post homo
		ShadowCoords.z = (LightCoords.z / LightCoords.w) * ShadowCoords.w;
		return ShadowCoords;
	}

	/*
		Compares the depth between the shadowmap's depth (ShadowSampler) and the vertex position's transformed, light-space depth (ShadowCoords.z)
	*/
	float GetShadowFactor(sampler ShadowSampler, float4 ShadowCoords)
	{
		float4 Texel = float4(0.5 / 1024.0, 0.5 / 1024.0, 0.0, 0.0);
		float4 Samples = 0.0;
		Samples.x = tex2Dproj(ShadowSampler, ShadowCoords).r;
		Samples.y = tex2Dproj(ShadowSampler, ShadowCoords + float4(Texel.x, 0.0, 0.0, 0.0)).r;
		Samples.z = tex2Dproj(ShadowSampler, ShadowCoords + float4(0.0, Texel.y, 0.0, 0.0)).r;
		Samples.w = tex2Dproj(ShadowSampler, ShadowCoords + Texel).r;
		float4 CMPBits = step(saturate(GetSlopedBasedBias(ShadowCoords.z)), Samples);
		return dot(CMPBits, 0.25);
	}
#endif
