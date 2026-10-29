"""Author Astral Rivals' original skinned character assets in Blender 4.3+.

No primitive character bodies are instantiated: anatomy, garments, faces and
curved hair locks are authored as smooth lofts and hand-shaped surfaces. The
result is a real armature-deformed GLB, with reusable keyed animation clips.
Run: blender --background --python tools/blender/build_characters.py
"""
import bpy, math, sys, json, os
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets'/'characters'
OUT.mkdir(parents=True,exist_ok=True)
SOURCE=ROOT/'tools'/'blender'/'source'
SOURCE.mkdir(parents=True,exist_ok=True)
(SOURCE/'.gdignore').touch()
REVIEWS=OUT/'reviews'
REVIEWS.mkdir(parents=True,exist_ok=True)
(REVIEWS/'.gdignore').touch()
sys.path.insert(0,str(Path(__file__).parent))
PARTS=[]
MAT={}
PAL={
 'kaizen':{'cloth':(0.025,.16,.49,1),'cloth_light':(.055,.32,.75,1),'hair':(.012,.018,.036,1),'hair_light':(.035,.065,.12,1),'energy':(.16,.69,1,1),'gold':(.84,.59,.18,1),'skin':(.69,.39,.24,1)},
 'ryuzen':{'cloth':(.027,.029,.055,1),'cloth_light':(.10,.095,.17,1),'hair':(.055,.06,.085,1),'hair_light':(.31,.34,.41,1),'energy':(.53,.18,.96,1),'gold':(.36,.29,.53,1),'skin':(.57,.32,.235,1)},
 'akira':{'cloth':(.81,.79,.70,1),'cloth_light':(.98,.97,.88,1),'hair':(.38,.025,.012,1),'hair_light':(.72,.075,.025,1),'energy':(1,.41,.035,1),'gold':(.87,.57,.12,1),'skin':(.72,.43,.28,1)}
}

def mat(name,color):
 m=bpy.data.materials.new(name);m.diffuse_color=color;m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=color
 p.inputs['Roughness'].default_value=.82;p.inputs['Specular IOR Level'].default_value=.18
 return m

def mesh(name,verts,faces,material,weights=None):
 data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
 obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
 obj.data.materials.append(MAT[material])
 for p in data.polygons:p.use_smooth=True
 if weights:
  groups={}
  for i,w in enumerate(weights):
   for bone,weight in w.items():
    if weight<=0:continue
    if bone not in groups:groups[bone]=obj.vertex_groups.new(name=bone)
    groups[bone].add([i],weight,'REPLACE')
 PARTS.append(obj);return obj

def rigid(bone):return lambda p,t:{bone:1.0}
def torso_w(p,t):
 z=p[2]
 if z<1.17:return {'hips':1}
 if z<1.42:
  w=(z-1.17)/.25;return {'spine':1-w,'chest':w}
 return {'chest':1}

def loft_z(name,rings,material,weight=torso_w,segments=32,shape=None,cap=True):
 verts=[];weights=[]
 for j,(z,rx,ry,cy) in enumerate(rings):
  for i in range(segments):
   a=2*math.pi*i/segments
   p=[rx*math.sin(a),cy-ry*math.cos(a),z]
   if shape:p=shape(p,a,j)
   verts.append(p);weights.append(weight(p,j/max(1,len(rings)-1)))
 faces=[]
 for j in range(len(rings)-1):
  for i in range(segments):
   a=j*segments+i;b=j*segments+(i+1)%segments
   faces.append((a,b,b+segments,a+segments))
 if cap:faces.extend([tuple(reversed(range(segments))),tuple(range((len(rings)-1)*segments,len(rings)*segments))])
 return mesh(name,verts,faces,material,weights)

