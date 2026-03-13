#!/usr/bin/env python3
"""Fix town.tscn: scale GLB models to match collision boxes, fix Y-positions, apply materials."""

import struct
import json
import re
import os
import sys

# ============================================================
# 1. Read GLB bounding boxes
# ============================================================

def get_glb_bounds(path):
    """Read GLB file and return bounding box info."""
    try:
        with open(path, 'rb') as f:
            magic, version, length = struct.unpack('<III', f.read(12))
            if magic != 0x46546C67:
                return None
            chunk_len, chunk_type = struct.unpack('<II', f.read(8))
            json_data = json.loads(f.read(chunk_len).decode('utf-8'))
            for mesh in json_data.get('meshes', []):
                for prim in mesh.get('primitives', []):
                    pos_idx = prim.get('attributes', {}).get('POSITION')
                    if pos_idx is not None:
                        acc = json_data['accessors'][pos_idx]
                        mn = acc.get('min', [0, 0, 0])
                        mx = acc.get('max', [0, 0, 0])
                        return {
                            'min': mn, 'max': mx,
                            'size': [mx[0]-mn[0], mx[1]-mn[1], mx[2]-mn[2]]
                        }
    except Exception as e:
        print(f"  WARNING: Could not read {path}: {e}")
    return None

# ============================================================
# 2. Define building/prop → GLB + collision box mappings
# ============================================================

BASE = os.path.dirname(os.path.abspath(__file__))

# Map of GLB resource IDs to file paths and intended collision box sizes
# Format: ext_resource_id → (glb_path, collision_box_WxHxD, material_type)
BUILDING_MAP = {
    '7_gs01':  ('assets/models/environment/general_store.glb',   (8, 4, 6),    'concrete'),
    '7_din01': ('assets/models/environment/diner.glb',           (10, 3.5, 8), 'concrete'),
    '7_hw01':  ('assets/models/environment/hardware_store.glb',  (7, 4, 7),    'concrete'),
    '7_bar01': ('assets/models/environment/bar_tavern.glb',      (9, 3, 6),    'wood'),
    '7_gas01': ('assets/models/environment/gas_station.glb',     (12, 4, 8),   'concrete'),
    '7_chr01': ('assets/models/environment/church.glb',          (10, 8, 15),  'concrete'),
    '7_wh01':  ('assets/models/environment/warehouse.glb',       (15, 6, 12),  'metal'),
    '7_fac01': ('assets/models/environment/factory.glb',         (12, 5, 10),  'metal'),
    '7_ah01':  ('assets/models/environment/abandoned_house_01.glb', (7, 4, 8), 'wood'),
    '7_ah02':  ('assets/models/environment/abandoned_house_02.glb', (8, 4, 7), 'wood'),
    '7_hc01':  ('assets/models/environment/house_colonial.glb',  (6, 3.5, 7), 'wood'),
    '7_mot01': ('assets/models/environment/motel.glb',           (20, 4, 6),  'concrete'),
    '7_rad01': ('assets/models/environment/radio_station.glb',   (3, 2, 3),   'metal'),
    '7_sch01': ('assets/models/environment/school.glb',          (15, 5, 10), 'concrete'),
    '7_rgr01': ('assets/models/environment/ranger_station.glb',  (6, 3, 5),   'wood'),
    '7_phm01': ('assets/models/environment/pharmacy.glb',        (8, 4, 7),   'concrete'),
    '7_trl01': ('assets/models/environment/trailer_home.glb',    (10, 3, 4),  'metal'),
}

