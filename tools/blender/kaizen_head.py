"""Kaizen's original Phase 1 portrait mesh, bound to the existing head bone.

The face uses controlled cheek/jaw planes and layered eye surfaces; the hair is
built from authored swept, ridged locks rather than stock cones or cylinders.
Coordinates match AstralHumanoid's existing rest pose. No animation is replaced.
"""
import math
from mathutils import Vector


_FACE_RINGS = [
        (1.776, .025, .039, .009), (1.791, .051, .058, .006),
        (1.817, .084, .076, .005), (1.850, .112, .090, .005),
        (1.886, .135, .099, .006), (1.924, .149, .110, .008),
        (1.968, .154, .120, .011), (2.012, .153, .123, .015),
        (2.054, .140, .117, .018), (2.089, .111, .097, .021),
        (2.116, .068, .058, .023), (2.129, .006, .006, .025),
    ]


def _front_y(x, z):
    """Depth of the actual facial surface for conforming eyelid/brow layers."""
    for lower, upper in zip(_FACE_RINGS, _FACE_RINGS[1:]):
        if lower[0] <= z <= upper[0]:
            t = (z - lower[0]) / (upper[0] - lower[0])
            rx, ry, cy = [lower[i] * (1-t) + upper[i] * t for i in range(1,4)]
            front = math.sqrt(max(0.0, 1.0 - (min(abs(x)/rx,.998))**2))
            blend = min(1.0,front/.40)
            blend = blend*blend*(3-2*blend)
            flattened = math.tanh(2.8*front)/math.tanh(2.8)
            return cy-ry*(front+(flattened-front)*blend)
    return -.105


def build(api):
    api.MAT['kaizen_hair_ridge'] = api.mat('KaizenHairRidge', (.12, .18, .27, 1))
    api.MAT['kaizen_eye_blue'] = api.mat('KaizenIris', (.055, .37, .61, 1))
    api.MAT['kaizen_lip'] = api.mat('KaizenFaceLip', (.25, .115, .085, 1))
    _face(api)
    _hair(api)


def _surface(api, name, points, material='skin'):
    return api.patch(name, points, material, 'head')


def _face(api):
    # A pointed chin and defined mandibular corners transition into broad
    # cheekbones. The front is deliberately flatter than the round rear skull.
    rings = _FACE_RINGS
    def planes(p, a, j):
        front = math.cos(a)
        if front > 0 and 2 <= j <= 8:
            z, rx, ry, cy = rings[j]
            # A smooth normalized profile flattens the eye/muzzle region.
            # Fade it into the original circular temple as cos(a) tends to
            # zero, so the front and rear meet continuously with the same
            # first derivative. Assigning a flat y directly here creates a
            # visible side seam at the front/back half boundary.
            blend = min(1.0, front / .40)
            blend = blend * blend * (3.0 - 2.0 * blend)
            flattened = math.tanh(2.8 * front) / math.tanh(2.8)
            profile = front + (flattened - front) * blend
            p[1] = cy - ry * profile
            if j in (4, 5):
                p[1] -= .004 * math.sin(abs(p[0]) / rx * math.pi) * blend
        return p
    api.loft_z('Kaizen_CheekJawSurface', rings, 'skin', api.rigid('head'), 64, planes)
    api.loft_z('Kaizen_Neck', [
        (1.645,.108,.083,.022),(1.675,.096,.079,.018),
        (1.715,.082,.073,.013),(1.755,.077,.069,.009),
        (1.790,.076,.066,.008),
    ], 'skin', api.rigid('neck'), 40)

    # Sculpted bridge, point and alar wings, kept small for a shonen profile.
    points = [(-.014,-.119,1.994),(.014,-.119,1.994),
              (-.012,-.144,1.949),(.012,-.144,1.949),
              (-.021,-.143,1.923),(.021,-.143,1.923),
              (0,-.172,1.928),(0,-.145,1.914),
              (-.009,-.155,1.922),(.009,-.155,1.922)]
    api.mesh('Kaizen_NoseBridge', points,
        [(0,1,3,2),(2,3,6),(2,6,8,4),(3,5,9,6),
         (4,8,7),(8,6,9,7),(9,5,7)],'skin',[{'head':1}]*len(points))
    _surface(api,'Kaizen_NoseUnderside',[(0,-.173,1.929),(.016,-.146,1.920),
             (.010,-.150,1.916),(-.002,-.169,1.923)],'skin_shadow')
    # A narrow anime nose contour preserves the sculpt at front-on gameplay
    # angles where the cel-light band can otherwise hide the bridge entirely.
    _surface(api,'Kaizen_NoseContour',[(-.010,-.152,1.947),
             (-.012,-.162,1.932),(-.009,-.165,1.927),
             (-.008,-.161,1.933),(-.008,-.152,1.944)],'skin_shadow')
    for s in [-1,1]:
        _surface(api,'Kaizen_Nostril',[(s*.012,-.150,1.920),(s*.020,-.145,1.921),
                 (s*.020,-.145,1.918),(s*.012,-.150,1.917)],'skin_shadow')
        _eye(api,s)
        # Restrained lower-eyelid/cheek crease, not a large painted triangle.
        _surface(api,'Kaizen_CheekCrease',[(s*.096,-.112,1.948),
                 (s*.126,-.102,1.955),(s*.114,-.108,1.946)],'skin_shadow')
        _surface(api,'Kaizen_JawAccent',[(s*.091,-.073,1.825),
                 (s*.116,-.067,1.855),(s*.108,-.072,1.835)],'skin_shadow')
        # Ears are a folded shell, not visible sphere-like attachments.
        ear = [(s*.145,.002,1.983),(s*.163,-.007,1.986),
               (s*.178,-.003,1.970),(s*.176,-.010,1.935),
               (s*.161,-.014,1.917),(s*.148,-.008,1.929)]
        _surface(api,'Kaizen_EarShell',ear,'skin')
        _surface(api,'Kaizen_EarFold',[(s*.159,-.015,1.972),
                 (s*.170,-.013,1.972),(s*.166,-.019,1.941),
                 (s*.157,-.018,1.935),(s*.162,-.020,1.953)],'skin_shadow')
    # Mouth is placed ahead of the front facial plane, with a sharp relaxed
    # corner and a tiny lower-lip highlight; no embedded or detached sticker.
    _surface(api,'Kaizen_Mouth', [(-.039,-.091,1.868),(-.016,-.095,1.869),
             (.012,-.096,1.867),(.035,-.092,1.871),(.032,-.093,1.867),
             (.010,-.097,1.864),(-.016,-.096,1.866)],'kaizen_lip')
    _surface(api,'Kaizen_LowerLip',[(-.012,-.094,1.853),(.019,-.094,1.854),
             (.009,-.095,1.850),(-.006,-.095,1.850)],'skin_light')


