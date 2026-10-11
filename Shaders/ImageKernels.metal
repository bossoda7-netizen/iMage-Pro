#include <CoreImage/CoreImage.h>
using namespace metal;

float2 warpCubic(float2 a,float2 b,float2 c,float2 d,float t) {
  return 0.5*((2.0*b)+(-a+c)*t+(2.0*a-5.0*b+4.0*c-d)*t*t+(-a+3.0*b-3.0*c+d)*t*t*t);
}
float2 warpRow(thread float2* q,int n,int x,int y) {
  if(x<0) return 2.0*q[y*n]-q[y*n+1];
  if(x>=n) return 2.0*q[y*n+n-1]-q[y*n+n-2];
  return q[y*n+x];
}
float2 warpNode(thread float2* q,int n,int x,int y) {
  if(y<0) return 2.0*warpRow(q,n,x,0)-warpRow(q,n,x,1);
  if(y>=n) return 2.0*warpRow(q,n,x,n-1)-warpRow(q,n,x,n-2);
  return warpRow(q,n,x,y);
}
float2 warpSurface(thread float2* q,int n,float2 uv) {
  float2 p=uv*float(n-1);int x=clamp(int(floor(p.x)),0,n-2),y=clamp(int(floor(p.y)),0,n-2);
  float2 row[4];
  for(int i=0;i<4;i++) row[i]=warpCubic(warpNode(q,n,x-1,y+i-1),warpNode(q,n,x,y+i-1),warpNode(q,n,x+1,y+i-1),warpNode(q,n,x+2,y+i-1),p.x-float(x));
  return warpCubic(row[0],row[1],row[2],row[3],p.y-float(y));
}

