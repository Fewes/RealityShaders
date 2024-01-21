
/*
	Include header files
*/

#include "shaders/RaDefines.fx"
#include "shaders/RealityGraphics.fxh"
#include "shaders/PBS.fxh"
#include "shaders/shared/Atmosphere.fxh"
#if !defined(INCLUDED_HEADERS)
	#include "RaDefines.fx"
	#include "RealityGraphics.fxh"
	#include "PBS.fxh"
	#include "shared/Atmosphere.fxh"
#endif

/*
	Description: Shared functions for BF2's main 3D shaders
*/

#if !defined(RACOMMON_FXH)
	#define RACOMMON_FXH
	#undef INCLUDED_HEADERS
	#define INCLUDED_HEADERS

	/*
		Cached shader variables
	*/

	/*
		The Light struct stores the properties of the sun and/or point light
		RaShaderBM: World-Space
		RaShaderSM: Object-Space
		RaShaderSTM: Object-Space
	*/
	struct Light
	{
		float3 pos;
		float3 dir;
		float4 color;
		float4 specularColor;
		float attenuation;
	};

	uniform bool alphaBlendEnable = true;
	uniform int srcBlend = 5;
	uniform int destBlend = 6;

	uniform bool AlphaTest = false;
	uniform int alphaRef = 20;
	uniform int CullMode = 3; // D3DCULL_CCW

	uniform float GlobalTime;
	uniform float WindSpeed = 0;

	uniform float4 HemiMapConstants;
	uniform float4 Transparency = 1.0;

	uniform float4x4 World;
	uniform float4x4 ViewProjection;
	uniform float4x4 WorldViewProjection;

	uniform float4 FogRange : fogRange;
	uniform float4 FogColor : fogColor;

	/*
		Shared transformation code
	*/

	float3 GetWorldPos(float3 ObjectPos)
	{
		return mul(float4(ObjectPos, 1.0), World).xyz;
	}

	float3 GetWorldNormal(float3 ObjectNormal)
	{
		return normalize(mul(ObjectNormal, (float3x3)World));
	}

	float3 GetWorldLightPos(float3 ObjectLightPos)
	{
		return mul(float4(ObjectLightPos, 1.0), World).xyz;
	}

	float3 GetWorldLightDir(float3 ObjectLightDir)
	{
		return mul(ObjectLightDir, (float3x3)World);
	}

	/*
		Shared thermal code
	*/

	bool IsTisActive()
	{
		return FogColor.r == 0;
	}

	/*
		Shared fogging and fading functions
	*/

	float GetFogValue(float3 ObjectPos, float3 CameraPos)
	{
		float FogDistance = distance(ObjectPos, CameraPos);
		float2 FogValues = FogDistance * FogRange.xy + FogRange.zw;
		float Close = max(FogValues.y, FogColor.w);
		float Far = pow(FogValues.x, 3.0);
		return saturate(Close - Far);
	}

	void ApplyFog(inout float3 Color, in float FogValue)
	{
		float3 Fog = FogColor.rgb;
		// Adjust fog for thermals same way as the sky in SkyDome
		if (IsTisActive())
		{
			// TIS uses Green + Red channel to determine heat
			Fog.r = 0.0;
			// Green = 1 means cold, Green = 0 hot. Invert channel so clouds (high green) become hot
			// Add constant to make everything colder
			Fog.g = (1.0 - FogColor.g) + 0.5;
		}

		Color = lerp(Fog, Color, FogValue);
	}

	float3 Uncharted2ToneMapping(float3 Color)
	{
		float A = 0.15;
		float B = 0.50;
		float C = 0.10;
		float D = 0.20;
		float E = 0.02;
		float F = 0.30;
		float W = 11.2;
		const float exposure = 4.0;
		Color *= exposure;
		Color = ((Color * (A * Color + C * B) + D * E) / (Color * (A * Color + B) + D * F)) - E / F;
		float white = ((W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F)) - E / F;
		Color /= white;
		return Color;
	}

	float3 Tonemap(float3 Color)
	{
		// Basic
		// return 1.0 - exp(-Color);
		return 1.0 - exp2(-Color * 2.0);
		// return Uncharted2ToneMapping(Color);

		// return exp(-1.0 / (2.72 * Color + 0.15));

		/*
		// Narkowicz 2015, "ACES Filmic Tone Mapping Curve"
		const float a = 2.51;
		const float b = 0.03;
		const float c = 2.43;
		const float d = 0.59;
		const float e = 0.14;
		return (Color * (a * Color + b)) / (Color * (c * Color + d) + e);
		*/
	}

	float3 GammaToLinear(float3 Color)
	{
		// return pow(Color, 2.2); // Slow
		return Color * (Color * (Color * 0.305306011 + 0.682171111) + 0.012522878); // Fast
		// return Color * Color; // Faster
	}

	float3 LinearToGamma(float3 Color)
	{
		// return pow(Color, 1.0 / 2.2); // Slow
		return max(1.055 * pow(abs(Color), 0.416666667) - 0.055, 0.0); // Fast?
		// return sqrt(Color); // Faster
	}

	float AmbientAmountFromDir(float3 dir)
	{
		return dir.y * 0.3 + 0.7;
	}

	void ApplyAtmosphere(inout float3 Color, float3 WorldPosition, float3 CameraPosition,
		float3 LightDir, float3 LightColor)
	{
		float3 rayDir = WorldPosition - CameraPosition;
		float rayLength = length(rayDir);
		rayDir /= rayLength;

#ifdef SKIP_ATMOSPHERE_FOG
		float FogFactor = 0.0;
#else
		float FogFactor = sq(1.0 - GetFogValue(WorldPosition, CameraPosition));
#endif
		// Fade = smoothstep(0.0, 0.001, GetFogValue(WorldPosition, CameraPosition));
		// Fade = smoothstep(690, 400, length(WorldPosition - CameraPosition));
		// Fade = 1.0 - saturate((length(WorldPosition - CameraPosition) - 400) / (690 - 400));

		rayLength = sq(rayLength) * 1e-2;
		
		float4 transmittance;
		float3 scattering = GetAtmosphere(CameraPosition, rayDir, rayLength, FIXED_LIGHT_DIR, LightColor, transmittance, FogFactor);
		Color = Color * transmittance.rgb + scattering;
#ifdef APPLY_SUN_DISC
		float3 sun = GetSunDisc(rayDir, FIXED_LIGHT_DIR) * 100.0;
		Color += sun * transmittance.xyz * transmittance.w;
#endif
	}

	/*
	// This function is a copy of GetAtmosphere from Atmosphere.fxh, but without transmittance and planet view.
	// Additionally, rayStart is assumed to be within the atmosphere.
	float3 GetSkyRadiance(float3 rayStart, float3 rayDir, float3 lightDir, float3 lightColor, float mieG = 1.0)
	{
		rayStart = float3(0, 100, 0);
		lightColor = float3(1, 1, 1); // TEMP

	#ifdef PREVENT_CAMERA_GROUND_CLIP
		rayStart.y = max(rayStart.y, 1.0);
	#endif

		// Planet and atmosphere intersection to get optical depth
		// TODO: Could simplify to circle intersection test if flat horizon is acceptable
		float opticalDepth = AtmosphereIntersection(rayStart, rayDir).y;
		
		// Note: This only works if camera XZ is at 0. Otherwise, swap for line below.
		float altitude = rayStart.y / ATMOSPHERE_HEIGHT;
		//float altitude = (length(rayStart - PLANET_CENTER) - PLANET_RADIUS) / ATMOSPHERE_HEIGHT;

		// Altitude-based density modulators
		float h = 1.0-1.0/(2.0+sq(opticalDepth)*M_DENSITY_HEIGHT_MOD);
		h = pow(h, 1.0+altitude*M_DENSITY_CAM_MOD); // Really need a pow here, bleh
		float sqh = sq(h);
		float densityR = sqh * DENSITY;
		float densityM = sq(sqh)*h * DENSITY;

	#ifdef NIGHT_LIGHT
		float nightLight = NIGHT_LIGHT;
	#else
		float nightLight = 0.0;
	#endif

		// Apply light transmittance (makes sky red as sun approaches horizon)
		lightColor *= GetLightTransmittance(rayStart, lightDir, h); // h bias makes twilight sky brighter
		
	#ifndef LIGHT_COLOR_IS_RADIANCE
		// If used in an environment where light "color" is not defined in radiometric units
		// we need to multiply with PI to correct the output.
		lightColor *= PI;
	#endif

		float3 R, M;
		GetRayleighMie(opticalDepth, densityR, densityM, R, M);
		
		// Combined scattering
		float costh = dot(rayDir, lightDir);
		float phaseR = PhaseR(costh);
		float phaseM = PhaseM(costh, mieG);
		float3 A = phaseR * lightColor + nightLight;
		float3 B = phaseM * lightColor + nightLight;
		float3 scattering = R * A + M * B;

		return scattering * EXPOSURE;
	}
	*/

	float3 GetIndirectDiffuse(float3 WorldPos, float3 WorldNormal)
	{
		return lerp(FIXED_AMBIENT2, FIXED_AMBIENT, WorldNormal.y * 0.5 + 0.5);
		// float3 Dir = normalize(lerp(float3(0, 1, 0), WorldNormal, 0.25));
		// return GetSkyRadiance(WorldPos, Dir, FIXED_LIGHT_DIR, FIXED_LIGHT_COLOR, 0.2);
	}

	float3 GetIndirectSpecular(float3 WorldPos, float3 ReflDir, float Roughness)
	{
		ReflDir.y = sign(ReflDir.y) * pow(abs(ReflDir.y), 0.2 + Roughness * 0.8);
		return lerp(FIXED_AMBIENT2, FIXED_AMBIENT, ReflDir.y * 0.5 + 0.5);
		// float MieG = lerp(0.8, 0.2, Roughness);
		// return GetSkyRadiance(WorldPos, ReflDir, FIXED_LIGHT_DIR, FIXED_LIGHT_COLOR, MieG);
	}

	float GetRoadZFade(float3 ObjectPos, float3 CameraPos, float2 FadeValues)
	{
		return saturate(1.0 - saturate((distance(ObjectPos.xyz, CameraPos.xyz) * FadeValues.x) - FadeValues.y));
	}

	/*
		Shared shadowing functions
	*/

	// Common dynamic shadow stuff
	uniform float4x4 ShadowProjMat : ShadowProjMatrix;
	uniform float4x4 ShadowOccProjMat : ShadowOccProjMatrix;
	uniform float4x4 ShadowTrapMat : ShadowTrapMatrix;

	#define CREATE_SHADOW_SAMPLER(SAMPLER_NAME, TEXTURE) \
		sampler SAMPLER_NAME = sampler_state \
		{ \
			Texture = (TEXTURE); \
			MinFilter = LINEAR; \
			MagFilter = LINEAR; \
			MipFilter = LINEAR; \
			AddressU = CLAMP; \
			AddressV = CLAMP; \
			AddressW = CLAMP; \
		}; \

	uniform texture ShadowMap : SHADOWMAP;
	#if defined(_CUSTOMSHADOWSAMPLER_)
		CREATE_SHADOW_SAMPLER(SampleShadowMap : register(_CUSTOMSHADOWSAMPLER_), ShadowMap)
	#else
		CREATE_SHADOW_SAMPLER(SampleShadowMap, ShadowMap)
	#endif

	uniform texture ShadowOccluderMap : SHADOWOCCLUDERMAP;
	CREATE_SHADOW_SAMPLER(SampleShadowOccluderMap, ShadowOccluderMap)

	// Description: Transforms the vertex position's depth from World/Object space to light space
	// tl: Make sure Pos and matrices are in same space!
	float4 GetShadowProjection(float4 Pos, uniform bool IsOccluder = false)
	{
		float4 ShadowCoords = mul(Pos, ShadowTrapMat);
		float4 LightCoords = (IsOccluder) ? mul(Pos, ShadowOccProjMat) : mul(Pos, ShadowProjMat);

		#if NVIDIA
			ShadowCoords.z = (LightCoords.z * ShadowCoords.w) / LightCoords.w; // (zL*wT)/wL == zL/wL post homo
		#else
			ShadowCoords.z = LightCoords.z;
		#endif

		return ShadowCoords;
	}
#endif