def tube(name,path,radii,material,weight,segments=16,shape=1.0):
 verts=[];weights=[]
 for j,p in enumerate(path):
  p=Vector(p);tangent=Vector(path[min(len(path)-1,j+1)])-Vector(path[max(0,j-1)])
  tangent.normalize();u=Vector((0,-1,0));u=(u-tangent*u.dot(tangent)).normalized();v=tangent.cross(u).normalized()
  r=radii[j];r=(r,r) if isinstance(r,(int,float)) else r
  for i in range(segments):
   a=2*math.pi*i/segments
   fold=1.0
   if name.startswith('TailoredLeg'):
    fold+=.065*math.sin(a*6+j*1.1)*math.sin(math.pi*j/(len(path)-1))
   pp=p+(u*math.cos(a)*r[0]+v*math.sin(a)*r[1])*fold
   verts.append(pp);weights.append(weight(pp,j/(len(path)-1)))
 faces=[]
 for j in range(len(path)-1):
  for i in range(segments):
   a=j*segments+i;b=j*segments+(i+1)%segments
   faces.append((a,b,b+segments,a+segments))
 faces.extend([tuple(reversed(range(segments))),tuple(range((len(path)-1)*segments,len(path)*segments))])
 return mesh(name,verts,faces,material,weights)

def patch(name,points,material,bone='head'):
 # A shaped polygon surface, optionally with a bevelled solid edge.
 pts=[Vector(p) for p in points]
 normal=(pts[1]-pts[0]).cross(pts[2]-pts[0])
 if normal.y>0 and sum(p.y for p in pts)<0:pts.reverse()
 center=sum(pts,Vector())/len(pts);pts.append(center)
 return mesh(name,pts,[(len(pts)-1,i,(i+1)%(len(pts)-1)) for i in range(len(pts)-1)],material,[{bone:1}]*len(pts))

def ribbon(name,path,width,material,bone='chest'):
 verts=[]
 for p in path:
  verts.extend([(p[0]-width/2,p[1],p[2]),(p[0]+width/2,p[1],p[2])])
 faces=[(2*i+2,2*i+3,2*i+1,2*i) for i in range(len(path)-1)]
 if sum(p[1] for p in path)>0:faces=[tuple(reversed(f)) for f in faces]
 return mesh(name,verts,faces,material,[{bone:1}]*len(verts))

def eye(side,identity):
 # Layered curved almond surfaces, ink upper lash and pointed outer corner.
 x=side*.073;z=1.979;y=-.126
 # Both eyes slope upward at the outer corner, giving an expressive shonen gaze.
 outline=[(-.061,-.002),(-.039,.015),(.016,.018),(.056,.015),(.043,-.008),(-.009,-.014)]
 def poly(scale,depth):
  return [(x+side*px*scale,y+depth+abs(px)*.07,z+pz*scale+side*0) for px,pz in outline]
 patch('ScleraAlmond'+str(side),poly(1,0),'white')
 # Iris is a subtly flattened disk clipped into the eye opening; deliberately
 # narrow pupils and specular flecks remain readable at phone resolution.
 cx=x-side*.003
 points=[(cx,y-.001,z-.001)]
 for i in range(25):
  a=2*math.pi*i/24
  points.append((cx+math.cos(a)*.016,y-.002,z+.001+math.sin(a)*.015))
 mesh('Iris'+str(side),points,[(0,i,i+1) for i in range(1,25)],'energy',[{'head':1}]*len(points))
 pts=[(cx,y-.004,z-.001)]+[(cx+math.cos(i*2*math.pi/20)*.008,y-.004,z-.001+math.sin(i*2*math.pi/20)*.015) for i in range(21)]
 mesh('Pupil'+str(side),pts,[(0,i,i+1) for i in range(1,21)],'ink',[{'head':1}]*len(pts))
 patch('EyeHighlight'+str(side),[(cx-.007,y-.006,z+.009),(cx-.001,y-.006,z+.012),(cx+.001,y-.006,z+.006),(cx-.005,y-.006,z+.004)],'white')
 lash=[(x+side*px,y-.006+abs(px)*.07,z+pz) for px,pz in [(-.062,-.002),(-.039,.020),(.018,.023),(.060,.017),(.059,.009),(.016,.016),(-.038,.011)]]
 patch('UpperInkLash'+str(side),lash,'ink')
 patch('LowerInkLash'+str(side),[(x+side*px,y-.005+abs(px)*.07,z+pz) for px,pz in [(-.008,-.015),(.043,-.008),(.055,.010),(.048,-.011),(-.008,-.018)]],'ink')
 patch('Brow'+str(side),[(x+side*px,-.129+abs(px)*.07,z+pz) for px,pz in [(-.060,.035),(-.054,.047),(.044,.061),(.061,.054),(.018,.047)]],'hair')
 patch('CheekInk'+str(side),[(side*.101,-.111,1.928),(side*.130,-.093,1.942),(side*.116,-.105,1.927)],'skin_shadow')