float grainHash(int2 p,uint seed) {
  uint h=uint(p.x)*0x8da6b343u ^ uint(p.y)*0xd8163841u ^ seed;
  h^=h>>16;h*=0x7feb352du;h^=h>>15;h*=0x846ca68bu;h^=h>>16;
  return float(h & 0x00ffffffu)/16777216.0;
}
float grainGaussian(int2 p,uint seed) {
  float u=max(0.00001,grainHash(p,seed));
  return sqrt(-2.0*log(u))*cos(6.2831853*grainHash(p,seed+7919u));
}
float grainNoise(float2 p,uint seed) {
  int2 cell=int2(floor(p));float2 t=fract(p);t=t*t*(3.0-2.0*t);
  float a=grainGaussian(cell,seed),b=grainGaussian(cell+int2(1,0),seed),c=grainGaussian(cell+int2(0,1),seed),d=grainGaussian(cell+int2(1,1),seed);
  float variance=dot(float2(1.0-t.x,t.x),float2(1.0-t.x,t.x))*dot(float2(1.0-t.y,t.y),float2(1.0-t.y,t.y));
  return mix(mix(a,b,t.x),mix(c,d,t.x),t.y)/sqrt(max(variance,0.01))*0.3;
}
extern "C" { namespace coreimage {
float4 filmGrain(sample_t image,float size,float strength,float colored,float style,float scale,destination dest) {
  float4 c=unpremultiply(image);float2 p=dest.coord()/scale/max(size,0.5);
  // Three restrained photographic patterns: fine, clumped and coarse.
  float n;
  if(style < 0.5) n=grainNoise(p*1.8,73u)*0.82+grainNoise(p*5.7+float2(13.3,7.1),179u)*0.18;
  else if(style < 1.5) n=grainNoise(p*0.72,307u)*0.68+grainNoise(p*3.1+float2(7.1,19.3),179u)*0.32;
  else if(style < 2.5) n=(grainNoise(p*1.6,911u)-grainNoise(p*0.42,911u)*0.35)*0.86+grainNoise(p*6.8+float2(21.3,3.7),179u)*0.14;
  else n=grainNoise(p*2.8,1777u)*0.55+grainNoise(p*11.0+float2(3.1,17.7),1979u)*0.45;
  float l=dot(c.rgb,float3(0.2126,0.7152,0.0722));
  float response=0.3+0.7*sqrt(clamp(l*(1.0-l)*4.0,0.0,1.0));
  float3 noise=float3(n);
  if(colored>0.5) {
    // Keep the colour grain visibly separated without contaminating alpha.
    float3 chroma=float3(grainNoise(p*1.23,991u),grainNoise(p*1.37,1979u),grainNoise(p*1.51,2971u));
    noise += chroma*0.92;
  }
  c.rgb=clamp(c.rgb+noise*strength*response,0.0,1.0);return premultiply(c);
}
float4 specialBlend(sample_t src, sample_t dst, float mode) {
  float4 s = unpremultiply(src); float4 d = unpremultiply(dst);
  float3 b;
  if (mode < 0.5) b = step(float3(1.0),s.rgb+d.rgb);
  else if (mode < 1.5) b = dot(s.rgb,float3(1.0)) < dot(d.rgb,float3(1.0)) ? s.rgb : d.rgb;
  else b = dot(s.rgb,float3(1.0)) > dot(d.rgb,float3(1.0)) ? s.rgb : d.rgb;
  float a = s.a+d.a-s.a*d.a;
  return float4((1.0-s.a)*dst.rgb+(1.0-d.a)*src.rgb+s.a*d.a*b,a);
}
float4 dissolve(sample_t src, destination dest) {
  float2 p = floor(dest.coord());
  float noise = fract(sin(dot(p,float2(12.9898,78.233)))*43758.5453);
  float4 c = unpremultiply(src);
  return noise < src.a ? float4(c.rgb,1.0) : float4(0.0);
}
float4 contourBevel(sample_t image, sample_t left, sample_t right, sample_t up, sample_t down,
  float depth, float3 light, float3 highlight, float amount) {
  float4 c = unpremultiply(image);
  float3 normal = normalize(float3((left.r-right.r)*depth,(down.r-up.r)*depth,1.0));
  float delta = clamp(dot(normal,light)-light.z,-1.0,1.0)*amount;
  c.rgb = delta > 0.0 ? mix(c.rgb,highlight,delta) : c.rgb*(1.0+delta);
  return premultiply(c);
}
// Detected joint coordinates are normalized in top-left image space.
float2 poseBody(float2 size,float2 origin,float2 sl,float2 sr,float2 hl,float2 hr,float2 lk,float2 rk,float2 la,float2 ra,float validLegs,float slim,float waist,float shoulder,float legs,destination dest) {
  float2 uv=float2((dest.coord().x-origin.x)/size.x,1.0-(dest.coord().y-origin.y)/size.y);
  float2 sc=(sl+sr)*0.5,hc=(hl+hr)*0.5;
  float span=max(length(sr-sl),0.03);
  float2 axis=normalize(sr-sl),normal=float2(-axis.y,axis.x);
  if(normal.y<0.0) normal=-normal;
  float2 torso=(sc+hc)*0.5;
  float torsoLength=max(length(hc-sc),span*0.5);
  float2 td=uv-torso;
  float tx=dot(td,axis)/(span*0.6),ty=dot(td,normal)/(torsoLength*0.6);
  float torsoMask=exp(-tx*tx*3.0-ty*ty*2.0);
  float2 wc=mix(sc,hc,0.72),wd=uv-wc;
  float waistMask=exp(-pow(dot(wd,axis)/(span*0.52),2.0)*3.0-pow(dot(wd,normal)/(torsoLength*0.24),2.0)*3.0);
  float2 sd=uv-sc;
  float shoulderX=dot(sd,axis);
  // Weight each shoulder around its detected joint. This follows the body
  // structure rather than the shirt silhouette and fades before the arms.
  float2 slv=uv-sl,srv=uv-sr;
  float shoulderMaskL=exp(-dot(slv,slv)/(span*span*0.012));
  float shoulderMaskR=exp(-dot(srv,srv)/(span*span*0.012));
  float shoulderMask=max(shoulderMaskL,shoulderMaskR);
  uv+=axis*(dot(td,axis)*clamp(slim,-1.0,1.0)*0.20*torsoMask+dot(wd,axis)*clamp(waist,-1.0,1.0)*0.25*waistMask+shoulderX*clamp(shoulder,-1.0,1.0)*0.20*shoulderMask);
  if(validLegs>0.5) {
    float2 ankle[2]={la,ra},hip[2]={hl,hr};
    float2 original=uv,offset=float2(0.0);
    float totalWeight=0.0;
    float stretch=1.0+clamp(legs,-1.0,1.0)*0.24;
    for(int i=0;i<2;i++) {
      float2 leg=ankle[i]-hip[i];
      float directionLength=dot(leg,leg);
      float t=dot(original-hip[i],leg)/max(directionLength,0.001);
      float2 nearest=hip[i]+leg*t;
      float width=max(span*0.24,0.035);
      float lateral=exp(-dot(original-nearest,original-nearest)/(width*width));
      float influence=smoothstep(0.0,0.06,t)*(1.0-smoothstep(stretch,stretch+0.45,t));
      float sourceT=t/stretch;
      // Inverse length mapping fixes each hip and moves the knee and ankle.
      // The foot continues with the same displacement, then fades into the background.
      float difference=t<=stretch ? t-sourceT : stretch-1.0;
      float weight=lateral*influence;
      offset+=leg*difference*weight;totalWeight+=weight;
    }
    uv-=offset/max(1.0,totalWeight);
  }

  return float2(uv.x*size.x,(1.0-uv.y)*size.y)+origin;
}
float2 waveDistortion(float amplitude,float wavelength,float angle,float phase,destination dest) {
  float2 axis=float2(cos(angle),sin(angle)),normal=float2(-axis.y,axis.x);
  float2 p=dest.coord();return p+normal*(amplitude*sin(dot(p,axis)*6.2831853/wavelength+phase));
}
float4 mesh(float2 size, float spread, float4 p0, float4 c0, float4 p1, float4 c1, float4 p2, float4 c2, float4 p3, float4 c3, float4 p4, float4 c4, float4 p5, float4 c5, float4 p6, float4 c6, float4 p7, float4 c7, float4 p8, float4 c8, float4 p9, float4 c9, float4 p10, float4 c10, float4 p11, float4 c11, float4 p12, float4 c12, float4 p13, float4 c13, float4 p14, float4 c14, float4 p15, float4 c15, destination dest) {
  float2 uv = float2(dest.coord().x/size.x,1.0-dest.coord().y/size.y);
  float4 color = float4(0.0); float sum = 0.0;
  if (p0.z > 0.5) { float2 d = uv-p0.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c0*w; sum += w; }
if (p1.z > 0.5) { float2 d = uv-p1.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c1*w; sum += w; }
if (p2.z > 0.5) { float2 d = uv-p2.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c2*w; sum += w; }
if (p3.z > 0.5) { float2 d = uv-p3.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c3*w; sum += w; }
if (p4.z > 0.5) { float2 d = uv-p4.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c4*w; sum += w; }
if (p5.z > 0.5) { float2 d = uv-p5.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c5*w; sum += w; }
if (p6.z > 0.5) { float2 d = uv-p6.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c6*w; sum += w; }
if (p7.z > 0.5) { float2 d = uv-p7.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c7*w; sum += w; }
if (p8.z > 0.5) { float2 d = uv-p8.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c8*w; sum += w; }
if (p9.z > 0.5) { float2 d = uv-p9.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c9*w; sum += w; }
if (p10.z > 0.5) { float2 d = uv-p10.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c10*w; sum += w; }
if (p11.z > 0.5) { float2 d = uv-p11.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c11*w; sum += w; }
if (p12.z > 0.5) { float2 d = uv-p12.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c12*w; sum += w; }
if (p13.z > 0.5) { float2 d = uv-p13.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c13*w; sum += w; }
if (p14.z > 0.5) { float2 d = uv-p14.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c14*w; sum += w; }
if (p15.z > 0.5) { float2 d = uv-p15.xy; float w = exp(-dot(d,d)*spread)+0.00001; color += c15*w; sum += w; }
  return premultiply(color/sum);
}
float2 warp(float2 size, float2 p0, float2 p1, float2 p2, float2 p3, float2 p4, float2 p5, float2 p6, float2 p7, float2 p8, destination dest) {
  float2 pos=float2(dest.coord().x/size.x,1.0-dest.coord().y/size.y);
  { float2 a=p0, b=p1-a, c=p3-a, d=p4-p1-p3+a;
      float2 uv=float2(0.5); for(int i=0;i<6;i++) {
        float2 error=a+b*uv.x+c*uv.y+d*uv.x*uv.y-pos;
        float2 du=b+d*uv.y, dv=c+d*uv.x; float determinant=du.x*dv.y-du.y*dv.x;
        if(abs(determinant)>0.000001) uv-=float2((error.x*dv.y-error.y*dv.x)/determinant,(du.x*error.y-du.y*error.x)/determinant);
      }
      if(uv.x>=0.0 && uv.x<=1.0 && uv.y>=0.0 && uv.y<=1.0) {
        float2 source=(uv+float2(0.0,0.0))*0.5;
        return float2(source.x*size.x,(1.0-source.y)*size.y);
      }
    }
{ float2 a=p1, b=p2-a, c=p4-a, d=p5-p2-p4+a;
      float2 uv=float2(0.5); for(int i=0;i<6;i++) {
        float2 error=a+b*uv.x+c*uv.y+d*uv.x*uv.y-pos;
        float2 du=b+d*uv.y, dv=c+d*uv.x; float determinant=du.x*dv.y-du.y*dv.x;
        if(abs(determinant)>0.000001) uv-=float2((error.x*dv.y-error.y*dv.x)/determinant,(du.x*error.y-du.y*error.x)/determinant);
      }
      if(uv.x>=0.0 && uv.x<=1.0 && uv.y>=0.0 && uv.y<=1.0) {
        float2 source=(uv+float2(1.0,0.0))*0.5;
        return float2(source.x*size.x,(1.0-source.y)*size.y);
      }
    }
{ float2 a=p3, b=p4-a, c=p6-a, d=p7-p4-p6+a;
      float2 uv=float2(0.5); for(int i=0;i<6;i++) {
        float2 error=a+b*uv.x+c*uv.y+d*uv.x*uv.y-pos;
        float2 du=b+d*uv.y, dv=c+d*uv.x; float determinant=du.x*dv.y-du.y*dv.x;
        if(abs(determinant)>0.000001) uv-=float2((error.x*dv.y-error.y*dv.x)/determinant,(du.x*error.y-du.y*error.x)/determinant);
      }
      if(uv.x>=0.0 && uv.x<=1.0 && uv.y>=0.0 && uv.y<=1.0) {
        float2 source=(uv+float2(0.0,1.0))*0.5;
        return float2(source.x*size.x,(1.0-source.y)*size.y);
      }
    }
{ float2 a=p4, b=p5-a, c=p7-a, d=p8-p5-p7+a;
      float2 uv=float2(0.5); for(int i=0;i<6;i++) {
        float2 error=a+b*uv.x+c*uv.y+d*uv.x*uv.y-pos;
        float2 du=b+d*uv.y, dv=c+d*uv.x; float determinant=du.x*dv.y-du.y*dv.x;
        if(abs(determinant)>0.000001) uv-=float2((error.x*dv.y-error.y*dv.x)/determinant,(du.x*error.y-du.y*error.x)/determinant);
      }
      if(uv.x>=0.0 && uv.x<=1.0 && uv.y>=0.0 && uv.y<=1.0) {
        float2 source=(uv+float2(1.0,1.0))*0.5;
        return float2(source.x*size.x,(1.0-source.y)*size.y);
      }
    }

  return float2(-100000.0);
}

float2 smoothWarp(float2 size,float dimension,float2 p0, float2 p1, float2 p2, float2 p3, float2 p4, float2 p5, float2 p6, float2 p7, float2 p8, float2 p9, float2 p10, float2 p11, float2 p12, float2 p13, float2 p14, float2 p15, float2 p16, float2 p17, float2 p18, float2 p19, float2 p20, float2 p21, float2 p22, float2 p23, float2 p24, float2 p25, float2 p26, float2 p27, float2 p28, float2 p29, float2 p30, float2 p31, float2 p32, float2 p33, float2 p34, float2 p35, float2 p36, float2 p37, float2 p38, float2 p39, float2 p40, float2 p41, float2 p42, float2 p43, float2 p44, float2 p45, float2 p46, float2 p47, float2 p48, float2 p49, float2 p50, float2 p51, float2 p52, float2 p53, float2 p54, float2 p55, float2 p56, float2 p57, float2 p58, float2 p59, float2 p60, float2 p61, float2 p62, float2 p63, float2 p64, float2 p65, float2 p66, float2 p67, float2 p68, float2 p69, float2 p70, float2 p71, float2 p72, float2 p73, float2 p74, float2 p75, float2 p76, float2 p77, float2 p78, float2 p79, float2 p80,destination dest) {
  float2 nodes[81]={p0,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12,p13,p14,p15,p16,p17,p18,p19,p20,p21,p22,p23,p24,p25,p26,p27,p28,p29,p30,p31,p32,p33,p34,p35,p36,p37,p38,p39,p40,p41,p42,p43,p44,p45,p46,p47,p48,p49,p50,p51,p52,p53,p54,p55,p56,p57,p58,p59,p60,p61,p62,p63,p64,p65,p66,p67,p68,p69,p70,p71,p72,p73,p74,p75,p76,p77,p78,p79,p80};int n=int(dimension);
  float2 pos=float2(dest.coord().x/size.x,1.0-dest.coord().y/size.y);
  float2 uv=clamp(pos,float2(0.0),float2(1.0));float best=length(warpSurface(nodes,n,uv)-pos);
  for(int y=0;y<n;y++) for(int x=0;x<n;x++) {
    float2 seed=float2(x,y)/float(n-1);float error=length(nodes[y*n+x]-pos);
    if(error<best) {best=error;uv=seed;}
  }
  for(int i=0;i<32;i++) {
    float2 p=warpSurface(nodes,n,uv),error=p-pos;
    if(length(error)<0.00001) break;
    float2 du=(warpSurface(nodes,n,uv+float2(0.0003,0.0))-p)/0.0003;
    float2 dv=(warpSurface(nodes,n,uv+float2(0.0,0.0003))-p)/0.0003;
    float determinant=du.x*dv.y-du.y*dv.x;
    if(abs(determinant)<0.00000001) return float2(-100000.0);
    float2 step=float2((error.x*dv.y-error.y*dv.x)/determinant,(du.x*error.y-du.y*error.x)/determinant);
    float factor=1.0;
    for(int j=0;j<8;j++) {if(length(warpSurface(nodes,n,uv-step*factor)-pos)<length(error)) break;factor*=0.5;}
    uv-=step*factor;
    if(any(abs(uv)>float2(4.0))) return float2(-100000.0);
  }
  if(any(uv<float2(-0.00001))||any(uv>float2(1.00001))||length(warpSurface(nodes,n,uv)-pos)>0.0001) return float2(-100000.0);
  return float2(uv.x*size.x,(1.0-uv.y)*size.y);
}
}}
