"""Kaizen-specific authored anatomy and gi for the Phase 1 character pass.

Uses the existing Astral humanoid rest pose and named deformation bones. There
are no stock primitive meshes: clothing, muscle contours, fingers and boots are
shaped cross-section surfaces, with integrated folds and bevelled profiles.
The helper is deliberately isolated so rebuilding Kaizen cannot alter the other
fighters. ``build(api)`` is called by build_characters.py.
"""
import math
from mathutils import Vector


def _smooth(t):
    t = max(0.0, min(1.0, t))
    return t*t*(3.0-2.0*t)


def _bone_mix(a, b, t):
    w = _smooth(t)
    return {a: 1.0-w, b: w}


def _strip(api, name, path, widths, material, bone, depth=0.0):
    """A curved, tapered, three-column ribbon; center ridge catches toon light."""
    vertices = []
    for j, point in enumerate(path):
        p = Vector(point)
        tangent = Vector(path[min(j+1, len(path)-1)])-Vector(path[max(0, j-1)])
        side = Vector((tangent.z, 0.0, -tangent.x)).normalized()
        width = widths[j] if isinstance(widths, (tuple, list)) else widths
        vertices.extend([p-side*width*.5, p+Vector((0, -depth, 0)), p+side*width*.5])
    faces = []
    for j in range(len(path)-1):
        for k in range(2):
            a = 3*j+k
            faces.append((a, a+1, a+4, a+3))
    # Long garment accents share the underlying cloth deformation instead of
    # floating away from it when the torso bends. Most short details are rigid.
    weights = [bone(p, 0.0) if callable(bone) else {bone: 1.0} for p in vertices]
    return api.mesh(name, vertices, faces, material, weights)


def _anatomical_limb(api, side, sign):
    """Asymmetric muscle sections, not constant-radius skin cylinders."""
    path = [(sign*.268, .016, 1.626), (sign*.315, .008, 1.610),
            (sign*.366, .002, 1.567), (sign*.413, -.004, 1.520),
            (sign*.465, -.008, 1.457), (sign*.511, -.005, 1.407),
            (sign*.540, .000, 1.370), (sign*.572, -.003, 1.317),
            (sign*.613, -.009, 1.256), (sign*.657, -.012, 1.184),
            (sign*.700, -.015, 1.100)]
    # Front depth, transverse width. Distinct deltoid, biceps, elbow and
    # brachioradialis bulges taper down to the carpal joint.
    radii = [(.066, .075), (.101, .104), (.104, .110), (.091, .101),
             (.092, .092), (.073, .074), (.061, .069), (.079, .081),
             (.077, .073), (.060, .058), (.044, .047)]
    verts, weights = [], []
    segments = 28
    for j, point in enumerate(path):
        p = Vector(point)
        tangent = (Vector(path[min(j+1, len(path)-1)])-Vector(path[max(0, j-1)])).normalized()
        front = Vector((0, -1, 0)); front = (front-tangent*front.dot(tangent)).normalized()
        across = tangent.cross(front).normalized()
        for i in range(segments):
            angle = 2*math.pi*i/segments
            # Upper arm has a low biceps peak toward the front; triceps spreads
            # across the back. Forearm has a diagonal extensor ridge.
            bump = 1.0
            if 2 <= j <= 5:
                bump += .095*max(0, math.cos(angle))**4 * math.sin((j-1)*math.pi/5)
                bump += .04*max(0, -math.cos(angle))**3
            if 7 <= j <= 9:
                bump += .055*max(0, math.cos(angle+sign*.6))**6
            point2 = p+(front*math.cos(angle)*radii[j][0]+across*math.sin(angle)*radii[j][1])*bump
            verts.append(point2)
            blend = (1.43-point2.z)/.12
            weights.append(_bone_mix('upper_arm.'+side, 'forearm.'+side, blend))
    faces = [(j*segments+i, j*segments+(i+1)%segments,
              (j+1)*segments+(i+1)%segments, (j+1)*segments+i)
             for j in range(len(path)-1) for i in range(segments)]
    faces += [tuple(reversed(range(segments))), tuple(range((len(path)-1)*segments, len(path)*segments))]
    api.mesh('KaizenSculptedArm.'+side, verts, faces, 'skin', weights)
    # Small tapered ink accents follow the deltoid/biceps anatomy. They are
    # intentionally sparse rather than drawing a separate outline on each lobe.
    _strip(api, 'DeltoidCrease.'+side,
           [(sign*.345, -.094, 1.581), (sign*.377, -.100, 1.551), (sign*.405, -.088, 1.521)],
           [.002, .005, .0006], 'skin_shadow', 'upper_arm.'+side)
    _strip(api, 'BicepsCrease.'+side,
           [(sign*.442, -.089, 1.471), (sign*.473, -.083, 1.445), (sign*.492, -.068, 1.417)],
           [.0005, .003, .0005], 'skin_shadow', 'upper_arm.'+side)


