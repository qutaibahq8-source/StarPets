import bpy, os, math
OUT=os.path.expanduser("~/StarPets/models"); os.makedirs(OUT,exist_ok=True)
def clear(): bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def setcol(o,c,rough=0.55):
    m=bpy.data.materials.new("m"); m.use_nodes=True
    b=m.node_tree.nodes.get("Principled BSDF"); b.inputs["Base Color"].default_value=c
    try: b.inputs["Roughness"].default_value=rough
    except: pass
    m.diffuse_color=c; o.data.materials.clear(); o.data.materials.append(m); return o
def join(objs,a):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active=a; bpy.ops.object.join(); return bpy.context.active_object
def sph(r,loc,scale=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r,location=loc,segments=20,ring_count=12); o=bpy.context.active_object
    if scale: o.scale=scale; bpy.ops.object.transform_apply(scale=True)
    return o
def cone(r1,d,loc,rot=(0,0,0),r2=0.0):
    bpy.ops.mesh.primitive_cone_add(radius1=r1,radius2=r2,depth=d,location=loc,rotation=rot); return bpy.context.active_object
def cyl(r,d,loc,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=r,depth=d,location=loc,rotation=rot); return bpy.context.active_object
def metabody(els):
    mb=bpy.data.metaballs.new("b"); mb.resolution=0.07; mb.render_resolution=0.07; mb.threshold=0.6
    o=bpy.data.objects.new("b",mb); bpy.context.collection.objects.link(o)
    for (loc,r) in els:
        e=mb.elements.new(); e.co=loc; e.radius=r
    bpy.context.view_layer.objects.active=o; o.select_set(True)
    bpy.ops.object.convert(target='MESH'); c=bpy.context.active_object
    bpy.ops.object.shade_smooth(); return c
def add(P,o,c,rough=0.55): bpy.ops.object.shade_smooth(); setcol(o,c,rough); P.append(o); return o

def build(cfg):
    fur=cfg["fur"]; paw=cfg.get("paw",fur); acc=cfg.get("acc",fur); eyec=cfg.get("eye",(0.9,0.65,0.15,1))
    wht=(0.95,0.95,0.93,1); blk=(0.05,0.05,0.07,1)
    g=cfg.get("girth",1.0); ml=cfg.get("muzzle",1.0); hz=cfg.get("headZ",1.02); hr=cfg.get("headR",1.0)
    els=[((0,-0.6,0.38),0.98*g),((0,0.05,0.42),1.02*g),((0,0.65,0.42),0.98*g),((0,1.2,0.34),0.86*g),
         ((0,-1.1,0.18),0.85*g),((0,-1.55,0.7),0.62),((0,-2.05,hz),0.66*hr),((0,-2.5,hz-0.18),0.33*ml*hr)]
    core=metabody(els); P=[]; add(P,core,fur)
    ll=cfg.get("legLen",1.0)
    for (x,y) in [(0.42,-1.1),(-0.42,-1.1),(0.5,1.05),(-0.5,1.05)]:
        add(P,cone(0.27,1.0,(x,y,-0.45),r2=0.16),fur); add(P,cyl(0.15,0.6,(x,y,-1.1)),fur); add(P,sph(0.2,(x,y,-1.42),(1.2,1.4,0.8)),paw)
    et=cfg.get("ear","pointy"); ez=hz+0.65
    for sx in (0.34,-0.34):
        if et=="pointy": add(P,cone(0.3,0.7,(sx,-2.0,ez)),fur); add(P,cone(0.15,0.5,(sx,-2.04,ez-0.08)),acc)
        elif et=="round": add(P,sph(0.33,(sx*1.25,-2.0,ez-0.15)),acc)
        elif et=="floppy":
            e=sph(0.28,(sx*1.55,-1.95,ez-0.6)); e.scale=(0.5,0.7,1.5); bpy.ops.object.transform_apply(scale=True); add(P,e,acc)
        elif et=="long":
            e=sph(0.26,(sx,-2.0,ez+0.55)); e.scale=(0.55,0.45,2.4); bpy.ops.object.transform_apply(scale=True); add(P,e,fur)
            e2=sph(0.15,(sx,-2.06,ez+0.55)); e2.scale=(0.5,0.4,2.0); bpy.ops.object.transform_apply(scale=True); add(P,e2,acc)
    tt=cfg.get("tail","bushy")
    if tt=="bushy": add(P,sph(0.5,(0,2.05,0.6),(1,1.7,1)),fur); add(P,sph(0.42,(0,2.8,0.95)),cfg.get("tailtip",wht))
    elif tt=="long": add(P,cone(0.22,1.6,(0,2.2,0.8),rot=(math.radians(60),0,0)),fur)
    elif tt=="stub": add(P,sph(0.32,(0,1.95,0.55)),fur)
    for sx in (0.32,-0.32):
        add(P,sph(0.16,(sx,-2.32,hz+0.04)),eyec,0.3); add(P,sph(0.085,(sx,-2.44,hz+0.03)),blk,0.3); add(P,sph(0.04,(sx+0.04,-2.49,hz+0.11)),wht,0.3)
    add(P,sph(0.12,(0,-2.78,hz-0.2)),blk,0.3)
    add(P,sph(0.3,(0.27,-2.28,0.56),(1,1.3,0.85)),wht); add(P,sph(0.3,(-0.27,-2.28,0.56),(1,1.3,0.85)),wht)
    if cfg.get("horns"):
        add(P,cone(0.16,0.7,(0.26,-2.1,hz+0.55)),(0.3,0.28,0.34,1)); add(P,cone(0.16,0.7,(-0.26,-2.1,hz+0.55)),(0.3,0.28,0.34,1))
    if cfg.get("spikes"):
        for i in range(4): add(P,cone(0.12,0.4,(0,-0.6+i*0.55,1.3)),acc)
    if cfg.get("wings"):
        for sx,r in ((0.8,55),(-0.8,-55)):
            w=sph(0.55,(sx,0.85,1.5)); w.scale=(1.7,0.1,1.15); w.rotation_euler=(math.radians(-18),0,math.radians(r)); bpy.ops.object.transform_apply(scale=True,rotation=True); add(P,w,acc)
    return join(P,core)

