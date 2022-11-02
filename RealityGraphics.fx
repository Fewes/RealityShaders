
/*
	Third-party shader code
	Author: [R-CON]papadanku
*/

#if !defined(REALITYGRAPHICS_FX)
	#define REALITYGRAPHICS_FX

	/*
		Shared color-based functions

		https://github.com/microsoft/DirectX-Graphics-Samples

		The MIT License (MIT)

		Copyright (c) 2015 Microsoft

		Permission is hereby granted, free of charge, to any person obtaining a copy
		of this software and associated documentation files (the "Software"), to deal
		in the Software without restriction, including without limitation the rights
		to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
		copies of the Software, and to permit persons to whom the Software is
		furnished to do so, subject to the following conditions:

		The above copyright notice and this permission notice shall be included in all
		copies or substantial portions of the Software.

		THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
		IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
		FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
		AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
		LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
		OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
		SOFTWARE.
	*/

	float3 RemoveSRGBCurve(float3 x)
	{
		float3 c = (x < 0.04045) ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4);
		return c;
	}

	float3 ApplySRGBCurve(inout float3 x)
	{
		float3 c = (x < 0.0031308) ? 12.92 * x : 1.055 * pow(x, 1.0 / 2.4) - 0.055;
		return c;
	}

	/*
		Shared depth-based functions
	*/

	// Gets slope-scaled bias from depth
	// Source: https://developer.amd.com/wordpress/media/2012/10/Isidoro-ShadowMapping.pdf
	float GetSlopedBasedBias(float Depth, uniform float SlopeScaleBias = -0.001, uniform float Bias = -0.003)
	{
		float M = max(abs(ddx(Depth)), abs(ddy(Depth)));
		return Depth + ((SlopeScaleBias * M) + Bias);
	}

	// Converts linear depth to logarithmic depth in the vertex shader
	// Source: https://outerra.blogspot.com/2013/07/logarithmic-depth-buffer-optimizations.html
	float4 GetLogarithmicDepth(float4 HPos)
	{
		const float FarPlane = 1000.0;
		float FCoef = 2.0 / log2(FarPlane + 1.0);
		HPos.z = log2(max(1e-6, 1.0 + HPos.w)) * FCoef - 1.0;
		return HPos;
	}

	// Description: Transforms the vertex position's depth from World/Object space to light space
	// tl: Make sure Pos and matrices are in same space!
	float4 GetMeshShadowProjection(float4 Pos, float4x4 LightTrapezMat, float4x4 LightMat)
	{
		float4 ShadowCoords = mul(Pos, LightTrapezMat);
		float4 LightCoords = mul(Pos, LightMat);
		ShadowCoords.z = (LightCoords.z * ShadowCoords.w) / LightCoords.w; // (zL*wT)/wL == zL/wL post homo
		return ShadowCoords;
	}

	// Description: Compares the depth between the shadowmap's depth (ShadowSampler)
	// and the vertex position's transformed, light-space depth (ShadowCoords.z)
	float4 GetShadowFactor(sampler ShadowSampler, float4 ShadowCoords)
	{
		float4 Texel = float4(0.5 / 1024.0, 0.5 / 1024.0, 0.0, 0.0);
		float4 Samples = 0.0;
		Samples.x = tex2Dproj(ShadowSampler, ShadowCoords);
		Samples.y = tex2Dproj(ShadowSampler, ShadowCoords + float4(Texel.x, 0.0, 0.0, 0.0));
		Samples.z = tex2Dproj(ShadowSampler, ShadowCoords + float4(0.0, Texel.y, 0.0, 0.0));
		Samples.w = tex2Dproj(ShadowSampler, ShadowCoords + Texel);
		float4 CMPBits = step(saturate(GetSlopedBasedBias(ShadowCoords.z)), Samples);
		return dot(CMPBits, 0.25);
	}

	/*
		Shared lighting functions

		Sources:
		- GetTangentBasis(): https://en.wikipedia.org/wiki/Gram-Schmidt_process
		- GetSpecular(): https://www.rorydriscoll.com/2009/01/25/energy-conservation-in-games/

		License: https://creativecommons.org/licenses/by-sa/3.0/
	*/

	// Gets Orthonormal (TBN) matrix
	float3x3 GetTangentBasis(float3 Tangent, float3 Normal, float Flip)
	{
		// Get Tangent and Normal
		Tangent = normalize(Tangent);
		Normal = normalize(Normal);

		// Re-orthogonalize Tangent with respect to Normal
		Tangent = normalize(Tangent - (Normal * dot(Tangent, Normal)));

		// Cross product and flip to create BiNormal
		float3 BiNormal = normalize(cross(Tangent, Normal)) * Flip;

		return float3x3(Tangent, BiNormal, Normal);
	}

	// Gets Lambertian diffuse value
	float GetLambert(float3 NormalVec, float3 LightVec)
	{
		return saturate(dot(NormalVec, LightVec));
	}

	// Gets normalized modified Blinn-Phong specular value
	float GetSpecular(float3 NormalVec, float3 HalfVec, uniform float N = 32.0)
	{
		float NFactor = (N + 8.0) / 8.0;
		float Specular = saturate(dot(NormalVec, HalfVec));
		return NFactor * pow(abs(Specular), N);
	}

	// Gets radial light attenuation value for pointlights
	float GetLightAttenuation(float3 LightVec, float Attenuation)
	{
		float SqDistance = dot(LightVec, LightVec);
		return saturate(1.0 - (SqDistance * Attenuation));
	}
#endif
