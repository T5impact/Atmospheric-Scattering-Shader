Shader "CustomRenderTexture/AtmosphereTexture"
{
    Properties
    {
        [Header(Optical Depth Texture)] [Space]

        _OpticalDepth("Optical Depth Texture", 2D) = "white" {}
        [Header(Ray Samples)] [Space]
        _samples("Samples", Int) = 20

        [Header(Planet Settings)] [Space]
        _atmosphereRadius("Atmosphere Radius", Float) = 10
        _planetRadius("Planet Radius", Float) = 8
        _sunDirection("Sun Direction", Vector) = (0,1,0)
        _sunIntensity("Sun Intensity", Float) = 2

        [Header(Ray Scattering Settings)] [Space]
        _rayScaleHeight ("Ray Scale Height", Float) = 40
        _rayScatterCoefficients("Ray Scattering Coefficients", Vector) = (0.1,0.2,0.05)
        _rayIntensity("Ray Intensity", Float) = 5
        _rayInfluence("Ray Influence", Range(0.0, 1.0)) = 1.0

        [Header(Mie Scattering Settings)] [Space]
        _mieScaleHeight ("Mie Scale Height", Float) = 20
        _mieScatterCoefficient("Mie Scattering Coefficients", Float) = 0.1
        _meanCosine("Mean Cosine", Range(-1.0,1.0)) = 0.76
        _mieIntensity("Mie Intensity", Float) = 5
        _mieInfluence("Mie Influence", Range(0.0, 1.0)) = 1.0
     }

     SubShader
     {
        Blend One Zero

        Pass
        {
            Name "AtmosphereTexture"

            CGPROGRAM
            #include "UnityCustomRenderTexture.cginc"

            #pragma vertex CustomRenderTextureVertexShader
            #pragma fragment frag
            #pragma target 3.0


            #define EPSILON 0.0001
            #define PI 3.14159265
            

            //Variables  
            sampler2D _CameraDepthTexture;
            sampler2D _OpticalDepth;
            float4 _OpticalDepth_ST;
            int _samples;
            float _atmosphereRadius;
            float _planetRadius;
            float3 _sunDirection;
            float _sunIntensity;
            float _rayScaleHeight;
            float3 _rayScatterCoefficients;
            float _rayInfluence;
            float _mieScaleHeight;
            float _mieScatterCoefficient;
            float _meanCosine;
            float _mieInfluence;
            float _rayIntensity;
            float _mieIntensity;



            float4 ComputeClipSpacePosition(float2 positionNDC, float deviceDepth)
            {
                float4 positionCS = float4(positionNDC * 2.0 - 1.0, deviceDepth, 1.0);

                return positionCS;
            }

            float3 ComputeWorldSpacePosition(float2 positionNDC, float deviceDepth, float4x4 invViewProjMatrix)
            {
                float4 positionCS = ComputeClipSpacePosition(positionNDC, deviceDepth);
                float4 hpositionWS = mul(invViewProjMatrix, positionCS);
                return hpositionWS.xyz / hpositionWS.w;
            }

            float2 raySphereIntersect(float3 rayOrigin, float3 rayDir, float3 center, float radius) {

                float3 toCenter = center - rayOrigin;

                float a = 1;
                float b = 2 * dot(toCenter, rayDir);
                float c = dot(toCenter, toCenter) - radius * radius;
                float discriminant = b * b - 4 * a * c;

                if (discriminant > 0) {
                    float s = sqrt(discriminant);

                    float dstToSphereNear = max(0, (-b - s) / (2 * a));
                    float dstToSphereFar = (-b + s) / (2 * a);

                    if (dstToSphereFar >= 0) {
                        return float2(dstToSphereNear, dstToSphereFar - dstToSphereNear);
                    }
                }

                return float2(0, 0);
            }

           float2 densityAtPoint(float3 samplePoint, float3 center) {
                float altitude = length(samplePoint - center) - _planetRadius;
                float altitude01 = saturate(max(0, altitude / (_atmosphereRadius - _planetRadius)));

                //return float2(exp(-altitude01 * max(0.001, _rayScaleHeight)), exp(-altitude01 * max(0.001, _mieScaleHeight))) * (1 - altitude01);
                return float2(exp(-altitude / max(0.001, _rayScaleHeight)), exp(-altitude / max(0.001, _mieScaleHeight)));
            }

            float2 opticalDepthBaked(float3 rayOrigin, float3 sunDir, float3 center) {

                float height = length(rayOrigin - center) - _planetRadius;

                float height01 = saturate(height / (_atmosphereRadius - _planetRadius));
                //height01 *= max(0, 1 - height01);

                float angle01 = 1 - (dot(normalize(rayOrigin - center), sunDir) * .5 + .5);

                float2 uv = float2(angle01, height01);

                //float rayDensity = SAMPLE_TEXTURE2D(_OpticalDepth, sampler_OpticalDepth, uv.xy).x;
                //float mieDensity = SAMPLE_TEXTURE2D(_OpticalDepth, sampler_OpticalDepth, uv.yx).y;

                return tex2D(_OpticalDepth, uv.xy).xy * 100;
            }

            float2 opticalDepth(float3 rayOrigin, float3 sunDir, float3 center, float dstThroughAtmosphere) {
                float stepSize = dstThroughAtmosphere / (10.0 - 1);

                float3 samplePoint = rayOrigin;

                float2 lightDepth = float2(0,0);

                for (uint i = 0; i < 10; i++)
                {
                    float2 localDensity = densityAtPoint(samplePoint, center);

                    lightDepth += localDensity * stepSize;

                    samplePoint += sunDir * stepSize;
                }

                return lightDepth;
            }

            float4 getLight(float3 rayOrigin, float3 rayDir, float3 center, float dstToAtmosphere, float dstThroughAtmosphere) {
                float3 dirToSun = -normalize(_sunDirection);

                float stepSize = dstThroughAtmosphere / (float)(_samples - 1);
                float3 samplePoint = rayOrigin + rayDir * dstToAtmosphere;

                float3 totalTransmittanceRay = 0;
                float totalTransmittanceMie = 0;

                float2 depth = 0;
                float2 lightDepth = 0;

                for (int i = 0; i < min(100, _samples); i++)
                {
                    float2 localDensity = densityAtPoint(samplePoint, center) * stepSize;

                    float2 lightDirInfo = raySphereIntersect(samplePoint, dirToSun, center, _atmosphereRadius);
                    float2 lightDirInfoPlanet = raySphereIntersect(samplePoint, dirToSun, center, _planetRadius);

                    float falloff = max(0, min(1, lightDirInfoPlanet.y / (_planetRadius)));

                    float2 localLightDepth = opticalDepth(samplePoint, dirToSun, center, lightDirInfo.y);// *falloff;//opticalDepth(samplePoint, center, dirToSun) * stepSize;
                    //float2 localLightDepth = opticalDepthBaked(samplePoint, dirToSun, center).xy;// / .01;
                    //lightDepth += localLightDepth;

                    depth.x += localDensity.x;// *stepSize* localLightDepth.x;
                    depth.y += localDensity.y;// *stepSize;

                    //if (lightDirInfoPlanet.y <= 0) {
                        float3 transmittanceRay = exp(-(depth.x + localLightDepth.x) * _rayScatterCoefficients);
                        //float3 transmittanceRay = exp(-(depth.x + localLightDepth.x));

                        totalTransmittanceRay += localDensity.x * transmittanceRay;
                    //}

                    //if (lightDirInfoPlanet.y <= 0) {
                        float transmittanceMie = exp(-(depth.y + localLightDepth.y) * _mieScatterCoefficient);
                        //float transmittanceMie = exp(-(depth.y + localLightDepth.y));

                        totalTransmittanceMie += localDensity.y * transmittanceMie;
                    //}

                    samplePoint += rayDir * stepSize;

                }

                return float4(totalTransmittanceRay, totalTransmittanceMie) * stepSize;
            }

            float4 frag(v2f_customrendertexture IN) : COLOR
            {
                float2 uv = 1 - IN.localTexcoord.xy;

                float3 center = mul(unity_ObjectToWorld, float4(0,0,0,1));

                float depth = tex2D(_CameraDepthTexture, IN.localTexcoord.xy);

                depth = lerp(_ProjectionParams.y, _ProjectionParams.z, Linear01Depth(depth));

                //Calculate world space position of current pixel in the render texture
                float3 pixelWorldPos = ComputeWorldSpacePosition(uv, 1, unity_CameraInvProjection);

                float3 viewDir = normalize(pixelWorldPos - _WorldSpaceCameraPos);

                //Calculate the points where the ray hits the atmosphere and where is exits the atmmosphere
                float2 atmosphereHitInfo = raySphereIntersect(_WorldSpaceCameraPos - EPSILON, viewDir, 0, _atmosphereRadius);

                float dstToAtmosphere = atmosphereHitInfo.x + EPSILON;
                float dstThroughAtmosphere = min(atmosphereHitInfo.y, depth - dstToAtmosphere);


                if(dstThroughAtmosphere <= 0) return 0;


                float3 sunDir = normalize(_sunDirection);

                float u = dot(viewDir, sunDir);
                float g = _meanCosine;

                float phaseRay = (3.0 / 16.0 * PI) * (1 + u * u); //Ray Scattering Phase function

                u = dot(viewDir, -sunDir);

                float phaseMie = ((3.0 / 8.0 * PI) * (((1.0 - g * g) * (1.0 + u * u)))) / (((2.0 + g * g) * pow(1.0 + g * g - 2 * g * u, 3.0 / 2.0))); //Mie Scattering Phase function

                float4 transmittance = getLight(_WorldSpaceCameraPos, normalize(viewDir), center, dstToAtmosphere, dstThroughAtmosphere);

                float3 rayTransmittance = transmittance.xyz;
                float mieTransmittance = transmittance.w;

                float3 color = _sunIntensity * (rayTransmittance * phaseRay * (_rayScatterCoefficients.xyz) * _rayInfluence * _rayIntensity 
                    + mieTransmittance * phaseMie * _mieScatterCoefficient * _mieInfluence * _mieIntensity);

                float alpha = dstThroughAtmosphere / (_atmosphereRadius * 2);
                alpha = saturate(length(color));

                return float4(color, alpha);
            }
            ENDCG
        }
    }
}
