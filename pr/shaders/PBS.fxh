#ifndef PBS_INCLUDED
#define PBS_INCLUDED

// Sourced from https://www.shadertoy.com/view/XlKSDR

#define PI 3.14159265359

// Temporary defines because many shaders are not fed sun direction or color
#define FIXED_AMBIENT float3(0.19, 0.2, 0.21)
#define FIXED_AMBIENT2 float3(0.18, 0.17, 0.16)
#define FIXED_LIGHT_DIR normalize(float3(1, 0.6, 1))
#define FIXED_LIGHT_COLOR float3(1, 1, 1)

//------------------------------------------------------------------------------
// BRDF
//------------------------------------------------------------------------------

float pow5(float x) {
    float x2 = x * x;
    return x2 * x2 * x;
}

float D_GGX(float linearRoughness, float NoH, const float3 h)
{
    // Walter et al. 2007, "Microfacet Models for Refraction through Rough Surfaces"
    float oneMinusNoHSquared = 1.0 - NoH * NoH;
    float a = NoH * linearRoughness;
    float k = linearRoughness / (oneMinusNoHSquared + a * a);
    float d = k * k * (1.0 / PI);
    return d;
}

float V_SmithGGXCorrelated(float linearRoughness, float NoV, float NoL)
{
    // Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"
    float a2 = linearRoughness * linearRoughness;
    float GGXV = NoL * sqrt((NoV - a2 * NoV) * NoV + a2);
    float GGXL = NoV * sqrt((NoL - a2 * NoL) * NoL + a2);
    return 0.5 / (GGXV + GGXL);
}

float3 F_Schlick(const float3 f0, float VoH)
{
    // Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"
    return f0 + (1.0 - f0) * pow5(1.0 - VoH);
}

float F_Schlick(float f0, float f90, float VoH)
{
    return f0 + (f90 - f0) * pow5(1.0 - VoH);
}

float Fd_Burley(float linearRoughness, float NoV, float NoL, float LoH)
{
    // Burley 2012, "Physically-Based Shading at Disney"
    float f90 = 0.5 + 2.0 * linearRoughness * LoH * LoH;
    float lightScatter = F_Schlick(1.0, f90, NoL);
    float viewScatter  = F_Schlick(1.0, f90, NoV);
    return lightScatter * viewScatter * (1.0 / PI);
}

float Fd_Lambert()
{
    return 1.0 / PI;
}

float2 PrefilteredDFG_Karis(float roughness, float NoV)
{
	// Karis 2014, "Physically Based Material on Mobile"
	const float4 c0 = float4(-1.0, -0.0275, -0.572,  0.022);
	const float4 c1 = float4( 1.0,  0.0425,  1.040, -0.040);

	float4 r = roughness * c0 + c1;
	float a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;

	return float2(-1.04, 1.04) * a004 + r.zw;
}

//------------------------------------------------------------------------------
// Shading
//------------------------------------------------------------------------------

struct SurfaceData
{
	float3 WorldPositon;
	float3 WorldNormal;
	float3 WorldViewDir;
	float NoV;
};

struct BRDFData
{
	float3 DiffuseColor;
	float3 F0;
	float Roughness;
	float LinearRoughness;
};

SurfaceData GetSurfaceData(float3 WorldPosition, float3 WorldNormal, float3 WorldViewDir)
{
	SurfaceData o = (SurfaceData)0.0;
	o.WorldPositon = WorldPosition;
	o.WorldNormal = WorldNormal;
	o.WorldViewDir = WorldViewDir;
	o.NoV = abs(dot(WorldNormal, WorldViewDir)) + 1e-5;
	return o;
}

BRDFData GetBBRDFData(float3 ColorMap, float Roughness, float Metallic)
{
	BRDFData o = (BRDFData)0.0;
	o.Roughness = Roughness;
	o.LinearRoughness = Roughness*Roughness;
	o.DiffuseColor = (1.0 - Metallic) * ColorMap;
	o.F0 = float3(0.04, 0.04, 0.04) * (1.0 - Metallic) + ColorMap * Metallic;
	return o;
}

float3 DirectPBS(SurfaceData Surface, BRDFData BRDF, float3 LightDir, float3 LightColor, float Attenuation = 1.0)
{
	LightDir = FIXED_LIGHT_DIR;
	LightColor = 1.0; // TEMP

#ifdef DEBUG_LIGHTING
	BRDF.DiffuseColor = 0.5;
#endif

	float3 H = normalize(Surface.WorldViewDir + LightDir);
	float NoL = saturate(dot(Surface.WorldNormal, LightDir));
	float NoH = saturate(dot(Surface.WorldNormal, H));
	float LoH = saturate(dot(LightDir, H));

	// Specular BRDF
	float D = D_GGX(BRDF.LinearRoughness, NoH, H);
	float V = V_SmithGGXCorrelated(BRDF.LinearRoughness, Surface.NoV, NoL);
	float3 F = F_Schlick(BRDF.F0, LoH);
	float3 Fr = (D * V) * F;

	// Diffuse BRDF
	float3 Fd = BRDF.DiffuseColor * Fd_Burley(BRDF.LinearRoughness, Surface.NoV, NoL, LoH); // TODO: Swtich to Fd_Lambert on lowspec

	float3 Color = Fd + Fr;
	Color *= (LightColor * NoL * Attenuation) * float3(0.98, 0.92, 0.89);

	// The physically based BRDF divides by PI because it assumes the light is using radiometric units.
	// BF2 however does not (like many older games). Instead a light with an intensity of 1 is assumed
	// to result in a white surface with a value of 1. To fix this, we remultiply the result with PI.
	Color *= PI;

	return Color;
}

float3 IndirectPBS(SurfaceData Surface, BRDFData BRDF, float3 IndirectDiffuse, float3 IndirectSpecular)
{
#ifdef DEBUG_LIGHTING
	BRDF.DiffuseColor = 0.5; // TEST
#endif

	float2 DFG = PrefilteredDFG_Karis(BRDF.Roughness, Surface.NoV);
	float3 SpecularColor = BRDF.F0 * DFG.x + DFG.y;
	float3 IBL = BRDF.DiffuseColor * IndirectDiffuse + SpecularColor * IndirectSpecular;
	return IBL;
}

float RoughnessFromSpecularExponent(float SpecularExponent)
{
	// https://simonstechblog.blogspot.com/2011/12/microfacet-brdf.html
	return sqrt(2.0 / (SpecularExponent + 2.0));
}

float RoughnessFromGlossAndExponent(float Gloss, float SpecularExponent)
{
	float SqrtRoughness = 1.0 - Gloss;
	return max(SqrtRoughness * SqrtRoughness, RoughnessFromSpecularExponent(SpecularExponent));
}

#endif // PBS_INCLUDED