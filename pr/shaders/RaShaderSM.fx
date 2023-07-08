#include "shaders/RealityGraphics.fxh"
#include "shaders/RaCommon.fxh"
#include "shaders/RaShaderSMCommon.fxh"

/*
	Description:
	- Renders lighting for skinnedmesh (objects that are dynamic, human-like with bones)
	- Skinning function currently for 2 bones
	- Calculates world-space lighting
*/

// Dep.checks, etc

#if _POINTLIGHT_
	#define _HASENVMAP_ 0
	#define _USEHEMIMAP_ 0
	#define _HASSHADOW_ 0
#endif

#undef _DEBUG_
// #define _DEBUG_
#if defined(_DEBUG_)
	#define _HASNORMALMAP_ 1
	#define _OBJSPACENORMALMAP_ 1
	#define _HASENVMAP_ 1
	#define _USEHEMIMAP_ 1
	#define _HASSHADOW_ 1
	#define _HASSHADOWOCCLUSION_ 1
	#define _POINTLIGHT_ 1
#endif

struct APP2VS
{
	float4 Pos : POSITION;
	float3 Normal : NORMAL;
	float BlendWeights : BLENDWEIGHT;
	float4 BlendIndices : BLENDINDICES;
	float2 TexCoord0 : TEXCOORD0;
	float3 Tan : TANGENT;
};

struct VS2PS
{
	float4 HPos : POSITION;
	float4 Pos : TEXCOORD0;

	float3 WorldTangent : TEXCOORD1;
	float3 WorldBinormal : TEXCOORD2;
	float3 WorldNormal : TEXCOORD3;

	float2 Tex0 : TEXCOORD4;
	float4 ShadowTex : TEXCOORD5;
	float4 ShadowOccTex : TEXCOORD6;
};

struct PS2FB
{
	float4 Color : COLOR;
	#if defined(LOG_DEPTH)
		float Depth : DEPTH;
	#endif
};

float4x3 GetBoneMatrix(APP2VS Input, uniform int Bone)
{
	// Compensate for lack of UBYTE4 on Geforce3
	int4 IndexVector = D3DCOLORtoUBYTE4(Input.BlendIndices);
	int IndexArray[4] = (int[4])IndexVector;
	return MatBones[IndexArray[Bone]];
}

float4 SkinObjectPos(APP2VS Input)
{
	float3 Pos1 = mul(Input.Pos, GetBoneMatrix(Input, 0));
	float3 Pos2 = mul(Input.Pos, GetBoneMatrix(Input, 1));
	return float4(lerp(Pos2, Pos1, Input.BlendWeights), 1.0);
}

float GetBinormalFlipping(APP2VS Input)
{
	int4 IndexVector = D3DCOLORtoUBYTE4(Input.BlendIndices);
	int IndexArray[4] = (int[4])IndexVector;
	return 1.0 + IndexArray[2] * -2.0;
}

VS2PS VS_SkinnedMesh(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	// Get skinned object-space data
	float4 ObjectPos = SkinObjectPos(Input);
	float3x3 ObjectTBN = GetTangentBasis(Input.Tan, Input.Normal, GetBinormalFlipping(Input));

	// Output HPos data
	Output.HPos = mul(ObjectPos, WorldViewProjection);

	// World-space data
	float4 WorldPos = mul(float4(Input.Pos.xyz, 1.0), World);
	float4 SkinWorldPos = mul(ObjectPos, World);
	float3x3 WorldMat = mul((float3x3)GetBoneMatrix(Input, 0), (float3x3)World);
	#if _OBJSPACENORMALMAP_
		// [object-space] -> [skinned object-space] -> [skinned world-space]
		Output.WorldTangent = WorldMat[0];
		Output.WorldBinormal = WorldMat[1];
		Output.WorldNormal = WorldMat[2];
	#else
		// [tangent-space] -> [object-space] -> [skinned object-space] -> [skinned world-space]
		float3x3 WorldTBN = mul(ObjectTBN, WorldMat);
		Output.WorldTangent = WorldTBN[0];
		Output.WorldBinormal = WorldTBN[1];
		Output.WorldNormal = WorldTBN[2];
	#endif
	#if _OBJSPACENORMALMAP_ || !_HASNORMALMAP_
		Output.Pos = WorldPos;
	#else
		Output.Pos = SkinWorldPos;
	#endif
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	// Texture-space data
	Output.Tex0 = Input.TexCoord0;
	#if _HASSHADOW_
		Output.ShadowTex = GetShadowProjection(SkinWorldPos);
	#endif
	#if _HASSHADOWOCCLUSION_
		Output.ShadowOccTex = GetShadowProjection(SkinWorldPos, true);
	#endif

	return Output;
}

// NOTE: This returns un-normalized for point, because point needs to be attenuated.
float3 GetWorldLightVec(float3 WorldPos)
{
	#if _POINTLIGHT_
		return GetWorldLightPos(Lights[0].pos.xyz) - WorldPos;
	#else
		return GetWorldLightDir(-Lights[0].dir.xyz);
	#endif
}

