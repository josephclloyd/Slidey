#!/usr/bin/env python3

from PIL import Image, ImageDraw
import os

def generate_icon(size):
    # Create image with gradient background
    img = Image.new('RGB', (size, size))
    draw = ImageDraw.Draw(img)

    # Draw gradient background (blue to purple)
    for y in range(size):
        ratio = y / size
        r = int(51 + ratio * (102 - 51))
        g = int(102 - ratio * (102 - 51))
        b = int(204 - ratio * (204 - 178))
        draw.line([(0, y), (size, y)], fill=(r, g, b))

    # Draw three overlapping photo frames
    frame_width = int(size * 0.5)
    frame_height = int(frame_width * 0.75)
    frame_thickness = max(2, int(size * 0.02))

    def draw_photo_frame(x, y, rotation=0):
        # Create a temporary image for the frame
        frame_img = Image.new('RGBA', (frame_width + 20, frame_height + 20), (0, 0, 0, 0))
        frame_draw = ImageDraw.Draw(frame_img)

        offset = 10
        # White frame border
        frame_draw.rectangle(
            [offset, offset, offset + frame_width, offset + frame_height],
            fill='white',
            outline='white'
        )

        # Dark image area
        frame_draw.rectangle(
            [offset + frame_thickness, offset + frame_thickness,
             offset + frame_width - frame_thickness, offset + frame_height - frame_thickness],
            fill=(76, 76, 76),
            outline=(76, 76, 76)
        )

        # Draw simple mountain shape
        img_x = offset + frame_thickness
        img_y = offset + frame_thickness
        img_w = frame_width - 2 * frame_thickness
        img_h = frame_height - 2 * frame_thickness

        mountain = [
            (img_x, img_y + img_h),
            (img_x + img_w * 0.3, img_y + img_h * 0.4),
            (img_x + img_w * 0.5, img_y + img_h * 0.7),
            (img_x + img_w * 0.7, img_y + img_h * 0.5),
            (img_x + img_w, img_y + img_h)
        ]
        frame_draw.polygon(mountain, fill=(128, 128, 128))

        # Draw sun/moon
        sun_radius = int(img_w * 0.12)
        sun_x = img_x + img_w * 0.75 - sun_radius
        sun_y = img_y + img_h * 0.25 - sun_radius
        frame_draw.ellipse(
            [sun_x, sun_y, sun_x + sun_radius * 2, sun_y + sun_radius * 2],
            fill=(178, 178, 178)
        )

        # Rotate if needed
        if rotation != 0:
            frame_img = frame_img.rotate(rotation, expand=False)

        # Paste onto main image
        img.paste(frame_img, (x - 10, y - 10), frame_img)

    # Draw frames at different positions with slight rotations
    center_x = size // 2
    center_y = size // 2

    draw_photo_frame(int(center_x - frame_width * 0.2), int(center_y - frame_height * 0.15), -8)
    draw_photo_frame(int(center_x - frame_width * 0.1), int(center_y - frame_height * 0.1), 6)
    draw_photo_frame(center_x - frame_width // 2, center_y - frame_height // 2, 0)

    return img

# Generate all required sizes
sizes = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

output_path = "slidey/Assets.xcassets/AppIcon.appiconset"

for filename, size in sizes:
    icon = generate_icon(size)
    filepath = os.path.join(output_path, filename)
    icon.save(filepath, 'PNG')
    print(f"Generated: {filename}")

print("Icon generation complete!")
