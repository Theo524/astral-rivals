"""Read-only Blender asset intake; no generation, rig edits, exports or saves.

Run: blender --background --disable-autoexec --python \
     tools/blender/inspect_character_source.py -- input.blend output.json

Counts describe the source mesh, before modifiers. Separate hair/clothing
islands and open surfaces are normal: these numbers are not an art-quality
score, a licence check or a substitute for rendering/deformation review.
"""
import collections
import argparse
import json
import sys
from pathlib import Path

import bpy


def mesh_report(obj):
    data = obj.data
    data.calc_loop_triangles()
    parents = list(range(len(data.vertices)))

    def find(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    for edge in data.edges:
        a, b = edge.vertices
        parents[find(a)] = find(b)
    components = collections.Counter(find(i) for i in range(len(parents)))
    edge_use = collections.Counter()
    for polygon in data.polygons:
        edge_use.update(tuple(sorted(pair)) for pair in polygon.edge_keys)
    influences = collections.Counter()
    group_names = {group.index: group.name for group in obj.vertex_groups}
    weighted_bones = collections.Counter()
    unweighted = 0
    underweighted = 0
    for vertex in data.vertices:
        weights = [group for group in vertex.groups if group.weight > 0]
        influences[len(weights)] += 1
        total = sum(group.weight for group in weights)
        unweighted += total <= 0
        underweighted += 0 < total < 0.999
        for group in weights:
            weighted_bones[group_names[group.group]] += 1
    return {
        "object": obj.name,
        "vertices": len(data.vertices),
        "triangles": len(data.loop_triangles),
        "faces_by_side_count": dict(collections.Counter(len(p.vertices) for p in data.polygons)),
        "connected_components": len(components),
        "largest_components": sorted(components.values(), reverse=True)[:20],
        "boundary_edges": sum(count == 1 for count in edge_use.values()),
        "overused_edges": sum(count > 2 for count in edge_use.values()),
        "uv_layers": [layer.name for layer in data.uv_layers],
        "shape_keys": [] if data.shape_keys is None else [key.name for key in data.shape_keys.key_blocks],
        "materials": [{
            "name": material.name,
            "base_rgba": list(material.diffuse_color),
            "image_textures": [node.image.name for node in material.node_tree.nodes
                               if node.type == 'TEX_IMAGE' and node.image]
                              if material.node_tree else [],
        } for material in data.materials if material is not None],
        "vertex_influence_histogram": dict(influences),
        "unweighted_vertices": unweighted,
        "underweighted_vertices": underweighted,
        "weighted_vertices_per_group": dict(weighted_bones),
        "modifiers": [modifier.type for modifier in obj.modifiers],
        "asset_metadata": asset_report(obj.asset_data),
    }


def asset_report(metadata):
    if metadata is None:
        return None
    return {"author": metadata.author, "license": metadata.license,
            "description": metadata.description}


def inspect(source, selected_meshes=None):
    bpy.ops.wm.open_mainfile(filepath=str(source.resolve()), use_scripts=False)
    meshes = [obj for obj in bpy.data.objects if obj.type == 'MESH']
    if selected_meshes:
        available = {obj.name for obj in meshes}
        missing = set(selected_meshes) - available
        if missing:
            raise SystemExit('Requested meshes not found: ' + ', '.join(sorted(missing)))
        meshes = [obj for obj in meshes if obj.name in selected_meshes]
    return {
        "source": str(source),
        "blender_version": bpy.app.version_string,
        "scope": "Source datablocks before modifiers; no asset mutation or quality certification",
        "mesh_filter": selected_meshes or [],
        "meshes": [mesh_report(obj) for obj in meshes],
        "collection_assets": [{"name": collection.name,
                               "metadata": asset_report(collection.asset_data)}
                              for collection in bpy.data.collections if collection.asset_data],
        "armatures": [{
            "object": obj.name,
            "bones": [{
                "name": bone.name,
                "parent": bone.parent.name if bone.parent else None,
                "head": [round(value, 5) for value in bone.head_local],
                "tail": [round(value, 5) for value in bone.tail_local],
            } for bone in obj.data.bones],
        } for obj in bpy.data.objects if obj.type == 'ARMATURE'],
        "actions": [{"name": action.name, "range": list(action.frame_range),
                     "fcurves": len(action.fcurves)} for action in bpy.data.actions],
    }


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--mesh', action='append', help='Inspect only this exact mesh name; repeatable')
    options = parser.parse_args(args)
    source, output = options.source, options.output
    if source.resolve() == output.resolve():
        raise SystemExit('Output must not overwrite the source')
    report = inspect(source, options.mesh)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    print('SOURCE_INSPECTION:', len(report['meshes']), 'meshes,',
          len(report['armatures']), 'armatures; report:', output)
