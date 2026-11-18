"""止め絵を、画素より細かくゆっくり動かして mp4 にする（音は入れない）。
使い方: python3 kenburns.py 絵.png 秒 出力.mp4"""
import sys, subprocess, math
from PIL import Image
src, T, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
W, H, FPS = 1280, 720, 24
im = Image.open(src).convert('RGB')
iw, ih = im.size
# 画面に収まる最小の倍率を基準に、寄りは 1.0→1.15
base = max(W/iw, H/ih)
def ease(u): return 0.5-0.5*math.cos(math.pi*u)
p = subprocess.Popen(['ffmpeg','-y','-v','error','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-',
  '-c:v','libx264','-preset','slow','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',out], stdin=subprocess.PIPE)
n = round(T*FPS)
for i in range(n):
    u = ease(i/(n-1))
    z = base*(1.0+0.15*u)
    vw, vh = W/z, H/z               # 元絵の中で見える幅と高さ
    cx = (vw/2) + (iw-vw)*(0.30+0.40*u)   # 左寄りから右寄りへ流す
    cy = (vh/2) + (ih-vh)*0.45
    x0, y0 = cx-vw/2, cy-vh/2
    fr = im.transform((W,H), Image.AFFINE, (1/z,0,x0, 0,1/z,y0), resample=Image.BICUBIC)
    p.stdin.write(fr.tobytes())
p.stdin.close(); p.wait()
