#include "shaders/RealityGraphics.fxh"
#include "shaders/RaCommon.fxh"
#if !defined(INCLUDED_HEADERS)
	#include "RealityGraphics.fxh"
	#include "RaCommon.fxh"
#endif

uniform float4x4 _WorldViewProj : WorldViewProjection;
uniform float4 _ViewPos : ViewPos;
uniform float4 _DiffuseColor : DiffuseColor;
uniform float _BlendFactor : BlendFactor;
uniform float _Material : Material;

uniform float4 _FogColor : FogColor;

uniform texture DetailTex0 : TEXLAYER0;
uniform texture DetailTex1 : TEXLAYER1;

sampler SampleDetailTex0 = sampler_state
{
	Texture = (DetailTex0);
	AddressU = CLAMP;
	AddressV = WRAP;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	MipFilter = LINEAR;
};

sampler SampleDetailTex1 = sampler_state
{
	Texture = (DetailTex1);
	AddressU = WRAP;
	AddressV = WRAP;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	MipFilter = LINEAR;
};

struct PS2FB
{
	float4 Color : COLOR0;
	#if defined(LOG_DEPTH)
		float Depth : DEPTH;
	#endif
};

struct APP2VS
{
	float4 Pos : POSITION;
	float2 Tex0 : TEXCOORD0;
	float2 Tex1 : TEXCOORD1;
	float Alpha : TEXCOORD2;
};

struct VS2PS
{
	float4 HPos : POSITION;
	float4 Pos : TEXCOORD0;
	float4 Tex0 : TEXCOORD1; // .xy = Tex0; .zw = Tex1;
	float Alpha : TEXCOORD2;
};

VS2PS VS_RoadEditable(APP2VS Input)
{
	VS2PS Output = (VS2PS)0.0;
	Input.Pos.y +=  0.01;
	Output.HPos = mul(Input.Pos, _WorldViewProj);

	Output.Pos = Output.HPos;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	Output.Tex0 = float4(Input.Tex0, Input.Tex1);
	Output.Alpha = Input.Alpha;

	return Output;
}

PS2FB PS_RoadEditable(VS2PS Input)
{
	PS2FB Output = (PS2FB)0.0;

	float4 ColorMap0 = tex2D(SampleDetailTex0, Input.Tex0.xy);
	float4 ColorMap1 = tex2D(SampleDetailTex1, Input.Tex0.zw);

	float4 OutputColor = 0.0;
	OutputColor.rgb = lerp(ColorMap1.rgb, ColorMap0.rgb, saturate(_BlendFactor));
	OutputColor.a = ColorMap0.a * Input.Alpha;

	Output.Color = OutputColor;

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
}

struct APP2VS_DrawMaterial
{
	float4 Pos : POSITION;
	float2 Tex0 : TEXCOORD0;
	float2 Tex1 : TEXCOORD1;
};

struct VS2PS_DrawMaterial
{
	float4 HPos : POSITION;
	float4 Pos : TEXCOORD0;
};

VS2PS_DrawMaterial VS_RoadEditable_DrawMaterial(APP2VS_DrawMaterial Input)
{
	VS2PS_DrawMaterial Output = (VS2PS_DrawMaterial)0.0;

	Output.HPos = mul(Input.Pos, _WorldViewProj);
	Output.Pos = Output.HPos;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	return Output;
}

PS2FB PS_RoadEditable_DrawMaterial(VS2PS_DrawMaterial Input)
{
	PS2FB Output = (PS2FB)0.0;

	float3 LocalPos = Input.Pos.xyz;

	Output.Color = float4((float3)_Material, 1.0);

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
}

technique roadeditable
<
	int DetailLevel = DLHigh+DLNormal+DLLow+DLAbysmal;
	int Compatibility = CMPR300+CMPNV2X;
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		// { 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0 },
		{ 0, D3DDECLTYPE_FLOAT2, D3DDECLUSAGE_TEXCOORD, 0 },
		{ 0, D3DDECLTYPE_FLOAT2, D3DDECLUSAGE_TEXCOORD, 1 },
		{ 0, D3DDECLTYPE_FLOAT1, D3DDECLUSAGE_TEXCOORD, 2 },
		DECLARATION_END // End macro
	};
>
{
	pass p0
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;
		FogEnable = FALSE;
		ZEnable = TRUE;
		ZWriteEnable = FALSE;
		FogEnable = TRUE;

		VertexShader = compile vs_3_0 VS_RoadEditable();
		PixelShader = compile ps_3_0 PS_RoadEditable();
	}

	pass p1 // draw material
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;
		DepthBias = -0.0001f;
		SlopeScaleDepthBias = -0.00001f;
		ZEnable = TRUE;
		ZWriteEnable = FALSE;

		VertexShader = compile vs_3_0 VS_RoadEditable_DrawMaterial();
		PixelShader = compile ps_3_0 PS_RoadEditable_DrawMaterial();
	}
}