def _glove(api, side, sign):
    forearm = 'forearm.'+side
    hand = 'hand.'+side
    # A fitted gauntlet stops below the forearm muscle, leaving a readable wrist.
    api.tube('KaizenWristWrap.'+side,
             [(sign*.630, -.009, 1.235), (sign*.656, -.012, 1.187),
              (sign*.680, -.014, 1.140), (sign*.702, -.015, 1.104)],
             [(.076, .074), (.067, .065), (.057, .056), (.052, .053)],
             'cloth_light', api.rigid(forearm), 24)
    api.tube('KaizenCuffPiping.'+side,
             [(sign*.627, -.009, 1.241), (sign*.633, -.010, 1.230)],
             [(.079, .077), (.078, .076)], 'gold', api.rigid(forearm), 24)
    for j in range(3):
        t = j*.24
        p0 = Vector((sign*.652, -.012, 1.193)).lerp(Vector((sign*.690, -.014, 1.122)), t)
        p1 = p0+Vector((sign*.007, 0, -.012))
        radius = .067-t*.013
        api.tube('KaizenWrapBand.'+side+str(j), [p0, p1],
                 [(radius, radius*.98), (radius-.001, radius*.97)],
                 'cloth_mid', api.rigid(forearm), 24)
    # Wrist-aligned palm. Rounded-square cross sections give an anatomical fist
    # plane and avoid the previous mitten-shaped termination of a skin tube.
    origin = Vector((sign*.700, -.015, 1.100))
    axis = Vector((sign*.050, -.010, -.120)).normalized()
    front = Vector((0, -1, 0)); front = (front-axis*front.dot(axis)).normalized()
    across = axis.cross(front).normalized()
    verts, weights = [], []
    profiles = [(0, .047, .045), (.027, .052, .057), (.065, .052, .062),
                (.105, .045, .060), (.123, .028, .048)]
    segments = 24
    for length, depth, width in profiles:
        center = origin+axis*length
        for i in range(segments):
            a = i*2*math.pi/segments
            # Exponent .68 rounds the palm corners without producing a sphere.
            ca = math.copysign(abs(math.cos(a))**.68, math.cos(a))
            sa = math.copysign(abs(math.sin(a))**.68, math.sin(a))
            verts.append(center+front*ca*depth+across*sa*width)
            weights.append({hand: 1})
    faces = [(j*segments+i, j*segments+(i+1)%segments,
              (j+1)*segments+(i+1)%segments, (j+1)*segments+i)
             for j in range(len(profiles)-1) for i in range(segments)]
    faces += [tuple(reversed(range(segments))), tuple(range((len(profiles)-1)*segments, len(profiles)*segments))]
    api.mesh('KaizenGlovePalm.'+side, verts, faces, 'inner', weights)
    # Four curled fingers have individual proximal knuckles and skin tips.
    # Fingers share the existing hand bone; no misleading promise of finger rig.
    for finger in range(4):
        offset = (finger-1.5)*.026
        c = origin+axis*(.083+.007*math.sin(finger*math.pi/3))+across*offset
        path = [c+front*.031-axis*.013, c+front*.048+axis*.007,
                c+front*.040+axis*.032, c+front*.012+axis*.035]
        api.tube('KaizenCurledFinger.'+side+str(finger), path,
                 [(.014,.012), (.016,.014), (.014,.013), (.010,.010)],
                 'skin', api.rigid(hand), 12)
        # Dark gaps at second knuckles improve readability on a phone.
        q = c+front*.049+axis*.009
        api.tube('KaizenFingerSeam.'+side+str(finger),
                 [q-across*.008, q+across*.008], [.0014,.0014],
                 'skin_shadow', api.rigid(hand), 6)
    thumbbase = origin+axis*.032+across*.052
    api.tube('KaizenFoldedThumb.'+side,
             [thumbbase, thumbbase+front*.030+axis*.019,
              origin+axis*.082+front*.053+across*.026],
             [(.022,.023), (.022,.021), (.014,.017)],
             'skin', api.rigid(hand), 14)
    # Broad back-of-hand panel keeps the dark glove distinct from the skin tips.
    points = [origin+axis*.019-front*.047-across*.035,
              origin+axis*.021-front*.047+across*.035,
              origin+axis*.085-front*.049+across*.044,
              origin+axis*.104-front*.040-across*.035]
    api.mesh('KaizenGloveBack.'+side, points, [(0,1,2,3)], 'cloth_light', [{hand:1}]*4)