def _eye(api,side):
    def p(x,z,layer=0):
        # Each eye is a single shallow tilted plane. Curving every polygon
        # independently in both x and z lets the triangulated white fan cut
        # back through the lid fan. Parallel layers guarantee stable ordering
        # for sclera/iris/pupil/lids at every point, including close-up views.
        return (side*x, -.131 + .14*x - layer*1.5, z)
    def bp(x,z,layer=0):
        # Brows remain conformed to the actual forehead, above the eye plane.
        return (side*x, _front_y(x,z) - .002 - layer, z)
    # Slanted upper lid and restrained sclera leave a focused adult expression.
    outline=[(.022,1.980),(.048,1.995),(.104,2.001),(.139,2.000),
             (.115,1.976),(.065,1.971),(.035,1.976)]
    _surface(api,'Kaizen_Sclera', [p(x,z,.001) for x,z in outline],'white')
    # Elliptical iris avoids giant toy-like eyes. Dark upper lid partially
    # occludes it naturally and the small catchlight remains readable nearby.
    cx,cz=.077,1.985
    ring=[p(cx+math.cos(a*math.tau/24)*.015,cz+math.sin(a*math.tau/24)*.013,.003)
          for a in range(24)]
    _surface(api,'Kaizen_Iris',ring,'kaizen_eye_blue')
    pupil=[p(cx+math.cos(a*math.tau/20)*.006,cz+math.sin(a*math.tau/20)*.011,.004)
           for a in range(20)]
    _surface(api,'Kaizen_EyePupil',pupil,'ink')
    _surface(api,'Kaizen_EyeCatchlight',[p(.070,1.992,.005),p(.075,1.994,.005),
             p(.077,1.989,.005),p(.072,1.988,.005)],'white')
    lid=[(.020,1.980),(.047,2.000),(.103,2.007),(.143,2.004),
         (.140,1.997),(.104,1.998),(.049,1.991)]
    _surface(api,'Kaizen_UpperLid',[p(x,z,.006) for x,z in lid],'ink')
    lower=[(.036,1.975),(.065,1.969),(.115,1.974),(.137,1.994),
           (.117,1.978),(.066,1.972)]
    _surface(api,'Kaizen_LowerLid',[p(x,z,.005) for x,z in lower],'ink')
    # Inner brow low, outer brow high: a deliberate, athletic fighting gaze.
    brow=[(.021,2.015),(.027,2.029),(.108,2.049),(.130,2.044),
          (.105,2.037),(.044,2.019)]
    _surface(api,'Kaizen_Brow',[bp(x,z,.005) for x,z in brow],'hair')
    _surface(api,'Kaizen_BrowShadow',[bp(.024,2.014,.002),bp(.056,2.023,.002),
             bp(.108,2.040,.002),bp(.098,2.029,.002),bp(.035,2.010,.002)],'skin_shadow')