float GetHemiLerp(float3 WorldPos, float3 WorldNormal)
{
	// LocalHeight scale, 1 for top and 0 for bottom
	float LocalHeight = (WorldPos.y - (World[3][1] - 0.5)) * 0.5;
	float Offset = ((LocalHeight * 2.0) - 1.0) + HeightOverTerrain;
	Offset = clamp(Offset, (1.0 - HeightOverTerrain) * -2.0, 0.8);
	return saturate(((WorldNormal.y + Offset) * 0.5) + 0.5);
}

PS2FB PS_SkinnedMesh(VS2PS Input)
{
	PS2FB Output = (PS2FB)0;

	// Get world-space data
	float3 WorldPos = Input.Pos.xyz;
	float3 WorldLightVec = GetWorldLightVec(WorldPos);
	float3 WorldLightDir = normalize(WorldLightVec);
	float3 WorldViewDir = normalize(WorldSpaceCamPos.xyz - WorldPos.xyz);
	float3x3 WorldTBN =
	{
		normalize(Input.WorldTangent),
		normalize(Input.WorldBinormal),
		normalize(Input.WorldNormal)
	};

	// (.a) stores the glossmap
	#if _HASNORMALMAP_
		float4 WorldNormal = tex2D(SampleNormalMap, Input.Tex0);
		WorldNormal.xyz = normalize((WorldNormal.xyz * 2.0) - 1.0);
		WorldNormal.xyz = mul(WorldNormal.xyz, WorldTBN);
	#else
		float4 WorldNormal = float4(WorldTBN[2], 0.0);
	#endif

	float4 ColorMap = tex2D(SampleDiffuseMap, Input.Tex0);

	#if _HASSHADOW_
		float Shadow = GetShadowFactor(SampleShadowMap, Input.ShadowTex);
	#else
		float Shadow = 1.0;
	#endif
	#if _HASSHADOWOCCLUSION_
		float ShadowOcc = GetShadowFactor(SampleShadowOccluderMap, Input.ShadowOccTex);
	#else
		float ShadowOcc = 1.0;
	#endif

	#if _POINTLIGHT_
		float3 Ambient = 0.0;
	#else
		#if _USEHEMIMAP_
			// GoundColor.a has an occlusion factor that we can use for static shadowing
			float2 HemiTex = GetHemiTex(WorldPos, WorldNormal, HemiMapConstants, true);
			float4 HemiMap = tex2D(SampleHemiMap, HemiTex);
			float HemiLerp = GetHemiLerp(WorldPos, WorldNormal);
			float3 Ambient = lerp(HemiMap, HemiMapSkyColor, HemiLerp);
		#else
			float3 Ambient = Lights[0].color.a;
		#endif
	#endif

	#if _POINTLIGHT_
		float Attenuation = GetLightAttenuation(WorldLightVec, Lights[0].attenuation);
	#else
		const float Attenuation = 1.0;
	#endif

	float Gloss = WorldNormal.a;
	float3 LightFactors = Attenuation * (Shadow * ShadowOcc);
	ColorPair Light = ComputeLights(WorldNormal.xyz, WorldLightDir, WorldViewDir, SpecularPower);
	float3 DiffuseRGB = (Light.Diffuse * Lights[0].color.rgb) * LightFactors;
	float3 SpecularRGB = ((Light.Specular * Gloss) * Lights[0].color.rgb) * LightFactors;

	// Only add specular to bundledmesh with a glossmap (.a channel in NormalMap or ColorMap)
	// Prevents non-detailed bundledmesh from looking shiny
	#if !_HASNORMALMAP_
		Light.Specular = 0.0;
	#endif
	float4 OutputColor = 1.0;
	OutputColor.rgb = (ColorMap.rgb * (Ambient + DiffuseRGB)) + SpecularRGB;
	OutputColor.a = ColorMap.a * Transparency.a;

	// Thermals
	if (IsTisActive())
	{
		#if _HASENVMAP_ // If EnvMap enabled, then should be hot on thermals
			OutputColor.rgb = float3(lerp(0.60, 0.30, ColorMap.b), 1.0, 0.0); // M // 0.61, 0.25
		#else // Else cold
			OutputColor.rgb = float3(lerp(0.43, 0.17, ColorMap.b), 1.0, 0.0);
		#endif
	}

	Output.Color = OutputColor;
	#if !_POINTLIGHT_
		ApplyFog(Output.Color.rgb, GetFogValue(WorldPos, WorldSpaceCamPos.xyz));
	#endif

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
}

technique VariableTechnique
{
	pass Pass0
	{
		AlphaTestEnable = (AlphaTest);
		AlphaRef = (AlphaTestRef);

		#if _POINTLIGHT_
			AlphaBlendEnable = TRUE;
			SrcBlend = ONE;
			DestBlend = ONE;
		#else
			AlphaBlendEnable = FALSE;
		#endif

		VertexShader = compile vs_3_0 VS_SkinnedMesh();
		PixelShader = compile ps_3_0 PS_SkinnedMesh();
	}
}
