"""Generate the app's own geometric artwork; no third-party photos or fonts ship."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont, ImageOps

root = Path(__file__).resolve().parents[1]
SKY, INK, ICE, GOLD = '#73d7ff', '#073b4b', '#e9f8ff', '#ffce86'

def symbol(draw, origin, scale):
    x, y = origin
    def box(values): return tuple((x if i % 2 == 0 else y) + v * scale for i, v in enumerate(values))
    def points(values): return [(x+a*scale,y+b*scale) for a,b in values]
    draw.rounded_rectangle(box((24,29,76,78)), radius=7*scale, fill=ICE)
    draw.polygon(points([(30,70),(43,49),(53,61),(61,52),(71,70)]), fill=INK)
    draw.ellipse(box((57,25,79,47)), fill=GOLD, outline=INK, width=round(3*scale))
    draw.line(points([(76,44),(84,52)]), fill=INK, width=round(5*scale))

def icon(size):
    image = Image.new('RGB',(size*4,size*4),SKY)
    symbol(ImageDraw.Draw(image),(0,0),size*4/108)
    return image.resize((size,size),Image.Resampling.LANCZOS)

# A full square for Play; Android applies the adaptive icon's system mask.
icon_image=icon(512)
for locale in ['en-US','zh-CN']:
    folder=root/'fastlane/metadata/android'/locale/'images'
    folder.mkdir(parents=True,exist_ok=True);icon_image.save(folder/'icon.png')

feature=Image.new('RGB',(1024*2,500*2),INK);d=ImageDraw.Draw(feature)
def font(path,size):
    return ImageFont.truetype(path,size*2)
sans='/System/Library/Fonts/Supplemental/Arial.ttf'
serif='/System/Library/Fonts/Supplemental/Georgia Bold.ttf'
d.text((64*2,50*2),'AI Gallery',font=font(sans,28),fill=SKY)
d.text((60*2,126*2),'Find that photo.',font=font(serif,58),fill=ICE)
d.text((64*2,220*2),'Search your gallery',font=font(sans,30),fill=ICE)
d.text((64*2,260*2),'in your own words.',font=font(sans,30),fill=ICE)
d.text((64*2,394*2),'ON-DEVICE PHOTO SEARCH',font=font(sans,17),fill=GOLD)
# The lens doubles as the sun in a framed landscape: photo search in one mark.
d.rounded_rectangle((696*2,90*2,970*2,392*2),radius=36*2,fill=SKY)
symbol(d,(675*2,82*2),5)
feature=feature.resize((1024,500),Image.Resampling.LANCZOS)
for locale in ['en-US','zh-CN']:
    feature.save(root/'fastlane/metadata/android'/locale/'images/featureGraphic.png')

# Demo gallery illustrations for screenshots. They are never app runtime data.
folder=root/'assets/branding/demo';folder.mkdir(exist_ok=True)
for index in range(12):
    image=Image.new('RGB',(720,720),['#bbe5f6','#e7f2e9','#fce8ce','#f2d9c9','#213854','#dcecd9'][index%6]);draw=ImageDraw.Draw(image)
    kind=index%6
    if kind==0:
        draw.ellipse((470,60,610,200),fill=GOLD);draw.rectangle((0,330,720,720),fill='#1a98ac')
        draw.polygon([(0,570),(720,420),(720,720),(0,720)],fill='#ffe0ab')
        for y in [370,410,450]:draw.arc((-80,y-20,800,y+80),0,180,fill=ICE,width=9)
    elif kind==1:
        draw.polygon([(0,610),(235,180),(500,610)],fill='#267c76');draw.polygon([(240,610),(500,255),(720,610)],fill='#46978b')
        draw.polygon([(185,270),(235,180),(292,274),(250,256),(222,276)],fill=ICE);draw.rectangle((0,610,720,720),fill='#123e4b')
    elif kind==2:
        draw.ellipse((110,110,610,610),fill='#fff9ed')
        for a in range(16):
            cx=360+165*math.cos(a*math.tau/16);cy=360+165*math.sin(a*math.tau/16)
            draw.ellipse((cx-56,cy-56,cx+56,cy+56),fill='#bd7138')
        draw.ellipse((190,190,530,530),fill='#e5a657',outline='#98592e',width=13)
        draw.rounded_rectangle((260,260,460,460),radius=24,outline='#98592e',width=14)
        draw.line((290,360,430,360),fill='#98592e',width=13);draw.line((360,290,360,430),fill='#98592e',width=13)
    elif kind==3:
        draw.polygon([(195,260),(208,100),(320,224),(420,224),(525,100),(540,270)],fill='#a56143')
        draw.ellipse((175,215,555,600),fill='#a56143')
        draw.ellipse((262,350,286,390),fill=INK);draw.ellipse((438,350,462,390),fill=INK)
        draw.polygon([(340,420),(380,420),(360,444)],fill='#ffc9b1')
    elif kind==4:
        draw.ellipse((440,65,620,245),fill='#fff1bf')
        for x,h in [(40,290),(190,410),(345,240),(495,350),(625,270)]:
            draw.rectangle((x,720-h,x+110,720),fill='#0c202f')
            for xx in range(x+20,x+95,32):
                for yy in range(740-h,690,55):draw.rectangle((xx,yy,xx+10,yy+19),fill=GOLD)
    else:
        draw.polygon([(235,470),(485,470),(450,665),(270,665)],fill='#cf8666')
        draw.line((360,490,360,160),fill='#256c59',width=20)
        for x,y in [(250,230),(365,295),(250,370),(365,135)]:draw.ellipse((x,y,x+120,y+175),fill='#378a64')
    if index >= 6:
        image=ImageOps.mirror(Image.blend(image,Image.new('RGB',image.size,'#f4b6b6'),0.06));draw=ImageDraw.Draw(image)
    draw.rounded_rectangle((25,25,156,70),radius=12,fill=ICE)
    draw.text((44,30),'DEMO',font=font(sans,16),fill=INK)
    image.resize((360,360),Image.Resampling.LANCZOS).save(folder/f'{index:02}.png')
print('Generated store icon, feature graphic and 12 labelled demo illustrations.')