def face(identity):
 rings=[(1.77,.035,.035,.006),(1.79,.065,.057,.008),(1.815,.091,.077,.008),(1.85,.113,.089,.008),(1.89,.136,.101,.006),(1.93,.150,.111,.005),(1.97,.157,.122,.005),(2.015,.154,.124,.008),(2.055,.139,.117,.012),(2.09,.109,.092,.016),(2.112,.060,.055,.018),(2.12,.005,.005,.018)]
 def sculpt(p,a,j):
  # Flatten the facial planes and define cheekbones/temple without block faces.
  front=max(0,math.cos(a))
  if 3<=j<=8:
   p[1]-=.009*front**4
  return p
 loft_z('AnatomicalFace',rings,'skin',rigid('head'),48,sculpt)
 loft_z('Neck',[(1.64,.115,.087,.018),(1.68,.096,.080,.014),(1.73,.081,.070,.010),(1.77,.074,.066,.006)],'skin',rigid('neck'),32)
 # Sculpted nose bridge + small nostril wing surfaces, same skin shader.
 verts=[(-.018,-.128,1.986),(.018,-.128,1.986),(-.015,-.147,1.941),(.015,-.147,1.941),(-.017,-.146,1.918),(.017,-.146,1.918),(0,-.177,1.927),(0,-.151,1.911)]
 mesh('NoseSculpt',verts,[(0,1,3,2),(2,3,6),(2,6,4),(3,5,6),(4,6,7),(6,5,7)],'skin',[{'head':1}]*8)
 patch('NoseInk',[(.002,-.178,1.929),(.017,-.149,1.917),(.013,-.151,1.915),(0,-.173,1.924)],'skin_shadow')
 patch('MouthInk',[(-.036,-.094,1.865),(-.006,-.105,1.868),(.027,-.100,1.865),(.036,-.096,1.867),(.025,-.102,1.861),(-.009,-.107,1.864)],'ink')
 patch('LipLight',[(-.015,-.106,1.852),(.018,-.104,1.853),(.010,-.108,1.849)],'skin_light')
 for side in [-1,1]:
  earpath=[(side*.147,.005,1.969),(side*.172,.005,1.970),(side*.176,.001,1.940),(side*.160,-.004,1.916)]
  tube('Ear'+str(side),earpath,[(.014,.022),(.018,.023),(.015,.022),(.008,.010)],'skin',rigid('head'),12)
  patch('EarFold'+str(side),[(side*.165,-.017,1.958),(side*.174,-.012,1.963),(side*.168,-.020,1.930),(side*.160,-.017,1.935)],'skin_shadow')
  eye(side,identity)

