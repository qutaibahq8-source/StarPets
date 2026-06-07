import bpy, os, math
OUT=os.path.expanduser("~/StarPets/models"); os.makedirs(OUT,exist_ok=True)
def clear(): bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def setcol(o,c,rough=0.5,metal=0.0):
    m=bpy.data.materials.new("m"); m.use_nodes=True; b=m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value=c
    try: b.inputs["Roughness"].default_value=rough; b.inputs["Metallic"].default_value=metal
    except: pass
    m.diffuse_color=c; o.data.materials.clear(); o.data.materials.append(m); return o
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
def metabody(els):
    mb=bpy.data.metaballs.new("b"); mb.resolution=0.05; mb.render_resolution=0.05; mb.threshold=0.6
    o=bpy.data.objects.new("b",mb); bpy.context.collection.objects.link(o)
    for (loc,r) in els:
        e=mb.elements.new(); e.co=loc; e.radius=r
    bpy.context.view_layer.objects.active=o; o.select_set(True)
    bpy.ops.object.convert(target='MESH'); c=bpy.context.active_object
    bpy.ops.object.shade_smooth(); return c
def add(P,o,c,rough=0.5,metal=0.0): bpy.ops.object.shade_smooth(); setcol(o,c,rough,metal); P.append(o); return o

clear()
FUR=(0.95,0.62,0.28,1); CREAM=(1,0.92,0.8,1)
# big head + small body fused (Pet Sim X style)
core=metabody([((0,-0.5,1.0),1.3),((0,0.15,0.55),1.0),((0,0.8,0.15),0.9)])
P=[]; add(P,core,FUR,0.5)
# stubby legs
for (x,y) in [(0.4,-0.05),(-0.4,-0.05),(0.45,0.95),(-0.45,0.95)]:
    add(P,sph(0.3,(x,y,-0.55),(1,1,1.15)),FUR,0.5)
# ears (rounded)
for sx in (0.62,-0.62): add(P,sph(0.34,(sx,-0.5,1.95)),FUR,0.5)
for sx in (0.62,-0.62): add(P,sph(0.18,(sx,-0.62,1.97)),(1,0.7,0.7,1),0.5)
# BIG glossy eyes (the Pet Sim X sparkle)
for sx in (0.5,-0.5):
    add(P,sph(0.34,(sx*0.95,-1.45,1.1)),(1,1,1,1),0.25)        # sclera
    add(P,sph(0.22,(sx*0.95,-1.66,1.06)),(0.05,0.08,0.18,1),0.15)  # iris
    add(P,sph(0.11,(sx*0.95+0.06,-1.78,1.22)),(1,1,1,1),0.1)   # big shine
    add(P,sph(0.05,(sx*0.95-0.06,-1.74,0.98)),(1,1,1,1),0.1)   # small shine
# muzzle + nose
add(P,sph(0.36,(0,-1.62,0.6),(1,0.8,0.7)),CREAM,0.5)
add(P,sph(0.14,(0,-1.9,0.66)),(0.1,0.08,0.1,1),0.2)
# blush
for sx in (0.85,-0.85):
    b=sph(0.2,(sx,-1.35,0.72)); b.scale=(1,0.2,0.7); bpy.ops.object.transform_apply(scale=True); add(P,b,(1,0.55,0.55,1),0.6)
# tail
add(P,sph(0.4,(0,1.4,0.45),(1,1.4,1)),FUR,0.5)
obj=join(P,core); obj.name="StarPet_Premium"
bpy.ops.wm.obj_export(filepath=os.path.join(OUT,"StarPet_Premium.obj"),up_axis='Y',forward_axis='NEGATIVE_Z')
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT,"StarPet_Premium.fbx"),use_selection=False,axis_up='Y',axis_forward='-Z')
# render (try EEVEE for gloss, fallback workbench)
bpy.ops.object.empty_add(location=(0,-0.4,0.9)); tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=(3.5,-5.2,2.2)); cam=bpy.context.active_object
cam.constraints.new('TRACK_TO').target=tgt
sc=bpy.context.scene; sc.camera=cam
sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='STUDIO'; sc.display.shading.color_type='MATERIAL'; sc.display.shading.show_shadows=True; sc.display.shading.show_cavity=True
sc.render.resolution_x=560; sc.render.resolution_y=560
sc.render.filepath=os.path.join(OUT,"preview.png"); sc.render.image_settings.file_format='PNG' 
bpy.ops.render.render(write_still=True); print("ENGINE",sc.render.engine,"DONE")
