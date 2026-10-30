"""Author ONE new straight punch as a baked Blender Action on an existing VRM.

This does not load Astral Rivals' old animation or run procedural corrections
in the game. The explicit anticipation/drive/contact/recoil design below is
sampled to editable bone keys; feet are solved against fixed floor anchors.
No geometry, material, expression or skin weight is changed by this module.
Call ``build(armature, human_bones=None)`` from the private Blender workflow.
"""
import math
import bpy
from mathutils import Vector, Quaternion, Matrix

FPS = 30
DURATION = 1.2
CONTACT_TIME = 0.4
ACTION = 'Kaizen_Straight_Punch'


def _smooth(t):
    t = max(0.0, min(1.0, t))
    return t*t*(3.0-2.0*t)


def _window(t, a, b):
    return _smooth((t-a)/max(1e-6, b-a))


def _names(rig, supplied):
    result = dict(supplied or {})
    if not result:
        try:
            mapping=rig.data.vrm_addon_extension.vrm1.humanoid.human_bones.human_bone_name_to_human_bone()
            result={getattr(key,'value',str(key)):value.node.bone_name for key,value in mapping.items() if value.node.bone_name}
        except (AttributeError,TypeError):
            pass
    # VRoid's original names are a fallback; the VRM addon map takes priority.
    for semantic, stem in [('hips','Hips'),('spine','Spine'),('chest','Chest'),
                           ('upperChest','UpperChest'),('neck','Neck'),('head','Head')]:
        result.setdefault(semantic, 'J_Bip_C_'+stem)
    for side, letter in [('left','L'),('right','R')]:
        for semantic, stem in [('Shoulder','Shoulder'),('UpperArm','UpperArm'),
                              ('LowerArm','LowerArm'),('Hand','Hand'),
                              ('UpperLeg','UpperLeg'),('LowerLeg','LowerLeg'),
                              ('Foot','Foot'),('Toes','ToeBase')]:
            result.setdefault(side+semantic,'J_Bip_'+letter+'_'+stem)
        for digit in ['Index','Middle','Ring','Little']:
            stem = 'Little' if digit == 'Little' else digit
            for index, joint in enumerate(['Proximal','Intermediate','Distal'],1):
                result.setdefault(side+digit+joint,'J_Bip_'+letter+'_'+stem+str(index))
        for index, joint in enumerate(['Metacarpal','Proximal','Distal'],1):
            result.setdefault(side+'Thumb'+joint,'J_Bip_'+letter+'_Thumb'+str(index))
    return {key:name for key,name in result.items() if name in rig.pose.bones}