def hair(identity):
 # Continuous cap and swept curved locks with varied cross-sections. Hair is
 # authored mesh geometry (not stock cones) and bound to the actual head bone.
 loft_z('HairCap',[(1.984,.155,.126,.017),(2.04,.163,.134,.020),(2.10,.144,.121,.023),(2.147,.096,.091,.026),(2.16,.004,.004,.026)],'hair',rigid('head'),40)
 wild=1.18 if identity=='akira' else (1.02 if identity=='kaizen' else .94)
 for i in range(12):
  a=2*math.pi*i/12
  base=Vector((math.sin(a)*.095,.02+math.cos(a)*.065,2.07))
  tip=Vector((math.sin(a)*(.22+(.025 if i%2 else -.015))*wild,.025+math.cos(a)*.17,2.29+(.085 if i%3==0 else .025)))
  if math.cos(a)<-.3:tip.z-=.08
  path=[base,base+Vector((math.sin(a)*.018,math.cos(a)*.01,.092)),base.lerp(tip,.64)+Vector((0,-.024,.055)),tip]
  tube('CrownLock%02d'%i,path,[(.025,.058),(.030,.057),(.017,.031),(.0005,.0005)],'hair',rigid('head'),8)
  if i%2==0:
   strip=[path[1]+Vector((-.012,-.035,.005)),path[2]+Vector((-.006,-.023,0)),tip]
   ribbon('HairInkHighlight',strip,.009,'hair_light','head')
 for i in range(7):
  x=(i-3)*.047
  base=(x*.65,-.075,2.12+(.02 if i%2 else 0))
  tip=(x*1.08,-.148,1.995+(.029 if i%2 else -.004))
  path=[base,(x,-.120,2.096),(x*1.06,-.153,2.045),tip]
  tube('SweptFringe%02d'%i,path,[(.012,.040),(.014,.037),(.009,.025),(.0005,.0005)],'hair',rigid('head'),8)
  patch('FringeHighlight',[(x-.012,-.148,2.091),(x-.005,-.161,2.052),(x+.001,-.153,2.024),(x+.003,-.148,2.079)],'hair_light')
 for side in [-1,1]:
  for i in range(4):
   path=[(side*.122,.018+i*.027,2.07-i*.017),(side*.168,.025+i*.03,2.02-i*.018),(side*(.205+i*.009),.015+i*.037,1.96-i*.033)]
   tube('SideBlade',path,[(.014,.038),(.014,.030),(.0005,.0005)],'hair',rigid('head'),8)

def limb_weight(side,arm=True):
 a=('upper_arm.' if arm else 'thigh.')+side;b=('forearm.' if arm else 'shin.')+side
 def calc(p,t):
  # Smooth deformations across a generous elbow/knee transition.
  w=max(0,min(1,(t-.36)/.27));return {a:1-w,b:w}
 return calc