# Props: ext_resource_id → (glb_path, target_size_WxHxD, material_type)
PROP_MAP = {
    '8_slmp': ('assets/models/props/street_lamp.glb',     (0.3, 4, 0.3),  'metal'),
    '8_bnch': ('assets/models/props/park_bench.glb',      (1.5, 0.8, 0.5),'wood'),
    '8_mbx':  ('assets/models/props/mailbox.glb',         (0.4, 1.0, 0.3),'metal'),
    '8_fhyd': ('assets/models/props/fire_hydrant.glb',    (0.3, 0.6, 0.3),'metal'),
    '8_phon': ('assets/models/props/phone_booth.glb',     (1.0, 2.2, 1.0),'metal'),
    '8_trsh': ('assets/models/props/trash_can.glb',       (0.5, 0.8, 0.5),'metal'),
    '8_gate': ('assets/models/props/rusty_gate.glb',      (3, 2, 0.2),    'metal'),
    '8_clnk': ('assets/models/props/chain_link_fence.glb',(10, 2, 0.2),   'metal'),
    '8_rbar': ('assets/models/props/road_barrier.glb',    (2, 1, 0.5),    'metal'),
    '8_cone': ('assets/models/props/traffic_cone.glb',    (0.3, 0.5, 0.3),'plastic'),
    '8_ocar': ('assets/models/props/old_car.glb',         (4, 1.5, 2),    'metal'),
    '8_ptk':  ('assets/models/props/pickup_truck.glb',    (5, 1.8, 2.2),  'metal'),
    '8_pcar': ('assets/models/props/police_car.glb',      (4.5, 1.5, 2),  'metal'),
    '8_wbrl': ('assets/models/props/wooden_barrel.glb',   (0.5, 0.8, 0.5),'wood'),
    '8_dmp':  ('assets/models/props/dumpster.glb',        (2, 1.5, 1.5),  'metal'),
    '8_wcrt': ('assets/models/props/wooden_crate.glb',    (0.6, 0.6, 0.6),'wood'),
    '8_genr': ('assets/models/props/generator.glb',       (1.0, 0.8, 0.6),'metal'),
    '8_tire': ('assets/models/props/tire_stack.glb',      (0.8, 1.0, 0.8),'rubber'),
    '8_dtree':('assets/models/props/dead_tree.glb',       (3, 5, 3),      'wood'),
    '8_bush': ('assets/models/props/overgrown_bushes.glb',(2, 1.2, 2),    'organic'),
    '8_otbl': ('assets/models/props/overturned_table.glb',(1.2, 0.4, 0.8),'wood'),
    '8_bchr': ('assets/models/props/broken_chair.glb',    (0.5, 0.8, 0.5),'wood'),
    '8_otv':  ('assets/models/props/old_tv.glb',          (0.5, 0.4, 0.4),'plastic'),
    '8_tcch': ('assets/models/props/torn_couch.glb',      (2.0, 0.8, 0.8),'fabric'),
    '8_rfr':  ('assets/models/props/rusted_refrigerator.glb',(0.7, 1.8, 0.7),'metal'),
    '8_fbks': ('assets/models/props/fallen_bookshelf.glb',(1.5, 0.5, 0.4),'wood'),
    '8_fcab': ('assets/models/props/filing_cabinet.glb',  (0.5, 1.2, 0.5),'metal'),
}

ALL_MODELS = {**BUILDING_MAP, **PROP_MAP}

# ============================================================
# 3. Calculate scale factors
# ============================================================

def calc_scale(glb_bounds, target_size):
    """Calculate uniform scale factor to fit model into target size."""
    gs = glb_bounds['size']
    if gs[0] < 0.001 or gs[1] < 0.001 or gs[2] < 0.001:
        return 1.0  # degenerate model

    # Calculate per-axis ratios
    ratios = [target_size[i] / gs[i] for i in range(3)]

    # Use uniform scale: average of X and Z ratios (footprint), capped by Y ratio
    # This keeps proportions while filling the footprint
    footprint_scale = (ratios[0] + ratios[2]) / 2.0
    height_scale = ratios[1]

    # Use the smaller of footprint vs height to avoid stretching
    scale = min(footprint_scale, height_scale)
    return round(scale, 3)


# ============================================================
# 4. Process the .tscn file
# ============================================================

