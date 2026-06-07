import bpy, os, math
OUT=os.path.expanduser("~/StarPets/models"); os.makedirs(OUT,exist_ok=True)
def clear(): bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def mat(n,c,r=0.55):
    m=bpy.data.materials.get(n) or bpy.data.materials.new(n); m.use_nodes=True
    b=m.node_tree.nodes.get("Principled BSDF"); b.inputs["Base Color"].default_value=c
    try: b.inputs["Roughness"].default_value=r
    except: pass
    m.diffuse_color=c; return m
def setmat(o,m): o.data.materials.clear(); o.data.materials.append(m)
def join(objs,a):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active=a; bpy.ops.object.join(); return bpy.context.active_object
def sph(r,loc,scale=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r,location=loc,segments=24,ring_count=16); o=bpy.context.active_object
    if scale: o.scale=scale; bpy.ops.object.transform_apply(scale=True)
    return o
def cone(r1,d,loc,rot=(0,0,0),r2=0.0):
    bpy.ops.mesh.primitive_cone_add(radius1=r1,radius2=r2,depth=d,location=loc,rotation=rot); return bpy.context.active_object
def cyl(r,d,loc,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=r,depth=d,location=loc,rotation=rot); return bpy.context.active_object
clear()
FUR=mat("fur",(0.82,0.42,0.18,1)); WHT=mat("wht",(0.95,0.95,0.93,1)); BLK=mat("blk",(0.06,0.06,0.07,1),0.3); AMB=mat("amb",(0.9,0.65,0.15,1),0.3)
# --- SMOOTH organic body via metaballs (they blend seamlessly) ---
mb=bpy.data.metaballs.new("body"); mb.resolution=0.07; mb.render_resolution=0.07; mb.threshold=0.6
mbobj=bpy.data.objects.new("Body",mb); bpy.context.collection.objects.link(mbobj)
def el(loc,r):
    e=mb.elements.new(); e.co=loc; e.radius=r; return e
el((0,-0.6,0.38),0.98); el((0,0.05,0.42),1.02); el((0,0.65,0.42),0.98); el((0,1.2,0.34),0.85)
el((0,-1.1,0.18),0.85); el((0,-1.55,0.7),0.62); el((0,-2.05,1.02),0.66); el((0,-2.5,0.84),0.33)
bpy.context.view_layer.objects.active=mbobj; mbobj.select_set(True)
bpy.ops.object.convert(target='MESH'); core=bpy.context.active_object; core.name="core"
bpy.ops.object.shade_smooth(); setmat(core,FUR); P=[core]
def add(o,m): bpy.ops.object.shade_smooth(); setmat(o,m); P.append(o); return o
for (x,y) in [(0.42,-1.1),(-0.42,-1.1),(0.5,1.05),(-0.5,1.05)]:
    add(cone(0.27,1.0,(x,y,-0.45),r2=0.16),FUR); add(cyl(0.15,0.6,(x,y,-1.1)),FUR); add(sph(0.19,(x,y,-1.42),(1.2,1.4,0.8)),BLK)
add(cone(0.3,0.7,(0.34,-2.0,1.72)),FUR); add(cone(0.3,0.7,(-0.34,-2.0,1.72)),FUR)
add(cone(0.15,0.5,(0.34,-2.05,1.64)),WHT); add(cone(0.15,0.5,(-0.34,-2.05,1.64)),WHT)
add(sph(0.5,(0,2.05,0.6),(1,1.7,1)),FUR); add(sph(0.42,(0,2.8,0.95)),WHT)
for x in (0.35,-0.35):
    add(sph(0.15,(x,-2.27,1.1)),AMB); add(sph(0.08,(x,-2.39,1.09)),BLK); add(sph(0.04,(x+0.04,-2.44,1.17)),WHT)
add(sph(0.13,(0,-2.83,0.84)),BLK)
add(sph(0.32,(0.28,-2.3,0.58),(1,1.3,0.85)),WHT); add(sph(0.32,(-0.28,-2.3,0.58),(1,1.3,0.85)),WHT)
add(sph(0.5,(0,-1.4,-0.1),(1,1.6,0.7)),WHT)
obj=join(P,core); obj.name="StarPet_Fox"
bpy.ops.wm.obj_export(filepath=os.path.join(OUT,"StarPet_Fox.obj"),up_axis='Y',forward_axis='NEGATIVE_Z')
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT,"StarPet_Fox.fbx"),use_selection=False,axis_up='Y',axis_forward='-Z')
bpy.ops.object.empty_add(location=(0,-0.3,0.5)); tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=(4.5,-5.5,2.6)); cam=bpy.context.active_object
cam.constraints.new('TRACK_TO').target=tgt
sc=bpy.context.scene; sc.camera=cam; sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='STUDIO'; sc.display.shading.color_type='MATERIAL'; sc.display.shading.show_shadows=True; sc.display.shading.show_cavity=True
sc.render.resolution_x=520; sc.render.resolution_y=520
sc.render.filepath=os.path.join(OUT,"preview.png"); sc.render.image_settings.file_format='PNG'
bpy.ops.render.render(write_still=True); print("TRIS",len(obj.data.polygons),"DONE")
