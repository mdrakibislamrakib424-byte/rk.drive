#!/bin/bash
echo "Starting update extraction..."

# 1. Zip file ta temporary folder-e extract kori
mkdir -p temp_extracted
unzip -o RK_Drive_Phase2_update.zip -d temp_extracted/

# 2. Folder structure create kori (jodi na thake)
mkdir -p scripts/world
mkdir -p shaders
mkdir -p data/places

# 3. File gulo sothik jaygay copy/replace kori
# --- Root files ---
[ -f "temp_extracted/main.tscn" ] && cp -f temp_extracted/main.tscn ./ && echo "Updated: main.tscn"
[ -f "temp_extracted/project.godot" ] && cp -f temp_extracted/project.godot ./ && echo "Updated: project.godot"

# --- Scripts world files ---
[ -f "temp_extracted/scripts/world/place_data.gd" ] && cp -f temp_extracted/scripts/world/place_data.gd scripts/world/ && echo "Updated: place_data.gd"
[ -f "temp_extracted/scripts/world/world_manager.gd" ] && cp -f temp_extracted/scripts/world/world_manager.gd scripts/world/ && echo "Updated: world_manager.gd"
[ -f "temp_extracted/scripts/world/road_layout.gd" ] && cp -f temp_extracted/scripts/world/road_layout.gd scripts/world/ && echo "Updated: road_layout.gd"
[ -f "temp_extracted/scripts/world/road_builder.gd" ] && cp -f temp_extracted/scripts/world/road_builder.gd scripts/world/ && echo "Updated: road_builder.gd"
[ -f "temp_extracted/scripts/world/ground_builder.gd" ] && cp -f temp_extracted/scripts/world/ground_builder.gd scripts/world/ && echo "Added/Updated: ground_builder.gd (Notun)"

# --- Scripts files ---
[ -f "temp_extracted/scripts/pause_menu.gd" ] && cp -f temp_extracted/scripts/pause_menu.gd scripts/ && echo "Updated: pause_menu.gd"
[ -f "temp_extracted/scripts/follow_camera.gd" ] && cp -f temp_extracted/scripts/follow_camera.gd scripts/ && echo "Added/Updated: follow_camera.gd (Notun)"
[ -f "temp_extracted/scripts/touch_controls.gd" ] && cp -f temp_extracted/scripts/touch_controls.gd scripts/ && echo "Added/Updated: touch_controls.gd (Notun)"
[ -f "temp_extracted/scripts/hud.gd" ] && cp -f temp_extracted/scripts/hud.gd scripts/ && echo "Added/Updated: hud.gd (Notun)"

# --- Shaders files ---
[ -f "temp_extracted/shaders/sky_blend.gdshader" ] && cp -f temp_extracted/shaders/sky_blend.gdshader shaders/ && echo "Updated: sky_blend.gdshader"
[ -f "temp_extracted/shaders/terrain.gdshader" ] && cp -f temp_extracted/shaders/terrain.gdshader shaders/ && echo "Updated: terrain.gdshader"

# --- Data places files ---
[ -f "temp_extracted/data/places/forest.tres" ] && cp -f temp_extracted/data/places/forest.tres data/places/ && echo "Updated: forest.tres"

# 4. Cleanup temporary folder
rm -rf temp_extracted
echo "All files updated and organized successfully!"
