import bpy, os, math
OUT=os.path.expanduser("~/StarPets/models"); os.makedirs(OUT,exist_ok=True)
def clear(): bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def mat(n,c,rough=0.25,metal=0.0):
    m=bpy.data.materials.get(n) or bpy.data.materials.new(n); m.use_nodes=True
    b=m.node_tree.nodes.get("Principled BSDF"); b.inputs["Base Color"].default_value=c
    try:
        b.inputs["Roughness"].default_value=rough
        b.inputs["Metallic"].default_value=metal
    except: pass
    m.diffuse_color=c; return m
def setmat(o,m): o.data.materials.clear(); o.data.materials.append(m)
def join(objs,a):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active=a; bpy.ops.object.join(); return bpy.context.active_object
def sph(r,loc,scale=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r,location=loc,segments=32,ring_count=20); o=bpy.context.active_object
    if scale: o.scale=scale; bpy.ops.object.transform_apply(scale=True)
    return o
def cone(r1,d,loc,rot=(0,0,0),r2=0.0):
    bpy.ops.mesh.primitive_cone_add(radius1=r1,radius2=r2,depth=d,location=loc,rotation=rot); return bpy.context.active_object
clear()
FUR=mat("fur",(0.95,0.62,0.30,1),0.3); WHT=mat("wht",(1,1,1,1),0.15); DARK=mat("dark",(0.05,0.05,0.09,1),0.08)
PINK=mat("pink",(1,0.5,0.6,1),0.3); ACC=mat("acc",(1,0.82,0.88,1),0.3)
# big head + small body fused (Pet Sim X proportions)
mb=bpy.data.metaballs.new("b"); mb.resolution=0.06; mb.threshold=0.6
o=bpy.data.objects.new("B",mb); bpy.context.collection.objects.link(o)
def el(loc,r,s=None):
    e=mb.elements.new(); e.co=loc; e.radius=r
    if s: e.type='ELLIPSOID'; e.size_x,e.size_y,e.size_z=s
el((0,-0.2,1.15),1.35)   # big head
el((0,-0.5,0.75),0.9)    # cheeks/jaw
el((0,0.45,0.15),0.85)   # small body
el((0,0.2,0.55),0.8)     # neck blend
bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.convert(target='MESH')
core=bpy.context.active_object; bpy.ops.object.shade_smooth(); setmat(core,FUR); P=[core]
def add(ob,m): bpy.ops.object.shade_smooth(); setmat(ob,m); P.append(ob); return ob
# cat ears
add(cone(0.5,0.85,(0.6,-0.2,2.15)),FUR); add(cone(0.5,0.85,(-0.6,-0.2,2.15)),FUR)
add(cone(0.28,0.6,(0.6,-0.32,2.05)),ACC); add(cone(0.28,0.6,(-0.6,-0.32,2.05)),ACC)
# BIG glossy eyes (tall ovals) + big shines (Pet Sim X signature)
for x in (0.5,-0.5):
    e=sph(0.42,(x,-1.05,1.2)); e.scale=(0.85,0.55,1.25); bpy.ops.object.transform_apply(scale=True); add(e,DARK)
    add(sph(0.17,(x+0.1,-1.32,1.5)),WHT)   # big top shine
    add(sph(0.09,(x-0.12,-1.28,0.98)),WHT) # small bottom shine
# nose + mouth + blush
add(sph(0.12,(0,-1.42,0.92)),PINK)
for x in (0.78,-0.78):
    b=sph(0.2,(x,-0.95,0.78)); b.scale=(1,0.3,0.6); bpy.ops.object.transform_apply(scale=True); add(b,PINK)
# stubby paws
for (x,y) in [(0.42,-0.55),(-0.42,-0.55),(0.4,0.7),(-0.4,0.7)]:
    add(sph(0.32,(x,y,-0.55),(1,1.1,0.8)),FUR)
# little tail
add(sph(0.28,(0,1.1,0.3)),FUR); add(sph(0.22,(0,1.45,0.6)),FUR)
obj=join(P,core); obj.name="StarPet_PSX"
bpy.ops.wm.obj_export(filepath=os.path.join(OUT,"StarPet_PSX.obj"),up_axis='Y',forward_axis='NEGATIVE_Z')
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT,"StarPet_PSX.fbx"),use_selection=False,axis_up='Y',axis_forward='-Z')
# --- glossy render (EEVEE) ---
bpy.ops.object.empty_add(location=(0,-0.5,0.9)); tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=(3.0,-5.2,1.8)); cam=bpy.context.active_object
cam.constraints.new('TRACK_TO').target=tgt
bpy.ops.object.light_add(type='SUN',location=(4,-3,8)); bpy.context.active_object.data.energy=4
bpy.ops.object.light_add(type='AREA',location=(-4,-5,4)); a=bpy.context.active_object; a.data.energy=300; a.data.size=8
sc=bpy.context.scene; sc.camera=cam
try:
    sc.render.engine='BLENDER_EEVEE_NEXT'
except Exception as e:
    print("eevee set fail",e); sc.render.engine='BLENDER_WORKBENCH'
try: sc.world.node_tree.nodes["Background"].inputs[0].default_value=(0.6,0.7,0.85,1); sc.world.node_tree.nodes["Background"].inputs[1].default_value=0.6
except Exception as e: print("world",e)
sc.render.resolution_x=560; sc.render.resolution_y=560
sc.render.filepath=os.path.join(OUT,"preview.png"); sc.render.image_settings.file_format='PNG'
bpy.ops.render.render(write_still=True); print("ENGINE",sc.render.engine,"DONE")
