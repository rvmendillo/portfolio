from pathlib import Path
from PIL import Image, ImageDraw

out = Path(__file__).parent / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
out.parent.mkdir(parents=True, exist_ok=True)
im = Image.new("RGB", (1024, 1024), (45, 34, 95))
d = ImageDraw.Draw(im)
d.rounded_rectangle((110, 110, 914, 914), radius=215, fill=(59, 48, 132), outline=(205, 190, 255), width=18)
d.polygon([(280,655),(468,467),(414,413),(226,601)], fill=(255,255,255))
d.rounded_rectangle((420,240,730,420), radius=46, fill=(255,255,255))
d.rounded_rectangle((510,378,618,730), radius=39, fill=(255,255,255))
d.polygon([(616,620),(796,800),(724,872),(544,692)], fill=(255,255,255))
im.save(out)
