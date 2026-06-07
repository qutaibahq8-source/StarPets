import bpy, os, math
OUT=os.path.expanduser("~/StarPets/models"); os.makedirs(OUT,exist_ok=True)
def clear(): bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def mat(n,c,rough=0.4):
    m=bpy.data.materials.get(n) or bpy.data.materials.new(n); m.use_nodes=True
    b=m.node_tree.nodes.get("Principled BSDF"); b.inputs["Base Color"].default_value=c
    try: b.inputs["Roughness"].default_value=rough
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
    bpy.ops.mesh.primitive_cone_add(radius1=r1,radius2=r2,depth=d,location=loc,rotation=rot,vertices=24); return bpy.context.active_object
clear()
BODY=mat("body",(0.5,0.66,0.92,1),0.45); WHT=mat("wht",(1,1,1,1),0.3); BLK=mat("blk",(0.03,0.03,0.05,1),0.15)
IRIS=mat("iris",(0.12,0.5,0.92,1),0.15); PINK=mat("pink",(1,0.6,0.66,1)); INEAR=mat("inear",(0.75,0.83,1.0,1))
# one clean chunky body (head merged into body)
mb=bpy.data.metaballs.new("b"); mb.resolution=0.05; mb.render_resolution=0.05; mb.threshold=0.6
mo=bpy.data.objects.new("B",mb); bpy.context.collection.objects.link(mo)
def el(loc,r):
    e=mb.elements.new(); e.co=loc; e.radius=r; return e
el((0,0.35,0.6),1.32); el((0,-0.5,1.0),1.05)
bpy.context.view_layer.objects.active=mo; mo.select_set(True)
bpy.ops.object.convert(target='MESH'); core=bpy.context.active_object; core.name="core"
bpy.ops.object.shade_smooth(); setmat(core,BODY); P=[core]
def add(o,m): bpy.ops.object.shade_smooth(); setmat(o,m); P.append(o); return o
# stubby legs
for (x,y) in [(0.5,-0.7),(-0.5,-0.7),(0.6,1.0),(-0.6,1.0)]:
    add(sph(0.36,(x,y,-0.2),(1,1,1.1)),BODY)
# ears
add(cone(0.32,0.66,(0.45,-0.55,1.95)),BODY); add(cone(0.32,0.66,(-0.45,-0.55,1.95)),BODY)
add(cone(0.17,0.46,(0.45,-0.62,1.88)),INEAR); add(cone(0.17,0.46,(-0.45,-0.62,1.88)),INEAR)
# FLAT eyes pressed onto the face (disc-like, not bulging)
for x in (0.4,-0.4):
    add(sph(0.34,(x,-1.18,1.1),(1,0.42,1.15)),WHT)
    add(sph(0.22,(x,-1.32,1.06),(1,0.42,1)),IRIS)
    add(sph(0.12,(x,-1.4,1.04),(1,0.42,1)),BLK)
    add(sph(0.07,(x+0.08,-1.44,1.22)),WHT)
    add(sph(0.04,(x-0.07,-1.42,0.95)),WHT)
# nose + curled tail
add(sph(0.12,(0,-1.46,0.74),(1,0.7,0.8)),PINK)
add(sph(0.42,(0,1.55,1.0),(1,1.2,1)),BODY); add(sph(0.3,(0,1.55,1.65)),WHT)
obj=join(P,core); obj.name="StarPet_Cat"
bpy.ops.wm.obj_export(filepath=os.path.join(OUT,"StarPet_Cat.obj"),up_axis='Y',forward_axis='NEGATIVE_Z')
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT,"StarPet_Cat.fbx"),use_selection=False,axis_up='Y',axis_forward='-Z')
bpy.ops.object.empty_add(location=(0,-0.3,0.85)); tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=(3.0,-5.0,1.9)); cam=bpy.context.active_object
cam.constraints.new('TRACK_TO').target=tgt
sc=bpy.context.scene; sc.camera=cam
try: sc.render.engine='BLENDER_EEVEE_NEXT'
except: sc.render.engine='BLENDER_EEVEE'
w=bpy.data.worlds.new("w"); sc.world=w; w.use_nodes=True
w.node_tree.nodes["Background"].inputs[0].default_value=(0.55,0.6,0.68,1)
bpy.ops.object.light_add(type='SUN',location=(4,-4,8)); bpy.context.active_object.data.energy=4
bpy.ops.object.light_add(type='AREA',location=(-4,-3,4)); bpy.context.active_object.data.energy=300
sc.render.resolution_x=560; sc.render.resolution_y=560
sc.render.filepath=os.path.join(OUT,"preview.png"); sc.render.image_settings.file_format='PNG'
bpy.ops.render.render(write_still=True); print("TRIS",len(obj.data.polygons),"DONE")