def _torso(api):
    # A tapered broad chest, short natural waist and swept shoulder line. The
    # front opening is actual missing garment topology, with skin below it.
    rings = [(1.065,.198,.123,.014,0), (1.115,.191,.121,.012,0),
             (1.180,.199,.132,.010,0), (1.255,.218,.145,.008,0),
             (1.330,.246,.154,.010,0), (1.395,.276,.165,.013,0),
             (1.455,.299,.172,.015,.11), (1.515,.313,.169,.018,.23),
             (1.565,.310,.151,.022,.34), (1.610,.277,.128,.025,.45),
             (1.650,.195,.102,.022,.62), (1.672,.100,.080,.018,.90)]
    verts, weights = [], []
    seg = 48
    for j, (z, rx, ry, cy, gap) in enumerate(rings):
        for i in range(seg+1):
            a = gap+(2*math.pi-2*gap)*i/seg
            # Torso is broad across the pectorals with flattened front planes.
            sx = math.copysign(abs(math.sin(a))**.90, math.sin(a))
            cf = math.copysign(abs(math.cos(a))**.82, math.cos(a))
            x, y = rx*sx, cy-ry*cf
            # Cloth tension sweeps diagonally from belt to axilla. These are
            # shallow integrated ridges, not floating polygons as fake folds.
            waist = math.exp(-((z-1.20)/.16)**2)
            fold = .006*waist*math.sin(a*7+(z-1.1)*17)
            y -= math.cos(a)*fold
            if 5 <= j <= 8:
                y -= .006*max(0,math.cos(a))**3*math.sin(a*4)**2
            p = (x,y,z); verts.append(p); weights.append(api.torso_w(p,0))
    faces = [(j*(seg+1)+i, j*(seg+1)+i+1,
              (j+1)*(seg+1)+i+1, (j+1)*(seg+1)+i)
             for j in range(len(rings)-1) for i in range(seg)]
    api.mesh('KaizenWrapGi', verts, faces, 'cloth', weights)
    # Natural trapezius/upper chest merges under the opening and shoulders.
    api.loft_z('KaizenChestUnderGi',
               [(1.405,.105,.111,.018), (1.465,.184,.141,.020),
                (1.535,.253,.141,.020), (1.590,.270,.119,.021),
                (1.635,.204,.101,.020), (1.667,.121,.079,.018),
                (1.696,.083,.067,.014)], 'skin', api.rigid('chest'), 40)
    # Wide layered lapels follow exactly the edge of the open V. Small gold
    # stitching and inset navy binding supply detail without a noisy texture.
    for sign in [-1,1]:
        path=[]
        for z,rx,ry,cy,gap in rings[5:]:
            path.append((sign*rx*math.sin(gap), cy-ry*math.cos(gap)-.005,z))
        _strip(api,'KaizenRolledLapel'+str(sign),path,
               [.013,.035,.045,.044,.042,.035,.028],'cloth_light','chest',.006)
        stitch=[(p[0]+sign*.014,p[1]-.002,p[2]) for p in path[1:]]
        _strip(api,'KaizenLapelStitch'+str(sign),stitch,.003,'gold','chest',.001)
        _strip(api,'KaizenClavicle'+str(sign),
               [(sign*.022,-.084,1.658),(sign*.072,-.094,1.640),(sign*.117,-.100,1.625)],
               [.001,.004,.0005],'skin_shadow','chest')
        # Fold valleys paired with narrow lit ridges on the lower front.
        for j in range(3):
            path=[(sign*(.175+j*.009),-.095,1.155+j*.044),
                  (sign*(.107+j*.022),-.135-j*.007,1.195+j*.060),
                  (sign*(.048+j*.025),-.145-j*.009,1.209+j*.064)]
            _strip(api,'KaizenGiTension'+str(sign)+str(j),path,
                   [.001,.009,.0007],'cloth_mid',api.torso_w,.002)
        # The armhole silhouette is defined by the actual garment shell. Extra
        # rigid binding strips here pulled away from the exposed deltoid in the
        # fighting stance, so the surface intentionally ends cleanly instead.
    # Rear central seam/folds make the standard combat view informative too.
    _strip(api,'KaizenBackSeam',[(0,.140,1.634),(0,.185,1.53),(0,.181,1.40),
                              (0,.156,1.27),(0,.138,1.13)],
           [.003,.004,.003,.003,.001],'cloth_mid',api.torso_w)
    for sign in [-1,1]:
        api.patch('KaizenBackFold'+str(sign),
                  [(sign*.065,.173,1.411),(sign*.213,.139,1.460),
                   (sign*.131,.167,1.429)],'cloth_mid','chest')
    # Celestial crest is stitched onto the upper back. No borrowed franchise mark.
    api.patch('KaizenBackCrest',[(-.032,.197,1.497),(0,.190,1.536),
                               (.032,.197,1.497),(0,.198,1.458)],'gold','chest')
    api.patch('KaizenCrestInset',[(-.017,.199,1.497),(0,.197,1.521),
                                (.017,.199,1.497),(0,.200,1.474)],'cloth_light','chest')


