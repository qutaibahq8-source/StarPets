import bpy, os
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
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r,location=loc,segments=20,ring_count=12); o=bpy.context.active_object
    if scale: o.scale=scale; bpy.ops.object.transform_apply(scale=True)
    return o
def cone(r1,d,loc,rot=(0,0,0),r2=0.0):
    bpy.ops.mesh.primitive_cone_add(radius1=r1,radius2=r2,depth=d,location=loc,rotation=rot); return bpy.context.active_object
def cyl(r,d,loc,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=r,depth=d,location=loc,rotation=rot); return bpy.context.active_object
import math

def build(cfg):
    FUR=mat("fur_"+cfg['name'],cfg['fur']); ACC=mat("acc_"+cfg['name'],cfg.get('acc',cfg['fur']))
    BEL=mat("bel_"+cfg['name'],cfg.get('belly',(0.95,0.95,0.92,1))); PAW=mat("paw_"+cfg['name'],cfg.get('paw',cfg['fur']))
    EYE=mat("eye_"+cfg['name'],cfg.get('eye',(0.2,0.5,0.9,1)),0.3); BLK=mat("blk",(0.06,0.06,0.07,1),0.3); WHT=mat("wht",(0.96,0.96,0.94,1))
    g=cfg.get('girth',1.0); ln=cfg.get('len',1.0); snout=cfg.get('snout',0.34); headR=cfg.get('head',0.66); headZ=cfg.get('headZ',1.02)
    mb=bpy.data.metaballs.new("b"); mb.resolution=0.08; mb.threshold=0.6
    o=bpy.data.objects.new("B",mb); bpy.context.collection.objects.link(o)
    def el(loc,r):
        e=mb.elements.new(); e.co=loc; e.radius=r
    el((0,1.2*ln,0.34),0.85*g); el((0,0.6*ln,0.42),0.98*g); el((0,0.0,0.42),1.02*g)
    el((0,-0.6*ln,0.4),0.96*g); el((0,-1.1*ln,0.2),0.82*g); el((0,-1.5*ln,0.72),0.6*g)
    el((0,-2.0*ln,headZ),headR); el((0,(-2.0*ln-snout),headZ-0.18),headR*0.5)
    bpy.context.view_layer.objects.active=o; o.select_set(True); bpy.ops.object.convert(target='MESH')
    core=bpy.context.active_object; core.name="core"; bpy.ops.object.shade_smooth(); setmat(core,FUR); P=[core]
    def add(ob,m): bpy.ops.object.shade_smooth(); setmat(ob,m); P.append(ob); return ob
    L=cfg.get('legLen',1.0); fy=-1.1*ln; by=1.05*ln
    for (x,y) in [(0.42*g,fy),(-0.42*g,fy),(0.5*g,by),(-0.5*g,by)]:
        add(cone(0.27,1.0*L,(x,y,-0.45),r2=0.16),FUR); add(cyl(0.15,0.6*L,(x,y,-0.45-0.6*L)),PAW); add(sph(0.19,(x,y,-0.78-1.2*L+0.5),(1.2,1.4,0.8)),PAW)
    hy=-2.0*ln; et=cfg.get('ear','pointy'); es=cfg.get('earSize',1.0)
    for x in (0.34,-0.34):
        if et=='pointy': add(cone(0.3*es,0.7*es,(x,hy+0.05,headZ+0.7*es)),FUR); add(cone(0.15*es,0.5*es,(x,hy,headZ+0.62*es)),ACC)
        elif et=='round': add(sph(0.34*es,(x*1.3,hy+0.05,headZ+0.55*es)),FUR); add(sph(0.18*es,(x*1.3,hy-0.1,headZ+0.55*es)),ACC)
        elif et=='long':
            e=sph(0.22,(x,hy+0.1,headZ+0.9*es)); e.scale=(0.7,0.5,2.2*es); bpy.ops.object.transform_apply(scale=True); add(e,FUR)
        elif et=='floppy':
            e=sph(0.26,(x*1.5,hy+0.2,headZ-0.1)); e.scale=(0.5,0.8,1.4*es); bpy.ops.object.transform_apply(scale=True); add(e,ACC)
    tl=cfg.get('tail','bushy'); ty=1.3*ln
    if tl=='bushy': add(sph(0.5,(0,ty+0.6,0.6),(1,1.7,1)),FUR); add(sph(0.42,(0,ty+1.4,0.95)),WHT)
    elif tl=='long': add(cone(0.28,1.6,(0,ty+0.7,0.55),rot=(math.radians(-60),0,0)),FUR)
    elif tl=='short': add(sph(0.32,(0,ty+0.3,0.45)),FUR)
    elif tl=='curl': add(sph(0.3,(0,ty+0.4,0.9)),FUR)
    for x in (0.35,-0.35):
        add(sph(0.15,(x,hy-snout*0.5,headZ+0.08)),EYE); add(sph(0.08,(x,hy-snout*0.5-0.12,headZ+0.07)),BLK); add(sph(0.04,(x+0.04,hy-snout*0.5-0.16,headZ+0.15)),WHT)
    add(sph(0.13,(0,(-2.0*ln-snout-0.25),headZ-0.2)),BLK)
    add(sph(0.5,(0,-1.4*ln,-0.1),(1,1.6,0.7)),BEL)
    if cfg.get('horn'): add(cone(0.16,1.0,(0,hy-0.4,headZ+0.55)),mat("horn",(1,0.9,0.5,1),0.3))
    if cfg.get('wings'):
        for x,r in ((1.0,28),(-1.0,-28)):
            w=sph(0.6,(x,0.4,0.7)); w.scale=(1.7,0.13,1.2); w.rotation_euler=(0,0,math.radians(r)); bpy.ops.object.transform_apply(scale=True,rotation=True); add(w,ACC)
    obj=join(P,core); obj.name=cfg['name']
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active=obj
    bpy.ops.wm.obj_export(filepath=os.path.join(OUT,cfg['name']+".obj"),export_selected_objects=True,up_axis='Y',forward_axis='NEGATIVE_Z')
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT,cfg['name']+".fbx"),use_selection=True,axis_up='Y',axis_forward='-Z')
    return obj

