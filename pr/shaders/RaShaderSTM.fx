
/*
	Include header files
*/

#include "shaders/RealityGraphics.fxh"
#include "shaders/shared/RealityDepth.fxh"
#include "shaders/shared/RealityDirectXTK.fxh"
#include "shaders/shared/RealityVertex.fxh"
#include "shaders/shared/RealityPixel.fxh"
#include "shaders/RaCommon.fxh"
#include "shaders/RaShaderSTM.fxh"
#if !defined(INCLUDED_HEADERS)
	#include "RealityGraphics.fxh"
	#include "shared/RealityDepth.fxh"
	#include "shared/RealityDirectXTK.fxh"
	#include "shared/RealityVertex.fxh"
	#include "shared/RealityPixel.fxh"
	#include "RaCommon.fxh"
	#include "RaShaderSTM.fxh"
#endif

/*
	Description:
	- Renders lighting for staticmesh (buildings, static props)
	- Calculates tangent-space lighting
*/

// tl: Alias packed data indices to regular indices:
#if defined(TexBasePackedInd)
	#define BaseTexID TexBasePackedInd
#endif
#if defined(TexDetailPackedInd)
	#define DetailTexID TexDetailPackedInd
#endif
#if defined(TexDirtPackedInd)
	#define DirtTexID TexDirtPackedInd
#endif
#if defined(TexCrackPackedInd)
	#define CrackTexID TexCrackPackedInd
#endif
#if defined(TexLightMapPackedInd)
	#define LightMapTexID TexLightMapPackedInd
#endif

#if (_NBASE_ || _NDETAIL_ || _NCRACK_ || _PARALLAXDETAIL_)
	#define _PERPIXEL_
#else
	// Only use crackmap if we have a per-pixel normalmap
	#define _CRACK_ 0
#endif

#undef _DEBUG_
// #define _DEBUG_
#if defined(_DEBUG_)
	#define _PERPIXEL_
	#define POINTLIGHT
#endif

#define PARALLAX_BIAS 0.0025

// Common vars
Light Lights[NUM_LIGHTS];

struct APP2VS
{
	float4 Pos : POSITION;
	float3 Normal : NORMAL;
	float3 Tan : TANGENT;
	float4 TexSets[NUM_TEXSETS] : TEXCOORD0;
};

struct VS2PS
{
	float4 HPos : POSITION;
	float4 Pos : TEXCOORD0;

	float3 WorldTangent : TEXCOORD1;
	float3 WorldBinormal : TEXCOORD2;
	float3 WorldNormal : TEXCOORD3;

	float4 BaseAndDetail : TEXCOORD4; // .xy = BaseTex; .zw = DetailTex;
	float4 DirtAndCrack : TEXCOORD5; // .xy = DirtTex; .zw = CrackTex;
	float4 LightMapTex : TEXCOORD6;
	float4 ShadowTex : TEXCOORD7;
};

struct PS2FB
{
	float4 Color : COLOR0;
	#if defined(LOG_DEPTH)
		float Depth : DEPTH;
	#endif
};

/*
	Common vertex shader methods
*/

float GetBinormalFlipping(APP2VS Input)
{
	return 1.0 + Input.Pos.w * -2.0;
}

VS2PS VS_StaticMesh(APP2VS Input)
{
	VS2PS Output = (VS2PS)0.0;

	// Object-space data
	float4 ObjectPos = float4(Input.Pos.xyz, 1.0) * PosUnpack;
	float3 ObjectTangent = Input.Tan * NormalUnpack.x + NormalUnpack.y; // Unpack object-space tangent
	float3 ObjectNormal = Input.Normal * NormalUnpack.x + NormalUnpack.y; // Unpack object-space normal
	float3x3 ObjectTBN = GetTangentBasis(ObjectTangent, ObjectNormal, GetBinormalFlipping(Input));

	// Output HPos
	Output.HPos = mul(ObjectPos, WorldViewProjection);

	// Output world-space data
	Output.Pos.xyz = GetWorldPos(ObjectPos.xyz);
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif
	float3x3 WorldTBN = mul(ObjectTBN, (float3x3)World);
	Output.WorldTangent = WorldTBN[0];
	Output.WorldBinormal = WorldTBN[1];
	Output.WorldNormal = WorldTBN[2];

	#if _BASE_
		Output.BaseAndDetail.xy = Input.TexSets[BaseTexID].xy * TexUnpack;
	#endif
	#if _DETAIL_ || _NDETAIL_
		Output.BaseAndDetail.zw = Input.TexSets[DetailTexID].xy * TexUnpack;
	#endif
	#if _DIRT_
		Output.DirtAndCrack.xy = Input.TexSets[DirtTexID].xy * TexUnpack;
	#endif
	#if _CRACK_
		Output.DirtAndCrack.zw = Input.TexSets[CrackTexID].xy * TexUnpack;
	#endif
	#if	_LIGHTMAP_
		Output.LightMapTex.xy = Input.TexSets[LightMapTexID].xy * TexUnpack * LightMapOffset.xy + LightMapOffset.zw;
	#endif
	#if _SHADOW_ && _LIGHTMAP_
		Output.ShadowTex = GetShadowProjection(ObjectPos);
	#endif

	return Output;
}