class Author:
    def __init__(self, rig, human_bones):
        self.rig = rig
        self.names = _names(rig,human_bones)
        required = ['hips','spine','chest','neck','head']
        for side in ['left','right']:
            required += [side+x for x in ['UpperArm','LowerArm','Hand','UpperLeg','LowerLeg','Foot']]
            required += [side+d+j for d in ['Index','Middle','Ring','Little']
                         for j in ['Proximal','Intermediate','Distal']]
            required += [side+'Thumb'+j for j in ['Metacarpal','Proximal','Distal']]
        missing = sorted(set(required)-set(self.names))
        if missing:
            raise ValueError('Missing existing humanoid joints: '+', '.join(missing))
        self.rest = {key:rig.data.bones[name].matrix_local.copy() for key,name in self.names.items()}
        self.up = (self.origin('head')-self.origin('hips')).normalized()
        self.left = (self.origin('leftUpperArm')-self.origin('rightUpperArm')).normalized()
        self.front = self.left.cross(self.up).normalized()
        self.scale = (self.origin('head')-self.origin('leftFoot')).dot(self.up)/1.46
        self.hip = self.origin('hips')
        self.foot = {}
        for side, sign in [('left',1),('right',-1)]:
            old = self.origin(side+'Foot')
            x = (old-self.hip).dot(self.left)
            # Modest spread and stagger, not a long cartoon lunge.
            self.foot[side] = old+self.left*(sign*.135*self.scale-x)+self.front*(.15 if sign>0 else -.17)*self.scale

    def pb(self, name):
        return self.rig.pose.bones[self.names[name]]

    def origin(self,name):
        return self.rest[name].translation.copy()

    def posed(self,name):
        return self.pb(name).head.copy()

    def update(self):
        bpy.context.view_layer.update()

    def global_rotation(self,name,rotation):
        pb = self.pb(name)
        rest = pb.bone.matrix_local.to_quaternion()
        if pb.parent:
            local_rest = pb.parent.bone.matrix_local.to_quaternion().inverted() @ rest
            desired = pb.parent.matrix.to_quaternion().inverted() @ rotation
            pb.rotation_quaternion = (local_rest.inverted() @ desired).normalized()
        else:
            pb.rotation_quaternion = (rest.inverted() @ rotation).normalized()
        self.update()

    def swing(self,name,child,direction,reference):
        original = (self.origin(child)-self.origin(name)).normalized()
        aim = (reference @ original).rotation_difference(Vector(direction).normalized())
        self.global_rotation(name,aim @ reference @ self.rest[name].to_quaternion())

    def two_bone(self,upper,lower,end,target,hint,reference):
        start = self.posed(upper)
        l1 = (self.origin(upper)-self.origin(lower)).length
        l2 = (self.origin(lower)-self.origin(end)).length
        aim = Vector(target)-start
        distance = max(abs(l1-l2)+.0001,min(aim.length,(l1+l2)*.97))
        axis = aim.normalized()
        pole = Vector(hint)-start
        pole -= axis*pole.dot(axis)
        if pole.length < .0001: pole = self.front-axis*self.front.dot(axis)
        pole.normalize()
        x = (l1*l1-l2*l2+distance*distance)/(2*distance)
        elbow = start+axis*x+pole*math.sqrt(max(0,l1*l1-x*x))
        self.swing(upper,lower,elbow-start,reference)
        self.swing(lower,end,start+axis*distance-self.posed(lower),reference)
        return (self.posed(end)-self.posed(lower)).normalized()

    @staticmethod
    def frame(direction,palm):
        y=Vector(direction).normalized();z=Vector(palm)-y*Vector(palm).dot(y)
        if z.length < .0001:z=Vector((0,0,1))-y*y.z
        z.normalize();x=y.cross(z).normalized()
        return Matrix((x,y,x.cross(y))).transposed().to_quaternion()

    def hand(self,side,direction,palm):
        forward=(self.origin(side+'MiddleProximal')-self.origin(side+'Hand')).normalized()
        across=self.origin(side+'IndexProximal')-self.origin(side+'LittleProximal')
        normal=forward.cross(across).normalized()*(1 if side=='left' else -1)
        frame=self.frame(forward,normal)
        correction=self.rest[side+'Hand'].to_quaternion().inverted() @ frame
        self.global_rotation(side+'Hand',self.frame(direction,palm) @ correction.inverted())

    def fingers(self,side,amount):
        hand=side+'Hand';forward=(self.origin(side+'MiddleProximal')-self.origin(hand)).normalized()
        across=self.origin(side+'IndexProximal')-self.origin(side+'LittleProximal')
        palm=forward.cross(across).normalized()*(1 if side=='left' else -1)
        for digit_index,digit in enumerate(['Index','Middle','Ring','Little']):
            for joint_index,joint in enumerate(['Proximal','Intermediate','Distal']):
                name=side+digit+joint;pb=self.pb(name)
                children=list(pb.bone.children)
                direction=(children[0].head_local-pb.bone.head_local) if children else (pb.bone.head_local-pb.bone.parent.head_local)
                world_axis=direction.normalized().cross(palm).normalized()
                local_axis=self.rest[name].to_quaternion().inverted() @ world_axis
                angle=[68+digit_index*2,90,48][joint_index]
                pb.rotation_quaternion=Quaternion(local_axis,math.radians(angle)*amount)
        self.update()
        # Fit thumb along the OUTSIDE of the finger roll using existing joints.
        names=[side+'Thumb'+x for x in ['Metacarpal','Proximal','Distal']]
        hand_delta=self.pb(hand).matrix.to_quaternion() @ self.rest[hand].to_quaternion().inverted()
        posed_palm=hand_delta @ palm;posed_forward=hand_delta @ forward
        span=(self.origin(hand)-self.origin(side+'MiddleProximal')).length
        first=self.posed(side+'IndexProximal')-posed_forward*span*.35+posed_palm*span*.20
        self.swing(names[0],names[1],first-self.posed(names[0]),hand_delta)
        target=(self.posed(side+'IndexIntermediate')+self.posed(side+'MiddleIntermediate'))*.5-posed_forward*span*.12+posed_palm*span*.1
        start=self.posed(names[1]);l1=(self.origin(names[1])-self.origin(names[2])).length
        children=list(self.pb(names[2]).bone.children)
        tip=(children[0].head_local-self.origin(names[2])).length if children else self.pb(names[2]).bone.length
        aim=target-start;d=max(abs(l1-tip)+.0001,min(aim.length,(l1+tip)*.995));axis=aim.normalized()
        pole=posed_palm-axis*posed_palm.dot(axis);pole.normalize()
        x=(l1*l1-tip*tip+d*d)/(2*d)
        bend=start+axis*x+pole*math.sqrt(max(0,l1*l1-x*x))
        self.swing(names[1],names[2],bend-start,hand_delta)
        rest_dir=(children[0].head_local-self.origin(names[2])) if children else (self.origin(names[2])-self.origin(names[1]))
        q=(hand_delta @ rest_dir.normalized()).rotation_difference(start+axis*d-self.posed(names[2]))
        self.global_rotation(names[2],q @ hand_delta @ self.rest[names[2]].to_quaternion())

    def pose(self,t):
        for name in self.names:
            pb=self.pb(name);pb.rotation_mode='QUATERNION';pb.rotation_quaternion=Quaternion();pb.location=Vector()
        self.update()
        coil=_window(t,.02,.20)*(1-_window(t,.22,.36))
        drive=_window(t,.20,.38)*(1-_window(t,.47,.90))
        if t <= .22: extension=0.0
        elif t <= CONTACT_TIME:extension=((t-.22)/(CONTACT_TIME-.22))**2
        elif t <= .433:extension=1.0
        elif t <= .60:extension=(1-(t-.433)/(.60-.433))**2
        else:extension=0.0
        hip_yaw=math.radians(-10+8*coil-12*drive)
        chest_yaw=math.radians(-6+7*coil-9*drive)
        hip_delta=self.front*((-.022*coil+.040*drive)*self.scale)+self.left*((-.012*coil+.014*drive)*self.scale)-self.up*((.066+.010*coil-.014*drive)*self.scale)
        self.pb('hips').location=self.rest['hips'].to_quaternion().inverted() @ hip_delta
        hip_q=Quaternion(self.up,hip_yaw)
        self.global_rotation('hips',hip_q @ self.rest['hips'].to_quaternion())
        core=Quaternion(self.up,chest_yaw) @ hip_q
        lean=Quaternion(self.left,math.radians(1+3*drive))
        for name,weight in [('spine',.38),('chest',.78),('upperChest',1.0)]:
            if name in self.names:
                rotation=Quaternion(self.up,hip_yaw+chest_yaw*weight) @ Quaternion(self.left,math.radians((1+3*drive)*weight))
                self.global_rotation(name,rotation @ self.rest[name].to_quaternion())
        self.global_rotation('neck',Quaternion(self.up,(hip_yaw+chest_yaw)*.25) @ self.rest['neck'].to_quaternion())
        self.global_rotation('head',Quaternion(self.left,math.radians(2.5)) @ self.rest['head'].to_quaternion())
        for side,sign in [('left',1),('right',-1)]:
            if side+'Shoulder' in self.names:
                extra=math.radians(-6*drive) if sign>0 else 0
                self.global_rotation(side+'Shoulder',Quaternion(self.up,extra) @ core @ lean @ self.rest[side+'Shoulder'].to_quaternion())
            foot_rotation=Quaternion(self.up,math.radians(4 if sign>0 else -15))
            ankle=self.foot[side].copy()
            if sign<0 and side+'Toes' in self.names:
                offset=self.origin(side+'Toes')-self.origin(side+'Foot')
                anchor=ankle+foot_rotation @ offset
                foot_rotation=Quaternion(self.up,math.radians(-15+7*drive)) @ Quaternion(self.left,math.radians(5*drive))
                ankle=anchor-foot_rotation @ offset
            hint=self.hip+self.left*sign*.14*self.scale+self.front*.32*self.scale-self.up*.32*self.scale
            self.two_bone(side+'UpperLeg',side+'LowerLeg',side+'Foot',ankle,hint,hip_q)
            self.global_rotation(side+'Foot',foot_rotation @ self.rest[side+'Foot'].to_quaternion())
            if side+'Toes' in self.names:self.global_rotation(side+'Toes',Quaternion(self.up,math.radians(4 if sign>0 else -15+7*drive)) @ self.rest[side+'Toes'].to_quaternion())
        head=self.posed('head')
        for side,sign in [('left',1),('right',-1)]:
            start=self.posed(side+'UpperArm')
            guard=head+self.left*sign*(.125 if sign>0 else .11)*self.scale-self.up*(.14 if sign>0 else .105)*self.scale+self.front*(.235 if sign>0 else .18)*self.scale
            wrist=guard.copy();hint=start+self.left*sign*.18*self.scale-self.up*.28*self.scale+self.front*.07*self.scale
            if sign>0:
                wrist-=self.front*.035*self.scale*coil
                length=(self.origin(side+'UpperArm')-self.origin(side+'LowerArm')).length+(self.origin(side+'LowerArm')-self.origin(side+'Hand')).length
                impact=start+(self.front-self.up*.035+self.left*.015).normalized()*length*.945
                wrist=wrist.lerp(impact,extension)
                hint=hint.lerp(start+self.left*.09*self.scale-self.up*.18*self.scale+self.front*.22*self.scale,extension)
            direction=self.two_bone(side+'UpperArm',side+'LowerArm',side+'Hand',wrist,hint,core)
            palm=(-self.front).lerp(-self.up,extension if sign>0 else 0).normalized()
            self.hand(side,direction,palm)
            self.fingers(side,.90+.10*extension)
        self.update()