def _belt(api):
    # Multiple slightly overlapping woven wraps give the waist volume and
    # separate the gi and trousers without an oversized block-shaped buckle.
    api.loft_z('KaizenSashFoundation',
               [(1.050,.206,.134,.011),(1.067,.210,.136,.010),
                (1.108,.207,.134,.010),(1.130,.201,.130,.011)],
               'inner',api.rigid('hips'),48)
    for j in range(3):
        api.loft_z('KaizenSashWrap'+str(j),
                   [(1.059+j*.020,.212-j*.002,.138-j*.001,.010),
                    (1.068+j*.020,.212-j*.002,.138-j*.001,.010)],
                   'cloth_mid',api.rigid('hips'),48,cap=False)
    api.loft_z('KaizenSashGoldEdge',
               [(1.116,.207,.135,.010),(1.122,.205,.133,.010)],
               'gold',api.rigid('hips'),48,cap=False)
    # Hand-shaped tied knot to the left of center, rather than a box buckle.
    api.tube('KaizenSashKnot',[(.053,-.137,1.085),(.068,-.157,1.087),
                             (.098,-.165,1.080),(.114,-.143,1.081)],
             [(.018,.027),(.025,.031),(.025,.029),(.015,.021)],
             'cloth_light',api.rigid('hips'),16)
    for index, (x, drop, sway) in enumerate([(.083,.29,.055),(.111,.21,-.008)]):
        path=[(x,-.149,1.072),(x+.012,-.164,1.010),
              (x+sway*.65,-.170,1.072-drop*.65),(x+sway,-.139,1.072-drop)]
        _strip(api,'KaizenSashTail'+str(index),path,[.044,.048,.042,.031],
               'cloth_light','hips',.003)
        _strip(api,'KaizenSashTailGold'+str(index),
               [(p[0]+.014,p[1]-.004,p[2]) for p in path],
               [.003,.003,.003,.002],'gold','hips')