float4 GetDiffuseMap(VS2PS Input, float2 ParallaxTex, out float DiffuseGloss)
{
	float4 Diffuse = 1.0;
	DiffuseGloss = StaticGloss;

	#if _BASE_
		Diffuse = tex2D(SampleDiffuseMap, Input.BaseAndDetail.xy);
	#endif

	// TODO: Fix parallax mapping
	#if (_DETAIL_ || _PARALLAXDETAIL_)
		float4 Detail = tex2D(SampleDetailMap, ParallaxTex);
	#endif

	#if (_DETAIL_ || _PARALLAXDETAIL_)
		Diffuse.rgb *= Detail.rgb;
		Diffuse.a = Detail.a;
		#if (!_ALPHATEST_)
			DiffuseGloss = Detail.a;
			Diffuse.a = Transparency.a;
		#else
			Diffuse.a *= Transparency.a;
		#endif
	#else
		Diffuse.a *= Transparency.a;
	#endif

	#if _DIRT_
		float4 DirtMap = tex2D(SampleDirtMap, Input.DirtAndCrack.xy);
		Diffuse.rgb *= DirtMap.rgb;
	#endif

	#if _CRACK_
		float4 Crack = tex2D(SampleCrackMap, Input.DirtAndCrack.zw);
		Diffuse.rgb = lerp(Diffuse.rgb, Crack.rgb, Crack.a);
	#endif

	return Diffuse;
}

// This also includes the composite Gloss map
float3 GetNormalMap(VS2PS Input, float2 ParallaxTex, float3x3 WorldTBN)
{
	#if defined(_PERPIXEL_)
		float3 TangentNormal = float3(0.0, 0.0, 1.0);
		#if	_NBASE_
			TangentNormal = tex2D(SampleNormalMap, Input.BaseAndDetail.xy).xyz;
		#endif
		#if _PARALLAXDETAIL_
			TangentNormal = tex2D(SampleNormalMap, ParallaxTex).xyz;
		#elif _NDETAIL_
			TangentNormal = tex2D(SampleNormalMap, Input.BaseAndDetail.zw).xyz;
		#endif
		#if _NCRACK_
			float3 CrackTangentNormals = tex2D(SampleCrackNormalMap, Input.DirtAndCrack.zw).xyz;
			float CrackMask = tex2D(SampleCrackMap, Input.DirtAndCrack.zw).a;
			TangentNormal = lerp(TangentNormal, CrackTangentNormals, CrackMask);
		#endif

		// [tangent-space] -> [object-space] -> [world-space]
		TangentNormal = normalize((TangentNormal * 2.0) - 1.0);
		float3 WorldNormal = normalize(mul(TangentNormal, WorldTBN));
		return WorldNormal;
	#else
		return WorldTBN[2];
	#endif
}

float3 GetLightmap(VS2PS Input)
{
	#if _LIGHTMAP_
		return tex2D(SampleLightMap, Input.LightMapTex.xy).rgb;
	#else
		return 1.0;
	#endif
}

float3 GetWorldLightVec(float3 WorldPos)
{
	#if _POINTLIGHT_
		return GetWorldLightPos(Lights[0].pos.xyz) - WorldPos;
	#else
		return GetWorldLightDir(-Lights[0].dir.xyz);
	#endif
}

