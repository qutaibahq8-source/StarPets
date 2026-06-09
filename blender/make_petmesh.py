import bpy, os
OUT=os.path.expanduser("~/StarPets/models"); os.makedirs(OUT,exist_ok=True)
def clear(): bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def join(objs,a):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active=a; bpy.ops.object.join(); return bpy.context.active_object
def sph(r,loc,scale=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r,location=loc,segments=24,ring_count=14); o=bpy.context.active_object
    if scale: o.scale=scale; bpy.ops.object.transform_apply(scale=True)
    return o
def metabody(els,res=0.09):
    mb=bpy.data.metaballs.new("b"); mb.resolution=res; mb.render_resolution=res; mb.threshold=0.6
    o=bpy.data.objects.new("b",mb); bpy.context.collection.objects.link(o)
    for (loc,r) in els:
        e=mb.elements.new(); e.co=loc; e.radius=r
    bpy.context.view_layer.objects.active=o; o.select_set(True)
    bpy.ops.object.convert(target='MESH'); c=bpy.context.active_object
    bpy.ops.object.shade_smooth(); return c
clear()
# distinct head (big) + body (smaller) + rounded ears + stubby legs + tail, all fused smooth
core=metabody([
  ((0,-0.55,1.05),1.15),   # head
  ((0,0.35,0.5),0.92),     # body
  ((0,-0.1,0.78),0.85),    # neck blend
  ((0.55,-0.55,1.75),0.4),((-0.55,-0.55,1.75),0.4),  # rounded ears
  ((0.42,0.15,-0.35),0.34),((-0.42,0.15,-0.35),0.34),# front legs
  ((0.45,0.9,-0.35),0.34),((-0.45,0.9,-0.35),0.34),  # back legs
  ((0,1.25,0.55),0.5),     # tail
])
core.name="Pet"
m=core.modifiers.new("d",'DECIMATE'); m.ratio=0.30
bpy.ops.object.modifier_apply(modifier=m.name)
bpy.ops.wm.obj_export(filepath=os.path.join(OUT,"PetMesh.obj"), up_axis='Y', forward_axis='NEGATIVE_Z', export_normals=True, export_uv=False, export_materials=False)
print("TRIS", len(core.data.polygons))
bpy.ops.object.empty_add(location=(0,-0.3,0.7)); tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=(3.4,-4.8,2.0)); cam=bpy.context.active_object
cam.constraints.new('TRACK_TO').target=tgt
sc=bpy.context.scene; sc.camera=cam; sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='STUDIO'; sc.display.shading.show_shadows=True; sc.display.shading.show_cavity=True
sc.render.resolution_x=480; sc.render.resolution_y=480
sc.render.filepath=os.path.join(OUT,"preview.png"); sc.render.image_settings.file_format='PNG'
bpy.ops.render.render(write_still=True); print("DONE")