def anatomy(identity):
 # Clothed torso with deliberately sculpted chest/waist profile.
 rings=[(1.04,.209,.133,.012),(1.10,.213,.138,.012),(1.18,.211,.135,.012),(1.27,.227,.148,.009),(1.37,.265,.166,.009),(1.47,.302,.174,.013),(1.56,.321,.165,.021),(1.62,.271,.130,.026),(1.65,.185,.105,.025)]
 def clothfold(p,a,j):
  p[1]-=math.cos(a)*.004*math.sin(a*8+j*1.1)
  return p
 loft_z('TailoredTorso',rings,'cloth',torso_w,40,clothfold)
 loft_z('Undershirt',[(1.56,.223,.128,.019),(1.64,.186,.104,.020),(1.69,.093,.078,.018)],'inner',rigid('chest'),32)
 loft_z('Belt',[(1.056,.221,.145,.007),(1.102,.224,.146,.007),(1.115,.221,.143,.007)],'gold',rigid('hips'),40)
 loft_z('TrouserHips',[(.95,.226,.143,.014),(1.01,.220,.139,.012),(1.08,.209,.130,.012)],'cloth',rigid('hips'),32)
 # Embroidered overlapping V lapels follow chest curvature instead of boxes.
 for side in [-1,1]:
  path=[(side*.119,-.092,1.642),(side*.111,-.145,1.58),(side*.071,-.170,1.50),(side*.031,-.169,1.425),(-side*.018,-.149,1.34)]
  ribbon('GiLapel',path,.045,'cloth_light')
  if identity!='kaizen':ribbon('LapelPiping',[(p[0]+side*.020,p[1]-.002,p[2]) for p in path],.006,'gold')
  patch('Collarbone',[(side*.03,-.098,1.643),(side*.116,-.110,1.621),(side*.09,-.123,1.601)],'skin_shadow','chest')
 # Fold accents taper into real garment shape rather than many separate lumps.
 for side in [-1,1]:
  for j in range(3):
   patch('GiFold',[(side*(.19-j*.03),-.130,1.17+j*.05),(side*(.11-j*.023),-.153,1.22+j*.062),(side*(.16-j*.025),-.143,1.175+j*.06)],'inner','spine')
 # A soft chest undersurface visible in the V; no detached sphere pectorals.
 patch('GiNeckSkin',[(-.090,-.089,1.661),(.090,-.089,1.661),(.094,-.144,1.58),(0,-.170,1.439),(-.094,-.144,1.58)],'skin','chest')
 # Integrated trapezius/collarbone surface removes the long cylinder neck and
 # anchors the shoulder anatomy into a believable adult upper body.
 if identity=='kaizen':
  loft_z('Trapezius',[(1.575,.291,.119,.015),(1.62,.240,.107,.018),(1.662,.149,.087,.017),(1.69,.092,.079,.014)],'skin',rigid('chest'),40)
 for sign,side in [(1,'L'),(-1,'R')]:
  s=sign
  arm=[(s*.291,0,1.61),(s*.345,0,1.575),(s*.404,-.003,1.518),(s*.475,-.004,1.447),(s*.54,0,1.37),(s*.584,-.003,1.302),(s*.645,-.010,1.207),(s*.7,-.015,1.10)]
  radii=[(.100,.105),(.115,.121),(.111,.117),(.096,.105),(.078,.086),(.092,.093),(.085,.081),(.055,.056)]
  tube('ArmAnatomy.'+side,arm,radii,'skin' if identity=='kaizen' else 'inner',limb_weight(side),20)
  # Deltoid sleeve integrated as a short tailored shoulder shell.
  if identity!='kaizen':
   sleeve=[(s*.252,.005,1.600),arm[1],arm[2],tuple(Vector(arm[2]).lerp(Vector(arm[3]),.3))]
   tube('ShoulderSleeve.'+side,sleeve,[(.094,.091),(.121,.126),(.116,.122),(.104,.112)],'cloth',rigid('upper_arm.'+side),24)
  tube('WristGuard.'+side,arm[5:],[(.101,.103),(.097,.096),(.064,.067)],'cloth_light',rigid('forearm.'+side),20)
  tube('GuardTrim.'+side,[arm[5],tuple(Vector(arm[5]).lerp(Vector(arm[6]),.19))],[(.104,.106),(.105,.107)],'gold',rigid('forearm.'+side),20)
  # Anatomical clenched fist with knuckle ridges and a folded thumb.
  hand=[(s*.700,-.015,1.105),(s*.727,-.022,1.065),(s*.755,-.022,1.017),(s*.757,-.022,.986)]
  tube('Fist.'+side,hand,[(.057,.055),(.065,.068),(.068,.063),(.040,.041)],'skin' if identity=='kaizen' else 'cloth',rigid('hand.'+side),20)
  for i in range(4):
   x=s*(.718+i*.017)
   tube('Knuckle.'+side,[(x,-.073,1.049),(x,-.083,1.028),(x,-.069,1.006)],[(.012,.013),(.014,.015),(.009,.011)],'skin' if identity=='kaizen' else 'cloth_light',rigid('hand.'+side),10)
  tube('Thumb.'+side,[(s*.706,-.047,1.069),(s*.704,-.074,1.036),(s*.733,-.084,1.019)],[(.024,.023),(.022,.022),(.015,.018)],'skin' if identity=='kaizen' else 'cloth_light',rigid('hand.'+side),12)
  leg=[(s*.135,.012,1.035),(s*.148,.010,.98),(s*.153,.008,.89),(s*.155,.010,.77),(s*.151,.006,.64),(s*.150,.004,.59),(s*.148,.004,.51),(s*.145,0,.39),(s*.14,-.010,.23),(s*.14,-.015,.16)]
  rr=[(.139,.139),(.151,.151),(.148,.145),(.124,.130),(.098,.107),(.092,.101),(.106,.105),(.092,.090),(.067,.070),(.06,.061)]
  tube('TailoredLeg.'+side,leg,rr,'cloth',limb_weight(side,False),24)
  tube('ShinBoot.'+side,leg[6:],[(.114,.116),(.101,.099),(.077,.079),(.069,.072)],'inner',rigid('shin.'+side),24)
  tube('BootCuff.'+side,[leg[6],tuple(Vector(leg[6]).lerp(Vector(leg[7]),.18))],[(.117,.119),(.116,.117)],'gold',rigid('shin.'+side),24)
  # Custom boot surface: heel, ankle, instep, toe and outsole ring profiles.
  verts=[];weights=[];seg=28
  for j,(z,rx,ry,cy) in enumerate([(.025,.083,.164,-.072),(.055,.088,.166,-.071),(.090,.085,.159,-.065),(.13,.074,.122,-.036),(.185,.065,.068,-.008)]):
   for i in range(seg):
    a=2*math.pi*i/seg;verts.append((s*.14+rx*math.sin(a),cy-ry*math.cos(a),z));weights.append({'foot.'+side:1})
  faces=[]
  for j in range(4):
   for i in range(seg):
    a=j*seg+i;b=j*seg+(i+1)%seg;faces.append((a,b,b+seg,a+seg))
  faces.append(tuple(reversed(range(seg))))
  mesh('SculptedBoot.'+side,verts,faces,'cloth_light',weights)
  ribbon('BootCenterGold',[(s*.14,-.222,.066),(s*.14,-.184,.108),(s*.14,-.095,.166)],.021,'gold','foot.'+side)
 # Offset flowing waist ties distinguish the warrior silhouette.
 for sign in [-1,1]:
  pts=[(sign*.13,-.145,1.08),(sign*.19,-.16,.96),(sign*.20,-.13,.79),(sign*.24,-.10,.71)]
  ribbon('WovenSash',pts,.07,'cloth_light','hips')
  ribbon('SashEdge',[(p[0]+sign*.031,p[1]-.002,p[2]) for p in pts],.007,'gold','hips')