PS2FB PS_StaticMesh(VS2PS Input)
{
	// Initialize variables
	float4 OutputColor = 1.0;
	PS2FB Output = (PS2FB)0.0;

	// World-space data
	float3 WorldPos = Input.Pos.xyz;
	float3 WorldLightVec = GetWorldLightVec(WorldPos);
	float3 WorldLightDir = normalize(WorldLightVec);
	float3 WorldViewDir = normalize(WorldSpaceCamPos.xyz - WorldPos);
	float3x3 WorldTBN =
	{
		normalize(Input.WorldTangent),
		normalize(Input.WorldBinormal),
		normalize(Input.WorldNormal)
	};

	// Tangent-space data
	// mul(mat, vec) == mul(vec, transpose(mat))
	float3 TanViewDir = normalize(mul(WorldTBN, WorldViewDir));
	float2 ParallaxTex = GetParallaxTex(SampleNormalMap, Input.BaseAndDetail.zw, TanViewDir, ParallaxScaleBias.xy * PARALLAX_BIAS, ParallaxScaleBias.wz);

	// Prepare texture data
	float Gloss;
	float4 ColorMap = GetDiffuseMap(Input, ParallaxTex, Gloss);
	float3 WorldNormal = GetNormalMap(Input, ParallaxTex, WorldTBN);

	#if defined(_PERPIXEL_)
		float SpecularExponent = SpecularPower;
	#else
		float SpecularExponent = 1.0;
	#endif

	// Prepare lighting data
	ColorPair Light = ComputeLights(WorldNormal, WorldLightDir, WorldViewDir, SpecularExponent);

	#if _POINTLIGHT_
		float3 DiffuseRGB = (Light.Diffuse * Lights[0].color.rgb);
		float3 SpecularRGB = (Light.Specular * Gloss) * StaticSpecularColor.rgb;

		float Attenuation = GetLightAttenuation(WorldLightVec, Lights[0].attenuation);
		DiffuseRGB *= Attenuation;
		SpecularRGB *= Attenuation;
		OutputColor.rgb = (ColorMap.rgb * DiffuseRGB) + SpecularRGB;
		OutputColor.rgb *= GetFogValue(WorldPos, WorldSpaceCamPos);
	#else
		// Directional light + Lightmap etc
		float3 Lightmap = GetLightmap(Input);

		float AmbientOcclusion = Lightmap.b;
		float Shadow = Lightmap.g;

		#if _LIGHTMAP_ && _SHADOW_
			Shadow *= GetShadowFactor(SampleShadowMap, Input.ShadowTex);
		#endif

		// float3 LightColor = Lights[0].color.rgb;	
		float3 LightColor = 1.0;//GetLightTransmittance(WorldPos, LightDir, 1.0);
		// float3 LightDir = WorldLightDir;
		float3 LightDir = FIXED_LIGHT_DIR;
		// float3 AmbientColor = StaticSkyColor.rgb;

		//float4 transmittance;
		//float3 AmbientColor = GetAtmosphere(WorldPos, WorldNormal, INFINITY, LightDir, LightColor, transmittance, 1.0);

		// We add ambient to get correct ambient for surfaces parallel to the sun
		// float3 AmbientLight = AmbientColor * AmbientOcclusion;

		float3 ReflDir = reflect(-WorldViewDir, WorldNormal);
		/*
		float3 AmbientDir = normalize(lerp(float3(0, 1, 0), WorldNormal, 0.25));
		float3 IndirectDiffuse = GetAtmosphere(WorldPos, AmbientDir, 1e10, LightDir, LightColor) * Fd_Lambert();
		float3 IndirectSpecular = GetAtmosphere(WorldPos, ReflDir, 1e10, LightDir, LightColor);
		*/
		float3 Albedo = GammaToLinear(ColorMap.rgb) * 2.0; // Original shader does 2x for some reason, keep
		float Roughness = RoughnessFromGlossAndExponent(Gloss, SpecularExponent);
		float Metallic = 0.0;
		// float3 IndirectDiffuse = FIXED_AMBIENT * AmbientOcclusion * AmbientAmountFromDir(WorldNormal);
		// float3 IndirectSpecular = FIXED_AMBIENT * AmbientOcclusion * AmbientAmountFromDir(reflect(-WorldViewDir, WorldNormal));
		float3 IndirectDiffuse = GetIndirectDiffuse(WorldPos, WorldNormal) * AmbientOcclusion;
		float3 IndirectSpecular = GetIndirectSpecular(WorldPos, ReflDir, Roughness) * AmbientOcclusion;
		SurfaceData Surface = GetSurfaceData(WorldPos, WorldNormal, WorldViewDir);
		BRDFData BRDF = GetBBRDFData(Albedo, Roughness, Metallic); 
		OutputColor.rgb = DirectPBS(Surface, BRDF, LightDir, LightColor, Shadow);
		OutputColor.rgb += IndirectPBS(Surface, BRDF, IndirectDiffuse, IndirectSpecular);
	#endif

	#if !_POINTLIGHT_
		//ApplyFog(OutputColor.rgb, GetFogValue(WorldPos, WorldSpaceCamPos.xyz));

		/*
		float FogDistance = distance(WorldPos, WorldSpaceCamPos.xyz);
		float2 FogValues = FogDistance * FogRange.xy + FogRange.zw;
		float Close = max(FogValues.y, FogColor.w);
		float Far = pow(FogValues.x, 3.0);
		return saturate(Close - Far);
		*/

		ApplyAtmosphere(OutputColor.rgb, WorldPos, WorldSpaceCamPos.xyz, WorldLightDir, Lights[0].color.rgb);
	#endif

	OutputColor.rgb = Tonemap(OutputColor.rgb);
	OutputColor.rgb = LinearToGamma(OutputColor.rgb);

	Output.Color.rgb = 0.5;

	// OutputColor.rgb = Gloss;

	Output.Color = float4(OutputColor.rgb, ColorMap.a);

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
};

technique defaultTechnique
{
	pass p0
	{
		#if defined(ENABLE_WIREFRAME)
			FillMode = WireFrame;
		#endif

		ZFunc = LESS;
		AlphaTestEnable = (AlphaTest);
		AlphaRef = 127; // temporary hack by johan because "m_shaderSettings.m_alphaTestRef = 127" somehow doesn't work

		#if _POINTLIGHT_
			ZFunc = LESSEQUAL;
			AlphaBlendEnable = TRUE;
			SrcBlend = ONE;
			DestBlend = ONE;
		#endif

		VertexShader = compile vs_3_0 VS_StaticMesh();
		PixelShader = compile ps_3_0 PS_StaticMesh();
	}
}