def _legs(api, side, sign):
    path=[(sign*.128,.015,1.048),(sign*.143,.014,.999),
          (sign*.155,.012,.931),(sign*.159,.012,.846),
          (sign*.157,.010,.755),(sign*.153,.007,.672),
          (sign*.150,.005,.610),(sign*.148,.004,.557),
          (sign*.148,.002,.512)]
    radii=[(.126,.125),(.141,.139),(.143,.138),(.135,.130),
           (.120,.117),(.103,.101),(.092,.093),(.095,.094),(.086,.086)]
    verts,weights=[],[]; seg=32
    for j,p in enumerate(path):
        for i in range(seg):
            a=i*2*math.pi/seg
            # Major gathered cloth folds rotate with the thigh, with a finer
            # compression ridge just above the boot. No constant tube profile.
            ridge=.045*math.cos(5*a+j*.62)+.021*math.cos(8*a-j*.31)
            ridge*=math.sin(math.pi*j/(len(path)-1))
            x=p[0]+math.sin(a)*radii[j][1]*(1+ridge)
            y=p[1]-math.cos(a)*radii[j][0]*(1+ridge)
            z=p[2]+.008*math.sin(3*a+j)*math.sin(math.pi*j/(len(path)-1))
            verts.append((x,y,z))
            weights.append(_bone_mix('thigh.'+side,'shin.'+side,(.68-z)/.16))
    faces=[(j*seg+i,j*seg+(i+1)%seg,(j+1)*seg+(i+1)%seg,(j+1)*seg+i)
           for j in range(len(path)-1) for i in range(seg)]
    faces.append(tuple(reversed(range(seg))))
    api.mesh('KaizenGatheredTrousers.'+side,verts,faces,'cloth',weights)
    # Shaped fold shadows sit near the front plane and taper to a point. The
    # geometry above does the actual silhouette work.
    for j in range(3):
        z=.75+j*.071
        _strip(api,'KaizenThighFold.'+side+str(j),
               [(sign*(.162+.064),-.073,z+.026),
                (sign*.161,-.126,z),(sign*(.161-.048),-.106,z-.012)],
               [.0005,.006,.0005],'cloth_mid','thigh.'+side)
    # Rear trouser seam, weighted to the leg rather than the torso.
    _strip(api,'KaizenTrouserBackSeam.'+side,
           [(sign*.157,.154,.96),(sign*.159,.150,.86),(sign*.157,.133,.76),
            (sign*.152,.108,.66)],.003,'cloth_mid','thigh.'+side)


