Shader "URP/Volumentric/AtmosphereUpscale"
{
    Properties
    {
        _AtmosphereTex ("Atmosphere Texture", 2D) = "white" {}
        //_TexSize ("Texture Size", Vector) = (960, 540,0,0)
        _TexSizeX("Texture Size X", Int) = 960
        _TexSizeY("Texture Size Y", Int) = 540
        _UseUpscaling("Use Upscaling", Int) = 1
    }
    SubShader
    {

        Cull Front

        ZWrite Off ZTest Off

        Blend SrcAlpha OneMinusSrcAlpha

        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
      
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                //float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 v_screenPos : TEXCOORD1;
            };

            sampler2D _AtmosphereTex;
            float4 _AtmosphereTex_ST;

            //float2 _TexSize
            float _TexSizeX;
            float _TexSizeY;

            int _UseUpscaling;


            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                //o.uv = TRANSFORM_TEX(v.uv, _AtmosphereTex);
                o.v_screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            float4 SampleTextureCatmullRom(in float2 uv, in float2 texSize)
            {
                // We're going to sample a a 4x4 grid of texels surrounding the target UV coordinate. We'll do this by rounding
                // down the sample location to get the exact center of our "starting" texel. The starting texel will be at
                // location [1, 1] in the grid, where [0, 0] is the top left corner.
                float2 samplePos = uv * texSize;
                float2 texPos1 = floor(samplePos - 0.5f) + 0.5f;

                // Compute the fractional offset from our starting texel to our original sample location, which we'll
                // feed into the Catmull-Rom spline function to get our filter weights.
                float2 f = samplePos - texPos1;

                // Compute the Catmull-Rom weights using the fractional offset that we calculated earlier.
                // These equations are pre-expanded based on our knowledge of where the texels will be located,
                // which lets us avoid having to evaluate a piece-wise function.
                float2 w0 = f * (-0.5f + f * (1.0f - 0.5f * f));
                float2 w1 = 1.0f + f * f * (-2.5f + 1.5f * f);
                float2 w2 = f * (0.5f + f * (2.0f - 1.5f * f));
                float2 w3 = f * f * (-0.5f + 0.5f * f);

                // Work out weighting factors and sampling offsets that will let us use bilinear filtering to
                // simultaneously evaluate the middle 2 samples from the 4x4 grid.
                float2 w12 = w1 + w2;
                float2 offset12 = w2 / (w1 + w2);

                // Compute the final UV coordinates we'll use for sampling the texture
                float2 texPos0 = texPos1 - 1;
                float2 texPos3 = texPos1 + 2;
                float2 texPos12 = texPos1 + offset12;

                texPos0 /= texSize;
                texPos3 /= texSize;
                texPos12 /= texSize;

                float4 result = 0.0f;
                result += tex2D(_AtmosphereTex, float2(texPos0.x, texPos0.y)) * w0.x * w0.y;
                result += tex2D(_AtmosphereTex, float2(texPos12.x, texPos0.y)) * w12.x * w0.y;
                result += tex2D(_AtmosphereTex, float2(texPos3.x, texPos0.y)) * w3.x * w0.y;

                result += tex2D(_AtmosphereTex, float2(texPos0.x, texPos12.y)) * w0.x * w12.y;
                result += tex2D(_AtmosphereTex, float2(texPos12.x, texPos12.y)) * w12.x * w12.y;
                result += tex2D(_AtmosphereTex, float2(texPos3.x, texPos12.y)) * w3.x * w12.y;

                result += tex2D(_AtmosphereTex, float2(texPos0.x, texPos3.y)) * w0.x * w3.y;
                result += tex2D(_AtmosphereTex, float2(texPos12.x, texPos3.y)) * w12.x * w3.y;
                result += tex2D(_AtmosphereTex, float2(texPos3.x, texPos3.y)) * w3.x * w3.y;

                return result;
            }

            float4 frag (v2f i) : SV_Target
            {
                float2 uv = i.v_screenPos.xy / i.v_screenPos.w;
                
                float2 texSize = float2(_TexSizeX,_TexSizeY);

                float4 col = 1;
                if(_UseUpscaling < 1)
                    col = tex2D(_AtmosphereTex, uv);
                else
                    col = SampleTextureCatmullRom(uv, texSize);

                return col;
            }
            ENDCG
        }
    }
}