cfgs=[
 {'name':'Fox','fur':(0.82,0.42,0.18,1),'ear':'pointy','tail':'bushy','eye':(0.9,0.65,0.15,1),'paw':(0.08,0.08,0.09,1)},
 {'name':'Wolf','fur':(0.45,0.46,0.5,1),'ear':'pointy','tail':'bushy','len':1.15,'girth':1.1,'eye':(0.95,0.85,0.2,1),'belly':(0.7,0.7,0.72,1)},
 {'name':'Kitten','fur':(0.9,0.6,0.3,1),'ear':'pointy','tail':'long','len':0.85,'eye':(0.3,0.8,0.4,1),'earSize':0.8},
 {'name':'Puppy','fur':(0.6,0.42,0.25,1),'ear':'floppy','tail':'short','len':0.9,'eye':(0.25,0.18,0.12,1)},
 {'name':'Panda','fur':(0.96,0.96,0.96,1),'ear':'round','tail':'short','girth':1.15,'acc':(0.06,0.06,0.08,1),'paw':(0.06,0.06,0.08,1),'belly':(0.96,0.96,0.96,1)},
 {'name':'Bunny','fur':(0.93,0.92,0.95,1),'ear':'long','tail':'curl','len':0.7,'girth':1.0,'acc':(1,0.8,0.85,1),'eye':(0.4,0.2,0.6,1)},
 {'name':'Dragon','fur':(0.3,0.62,0.4,1),'ear':'pointy','tail':'long','len':1.1,'horn':True,'wings':True,'acc':(0.5,0.85,0.55,1),'eye':(0.95,0.4,0.2,1)},
 {'name':'Unicorn','fur':(0.96,0.92,0.97,1),'ear':'pointy','tail':'long','len':1.1,'girth':1.05,'horn':True,'acc':(1,0.7,0.85,1),'eye':(0.5,0.3,0.7,1)},
]
clear()
for i,c in enumerate(cfgs):
    obj=build(c); obj.location.x=i*5.0; obj.rotation_euler=(0,0,__import__('math').radians(32))
bpy.ops.object.empty_add(location=((len(cfgs)-1)*2.5,-0.6,0.4)); tgt=bpy.context.active_object
bpy.ops.object.camera_add(location=((len(cfgs)-1)*2.5,-22,5)); cam=bpy.context.active_object
cam.constraints.new('TRACK_TO').target=tgt; cam.data.type='ORTHO'; cam.data.ortho_scale=len(cfgs)*5.6
sc=bpy.context.scene; sc.camera=cam; sc.render.engine='BLENDER_WORKBENCH'
sc.display.shading.light='STUDIO'; sc.display.shading.color_type='MATERIAL'; sc.display.shading.show_shadows=True; sc.display.shading.show_cavity=True
sc.render.resolution_x=2600; sc.render.resolution_y=620
sc.render.filepath=os.path.join(OUT,"realistic_set.png"); sc.render.image_settings.file_format='PNG'
bpy.ops.render.render(write_still=True); print("DONE")