def process_tscn(input_path, output_path):
    with open(input_path, 'r') as f:
        content = f.read()

    lines = content.split('\n')

    # Pre-compute scale factors for all models
    scale_cache = {}
    for res_id, (glb_rel, target, mat) in ALL_MODELS.items():
        glb_path = os.path.join(BASE, glb_rel)
        bounds = get_glb_bounds(glb_path)
        if bounds:
            scale = calc_scale(bounds, target)
            min_y = bounds['min'][1]
            scale_cache[res_id] = (scale, min_y, bounds['size'])
            is_building = res_id in BUILDING_MAP
            label = "BUILDING" if is_building else "PROP"
            print(f"  {label} {res_id:10s}: GLB {bounds['size'][0]:.1f}x{bounds['size'][1]:.1f}x{bounds['size'][2]:.1f} → target {target[0]}x{target[1]}x{target[2]} → scale={scale:.2f}x")
        else:
            print(f"  WARNING: No bounds for {res_id}")

    # Pattern to find instance lines with ExtResource
    instance_pattern = re.compile(r'instance=ExtResource\("([^"]+)"\)')
    node_pattern = re.compile(r'\[node name="([^"]+)"')
    transform_pattern = re.compile(r'transform = Transform3D\(([^)]+)\)')

    new_lines = []
    i = 0
    buildings_fixed = 0
    props_fixed = 0

    while i < len(lines):
        line = lines[i]

        # Check if this is a node with a GLB instance
        inst_match = instance_pattern.search(line)
        if inst_match:
            res_id = inst_match.group(1)
            if res_id in scale_cache:
                scale, min_y, glb_size = scale_cache[res_id]
                is_building = res_id in BUILDING_MAP

                # Check if this is a "Model" node (child of a StaticBody3D building)
                # or a direct prop instance
                node_match = node_pattern.search(line)
                node_name = node_match.group(1) if node_match else ""

                if node_name == "Model" and is_building:
                    # This is a building Model node — apply scale and Y-offset
                    # The Model is relative to its parent StaticBody3D
                    # We want the model bottom to be at Y=0 relative to parent
                    y_offset = -min_y * scale

                    # Check if there's already a transform line
                    if i + 1 < len(lines) and 'transform = Transform3D' in lines[i + 1]:
                        # Replace existing transform with scaled version
                        new_transform = f'transform = Transform3D({scale}, 0, 0, 0, {scale}, 0, 0, 0, {scale}, 0, {round(y_offset, 3)}, 0)'
                        new_lines.append(line)
                        i += 1
                        new_lines.append(new_transform)
                        buildings_fixed += 1
                    else:
                        # Insert transform after the node line
                        new_lines.append(line)
                        new_transform = f'transform = Transform3D({scale}, 0, 0, 0, {scale}, 0, 0, 0, {scale}, 0, {round(y_offset, 3)}, 0)'
                        new_lines.append(new_transform)
                        buildings_fixed += 1

                    # Now fix the parent StaticBody3D Y-position (go back and fix it)
                    # The parent was 2-4 lines before this Model node
                    for j in range(len(new_lines) - 3, max(0, len(new_lines) - 8), -1):
                        if 'type="StaticBody3D"' in new_lines[j]:
                            # Found parent - fix its transform on the next line
                            if j + 1 < len(new_lines) and 'transform = Transform3D' in new_lines[j + 1]:
                                t_match = transform_pattern.search(new_lines[j + 1])
                                if t_match:
                                    vals = [v.strip() for v in t_match.group(1).split(',')]
                                    if len(vals) >= 12:
                                        # Set Y position to 0 (was half-height for centered boxes)
                                        vals[10] = '0'  # Y position
                                        new_lines[j + 1] = f'transform = Transform3D({", ".join(vals)})'
                            break

                    i += 1
                    continue

                elif not is_building:
                    # This is a prop instance — apply scale
                    # Props are either direct instances or Model children

                    # Check for existing transform
                    if i + 1 < len(lines) and 'transform = Transform3D' in lines[i + 1]:
                        t_match = transform_pattern.search(lines[i + 1])
                        if t_match:
                            vals = [float(v.strip()) for v in t_match.group(1).split(',')]
                            if len(vals) >= 12:
                                # Apply scale to existing transform matrix
                                # Scale the rotation/scale columns
                                for col in range(3):  # columns 0,1,2
                                    for row in range(3):  # rows 0,1,2
                                        vals[col * 3 + row] *= scale
                                # Y offset for model bottom
                                y_offset = -min_y * scale
                                vals[10] += y_offset  # adjust Y position

                                formatted = ', '.join(f'{v:.6g}' if v != int(v) else str(int(v)) for v in vals)
                                new_lines.append(line)
                                i += 1
                                new_lines.append(f'transform = Transform3D({formatted})')
                                props_fixed += 1
                                i += 1
                                continue
                    else:
                        # No transform line — insert one
                        y_offset = -min_y * scale
                        new_lines.append(line)
                        new_lines.append(f'transform = Transform3D({scale}, 0, 0, 0, {scale}, 0, 0, 0, {scale}, 0, {round(y_offset, 3)}, 0)')
                        props_fixed += 1
                        i += 1
                        continue

        new_lines.append(line)
        i += 1

    print(f"\n  Fixed {buildings_fixed} buildings, {props_fixed} props")

    with open(output_path, 'w') as f:
        f.write('\n'.join(new_lines))

    return buildings_fixed, props_fixed


# ============================================================
# 5. Generate material applicator GDScript
# ============================================================