def _lock(api,name,path,widths,depths,highlight=False):
    """A swept eight-sided sculpted lock with a long, clean front ridge.

    Width and thickness are authored independently at each ring. The main
    ridges are gently smoothed; a narrower inset ribbon catches the cool light.
    """
    centers=[Vector(p) for p in path]
    verts=[]
    # Diamond front section with broad side facets, not a circular cone.
    cross=[(-1,0),(-.66,-.70),(0,-1),(.66,-.70),(1,0),(.60,.62),(0,.82),(-.60,.62)]
    axes=[]
    for j,c in enumerate(centers):
        tangent=(centers[min(j+1,len(centers)-1)]-centers[max(0,j-1)]).normalized()
        front=Vector((0,-1,0));front=(front-tangent*front.dot(tangent)).normalized()
        across=front.cross(tangent).normalized()
        axes.append((front,across))
        for x,y in cross:
            # cross negative y points toward viewer; front is -Y.
            verts.append(c+across*x*widths[j]+front*(-y)*depths[j])
    faces=[]
    for j in range(len(centers)-1):
        for i in range(8):
            a=j*8+i;b=j*8+(i+1)%8
            faces.append((a,b,b+8,a+8))
    faces += [tuple(reversed(range(8))),tuple(range((len(centers)-1)*8,len(centers)*8))]
    obj=api.mesh(name,verts,faces,'hair',[{'head':1}]*len(verts))
    if highlight:
        pts=[]
        for j in range(1,len(centers)):
            f,a=axes[j];c=centers[j]+f*(depths[j]+.0006)
            w=widths[j]*.11
            pts.extend([c-a*w,c+a*w])
        fs=[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(centers)-2)]
        if fs:api.mesh(name+'_Ridge',pts,fs,'kaizen_hair_ridge',[{'head':1}]*len(pts))
    return obj


def _hair(api):
    # Continuous skull cap under overlapping clumps; staggered root heights
    # produce a swept silhouette rather than a symmetric paper crown.
    api.loft_z('Kaizen_HairScalp',[
        (1.996,.155,.126,.027),(2.041,.163,.134,.031),
        (2.091,.151,.127,.036),(2.137,.116,.099,.040),
        (2.166,.065,.065,.045),(2.174,.006,.006,.046),
    ],'hair',api.rigid('head'),48)
    # Left/right blades intentionally differ in height and sweep.
    crown=[
        ((-.085,.026,2.098),(-.126,-.002,2.191),(-.202,-.005,2.307)),
        ((-.028,.028,2.128),(-.048,-.008,2.244),(-.092,-.014,2.380)),
        (( .030,.034,2.138),( .045,.006,2.256),( .078,.015,2.400)),
        (( .088,.037,2.105),( .144,.020,2.224),( .219,.029,2.335)),
        ((-.127,.036,2.062),(-.181,.028,2.125),(-.278,.010,2.205)),
        (( .130,.042,2.066),( .194,.032,2.131),( .288,.025,2.210)),
    ]
    for i,(a,b,c) in enumerate(crown):
        mid=Vector(b).lerp(Vector(c),.50)+Vector((0,-.008,.006))
        _lock(api,'Kaizen_CrownBlade_%02d'%i,[a,b,mid,c],
              [.045,.055,.033,.0007],[.027,.034,.020,.0007],i%2==0)
    # Back silhouette has broad swept leaves and a descending nape fan.
    for side in [-1,1]:
        for i in range(4):
            base=(side*(.078+i*.016),.083+i*.014,2.112-i*.026)
            tip=(side*(.213+i*.008),.118+i*.025,2.241-i*.103)
            middle=Vector(base).lerp(Vector(tip),.5)+Vector((side*.018,0,.027))
            _lock(api,'Kaizen_BackSweep', [base,middle,tip],
                  [.050,.051,.0007],[.029,.026,.0006],i==0)
        _lock(api,'Kaizen_NapeLock',[(side*.069,.111,2.014),
               (side*.104,.136,1.958),(side*.128,.139,1.892)],
              [.041,.036,.0007],[.020,.020,.0006])
    # Layered face-framing bangs leave both eyes and most brows uncovered.
    bangs=[
        ([(-.082,-.081,2.148),(-.083,-.127,2.099),(-.124,-.146,2.020)], [.043,.043,.0007]),
        ([(-.023,-.093,2.163),(-.019,-.147,2.113),(-.052,-.164,2.029)], [.049,.043,.0007]),
        ([( .037,-.090,2.168),( .044,-.144,2.112),( .017,-.168,2.041)], [.049,.042,.0007]),
        ([( .098,-.069,2.144),( .123,-.118,2.099),( .155,-.134,2.025)], [.043,.035,.0007]),
    ]
    for i,(path,widths) in enumerate(bangs):
        _lock(api,'Kaizen_Forelock_%02d'%i,path,widths,[.018,.021,.0007],True)
    for side in [-1,1]:
        _lock(api,'Kaizen_TempleBlade',[(side*.131,-.023,2.095),
               (side*.164,-.044,2.023),(side*.178,-.057,1.951)],
              [.027,.024,.0006],[.018,.019,.0006],True)