def build(armature,human_bones=None):
    """Bake editable 30fps keys and return non-identifying timing metadata."""
    author=Author(armature,human_bones)
    if not armature.animation_data:armature.animation_data_create()
    action=bpy.data.actions.new(ACTION)
    armature.animation_data.action=action
    scene=bpy.context.scene;scene.render.fps=FPS;scene.frame_start=1;scene.frame_end=1+round(DURATION*FPS)
    previous={}
    for frame in range(scene.frame_start,scene.frame_end+1):
        scene.frame_set(frame);author.pose((frame-1)/FPS)
        for semantic,name in author.names.items():
            pb=armature.pose.bones[name]
            q=pb.rotation_quaternion.copy()
            if name in previous and previous[name].dot(q)<0:q.negate();pb.rotation_quaternion=q
            previous[name]=q.copy()
            pb.keyframe_insert('rotation_quaternion',frame=frame,group=name)
            if semantic=='hips':pb.keyframe_insert('location',frame=frame,group=name)
    for curve in action.fcurves:
        for key in curve.keyframe_points:key.interpolation='LINEAR'
    action['authoring']='Original manually designed straight-punch key poses; no source motion retarget'
    action['contact_seconds']=CONTACT_TIME
    scene.frame_set(1);bpy.context.view_layer.update()
    return {'action':action.name,'fps':FPS,'duration':DURATION,'windup_seconds':.20,
            'contact_seconds':CONTACT_TIME,'recovery_seconds':.60,'return_seconds':DURATION,
            'baked_frames':scene.frame_end-scene.frame_start+1,'humanoid_bones_keyed':len(author.names)}