def generate_material_script(output_path):
    """Create a GDScript that applies materials to untextured GLB models at runtime."""
    script = '''extends Node
## Auto-applies materials to imported GLB models that lack embedded textures.
## Attach to Town scene root or add as autoload.

const MATERIAL_MAP: Dictionary = {
	"concrete": "res://materials/concrete_wall.tres",
	"wood": "res://materials/old_wood.tres",
	"metal": "res://materials/rusty_metal.tres",
	"asphalt": "res://materials/asphalt.tres",
	"grass": "res://materials/grass.tres",
}

# Map building/prop names to material types
const NODE_MATERIALS: Dictionary = {
	# Buildings
	"general_store": "concrete",
	"diner": "concrete",
	"hardware_store": "concrete",
	"bar_tavern": "wood",
	"gas_station": "concrete",
	"church": "concrete",
	"warehouse": "metal",
	"factory": "metal",
	"abandoned_house": "wood",
	"house_colonial": "wood",
	"house_ranch": "wood",
	"motel": "concrete",
	"radio_station": "metal",
	"school": "concrete",
	"ranger_station": "wood",
	"pharmacy": "concrete",
	"trailer_home": "metal",
	# Props
	"street_lamp": "metal",
	"park_bench": "wood",
	"mailbox": "metal",
	"fire_hydrant": "metal",
	"phone_booth": "metal",
	"trash_can": "metal",
	"rusty_gate": "metal",
	"chain_link_fence": "metal",
	"road_barrier": "metal",
	"traffic_cone": "metal",
	"old_car": "metal",
	"pickup_truck": "metal",
	"police_car": "metal",
	"wooden_barrel": "wood",
	"dumpster": "metal",
	"wooden_crate": "wood",
	"generator": "metal",
	"tire_stack": "metal",
	"dead_tree": "wood",
	"overgrown_bushes": "wood",
	"overturned_table": "wood",
	"broken_chair": "wood",
	"old_tv": "metal",
	"torn_couch": "wood",
	"rusted_refrigerator": "metal",
	"fallen_bookshelf": "wood",
	"filing_cabinet": "metal",
}

var _material_cache: Dictionary = {}


func _ready() -> void:
	# Pre-load materials
	for mat_type: String in MATERIAL_MAP:
		var path: String = MATERIAL_MAP[mat_type]
		if ResourceLoader.exists(path):
			_material_cache[mat_type] = load(path)

	# Apply materials to all GLB instances in the scene tree
	call_deferred("_apply_materials_recursive", get_parent())


func _apply_materials_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		# Skip if already has a material
		if mesh_inst.material_override != null:
			return
		if mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
			var has_material := false
			for s: int in mesh_inst.mesh.get_surface_count():
				if mesh_inst.mesh.surface_get_material(s) != null:
					has_material = true
					break
			if not has_material:
				# Find material type from ancestor node names
				var mat_type: String = _find_material_for_node(node)
				if mat_type in _material_cache:
					mesh_inst.material_override = _material_cache[mat_type]

	for child: Node in node.get_children():
		_apply_materials_recursive(child)


func _find_material_for_node(node: Node) -> String:
	"""Walk up the tree to find matching material from NODE_MATERIALS."""
	var current: Node = node
	while current != null:
		var node_name_lower: String = current.name.to_lower()
		for key: String in NODE_MATERIALS:
			if key in node_name_lower:
				return NODE_MATERIALS[key]
		# Also check the scene file path for instanced scenes
		if current.scene_file_path != "":
			var scene_lower: String = current.scene_file_path.to_lower()
			for key: String in NODE_MATERIALS:
				if key in scene_lower:
					return NODE_MATERIALS[key]
		current = current.get_parent()
	return "concrete"  # fallback
'''
    with open(output_path, 'w') as f:
        f.write(script)
    print(f"  Created material applicator: {output_path}")


# ============================================================
# Main
# ============================================================

if __name__ == '__main__':
    print("=== Town Scene Fixer ===\n")

    tscn_path = os.path.join(BASE, 'levels/town/town.tscn')

    if not os.path.exists(tscn_path):
        print(f"ERROR: {tscn_path} not found")
        sys.exit(1)

    print("Computing scale factors...")
    b, p = process_tscn(tscn_path, tscn_path)

    print("\nGenerating material applicator script...")
    generate_material_script(os.path.join(BASE, 'levels/town/material_applicator.gd'))

    print(f"\nDone! Fixed {b} buildings and {p} props in town.tscn")
    print("Next: Add MaterialApplicator node to Town scene and attach material_applicator.gd")
