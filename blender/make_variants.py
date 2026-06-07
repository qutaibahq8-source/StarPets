import bpy, os, math
OUT=os.path.expanduser("~/StarPets/models"); os.makedirs(OUT,exist_ok=True)

def clear(): bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def mat(name,rgba,rough=0.6):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes=True; b=m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value=rgba
    try: b.inputs["Roughness"].default_value=rough
    except: pass
    m.diffuse_color=rgba; return m
def setmat(o,m): o.data.materials.clear(); o.data.materials.append(m)
def join(objs,a):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active=a; bpy.ops.object.join(); return bpy.context.active_object
def add(prim,m,**kw):
    prim(**kw); o=bpy.context.active_object; bpy.ops.object.shade_smooth(); setmat(o,m); return o

WHT=mat("wht",(1,1,1,1)); BLK=mat("blk",(0.05,0.05,0.07,1),0.3); PINK=mat("pink",(1,0.55,0.62,1))
NAVY=mat("navy",(0.10,0.11,0.20,1),0.25); BLUSH=mat("blush",(1,0.5,0.55,1))

def build(cfg):
    fur=mat("fur_"+cfg['name'],cfg['fur']); acc=mat("acc_"+cfg['name'],cfg.get('accent',cfg['fur']))
    h=add(bpy.ops.mesh.primitive_uv_sphere_add,fur,radius=1.25,location=(0,-0.5,0.62))
    b=add(bpy.ops.mesh.primitive_uv_sphere_add,fur,radius=1.05,location=(0,0.6,-0.2)); b.scale=(1,1.05,1); bpy.ops.object.transform_apply(scale=True)
    core=join([h,b],h); rm=core.modifiers.new("rm",'REMESH'); rm.mode='VOXEL'; rm.voxel_size=0.08
    bpy.context.view_layer.objects.active=core; bpy.ops.object.modifier_apply(modifier=rm.name)
    bpy.ops.object.shade_smooth(); setmat(core,fur); P=[core]
    et=cfg.get('ear')
    for x in (0.55,-0.55):
        if et=='pointy': P.append(add(bpy.ops.mesh.primitive_cone_add,fur,radius1=0.33,depth=0.85,location=(x,-0.55,1.6)))
        elif et=='long':
            e=add(bpy.ops.mesh.primitive_uv_sphere_add,fur,radius=0.3,location=(x*0.5,-0.55,1.9)); e.scale=(0.6,0.5,2.2); bpy.ops.object.transform_apply(scale=True); P.append(e)
        elif et=='round':
            P.append(add(bpy.ops.mesh.primitive_uv_sphere_add,acc,radius=0.42,location=(x,-0.55,1.5)))
        elif et=='floppy':
            e=add(bpy.ops.mesh.primitive_uv_sphere_add,acc,radius=0.3,location=(x*1.15,-0.4,0.7)); e.scale=(0.5,0.7,1.4); bpy.ops.object.transform_apply(scale=True); P.append(e)
    # eyes (soft & cute: white sclera, navy iris, BIG shines)
    for x in (0.45,-0.45):
        P.append(add(bpy.ops.mesh.primitive_uv_sphere_add,WHT,radius=0.36,location=(x,-1.45,0.78)))
        P.append(add(bpy.ops.mesh.primitive_uv_sphere_add,NAVY,radius=0.21,location=(x,-1.7,0.74)))
        P.append(add(bpy.ops.mesh.primitive_uv_sphere_add,WHT,radius=0.12,location=(x+0.07,-1.86,0.9)))
        P.append(add(bpy.ops.mesh.primitive_uv_sphere_add,WHT,radius=0.06,location=(x-0.08,-1.84,0.66)))
        if cfg.get('patches'): P.append(add(bpy.ops.mesh.primitive_uv_sphere_add,BLK,radius=0.42,location=(x,-1.3,0.78)))
    # blush cheeks
    for x in (0.72,-0.72):
        bl=add(bpy.ops.mesh.primitive_uv_sphere_add,BLUSH,radius=0.2,location=(x,-1.35,0.4)); bl.scale=(1,0.25,0.7); bpy.ops.object.transform_apply(scale=True); P.append(bl)
    P.append(add(bpy.ops.mesh.primitive_uv_sphere_add,PINK,radius=0.14,location=(0,-1.78,0.5)))
    # legs
    for x in (0.5,-0.5):
        for y in (-0.45,0.75):
            P.append(add(bpy.ops.mesh.primitive_cylinder_add,fur,radius=0.27,depth=0.55,location=(x,y,-1.0)))
            P.append(add(bpy.ops.mesh.primitive_uv_sphere_add,fur,radius=0.3,location=(x,y,-1.25)))
    # tail
    t=cfg.get('tail')
    if t=='fluffy': P.append(add(bpy.ops.mesh.primitive_uv_sphere_add,acc,radius=0.5,location=(0,1.5,0.3)))
    elif t=='long': P.append(add(bpy.ops.mesh.primitive_cone_add,fur,radius1=0.3,depth=1.3,location=(0,1.5,0.3),rotation=(math.radians(-55),0,0)))
    if cfg.get('horn'):
        hn=add(bpy.ops.mesh.primitive_cone_add,acc,radius1=0.18,depth=0.9,location=(0,-1.3,1.55)); P.append(hn)
    if cfg.get('wings'):
        for x,r in ((1.0,25),(-1.0,-25)):
            w=add(bpy.ops.mesh.primitive_uv_sphere_add,acc,radius=0.6,location=(x,0.7,0.6)); w.scale=(1.6,0.15,1.1); 
            w.rotation_euler=(0,0,math.radians(r)); bpy.ops.object.transform_apply(scale=True,rotation=True); P.append(w)
    if cfg.get('beak'):
        P.append(add(bpy.ops.mesh.primitive_cone_add,mat("beak",(1,0.75,0.2,1)),radius1=0.2,depth=0.4,location=(0,-1.75,0.5),rotation=(math.radians(90),0,0)))
    return join(P,core)