ANIMALS=[
 {"name":"Wolf","fur":(0.5,0.52,0.56,1),"paw":(0.3,0.31,0.34,1),"acc":(0.85,0.86,0.9,1),"eye":(0.9,0.8,0.2,1),"ear":"pointy","tail":"bushy","girth":1.1,"muzzle":1.2,"tailtip":(0.3,0.31,0.34,1)},
 {"name":"Kitten","fur":(0.85,0.85,0.87,1),"paw":(0.9,0.9,0.92,1),"acc":(1,0.8,0.85,1),"eye":(0.3,0.7,0.4,1),"ear":"pointy","tail":"long","girth":0.85,"muzzle":0.7,"headR":1.05},
 {"name":"Puppy","fur":(0.78,0.55,0.3,1),"paw":(0.6,0.42,0.22,1),"acc":(0.6,0.42,0.22,1),"eye":(0.25,0.18,0.1,1),"ear":"floppy","tail":"stub","girth":1.0,"muzzle":0.9},
 {"name":"Panda","fur":(0.95,0.95,0.95,1),"paw":(0.08,0.08,0.1,1),"acc":(0.08,0.08,0.1,1),"eye":(0.1,0.1,0.1,1),"ear":"round","tail":"stub","girth":1.25,"muzzle":0.7,"headR":1.1},
 {"name":"Dragon","fur":(0.32,0.6,0.4,1),"paw":(0.22,0.45,0.3,1),"acc":(0.5,0.9,0.55,1),"eye":(0.9,0.3,0.2,1),"ear":"pointy","tail":"long","girth":1.1,"muzzle":1.0,"horns":True,"wings":True,"spikes":True},
 {"name":"Tiger","fur":(0.9,0.55,0.15,1),"paw":(0.95,0.9,0.85,1),"acc":(0.1,0.08,0.06,1),"eye":(0.9,0.8,0.2,1),"ear":"pointy","tail":"long","girth":1.15,"muzzle":1.0},
 {"name":"Snow Leopard","fur":(0.9,0.91,0.95,1),"paw":(0.8,0.82,0.88,1),"acc":(0.6,0.62,0.7,1),"eye":(0.4,0.7,0.9,1),"ear":"pointy","tail":"long","girth":1.05,"muzzle":0.95},
 {"name":"Shadow Wolf","fur":(0.18,0.18,0.26,1),"paw":(0.1,0.1,0.14,1),"acc":(0.5,0.3,0.8,1),"eye":(0.7,0.3,1.0,1),"ear":"pointy","tail":"bushy","girth":1.1,"muzzle":1.2,"tailtip":(0.5,0.3,0.8,1)},
 {"name":"Bunny","fur":(0.95,0.93,0.96,1),"paw":(0.95,0.93,0.96,1),"acc":(1,0.8,0.85,1),"eye":(0.7,0.4,0.9,1),"ear":"long","tail":"stub","girth":0.95,"muzzle":0.6,"headR":1.1},
 {"name":"Kirin","fur":(0.95,0.85,0.4,1),"paw":(0.8,0.6,0.2,1),"acc":(1,0.95,0.6,1),"eye":(0.9,0.3,0.3,1),"ear":"pointy","tail":"long","girth":1.05,"muzzle":1.0,"horns":True,"spikes":True},
 {"name":"Celestial Dragon","fur":(0.4,0.55,0.9,1),"paw":(0.3,0.4,0.7,1),"acc":(0.7,0.85,1.0,1),"eye":(1,0.9,0.4,1),"ear":"pointy","tail":"long","girth":1.1,"muzzle":1.0,"horns":True,"wings":True,"spikes":True},
]
clear()
for i,cfg in enumerate(ANIMALS):
    obj=build(cfg); obj.name=cfg["name"]
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active=obj
    bpy.ops.wm.obj_export(filepath=os.path.join(OUT,cfg["name"]+".obj"),export_selected_objects=True,up_axis='Y',forward_axis='NEGATIVE_Z')
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT,cfg["name"]+".fbx"),use_selection=True,axis_up='Y',axis_forward='-Z')
    obj.location.x=i*6.0
    obj.rotation_euler=(0,0,math.radians(38))
bpy.ops.object.empty_add(location=((len(ANIMALS)-1)*3.0,0,0.5)); tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=((len(ANIMALS)-1)*3.0,-16,4)); cam=bpy.context.active_object
cam.constraints.new('TRACK_TO').target=tgt; cam.data.type='ORTHO'; cam.data.ortho_scale=len(ANIMALS)*6.6
sc=bpy.context.scene; sc.camera=cam; sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='STUDIO'; sc.display.shading.color_type='MATERIAL'; sc.display.shading.show_shadows=True; sc.display.shading.show_cavity=True
sc.render.resolution_x=2400; sc.render.resolution_y=440
sc.render.filepath=os.path.join(OUT,"realistic_set.png"); sc.render.image_settings.file_format='PNG'
bpy.ops.render.render(write_still=True); print("DONE")
