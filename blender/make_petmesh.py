import bpy, os, math
OUT=os.path.expanduser("~/StarPets/models"); os.makedirs(OUT,exist_ok=True)
def clear(): bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def join(objs,a):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active=a; bpy.ops.object.join(); return bpy.context.active_object
def sph(r,loc,scale=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r,location=loc,segments=20,ring_count=12); o=bpy.context.active_object
    if scale: o.scale=scale; bpy.ops.object.transform_apply(scale=True)
    return o
def cone(r1,d,loc,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cone_add(radius1=r1,radius2=0,depth=d,location=loc,rotation=rot); return bpy.context.active_object
def metabody(els):
    mb=bpy.data.metaballs.new("b"); mb.resolution=0.12; mb.render_resolution=0.12; mb.threshold=0.6
    o=bpy.data.objects.new("b",mb); bpy.context.collection.objects.link(o)
    for (loc,r) in els:
        e=mb.elements.new(); e.co=loc; e.radius=r
    bpy.context.view_layer.objects.active=o; o.select_set(True)
    bpy.ops.object.convert(target='MESH'); c=bpy.context.active_object
    bpy.ops.object.shade_smooth(); return c
clear()
# cute-but-clean creature: big head + body fused, ears, big eyes, stubby legs, tail
core=metabody([((0,-0.5,1.0),1.3),((0,0.2,0.55),1.0),((0,0.85,0.15),0.85)])
P=[core]
for (x,y) in [(0.4,-0.05),(-0.4,-0.05),(0.45,0.95),(-0.45,0.95)]:
    P.append(sph(0.3,(x,y,-0.55),(1,1,1.2)))
for sx in (0.6,-0.6): P.append(cone(0.36,0.8,(sx,-0.5,1.95)))   # pointy ears
P.append(sph(0.42,(0,1.45,0.35),(1,1.5,1)))                      # tail
obj=join(P,core); obj.name="Pet"
# decimate to a low, in-engine-friendly poly count
m=obj.modifiers.new("d",'DECIMATE'); m.ratio=0.18
bpy.ops.object.modifier_apply(modifier=m.name)
bpy.ops.wm.obj_export(filepath=os.path.join(OUT,"PetMesh.obj"), up_axis='Y', forward_axis='NEGATIVE_Z', export_normals=True, export_uv=False, export_materials=False)
print("TRIS", len(obj.data.polygons))
# render
bpy.ops.object.empty_add(location=(0,-0.3,0.7)); tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=(3.5,-5,2.2)); cam=bpy.context.active_object
cam.constraints.new('TRACK_TO').target=tgt
import bpy as B; sc=B.context.scene; sc.camera=cam; sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='STUDIO'; sc.display.shading.show_shadows=True; sc.display.shading.show_cavity=True
sc.render.resolution_x=480; sc.render.resolution_y=480
sc.render.filepath=os.path.join(OUT,"preview.png"); sc.render.image_settings.file_format='PNG'
bpy.ops.render.render(write_still=True); print("DONE")
