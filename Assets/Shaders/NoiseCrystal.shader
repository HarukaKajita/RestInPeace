Shader "NoiseCrystal/comp"
{
	Properties
	{
		_Iteration("Iteration", Range(1,8)) = 8
		[KeywordEnum(VALUE, PERLINE, FBM, CELLULAR)]_NoiseType("Noise Type", int) = 0
		_NoiseScale("Noise Scale", Range(0,100)) = 1.0
		[PowerSlider(5)]_Attenuation("Attenuation Strength", Range(0,20)) = 1
		[PowerSlider(5)]_BaseAlphaStrength("Base Alpha Strength", Range(0,1)) = 2
		[HDR] _InColor ("In Color", color) = (1,0,0,1)
		[HDR] _OutColor ("Out Color", color) = (0,0,1,1)
		_ColorMultiply ("Color Multiply", Range(0,10)) = 1
		_GradientPower ("Gradient Power", range(0,2)) = 0.5
		_FresnelPower ("Fresnel Power", Range(0, 10)) = 2
		_ETA("Refractive", Range(0,2)) = 1.0
		_RefractDistance ("Background Distortion",Range(0,1)) = 0.1

		[HideInInspector]_Radius ("Radius", Range(0,0.5)) = 0.495
	}
	SubShader
	{
		Tags { "RenderType"="Transparent" "Queue"="Transparent"}
		Blend SrcAlpha OneMinusSrcAlpha
		
		ZWrite off
		LOD 100
		GrabPass{}
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"
			#include "Noise3D.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float3 normal : NORMAL;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
				float3 oPos : TEXCOORD1;
				float3 wPos : TEXCOORD2;
				float3 normal : TEXCOORD3;
				float4 screenPos : TEXCOOR4;
			};
			
			sampler2D _GrabTexture;
			sampler2D _MainTex;
			float4 _MainTex_ST;
			int _Iteration;
			float _Attenuation;
			float _BaseAlphaStrength;
			fixed3 _InColor;
			fixed3 _OutColor;
			float _ColorMultiply;
			float _GradientPower;
			int _NoiseType;
			float _NoiseScale;
			float _FresnelPower;
			float _ETA;
			float _RefractDistance;

			float _Radius;

			float3 getNoise(float3 pos){
				pos *= _NoiseScale;
				pos.y += _Time.y;
				float3 noiseVec = 0;
				if(_NoiseType == 0){
					noiseVec = valNoise3D(pos)*2-1;
				} else if(_NoiseType == 1){
					noiseVec = pNoise3D(pos)*2-1;
				} else if(_NoiseType == 3){
					noiseVec = rand3D(getNearCellPos(pos));
				} else if(_NoiseType == 2){
					noiseVec = fbm3D(pos)*2-1;
				}
				return noiseVec;
			}
			
			float getLengthToNearIntersection(float3 cPos, float3 dir){
                return -(dot(cPos, dir) 
                            + sqrt(pow(dot(cPos, dir), 2)
                                    - dot(dir, dir) * (dot(cPos, cPos) - _Radius*_Radius)
                              )
                        )
                        / dot(dir, dir);
			}
			
			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = TRANSFORM_TEX(v.uv, _MainTex);
				o.oPos = v.vertex;
				o.wPos = mul(unity_ObjectToWorld, v.vertex);
				o.normal = v.normal;
				o.screenPos = ComputeGrabScreenPos(o.vertex);
				return o;
			}
			
			fixed4 frag (v2f i) : SV_Target
			{
				float3 oPos = i.oPos;
				float3 wPos = i.wPos;
				float3 vDir = normalize(UnityWorldSpaceViewDir(wPos));
				float3 wNormal = normalize(UnityObjectToWorldNormal(i.normal));
				float3 rDir   = normalize(reflect(-vDir, wNormal));
				float NdotV = dot(wNormal, vDir);
				float fresnel = pow(NdotV, _FresnelPower);
				float3 oNormal = normalize(i.normal);
				float3 wCamPos = _WorldSpaceCameraPos;
				float3 oCamPos = mul(unity_WorldToObject, float4(_WorldSpaceCameraPos,1));
				float3 eDir = normalize(oPos - oCamPos);
				float3 refractDir = normalize(refract(eDir, oNormal, _ETA*fresnel));
				///RayMarching
				float3 delta = refractDir * (1.0/(float)_Iteration);
				float defaultStep = getLengthToNearIntersection(oCamPos, eDir);
				float3 currentPos = oCamPos + eDir*(defaultStep+0.00001);
				fixed4 noiseCol = 0;
				///

				
				///backgroundCol
				float4 distortedPos = float4(currentPos + refractDir*_RefractDistance, 1);
				distortedPos = ComputeGrabScreenPos(UnityObjectToClipPos(distortedPos));
				float2 distortedUV = distortedPos.xy / distortedPos.w ;
				fixed3 backCol = tex2D(_GrabTexture, distortedUV);
				///
				
				fixed4 col = 0;
				for(int j = 0; j < _Iteration; j++){
					
					float3 normal = normalize(getNoise(currentPos));
					float3 wp = mul(unity_ObjectToWorld, float4(currentPos,1));
					float3 lDir = normalize(UnityWorldSpaceLightDir(wp));
					float3 vDir = normalize(UnityWorldSpaceViewDir(wp));
					float3 hDir = normalize(lDir + vDir);
					float  NdotH = dot(normal, hDir)*0.5+0.5;
					float reflection = pow(NdotH, _Attenuation*2);
					float len = length(currentPos)/_Radius;
					float alpha = reflection * _BaseAlphaStrength *saturate(exp(-1*(len)));
					float interpolation = pow(dot(oNormal, eDir)*0.5+0.5, _GradientPower);
					noiseCol.rgb = lerp(_InColor, _OutColor, interpolation);
					noiseCol.a += saturate(alpha);
					currentPos += delta;
					if(length(currentPos) > _Radius) break;
				}
				noiseCol = saturate(noiseCol)* _ColorMultiply;
				float3 reflectCol = UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, rDir);
				col.rgb = lerp(backCol, noiseCol.rgb, noiseCol.a);
				col.a = noiseCol.a > 1 ? 1 : noiseCol.a;
				col.rgb = lerp(reflectCol, col.rgb, col.a*col.a);
				return col;
			}
			ENDCG
		}
	}
}