def armor(identity):
 if identity=='ryuzen':
  for s in [-1,1]:
   # Sculpted layered chest plates, bevel-like surfaces rather than boxes.
   verts=[(s*.025,-.178,1.475),(s*.245,-.154,1.546),(s*.282,-.138,1.422),(s*.068,-.176,1.365),(s*.15,-.199,1.455)]
   mesh('RavenBreastplate',verts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],'cloth_light',[{'chest':1}]*5)
   ribbon('ArmorEnergyInlay',[(s*.08,-.193,1.475),(s*.19,-.180,1.485),(s*.24,-.161,1.467)],.012,'energy')
   for j in range(3):
    patch('AbdominalPlate',[(s*.018,-.164,1.34-j*.055),(s*.16,-.148,1.34-j*.055),(s*.145,-.152,1.30-j*.055),(s*.018,-.167,1.30-j*.055)],'cloth_light','spine')
   patch('AngularPauldron',[(s*.27,-.09,1.65),(s*.40,-.08,1.63),(s*.44,.03,1.56),(s*.33,.11,1.58),(s*.25,.07,1.66)],'gold','upper_arm.L' if s>0 else 'upper_arm.R')
  loft_z('HighCombatCollar',[(1.63,.144,.105,.02),(1.72,.111,.094,.022),(1.75,.106,.090,.022)],'cloth_light',rigid('neck'),32,cap=False)
 if identity=='akira':
  for s in [-1,1]:
   # White coat split panels with gold trim and a flowing back mantle.
   ribbon('SolarCoatFront',[(s*.18,-.139,1.073),(s*.24,-.155,.92),(s*.32,-.10,.68),(s*.35,-.04,.58)],.17,'cloth_light','hips')
   ribbon('CoatGold',[(s*.25,-.145,1.073),(s*.31,-.160,.92),(s*.39,-.105,.68),(s*.42,-.045,.58)],.018,'gold','hips')
   verts=[(s*.23,-.09,1.65),(s*.37,-.07,1.67),(s*.44,.035,1.58),(s*.35,.14,1.60),(s*.25,.08,1.67),(s*.32,0,1.707)]
   mesh('SolarPauldron',verts,[(0,1,5),(1,2,5),(2,3,5),(3,4,5),(4,0,5)],'gold',[{'upper_arm.L' if s>0 else 'upper_arm.R':1}]*6)
  patch('MantleBack',[(-.21,.115,1.61),(.21,.115,1.61),(.31,.22,1.10),(.24,.25,.81),(0,.28,.72),(-.24,.25,.81),(-.31,.22,1.10)],'cloth_light','chest')
  ribbon('MantleGold',[(0,.117,1.61),(0,.24,1.08),(0,.282,.74)],.023,'gold','chest')