cfgs=[
 {'name':'Kitten','fur':(0.96,0.62,0.3,1),'ear':'pointy','tail':'long','accent':(0.96,0.62,0.3,1)},
 {'name':'Bunny','fur':(0.95,0.93,0.96,1),'ear':'long','tail':'fluffy','accent':(1,0.85,0.9,1)},
 {'name':'Fox','fur':(0.9,0.42,0.18,1),'ear':'pointy','tail':'fluffy','accent':(1,1,1,1)},
 {'name':'Panda','fur':(0.96,0.96,0.96,1),'ear':'round','accent':(0.06,0.06,0.08,1),'patches':True,'tail':'fluffy'},
 {'name':'Dragon','fur':(0.35,0.7,0.42,1),'ear':'pointy','tail':'long','accent':(0.5,0.9,0.55,1),'horn':True,'wings':True},
 {'name':'Unicorn','fur':(0.97,0.9,0.98,1),'ear':'pointy','tail':'fluffy','accent':(1,0.7,0.85,1),'horn':True},
]
clear()
for i,cfg in enumerate(cfgs):
    obj=build(cfg); obj.name=cfg['name']
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active=obj
    bpy.ops.wm.obj_export(filepath=os.path.join(OUT,cfg['name']+".obj"),export_selected_objects=True,up_axis='Y',forward_axis='NEGATIVE_Z')
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT,cfg['name']+".fbx"),use_selection=True,axis_up='Y',axis_forward='-Z')
    obj.location.x=i*4.0
# group render
bpy.ops.object.empty_add(location=((len(cfgs)-1)*2.0,-0.3,0.4)); tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=((len(cfgs)-1)*2.0,-16,3.5)); cam=bpy.context.active_object
cam.constraints.new('TRACK_TO').target=tgt; cam.data.type='ORTHO'; cam.data.ortho_scale=len(cfgs)*4.4
sc=bpy.context.scene; sc.camera=cam; sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='STUDIO'; sc.display.shading.color_type='MATERIAL'
sc.display.shading.show_shadows=True; sc.display.shading.show_cavity=True
sc.render.resolution_x=1500; sc.render.resolution_y=300
sc.render.filepath=os.path.join(OUT,"variants.png"); sc.render.image_settings.file_format='PNG'
bpy.ops.render.render(write_still=True); print("DONE")
