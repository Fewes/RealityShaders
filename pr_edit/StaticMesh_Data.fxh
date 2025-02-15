
#if !defined(STATICMESH_DATA_FXH)
	#define STATICMESH_DATA_FXH
	#undef INCLUDED_HEADERS
	#define INCLUDED_HEADERS

	// UNIFORM INPUTS
	uniform float4x4 _WorldMatrix : World; // : register(vs_3_0, c0);
	uniform float4x4 _WorldViewMatrix : WorldView; //: register(vs_3_0, c8);
	uniform float4x4 _WorldViewITMatrix : WorldViewIT; //: register(vs_3_0, c8);
	uniform float4x4 _ViewProjMatrix : WorldViewProjection : register(c0);
	uniform float4x4 _ViewInverseMatrix : ViewI; //: register(vs_3_0, c8);
	// float4x3 _OneBoneSkinning[26]: matONEBONESKINNING : register(c15) < bool sparseArray = true; int arrayStart = 15; >;

	uniform float4 _AmbientColor : Ambient = { 0.0, 0.0, 0.0, 1.0 };
	uniform float4 _DiffuseColor : Diffuse = { 1.0, 1.0, 1.0, 1.0 };
	uniform float4 _SpecularColor : Specular = { 0.0, 0.0, 0.0, 1.0 };
	uniform float4 _FuzzyLightScaleValue : FuzzyLightScaleValue = { 1.75, 1.75, 1.75, 1.0 };
	uniform float4 _LightmapOffset : LightmapOffset;
	uniform float _DropShadowClipHeight : DROPSHADOWCLIPHEIGHT;
	uniform float4 _ParallaxScaleBias : PARALLAXSCALEBIAS;

	uniform bool _AlphaTest : AlphaTest = false;

	uniform float4 _ParaboloidValues : ParaboloidValues;
	uniform float4 _ParaboloidZValues : ParaboloidZValues;

	uniform texture texture0 : TEXLAYER0;
	uniform texture texture1 : TEXLAYER1;
	uniform texture texture2 : TEXLAYER2;
	uniform texture texture3 : TEXLAYER3;
	uniform texture texture4 : TEXLAYER4;
	uniform texture texture5 : TEXLAYER5;
	uniform texture texture6 : TEXLAYER6;
	uniform texture texture7 : TEXLAYER7;

	#define CREATE_SAMPLER(SAMPLER_NAME, TEXTURE_NAME, FILTER, ADDRESS) \
		sampler SAMPLER_NAME = sampler_state \
		{ \
			Texture = (TEXTURE_NAME); \
			MinFilter = FILTER; \
			MagFilter = FILTER; \
			MipFilter = FILTER; \
			AddressU = ADDRESS; \
			AddressV = ADDRESS; \
		}; \

	CREATE_SAMPLER(SamplerWrap0, texture0, LINEAR, WRAP)
	CREATE_SAMPLER(SamplerWrap1, texture1, LINEAR, WRAP)
	CREATE_SAMPLER(SamplerWrap2, texture2, LINEAR, WRAP)
	CREATE_SAMPLER(SamplerWrap3, texture3, LINEAR, WRAP)
	CREATE_SAMPLER(SamplerWrap4, texture4, LINEAR, WRAP)
	CREATE_SAMPLER(SamplerWrap5, texture5, LINEAR, WRAP)
	CREATE_SAMPLER(SamplerWrap6, texture6, LINEAR, WRAP)
	CREATE_SAMPLER(SamplerWrap7, texture7, LINEAR, WRAP)

	CREATE_SAMPLER(SamplerWrapAniso0, texture0, ANISOTROPIC, WRAP)
	CREATE_SAMPLER(SamplerWrapAniso1, texture1, ANISOTROPIC, WRAP)
	CREATE_SAMPLER(SamplerWrapAniso2, texture2, ANISOTROPIC, WRAP)
	CREATE_SAMPLER(SamplerWrapAniso3, texture3, ANISOTROPIC, WRAP)
	CREATE_SAMPLER(SamplerWrapAniso4, texture4, ANISOTROPIC, WRAP)
	CREATE_SAMPLER(SamplerWrapAniso5, texture5, ANISOTROPIC, WRAP)
	CREATE_SAMPLER(SamplerWrapAniso6, texture6, ANISOTROPIC, WRAP)
	CREATE_SAMPLER(SamplerWrapAniso7, texture7, ANISOTROPIC, WRAP)

	CREATE_SAMPLER(SamplerClamp0, texture0, LINEAR, CLAMP)
	CREATE_SAMPLER(SamplerClamp1, texture1, LINEAR, CLAMP)
	CREATE_SAMPLER(SamplerClamp2, texture2, LINEAR, CLAMP)
	CREATE_SAMPLER(SamplerClamp3, texture3, LINEAR, CLAMP)
	CREATE_SAMPLER(SamplerClamp4, texture4, LINEAR, CLAMP)
	CREATE_SAMPLER(SamplerClamp5, texture5, LINEAR, CLAMP)
	CREATE_SAMPLER(SamplerClamp6, texture6, LINEAR, CLAMP)
	CREATE_SAMPLER(SamplerClamp7, texture7, LINEAR, CLAMP)

	uniform float4 lightPos : LightPosition : register(vs_3_0, c12)
	<
		string Object = "PointLight";
		string Space = "World";
	> = {0.0, 0.0, 1.0, 1.0};

	uniform float4 _LightDir : LightDirection;
	uniform float4 _SunColor : SunColor;
	uniform float4 _EyePos : EyePos;
	uniform float4 _EyePosObjectSpace : EyePosObjectSpace;

	float2 GetOffsetsFromAlpha(float2 HeightTex, sampler2D HeightSampler, float4 ScaleBias, float3 ViewVec)
	{
		float2 Height = tex2D(HeightSampler, HeightTex).aa;
		float3 NViewVec = normalize(ViewVec) * float3(1.0, -1.0, 1.0);

		Height = (Height * ScaleBias.xy) + ScaleBias.wz;
		return Height * NViewVec.xy;
	}

	float3x3 GetTangentBasis(float3 Tangent, float3 Normal, float Flip)
	{
		// Get Tangent and Normal
		// Cross product and flip to create Binormal
		float3 Binormal = normalize(cross(Tangent, Normal)) * Flip;
		return float3x3(Tangent, Binormal, Normal);
	}

	void GetViewTangentBasis
	(
		in float3x3 TangentBasis,
		out float3 Mat1, out float3 Mat2, out float3 Mat3
	)
	{
		// Calculate tangent->view space transformation
		float3x3 TangentToView = transpose(mul(TangentBasis, (float3x3)_WorldViewITMatrix));
		Mat1 = TangentToView[0];
		Mat2 = TangentToView[1];
		Mat3 = TangentToView[2];
	}

	float4 UnpackNormal(float4 NormalMap, float3x3 ViewMatrix)
	{
		ViewMatrix = float3x3
		(
			normalize(ViewMatrix[0]),
			normalize(ViewMatrix[1]),
			normalize(ViewMatrix[2])
		);

		NormalMap.xyz = normalize((NormalMap.xyz * 2.0) - 1.0);
		return float4(mul(ViewMatrix, NormalMap.xyz), NormalMap.a);
	}

#endif
