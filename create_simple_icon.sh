#!/bin/bash

OUTPUT_DIR="slidey/Assets.xcassets/AppIcon.appiconset"

# Create master icon at high resolution
create_master_icon() {
    local size=1024
    local padding=$((size/40))
    cat > /tmp/icon_master.svg << SVGEOF
<?xml version="1.0" encoding="UTF-8"?>
<svg width="${size}" height="${size}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="grad1" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:rgb(88,86,214);stop-opacity:1" />
      <stop offset="100%" style="stop-color:rgb(255,78,125);stop-opacity:1" />
    </linearGradient>
    <linearGradient id="skyGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:rgb(135,206,250);stop-opacity:1" />
      <stop offset="100%" style="stop-color:rgb(100,149,237);stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="${size}" height="${size}" rx="$((size/5))" fill="url(#grad1)"/>
  
  <!-- Three overlapping photo frames filling edge-to-edge -->
  <g transform="translate($((size/2)),$((size/2)))">
    <!-- Back frame (rotated left) -->
    <g transform="rotate(-18)">
      <rect x="-$((size/2-padding))" y="-$((size*2/5))" width="$((size-padding*2))" height="$((size*4/5))" fill="white" rx="$((size/35))"/>
      <rect x="-$((size/2-padding-size/30))" y="-$((size*2/5-size/30))" width="$((size-padding*2-size/15))" height="$((size*4/5-size/15))" fill="url(#skyGrad)"/>
      <polygon points="-$((size/2-padding-size/30)),$((size*2/5-size/15)) -$((size/4)),-$((size/10)) $((size/6)),$((size/20)) $((size*3/10)),-$((size/20)) $((size/2-padding-size/30)),$((size*2/5-size/15))" fill="#2d5a3d"/>
      <circle cx="$((size/4))" cy="-$((size/6))" r="$((size/14))" fill="#FFD700"/>
    </g>
    
    <!-- Middle frame (rotated right) -->
    <g transform="rotate(15)">
      <rect x="-$((size/2-padding))" y="-$((size*2/5))" width="$((size-padding*2))" height="$((size*4/5))" fill="white" rx="$((size/35))"/>
      <rect x="-$((size/2-padding-size/30))" y="-$((size*2/5-size/30))" width="$((size-padding*2-size/15))" height="$((size*4/5-size/15))" fill="url(#skyGrad)"/>
      <polygon points="-$((size/2-padding-size/30)),$((size*2/5-size/15)) -$((size/4)),-$((size/10)) $((size/6)),$((size/20)) $((size*3/10)),-$((size/20)) $((size/2-padding-size/30)),$((size*2/5-size/15))" fill="#4a7c59"/>
      <circle cx="$((size/4))" cy="-$((size/6))" r="$((size/14))" fill="#FFA500"/>
    </g>
    
    <!-- Front frame (straight) -->
    <g>
      <rect x="-$((size/2-padding))" y="-$((size*2/5))" width="$((size-padding*2))" height="$((size*4/5))" fill="white" rx="$((size/35))"/>
      <rect x="-$((size/2-padding-size/30))" y="-$((size*2/5-size/30))" width="$((size-padding*2-size/15))" height="$((size*4/5-size/15))" fill="url(#skyGrad)"/>
      <polygon points="-$((size/2-padding-size/30)),$((size*2/5-size/15)) -$((size/4)),-$((size/10)) $((size/6)),$((size/20)) $((size*3/10)),-$((size/20)) $((size/2-padding-size/30)),$((size*2/5-size/15))" fill="#3d6e4f"/>
      <circle cx="$((size/4))" cy="-$((size/6))" r="$((size/14))" fill="#FFB347"/>
    </g>
  </g>
</svg>
SVGEOF
    
    # Render at 1024x1024
    qlmanage -t -s 1024 -o /tmp /tmp/icon_master.svg > /dev/null 2>&1
}

# Scale master to target size
scale_icon() {
    local size=$1
    local output=$2
    
    if [ -f "/tmp/icon_master.svg.png" ]; then
        sips -z $size $size "/tmp/icon_master.svg.png" --out "$OUTPUT_DIR/$output" > /dev/null 2>&1
        echo "Generated: $output"
    fi
}

# Create master icon once
create_master_icon

# Scale to all required sizes
scale_icon 16 "icon_16x16.png"
scale_icon 32 "icon_16x16@2x.png"
scale_icon 32 "icon_32x32.png"
scale_icon 64 "icon_32x32@2x.png"
scale_icon 128 "icon_128x128.png"
scale_icon 256 "icon_128x128@2x.png"
scale_icon 256 "icon_256x256.png"
scale_icon 512 "icon_256x256@2x.png"
scale_icon 512 "icon_512x512.png"
scale_icon 1024 "icon_512x512@2x.png"

# Copy for the special 128pt @2x
cp "$OUTPUT_DIR/icon_256x256.png" "$OUTPUT_DIR/icon_256x256 1.png"

# Cleanup
rm -f /tmp/icon_master.svg /tmp/icon_master.svg.png

echo "Icon generation complete!"