def make_rig():
 data=bpy.data.armatures.new('AstralHumanoid');rig=bpy.data.objects.new('AstralRig',data);bpy.context.collection.objects.link(rig)
 bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 defs=[('root',(0,0,0),(0,0,.12),None),('hips',(0,0,1.02),(0,0,1.18),'root'),('spine',(0,0,1.18),(0,0,1.40),'hips'),('chest',(0,0,1.40),(0,0,1.68),'spine'),('neck',(0,0,1.68),(0,0,1.75),'chest'),('head',(0,0,1.75),(0,0,2.04),'neck')]
 for sign,side in [(1,'L'),(-1,'R')]:
  defs.extend([('upper_arm.'+side,(sign*.29,0,1.64),(sign*.54,0,1.37),'chest'),('forearm.'+side,(sign*.54,0,1.37),(sign*.70,-.015,1.10),'upper_arm.'+side),('hand.'+side,(sign*.70,-.015,1.10),(sign*.75,-.025,.98),'forearm.'+side),('thigh.'+side,(sign*.14,0,1.04),(sign*.15,.005,.60),'hips'),('shin.'+side,(sign*.15,.005,.60),(sign*.14,-.015,.16),'thigh.'+side),('foot.'+side,(sign*.14,-.015,.16),(sign*.14,-.20,.08),'shin.'+side)])
 for name,head,tail,parent in defs:
  b=data.edit_bones.new(name);b.head=head;b.tail=tail;b.roll=0
  if parent:b.parent=data.edit_bones[parent]
 bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True
 return rig

def setup_scene():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for datablock in list(bpy.data.actions):bpy.data.actions.remove(datablock)
 for datablock in list(bpy.data.materials):bpy.data.materials.remove(datablock)
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=40;scene.cycles.use_denoising=False
 scene.render.resolution_x=900;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
 scene.world.color=(.045,.055,.085)
 scene.view_settings.view_transform='Standard';scene.view_settings.look='Medium High Contrast'
 scene.render.image_settings.file_format='PNG'
 return scene

def render_review(scene,rig,identity):
 # Actual offline-rendered geometry review, distinct from gameplay validation.
 camdata=bpy.data.cameras.new('ReviewCamera');cam=bpy.data.objects.new('ReviewCamera',camdata);bpy.context.collection.objects.link(cam)
 cam.location=(3.15,-5.8,2.6);target=Vector((0,0,1.2));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=2.72;scene.camera=cam
 lights=[]
 for name,loc,power,size,color in [('Key',(-3,-4,5),650,4,(.85,.92,1)),('Fill',(3,-2,3),450,3,(1,.78,.57)),('Rim',(1,3,4),950,3,(.46,.72,1))]:
  d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;d.color=color
  o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=loc;o.rotation_euler=(Vector((0,0,1.2))-o.location).to_track_quat('-Z','Y').to_euler();lights.append(o)
 # Plane is a review-only object and never exported with the character.
 plane_mesh=bpy.data.meshes.new('ReviewFloor');plane_mesh.from_pydata([(-200,-200,0),(200,-200,0),(200,200,0),(-200,200,0)],[],[(0,1,2,3)])
 floor=bpy.data.objects.new('ReviewFloor',plane_mesh);bpy.context.collection.objects.link(floor);floor.location.z=-.002
 floor.data.materials.append(mat('ReviewFloor',(.025,.035,.055,1)))
 scene.render.filepath=str(REVIEWS/(identity+'_review.png'));scene.render.film_transparent=False
 scene.frame_set(1)
 bpy.ops.render.render(write_still=True)
 for o in lights+[cam,floor]:bpy.data.objects.remove(o,do_unlink=True)

