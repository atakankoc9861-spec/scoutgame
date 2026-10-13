"""Mağaza fragmanı: video2-4 + key art kapanış. trailer.py <kaynak> <çıktı klasörü>"""
import subprocess, sys
S = sys.argv[1] if len(sys.argv) > 1 else "/home/claude/scout_assets_in"
O = sys.argv[2] if len(sys.argv) > 2 else "/home/claude/trailer"
F = "/home/claude/scout/fonts/Oswald-Bold.ttf"
FR = "/home/claude/scout/fonts/Oswald-Regular.ttf"
M = "/home/claude/scout/audio/menu.ogg"
TX = {"tr": ["Her yetenek bir hikâye.", "Dosyaları sen tutarsın.", "Bir sonraki yıldızı sen bul.", "SCOUT KARİYERİ", "Yakında Google Play’de"],
      "en": ["Every talent has a story.", "You keep the files.", "Find the next star.", "SCOUT CAREER", "Coming soon to Google Play"]}
def cap(i, txt, dur):
    return (f"[{i}:v]trim=0:{dur},setpts=PTS-STARTPTS,fps=24,scale=1280:720,format=yuv420p,"
            f"drawtext=fontfile={F}:text='{txt}':fontcolor=white:fontsize=56:x=(w-tw)/2:y=h-140:"
            f"alpha='if(lt(t,1.5),0,if(lt(t,2.5),t-1.5,if(lt(t,{dur-2}),1,max(0,{dur-1}-t))))':shadowcolor=black@0.6:shadowx=2:shadowy=2")
for L, t in TX.items():
    X = "(w*0.72-tw/2)"
    fc = ";".join([cap(0, t[0], 10) + "[a]", cap(1, t[1], 12) + "[b]", cap(2, t[2], 13) + "[c]",
        f"[3:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,fps=24,format=yuv420p,eq=brightness=-0.1,"
        f"drawtext=fontfile={F}:text='GÖZCÜ':fontcolor=0xF1E6CF:fontsize=140:x={X}:y=(h-th)/2-70:alpha='min(1,t/0.8)',"
        f"drawtext=fontfile={FR}:text='{t[3]}':fontcolor=0xC9A24A:fontsize=44:x={X}:y=(h/2)+50:alpha='min(1,max(0,(t-0.6)/0.8))',"
        f"drawtext=fontfile={FR}:text='{t[4]}':fontcolor=white:fontsize=32:x={X}:y=(h/2)+115:alpha='min(1,max(0,(t-1.2)/0.8))'[d]",
        "[a][b]xfade=transition=fade:duration=1:offset=9[ab]", "[ab][c]xfade=transition=fade:duration=1:offset=20[abc]",
        "[abc][d]xfade=transition=fadeblack:duration=1:offset=32[v]",
        "[4:a]atrim=0:37,asetpts=PTS-STARTPTS,afade=t=in:d=1.5,afade=t=out:st=34:d=3,volume=0.9[mu]",
        "[1:a]atrim=0:12,asetpts=PTS-STARTPTS,adelay=9000|9000,volume=0.35[a1]",
        "[2:a]atrim=0:13,asetpts=PTS-STARTPTS,adelay=20000|20000,volume=0.35[a2]",
        "[mu][a1][a2]amix=inputs=3:duration=first:normalize=0[au]"])
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", f"{S}/video2.mp4", "-i", f"{S}/video3.mp4", "-i", f"{S}/video4.mp4",
           "-loop", "1", "-t", "5", "-i", f"{S}/key_art.jpg", "-i", M, "-filter_complex", fc, "-map", "[v]", "-map", "[au]",
           "-t", "37", "-c:v", "libx264", "-crf", "19", "-preset", "medium", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k",
           "-movflags", "+faststart", f"{O}/trailer_{L}.mp4"]
    subprocess.run(cmd, check=True)
    print("ok", L)
