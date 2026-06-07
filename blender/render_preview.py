import bpy, os, math
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.ops.wm.obj_import(filepath=os.path.expanduser("~/StarPets/models/StarPet_Critter.obj"))
obj = bpy.context.selected_objects[0]
# empty target at model center
bpy.ops.object.empty_add(location=(0,0,0.3)); tgt = bpy.context.active_object
# camera looking at it
bpy.ops.object.camera_add(location=(5,-6,3.5)); cam = bpy.context.active_object
c = cam.constraints.new('TRACK_TO'); c.target = tgt
bpy.context.scene.camera = cam
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.resolution_x = 420; sc.render.resolution_y = 420
sc.render.filepath = os.path.expanduser("~/StarPets/models/preview.png")
sc.render.image_settings.file_format = 'PNG'
try:
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.show_cavity = True
except Exception as e:
    print("shade cfg:", e)
bpy.ops.render.render(write_still=True)
print("RENDERED")