def _boots(api, side, sign):
    shin='shin.'+side; foot='foot.'+side
    api.tube('KaizenBootUpper.'+side,
             [(sign*.148,.002,.535),(sign*.147,.001,.506),
              (sign*.145,-.002,.438),(sign*.143,-.007,.347),
              (sign*.141,-.012,.242),(sign*.140,-.015,.166)],
             [(.094,.093),(.101,.099),(.094,.091),(.081,.079),
              (.065,.066),(.058,.063)],'inner',api.rigid(shin),28)
    # The shin guard is a curved inset rather than a chunky detached plate.
    _strip(api,'KaizenBootShinPanel.'+side,
           [(sign*.148,-.097,.506),(sign*.146,-.096,.448),
            (sign*.143,-.088,.351),(sign*.141,-.074,.260),
            (sign*.140,-.071,.197)],
           [.073,.078,.064,.047,.031],'cloth_light',shin,.008)
    _strip(api,'KaizenBootGoldSeam.'+side,
           [(sign*.148,-.109,.500),(sign*.146,-.108,.442),
            (sign*.143,-.101,.350),(sign*.141,-.085,.263)],
           [.004,.004,.004,.003],'gold',shin)
    api.tube('KaizenBootCuff.'+side,
             [(sign*.148,.002,.526),(sign*.148,.002,.513),(sign*.148,.002,.503)],
             [(.098,.096),(.104,.102),(.102,.100)],'gold',api.rigid(shin),28)
    # Flat sole and shaped rounded-square toe are kept proportionate to the
    # long human foot. A raised instep actually joins the ankle at .16m.
    profiles=[(.020,.079,.153,-.065),(.035,.085,.160,-.067),
              (.055,.085,.158,-.066),(.075,.082,.152,-.062),
              (.100,.076,.131,-.043),(.129,.066,.099,-.022),
              (.163,.058,.064,-.012),(.189,.055,.056,-.009)]
    verts,weights=[],[];seg=32
    for j,(z,rx,ry,cy) in enumerate(profiles):
        for i in range(seg):
            a=i*2*math.pi/seg
            # Rounded-square toe across front half, oval ankle at upper rings.
            power=.72 if j<4 else 1.0
            x=sign*.14+rx*math.copysign(abs(math.sin(a))**power,math.sin(a))
            y=cy-ry*math.copysign(abs(math.cos(a))**power,math.cos(a))
            verts.append((x,y,z));weights.append({foot:1})
    faces=[(j*seg+i,j*seg+(i+1)%seg,(j+1)*seg+(i+1)%seg,(j+1)*seg+i)
           for j in range(len(profiles)-1) for i in range(seg)]
    faces += [tuple(reversed(range(seg))),tuple(range((len(profiles)-1)*seg,len(profiles)*seg))]
    boot=api.mesh('KaizenShapedBootFoot.'+side,verts,faces,'cloth_light',weights)
    # Give outsole polygons a dark rubber material while retaining one mesh.
    boot.data.materials.append(api.MAT['inner'])
    for polygon in boot.data.polygons:
        if polygon.center.z<.047:polygon.material_index=1
    # Instep chevron and two horizontal lacing bands draw a clear foot direction.
    _strip(api,'KaizenBootInstep.'+side,
           [(sign*.14,-.211,.078),(sign*.14,-.173,.108),(sign*.14,-.107,.147)],
           [.017,.021,.017],'gold',foot,.002)
    for j in range(2):
        z=.120+j*.018; y=-.137+j*.028
        _strip(api,'KaizenBootLace.'+side+str(j),
               [(sign*.14-.043,y+.015,z-.003),(sign*.14,y-.006,z),
                (sign*.14+.043,y+.015,z-.003)],
               [.004,.005,.004],'inner',foot)


def build(api):
    """Build only Kaizen body components, using the existing rig contract."""
    api.MAT['cloth_mid']=api.mat('KaizenClothFold',(.018,.082,.255,1))
    _torso(api)
    # Cloth bridge beneath both individual legs prevents a visible split hole.
    api.loft_z('KaizenTrouserSeat',[(.960,.220,.126,.020),
                                   (1.020,.215,.131,.017),
                                   (1.075,.197,.125,.012)],
               'cloth',api.rigid('hips'),40)
    _belt(api)
    for sign, side in [(1,'L'),(-1,'R')]:
        _anatomical_limb(api,side,sign)
        _glove(api,side,sign)
        _legs(api,side,sign)
        _boots(api,side,sign)
