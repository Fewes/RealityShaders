
/*
	Description: Renders object's diffuse map
	
	Global variables we use to hold the view matrix, projection matrix,
	ambient material, diffuse material, and the light vector that
	describes the direction to the light source. These variables are
	initialized from the application.
*/

#include "shaders/RealityGraphics.fxh"

#include "shaders/RaCommon.fxh"

uniform bool AlphaBlendEnable = false;
uniform float4x4 Bones[26];
uniform float4 ObjectSpaceCamPos;

uniform texture DiffuseMap;
sampler SampleDiffuseMap = sampler_state
{
	Texture = (DiffuseMap);
	MipFilter = LINEAR;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = WRAP;
	AddressV = WRAP;
	SRGBTexture = FALSE;
};

string TemplateParameters[] =
{
	"DiffuseMap",
	"ViewProjection"
};

string InstanceParameters[] =
{
	"Bones",
	"AlphaBlendEnable",
	"ObjectSpaceCamPos"
};

string reqVertexElement[] =
{
	"Position",
	"TBase2D",
	"Bone4Idcs"
};

struct APP2VS
{
	float3 Pos : POSITION0;
	float2 Tex0 : TEXCOORD0;
	float4 BlendIndices : BLENDINDICES;
};

struct VS2PS
{
	float4 HPos : POSITION;
	float2 Tex : TEXCOORD0;
};

VS2PS DiffuseBone_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	// Compensate for lack of UBYTE4 on Geforce3
	int4 IndexVector = D3DCOLORtoUBYTE4(Input.BlendIndices);
	int IndexArray[4] = (int[4])IndexVector;

	Output.HPos = mul(float4(Input.Pos.xyz, 1.0), mul(Bones[IndexArray[0]], ViewProjection));
	Output.Tex = Input.Tex0;

	return Output;
}

float4 DiffuseBone_PS(VS2PS Input) : COLOR
{
	return tex2D(SampleDiffuseMap, Input.Tex) * float4(1.0, 0.0, 1.0, 1.0);
};

technique defaultTechnique
{
	pass P0
	{
		#if defined(ENABLE_WIREFRAME)
			FillMode = WireFrame;
		#endif

		AlphaTestEnable = <AlphaTest>;
		AlphaRef = <alphaRef>;

		AlphaBlendEnable = <AlphaBlendEnable>;
		SrcBlend = <srcBlend>;
		DestBlend = <destBlend>;

		VertexShader = compile vs_3_0 DiffuseBone_VS();
		PixelShader = compile ps_3_0 DiffuseBone_PS();
	}
}