def build(identity):
 global PARTS,MAT
 scene=setup_scene();PARTS=[];p=PAL[identity]
 MAT={k:mat(k.title(),v) for k,v in p.items()}
 MAT.update({'ink':mat('Ink',(.006,.009,.017,1)),'white':mat('Sclera',(.93,.96,.98,1)),'inner':mat('Inner',(.015,.025,.055,1)),'skin_shadow':mat('FaceShadow',tuple(c*.64 for c in p['skin'][:3])+(1,)),'skin_light':mat('FaceHighlight',tuple(min(1,c*1.19) for c in p['skin'][:3])+(1,))})
 anatomy(identity);face(identity);hair(identity);armor(identity)
 # Adult anime proportions: a tapered ~0.32m head on a 2.3m silhouette, with
 # the jaw closely coupled to the trapezius rather than a visible neck tube.
 for part in PARTS:
  if part.vertex_groups.get('head') is not None:
   for vertex in part.data.vertices:
    vertex.co.x*=.91
    vertex.co.z=(vertex.co.z-1.96)*.92+1.915
 # Merge by material into ONE skinned surface asset, preserve all vertex groups.
 bpy.ops.object.select_all(action='DESELECT')
 for part in PARTS:part.select_set(True)
 bpy.context.view_layer.objects.active=PARTS[0];bpy.ops.object.join();body=bpy.context.object;body.name=identity.title()+'_SkinnedSurface'
 # Recalculate mesh normals consistently; retain authored smooth facial surfaces.
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
 bpy.ops.object.select_all(action='DESELECT');rig=make_rig()
 body.parent=rig;modifier=body.modifiers.new('ArmatureDeform','ARMATURE');modifier.object=rig
 # Every authored vertex has real bone weights. No rigid mesh pivot animation.
 rig['character_identity']=identity;rig['author']='Astral Rivals original authored asset'
 metadata={}
 try:
  from animation_library import build_animations
  metadata=build_animations(rig,identity)
 except ImportError:
  print('Animation helper not yet present; export rig now and rerun after helper arrives.')
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);body.select_set(True);bpy.context.view_layer.objects.active=rig
 export_args=dict(filepath=str(OUT/(identity+'.glb')),export_format='GLB',use_selection=True,export_apply=False,export_animations=True,export_skins=True,export_yup=True,export_all_influences=False,export_force_sampling=True,export_frame_range=False)
 props=bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
 if 'export_animation_mode' in props:export_args['export_animation_mode']='ACTIONS'
 if 'export_nla_strips' in props:export_args['export_nla_strips']=True
 bpy.ops.export_scene.gltf(**export_args)
 from animation_library import normalize_glb_quaternions
 normalize_glb_quaternions(OUT/(identity+'.glb'))
 body.data.calc_loop_triangles()
 info={'identity':identity,'vertices':len(body.data.vertices),'triangles':len(body.data.loop_triangles),'bones':len(rig.data.bones),'material_surfaces':len(body.data.materials),'animations':metadata,'source':'Original mesh surfaces and rig authored by Astral Rivals; no third-party assets.'}
 (OUT/(identity+'_asset.json')).write_text(json.dumps(info,indent=2,default=str))
 print('ASSET COMPLETE',json.dumps(info,default=str))
 # Asset export comes first. Review may take a while on a software CPU renderer.
 if os.environ.get('ASTRAL_SKIP_REVIEWS')!='1':
  rig.animation_data.action=bpy.data.actions.get('idle')
  scene.frame_set(1);bpy.context.view_layer.update()
  render_review(scene,rig,identity)
 bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(identity+'.blend')))

if __name__=='__main__':
 args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
 for identity in args or ['kaizen','ryuzen','akira']:build(identity)
