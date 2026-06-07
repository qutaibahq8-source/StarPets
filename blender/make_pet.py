import bpy, os, math

def clear():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def join(objs, active):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.join(); return bpy.context.active_object
def apply_mod(obj, mod):
    bpy.context.view_layer.objects.active = obj; bpy.ops.object.modifier_apply(modifier=mod.name)
def mat(name, rgba, rough=0.65):
    m=bpy.data.materials.new(name); m.use_nodes=True
    b=m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value=rgba
    try: b.inputs["Roughness"].default_value=rough
    except: pass
    m.diffuse_color=rgba; return m
def setmat(obj,m):
    obj.data.materials.clear(); obj.data.materials.append(m)

clear()
FUR  = mat("Fur",(0.95,0.62,0.32,1))
PINK = mat("Pink",(1.0,0.55,0.62,1))
WHT  = mat("White",(1,1,1,1))
BLK  = mat("Black",(0.04,0.04,0.06,1),0.3)

# big cute head + smaller body, fused
bpy.ops.mesh.primitive_uv_sphere_add(radius=1.15, location=(0,-0.55,0.6)); head=bpy.context.active_object
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.95, location=(0,0.65,-0.15)); body=bpy.context.active_object; body.scale=(1,1.1,1); bpy.ops.object.transform_apply(scale=True)
core=join([head,body],head)
rm=core.modifiers.new("rm",'REMESH'); rm.mode='VOXEL'; rm.voxel_size=0.07; apply_mod(core,rm)
bpy.ops.object.shade_smooth(); setmat(core,FUR)
parts=[core]

def add(prim, m, **kw):
    prim(**kw); o=bpy.context.active_object; bpy.ops.object.shade_smooth(); setmat(o,m); parts.append(o); return o

# ears (rounded) + inner
for x in (0.55,-0.55):
    add(bpy.ops.mesh.primitive_uv_sphere_add, FUR, radius=0.42, location=(x,-0.55,1.55))
    add(bpy.ops.mesh.primitive_uv_sphere_add, PINK, radius=0.24, location=(x,-0.72,1.6))
# big eyes (white + pupil + highlight)
for x in (0.42,-0.42):
    add(bpy.ops.mesh.primitive_uv_sphere_add, WHT, radius=0.32, location=(x,-1.4,0.7))
    add(bpy.ops.mesh.primitive_uv_sphere_add, BLK, radius=0.20, location=(x,-1.62,0.66))
    add(bpy.ops.mesh.primitive_uv_sphere_add, WHT, radius=0.07, location=(x+0.06,-1.74,0.78))
# nose
add(bpy.ops.mesh.primitive_uv_sphere_add, PINK, radius=0.16, location=(0,-1.68,0.35))
# stubby legs + feet
for x in (0.5,-0.5):
    for y in (-0.45,0.75):
        add(bpy.ops.mesh.primitive_cylinder_add, FUR, radius=0.27, depth=0.55, location=(x,y,-1.0))
        add(bpy.ops.mesh.primitive_uv_sphere_add, FUR, radius=0.3, location=(x,y,-1.25))
# fluffy tail
add(bpy.ops.mesh.primitive_uv_sphere_add, FUR, radius=0.45, location=(0,1.45,0.25))

obj=join(parts,core); obj.name="StarPet_Critter"
out=os.path.expanduser("~/StarPets/models"); os.makedirs(out,exist_ok=True)
bpy.ops.wm.obj_export(filepath=os.path.join(out,"StarPet_Critter.obj"), up_axis='Y', forward_axis='NEGATIVE_Z')
bpy.ops.export_scene.fbx(filepath=os.path.join(out,"StarPet_Critter.fbx"), use_selection=False, axis_up='Y', axis_forward='-Z')

# ---- render (workbench, material colors) ----
bpy.ops.object.empty_add(location=(0,-0.3,0.45)); tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=(3.2,-5.5,2.3)); cam=bpy.context.active_object
cam.constraints.new('TRACK_TO').target=tgt
sc=bpy.context.scene; sc.camera=cam
sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='STUDIO'; sc.display.shading.color_type='MATERIAL'
sc.display.shading.show_shadows=True; sc.display.shading.show_cavity=True
sc.render.resolution_x=480; sc.render.resolution_y=480
try: sc.world.color=(0.16,0.17,0.2)
except: pass
sc.render.filepath=os.path.join(out,"preview.png"); sc.render.image_settings.file_format='PNG'
bpy.ops.render.render(write_still=True)
print("TRIS:", len(obj.data.polygons), "RENDERED")
