extends RefCounted
## Hızlı maç motoru (izlenmeyen maçlar): animasyonsuz "top sahipliği zinciri".
##
## Canlı motorla (sim/live_engine.gd) ortak olanlar (statik fonksiyon / sabit olarak paylaşılır):
##  - form_shift(): maç günü formu, ev sahibi avantajı (HOME_FM), büyük maç etkisi
##  - norm_factor(): özelliklerin maç seviyesine göre ölçeklenmesi (canlı at() ile aynı: 10 + (a - ort) * f)
##  - duel_p() / DUEL_K: tüm ikili mücadeleler; düello özellik karışımları canlı eylemlerle aynı
##  - decision_temp(): seçenek seçiminde softmax sıcaklığı (karar özelliği)
##  - lead_shift(): skor durumu etkisi; fatigue(): 70. dakikadan sonra yorgunluk
##  - rating_base(): maç puanı formülü (aynı ölçek)
## Farkı: 22 oyuncunun konumu yerine top dört bölgeden birindedir (0 kendi üçte biri, 1 orta saha,
## 2 hücum üçte biri, 3 ceza sahası). Topa sahip oyuncu canlı motordaki gibi seçenekleri
## (kısa pas, ileri pas / ara pas, çalım, top sürme, şut, orta, geri pas) değer + softmax ile seçer.
##
## Arayüz (Dalga 3): simulate(g, m, youth, seed_v) -> Dictionary
##  - Saf: m, g.s ve g.rng'ye dokunmaz (yalnızca okur; kendi RNG'si vardır).
##  - Deterministik: aynı seed_v + aynı m + aynı oyuncular -> aynı sonuç (çağrı sırasından bağımsız).
##  - m.xi_h / m.xi_a dolu gelmeli; motor ilk 11 seçmez.
##  - Dönüş: {gh, ga, ev:[{t:"g", pid, as, side, min}], rt:{pid: puan}, cards:{pid:{yc, rc}},
##    team:{h:{sh, sot, fouls, corners, poss, ...}, a:{...}}}

const LiveEngine = preload("res://sim/live_engine.gd")
const QSelf = preload("res://sim/quick_engine.gd")

# ham özellik sırası
const AK := ["pace", "stamina", "strength", "agility", "passing", "dribbling", "finishing", "first_touch",
	"crossing", "tackling", "heading", "positioning", "vision", "decisions", "composure", "work_rate",
	"reflexes", "handling"]
enum { A_PACE, A_STA, A_STR, A_AGI, A_PAS, A_DRB, A_FIN, A_FT, A_CRS, A_TCK, A_HEAD, A_POS, A_VIS,
	A_DEC, A_CMP, A_WR, A_REF, A_HND, NA }
# bileşik beceriler (canlı motordaki düello karışımları)
enum { C_PAS, C_PASL, C_THR, C_DRB, C_TCK, C_INT, C_PRS, C_RES, C_FIN, C_HFIN, C_AIRA, C_AIRD,
	C_CRS, C_FT, C_PACE, C_GK, C_HND, C_CMP, C_DEC, C_VIS, C_KFIN, C_TCKL, NC }
# bileşiğin ağırlık toplamı (yorgunluk düşüşü için; C_FT 0.022 + 0.01)
const CW := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 0.032, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]

# rol -> bölge ağırlıkları [topa sahip: z0, z1, z2, z3 (ceza sahasında bitirici)]
const ROLE_W := {
	"GK": [0.0, 0.0, 0.0, 0.0],
	"CB": [1.0, 0.35, 0.04, 0.12],
	"LB": [0.75, 0.6, 0.45, 0.1], "RB": [0.75, 0.6, 0.45, 0.1],
	"DM": [0.9, 0.9, 0.25, 0.12],
	"CM": [0.55, 1.0, 0.55, 0.3],
	"AM": [0.15, 0.9, 0.95, 0.6],
	"LW": [0.1, 0.65, 1.0, 0.75], "RW": [0.1, 0.65, 1.0, 0.75],
	"ST": [0.05, 0.3, 0.8, 1.7],
}
# rakibin hangi oyuncusu savunur (topun hücum eden takıma göre bölgesi)
const DEF_W := {
	"GK": [0.0, 0.0, 0.0, 0.1],
	"CB": [0.0, 0.15, 1.0, 1.2],
	"LB": [0.1, 0.35, 0.8, 0.6], "RB": [0.1, 0.35, 0.8, 0.6],
	"DM": [0.25, 1.0, 0.8, 0.6],
	"CM": [0.5, 1.0, 0.35, 0.25],
	"AM": [0.8, 0.6, 0.1, 0.05],
	"LW": [0.8, 0.45, 0.1, 0.05], "RW": [0.8, 0.45, 0.1, 0.05],
	"ST": [1.0, 0.25, 0.02, 0.02],
}
const WIDE := {"LB": true, "RB": true, "LW": true, "RW": true}

# ---- kalibrasyon (gerçek futbol hedefleri: tests/baseline/BASELINE.md §4)
const V := [0.002, 0.02, 0.064, 0.14]         # bölge değeri (canlı value() temsilcileri)
const LOSS := [0.07, 0.026, 0.014, 0.012]     # top kaybı maliyeti (rakibin o noktadaki değeri)
const PRESS := [0.3, 0.32, 0.45, 0.6]         # bölgeye göre ortalama baskı
const ACT_T := [9.0, 9.0, 7.8, 5.2]           # eylem başına maç saniyesi
const PASS_T := 5.8                            # kısa pas başına maç saniyesi
const FWD_BASE := [0.8, 0.7, 0.36]            # ileri pas / ara pas taban başarısı
const THRU_SEE := 0.50                         # hücum üçte birinde ara pası görme tabanı (+vizyon)
const NEAR_P := [0.35, 0.45, 0.75, 0.75]       # çalımda rakibin yakında olma olasılığı
const XG_BOX := [0.11, 0.3, 0.2, 0.11]        # ceza sahası şut değeri: normal, ara pas, geri pas, serbest
const XG_FAR := 0.055
const DIST_BOX := [14.0, 9.0, 10.5, 14.0]     # şut mesafesi (isabet/kurtarış düellosu için)
const DIST_FAR := 24.0
const PRESS_EV := 0.075                        # rakibin top kapma girişimi olasılığı (eylem başına)
const FOUL_EV := 0.055                         # mücadelede faul olasılığı (eylem başına, savunmacının sertliğiyle)
const Q_HOME_K := 0.1                          # bölge modelinde ev sahibi etkisi canlıdan zayıf kalıyor: ek kayma
const Q_LEVEL_K := 0.55                        # berabere-son-dakika temkini bölge modelinde daha güçlü etkiliyor
const RED_P := 0.0004                         # doğrudan kırmızı (faul başına; ikinci sarılar ayrıca)
const Q_SHOT_ON_ADJ := -0.13                     # isabet tabanı düzeltmesi
const Q_SAVE_ADJ := 0.215                        # kurtarış tabanı düzeltmesi

var rng := RandomNumberGenerator.new()
# sabit tabloların paketlenmiş kopyaları (sıcak döngüde Variant dizisi okumamak için)
var pV := PackedFloat32Array(V)
var pLOSS := PackedFloat32Array(LOSS)
var pPRESS := PackedFloat32Array(PRESS)
var pACT := PackedFloat32Array(ACT_T)
var pFWD := PackedFloat32Array(FWD_BASE)
var pNEAR := PackedFloat32Array(NEAR_P)
var pXGB := PackedFloat32Array(XG_BOX)
var pDIST := PackedFloat32Array(DIST_BOX)
var wide := PackedInt32Array()
var n := 0
var ids: Array = []
var ovr_v := PackedFloat32Array()   # oyuncu ovr (yalnız maç puanı: kalite terimi)
var side_of := PackedInt32Array()
var role: Array = []
var comp0 := PackedFloat32Array()
var comp := PackedFloat32Array()
var fat := PackedFloat32Array()
var on := PackedInt32Array()
var gk_i := PackedInt32Array([-1, -1])
# seçim tabloları: [taraf*4 + bölge] -> oyuncu dizini ve kümülatif ağırlık
var pk_i: Array = []
var pk_c: Array = []
var df_i: Array = []
var df_c: Array = []
# oyuncu istatistikleri
var s_p := PackedInt32Array()
var s_po := PackedInt32Array()
var s_kp := PackedInt32Array()
var s_d := PackedInt32Array()
var s_do := PackedInt32Array()
var s_t := PackedInt32Array()
var s_s := PackedInt32Array()
var s_g := PackedInt32Array()
var s_as := PackedInt32Array()
var s_sv := PackedInt32Array()
var s_err := PackedInt32Array()
var s_air := PackedInt32Array()
var s_airok := PackedInt32Array()
var s_yc := PackedInt32Array()
var s_rc := PackedInt32Array()
# takım istatistikleri [ev, dep]
var t_sh := PackedInt32Array([0, 0])
var t_sot := PackedInt32Array([0, 0])
var t_fl := PackedInt32Array([0, 0])
var t_co := PackedInt32Array([0, 0])
var t_p := PackedInt32Array([0, 0])
var t_po := PackedInt32Array([0, 0])
var poss_t := PackedFloat32Array([0.0, 0.0])
var score := PackedInt32Array([0, 0])
var men := PackedInt32Array([11, 11])
var clock := 0.0
var late_step := 0
var ev: Array = []
var ls_c := PackedFloat32Array([0.0, 0.0])    # taraf başına skor durumu kayması (önbellek)
# akış durumu
var half := 1
var half_end := LiveEngine.HALF
var sd := 0
var z := 1
var c := -1
var asst := -1
var ch := 0          # 0 normal, 1 ara pas, 2 geri pas/kesme, 3 serbest vuruş
var _depth := 0
var n_act := 0        # eylem sayısı (ölçüm)

const R_KEEP := 0    # hücum eden takımda kaldı (hücum üçte biri)
const R_GOAL := 1
const R_GK := 2      # rakip kaleci topla (tuttu / aut)
const R_OPP := 3     # rakip kendi bölgesinde topla

static func simulate(g, m: Dictionary, youth: bool, seed_v: int) -> Dictionary:
	var qe: QSelf = QSelf.new()
	return qe._run(g, m, youth, seed_v)

func _run(g, m: Dictionary, youth: bool, seed_v: int) -> Dictionary:
	rng.seed = seed_v if seed_v != 0 else 0x5EED
	_prepare(g, m, youth)
	_play()
	return _result()

# ================================================================ hazırlık

func _prepare(g, m: Dictionary, youth: bool) -> void:
	var raw := PackedFloat32Array()
	var ph := int(g.club(m.h).get("prestige", 0))
	var pa := int(g.club(m.a).get("prestige", 0))
	for hs in 2:
		var xi: Array = m.xi_h if hs == 0 else m.xi_a
		for pid in xi:
			var p: Dictionary = g.player(pid)
			if p.is_empty():
				continue
			var fm := LiveEngine.form_shift(rng, p, hs == 0, youth, pa if hs == 0 else ph) + (Q_HOME_K if hs == 0 else 0.0)
			var at: Dictionary = p.attrs
			for k in AK:
				raw.append(clampf(float(at[k]) + fm, 1.0, 20.0))
			ids.append(pid)
			ovr_v.append(float(p.ovr))
			side_of.append(hs)
			role.append(p.pos)
			wide.append(1 if WIDE.has(p.pos) else 0)
			on.append(1)
			if p.pos == "GK" and gk_i[hs] < 0:
				gk_i[hs] = ids.size() - 1
	n = ids.size()
	for hs in 2:
		if gk_i[hs] < 0:
			for i in n:
				if side_of[i] == hs:
					gk_i[hs] = i
					break
	# maç seviyesine göre ölçek (canlı at(): GK özellikleri yalnız kalecilerde, dayanıklılık herkeste)
	var A := PackedFloat32Array()
	A.resize(n * NA)
	for k in NA:
		var gk_attr := k == A_REF or k == A_HND
		var tot := 0.0
		var cnt := 0
		for i in n:
			var is_gk: bool = role[i] == "GK"
			if is_gk != gk_attr and k != A_STA:
				continue
			tot += raw[i * NA + k]
			cnt += 1
		var avg := tot / float(cnt) if cnt > 0 else 10.0
		var vs := 0.0
		for i in n:
			var is_gk2: bool = role[i] == "GK"
			if is_gk2 != gk_attr and k != A_STA:
				continue
			var dv := raw[i * NA + k] - avg
			vs += dv * dv
		var f := LiveEngine.norm_factor(sqrt(vs / float(maxi(1, cnt))))
		for i in n:
			A[i * NA + k] = 10.0 + (raw[i * NA + k] - avg) * f
	comp0.resize(n * NC)
	fat.resize(n)
	for i in n:
		var a := i * NA
		var o := i * NC
		var pas := A[a + A_PAS]
		var vis := A[a + A_VIS]
		comp0[o + C_PAS] = pas
		comp0[o + C_PASL] = pas * 0.65 + vis * 0.35
		comp0[o + C_THR] = pas * 0.5 + vis * 0.5
		comp0[o + C_DRB] = A[a + A_DRB] * 0.55 + A[a + A_AGI] * 0.25 + A[a + A_PACE] * 0.2
		comp0[o + C_TCK] = A[a + A_TCK] * 0.6 + A[a + A_POS] * 0.4
		comp0[o + C_INT] = A[a + A_POS] * 0.6 + A[a + A_DEC] * 0.4
		comp0[o + C_PRS] = A[a + A_TCK] * 0.6 + A[a + A_POS] * 0.25 + A[a + A_WR] * 0.15
		comp0[o + C_RES] = A[a + A_DRB] * 0.5 + A[a + A_CMP] * 0.3 + A[a + A_STR] * 0.2
		comp0[o + C_FIN] = A[a + A_FIN] * 0.7 + A[a + A_CMP] * 0.3
		comp0[o + C_HFIN] = A[a + A_HEAD] * 0.6 + A[a + A_FIN] * 0.2 + A[a + A_CMP] * 0.2
		comp0[o + C_AIRA] = A[a + A_HEAD] * 0.7 + A[a + A_STR] * 0.3
		comp0[o + C_AIRD] = A[a + A_HEAD] * 0.6 + A[a + A_STR] * 0.4
		comp0[o + C_CRS] = A[a + A_CRS]
		comp0[o + C_FT] = A[a + A_FT] * 0.022 + A[a + A_CMP] * 0.01
		comp0[o + C_PACE] = A[a + A_PACE]
		comp0[o + C_GK] = A[a + A_REF] * 0.65 + A[a + A_HND] * 0.35
		comp0[o + C_HND] = A[a + A_HND]
		comp0[o + C_CMP] = A[a + A_CMP]
		comp0[o + C_DEC] = A[a + A_DEC]
		comp0[o + C_VIS] = vis
		comp0[o + C_KFIN] = A[a + A_FIN] * 0.6 + A[a + A_CMP] * 0.4
		comp0[o + C_TCKL] = A[a + A_TCK]
		fat[i] = A[a + A_STA]
	comp = comp0.duplicate()
	for arr in [s_p, s_po, s_kp, s_d, s_do, s_t, s_s, s_g, s_as, s_sv, s_err, s_air, s_airok, s_yc, s_rc]:
		arr.resize(n)
		arr.fill(0)
	_rebuild_tables()

func _rebuild_tables() -> void:
	pk_i = []
	pk_c = []
	df_i = []
	df_c = []
	for si in 2:
		for zz in 4:
			var ia := PackedInt32Array()
			var ca := PackedFloat32Array()
			var ib := PackedInt32Array()
			var cb := PackedFloat32Array()
			var ta := 0.0
			var tb := 0.0
			for i in n:
				if side_of[i] != si or on[i] == 0:
					continue
				var w: float = ROLE_W[role[i]][zz]
				var w2: float = DEF_W[role[i]][zz]
				if w > 0.0:
					ta += w
					ia.append(i)
					ca.append(ta)
				if w2 > 0.0:
					tb += w2
					ib.append(i)
					cb.append(tb)
			pk_i.append(ia)
			pk_c.append(ca)
			df_i.append(ib)
			df_c.append(cb)

func _late_update() -> void:
	## yorgunluk: 70. dakikadan sonra beş kademede (canlı motorda süreklidir)
	var st := clampi(int((clock - 4200.0) / 300.0) + 1, 0, 5) if clock > 4200.0 else 0
	if st == late_step:
		return
	late_step = st
	_ls_update()
	var clk := 4200.0 + 300.0 * float(st) - 150.0
	for i in n:
		var fd := LiveEngine.fatigue(fat[i], clk)
		var o := i * NC
		for k in NC:
			comp[o + k] = comp0[o + k] - fd * CW[k]

# ================================================================ yardımcılar

func _pick(si: int, zz: int, excl: int) -> int:
	var ia: PackedInt32Array = pk_i[si * 4 + zz]
	var ca: PackedFloat32Array = pk_c[si * 4 + zz]
	var cnt := ia.size()
	if cnt == 0:
		return -1
	for _try in 3:
		var r := rng.randf() * ca[cnt - 1]
		for j in cnt:
			if r <= ca[j]:
				if ia[j] != excl:
					return ia[j]
				break
	return ia[0] if ia[0] != excl or cnt == 1 else ia[1]

func _pick_def(si: int, zz: int) -> int:
	var ia: PackedInt32Array = df_i[si * 4 + zz]
	var ca: PackedFloat32Array = df_c[si * 4 + zz]
	var cnt := ia.size()
	if cnt == 0:
		return -1
	var r := rng.randf() * ca[cnt - 1]
	for j in cnt:
		if r <= ca[j]:
			return ia[j]
	return ia[cnt - 1]

func _ls_update() -> void:
	for si in 2:
		var lead: int = score[si] - score[1 - si]
		var sh := LiveEngine.lead_shift(lead, clock)
		if lead == 0:
			sh *= Q_LEVEL_K
		ls_c[si] = sh + float(men[si] - men[1 - si]) * 0.6

func _tick(secs: float) -> void:
	clock += secs
	poss_t[sd] += secs

func _go(nsd: int, nz: int, nc: int) -> void:
	sd = nsd
	z = nz
	c = nc
	asst = -1
	ch = 0

func _apply(r: int) -> void:
	var o := 1 - sd
	if r == R_KEEP:
		_go(sd, 2, -1)
	elif r == R_GOAL:
		_go(o, 1, -1)
	elif r == R_GK:
		_go(o, 0, gk_i[o])
	else:
		_go(o, 0, -1)

func _turnover(df: int) -> void:
	## top kaybı: rakip, topun bulunduğu yerin aynası bölgede başlar
	_go(1 - sd, 2 - mini(z, 2), df)

# ================================================================ maç akışı

func _play() -> void:
	_go(0, 1, -1)
	var guard := 0
	while guard < 3000:
		guard += 1
		if clock >= half_end:
			if half == 1:
				half = 2
				half_end = LiveEngine.FULL + rng.randf_range(60.0, 240.0)
				_go(1, 1, -1)
				continue
			break
		if clock > 4200.0:
			_late_update()
		if c < 0 or on[c] == 0:
			c = _pick(sd, z, -1)
			if c < 0:
				break
		n_act += 1
		_action()

func _action() -> void:
	var o := 1 - sd
	var ls := ls_c[sd]
	var co := c * NC
	# ---- kaleci topla (canlı: _gk_decide)
	if c == gk_i[sd]:
		_tick(8.0)
		s_p[c] += 1
		t_p[sd] += 1
		if rng.randf() < 0.55 + comp[co + C_PAS] * 0.015:
			s_po[c] += 1
			t_po[sd] += 1
			_go(sd, 0, -1)
		elif rng.randf() < 0.45:
			s_po[c] += 1
			t_po[sd] += 1
			_go(sd, 1, -1)
		else:
			_go(o, 1, -1)
		return
	var df := _pick_def(o, z)
	var dfo := df * NC
	var prs: float = pPRESS[z]
	# ---- ikili mücadelede faul (çekme, itme, geç müdahale): sert/zayıf savunmacı daha çok faul yapar
	if df >= 0 and rng.randf() < FOUL_EV * (1.0 + (10.0 - comp[dfo + C_TCKL]) * 0.05 + (comp[co + C_DRB] - 10.0) * 0.04):
		_foul_flow(df)
		return
	# ---- rakip baskısı (canlı: _defend_owner)
	if df >= 0 and rng.randf() < PRESS_EV * (0.7 + comp[dfo + C_PRS] * 0.03):
		if rng.randf() < LiveEngine.duel_p(comp[dfo + C_PRS], comp[co + C_RES] + ls, 0.24, 0.03):
			s_t[df] += 1
			if rng.randf() < 0.13:
				_foul_flow(df)
				return
			_tick(pACT[z] * 0.5)
			_turnover(df)
			return
	# ---- serbest vuruş (hücum üçte biri)
	if ch == 3:
		ch = 0
		var u := rng.randf()
		if u < 0.3:
			_tick(6.0)
			_apply(_shot(_best(sd, C_FIN), DIST_FAR - 1.0, 0, -1))
			return
		elif u < 0.75:
			_apply(_cross(_best(sd, C_CRS), true))
			return
	# ---- seçenekler (canlı: _decide). -1e9 = seçenek yok
	var loss: float = pLOSS[z]
	var pas := comp[co + C_PAS] + ls
	var v_s := -1e9
	var p_s := 0.0
	var v_f := -1e9
	var p_f := 0.0
	var v_d := -1e9
	var p_d := 0.93
	var near := false
	var v_sh := -1e9
	var v_cr := -1e9
	var v_cu := -1e9
	var p_cu := 0.0
	if z < 3:
		p_s = clampf(0.935 + (pas - 10.0) * 0.012 - prs * 0.07, 0.5, 0.985)
		v_s = p_s * (pV[z] * 1.15 + 0.004) - (1.0 - p_s) * loss
	if z < 2 or (z == 2 and rng.randf() < THRU_SEE + (comp[co + C_VIS] - 10.0) * 0.05):
		var att: float = (comp[co + C_PASL] if z == 0 else (comp[co + C_PAS] if z == 1 else comp[co + C_THR])) + ls
		var de := comp[dfo + C_INT] if df >= 0 else 10.0
		p_f = LiveEngine.duel_p(att, de, pFWD[z] - prs * 0.08, 0.024)
		v_f = p_f * (pV[z + 1] * (1.6 if z == 2 else 1.0) + 0.004) - (1.0 - p_f) * loss
	if z < 3 or rng.randf() < 0.4:
		near = df >= 0 and rng.randf() < pNEAR[z]
		if near:
			p_d = LiveEngine.duel_p(comp[co + C_DRB] + ls, comp[dfo + C_TCK], 0.5, 0.03)
			v_d = p_d * pV[mini(z + 1, 3)] * 0.9 - (1.0 - p_d) * loss - (0.006 - (comp[co + C_DRB] - 10.0) * 0.0006)
		else:
			v_d = p_d * (pV[mini(z + 1, 3)] * 0.45 + pV[z] * 0.55) - (1.0 - p_d) * loss + 0.002
	if z >= 2:
		var xg0: float = XG_FAR if z == 2 else pXGB[ch]
		v_sh = xg0 * (0.6 + (comp[co + C_FIN] + ls) * 0.03) * (1.0 - prs * 0.3) * (1.05 if z == 2 else 1.5)
	if z == 2 and (wide[c] == 1 or rng.randf() < 0.2):
		v_cr = (0.3 + comp[co + C_CRS] * 0.025) * 1.8 * 0.085 * 0.55
	if z == 3 and ch != 2:
		p_cu = LiveEngine.duel_p(pas, comp[dfo + C_INT] if df >= 0 else 10.0, 0.62, 0.024)
		v_cu = p_cu * pXGB[2] * 0.9 * 1.5 * 1.1 - (1.0 - p_cu) * loss
	# softmax (canlı motorla aynı sıcaklık)
	var temp := LiveEngine.decision_temp(comp[co + C_DEC])
	var mx := maxf(maxf(maxf(v_s, v_f), maxf(v_d, v_sh)), maxf(v_cr, v_cu))
	var w_s := exp((v_s - mx) / temp) if v_s > -1e8 else 0.0
	var w_f := exp((v_f - mx) / temp) if v_f > -1e8 else 0.0
	var w_d := exp((v_d - mx) / temp) if v_d > -1e8 else 0.0
	var w_sh := exp((v_sh - mx) / temp) if v_sh > -1e8 else 0.0
	var w_cr := exp((v_cr - mx) / temp) if v_cr > -1e8 else 0.0
	var w_cu := exp((v_cu - mx) / temp) if v_cu > -1e8 else 0.0
	var r := rng.randf() * (w_s + w_f + w_d + w_sh + w_cr + w_cu)
	if r < w_s:
		_short(df, p_s)
		return
	r -= w_s
	if r < w_f:
		_forward(df, p_f)
		return
	r -= w_f
	if r < w_d:
		if near:
			s_d[c] += 1
			_tick(pACT[z] * 0.8)
			if rng.randf() < p_d:
				s_do[c] += 1
				if z < 3:
					z += 1
				ch = 0
			else:
				s_t[df] += 1
				if rng.randf() < 0.2 - comp[dfo + C_TCKL] * 0.005:
					_foul_flow(df)
					return
				_turnover(df)
		else:
			_tick(pACT[z])
			if z < 2 and rng.randf() < 0.35 + (comp[co + C_PACE] - 10.0) * 0.02:
				z += 1
		return
	r -= w_d
	if r < w_sh:
		_tick(pACT[z])
		var dist: float = DIST_FAR if z == 2 else pDIST[ch]
		_apply(_shot(c, dist, 0, asst if (ch == 1 or ch == 2) else -1))
		return
	r -= w_sh
	if r < w_cr:
		_tick(pACT[z])
		_apply(_cross(c, false))
		return
	# geri pas / kesme
	s_p[c] += 1
	t_p[sd] += 1
	_tick(2.5)
	if rng.randf() < p_cu:
		s_po[c] += 1
		t_po[sd] += 1
		s_kp[c] += 1
		asst = c
		var nc := _pick(sd, 3, c)
		c = nc if nc >= 0 else c
		ch = 2
	else:
		if df >= 0:
			s_t[df] += 1
		_go(o, 0, df)

func _short(df: int, pp: float) -> void:
	## kısa pas dizisi (3-7 pas, aynı oyuncuya yazılır; sonra top başka oyuncuya geçer)
	var kn := 3 + rng.randi_range(0, 4)
	for _j in kn:
		s_p[c] += 1
		t_p[sd] += 1
		if rng.randf() < pp:
			s_po[c] += 1
			t_po[sd] += 1
			_tick(PASS_T)
		else:
			if df >= 0:
				s_t[df] += 1
			_tick(2.0)
			if rng.randf() < 0.25:
				_tick(6.0)   # taç
			_turnover(df)
			return
	asst = c
	var nc := _pick(sd, z, c)
	c = nc if nc >= 0 else c
	if z < 2 and rng.randf() < 0.12:
		z += 1   # sabırlı oyunla ilerleme

func _forward(df: int, pp: float) -> void:
	s_p[c] += 1
	t_p[sd] += 1
	_tick(pACT[z])
	if rng.randf() >= pp:
		if df >= 0:
			s_t[df] += 1
		_turnover(df)
		return
	s_po[c] += 1
	t_po[sd] += 1
	var nz := z + 1
	var r_i := _pick(sd, nz, c)
	if r_i < 0:
		r_i = c
	if nz == 3:
		s_kp[c] += 1
	# ilk dokunuş baskı altında (canlı: _arrive)
	if nz >= 2 and df >= 0 and rng.randf() < 0.4 and rng.randf() > 0.55 + comp[r_i * NC + C_FT]:
		s_err[r_i] += 1
		if rng.randf() < 0.5:
			z = nz
			_turnover(df)
			return
	asst = c
	c = r_i
	z = nz
	ch = 1 if nz == 3 else 0

func _foul_flow(df: int) -> void:
	var fr := _foul(df)
	if fr == 1:
		_tick(40.0)
		_apply(_shot(_best(sd, C_FIN), 11.0, 4, -1))
	elif fr == 2:
		_tick(30.0)
		ch = 3 if z >= 2 else 0
		if z == 3:
			z = 2

func _best(si: int, cc: int) -> int:
	var b := -1
	var bv := -1e9
	for i in n:
		if side_of[i] == si and on[i] == 1 and i != gk_i[si]:
			var v := comp[i * NC + cc]
			if v > bv:
				bv = v
				b = i
	return b

func _shot(sh: int, dist: float, kind: int, a_i: int) -> int:
	## kind 0 ayak, 1 kafa, 4 penaltı (canlı: _do_shot + _shot_arrive)
	var o := 1 - sd
	var ls := ls_c[sd]
	var pen := kind == 4
	var so := sh * NC
	var ae := (comp[so + C_HFIN] if kind == 1 else comp[so + C_FIN]) + ls
	var prs := 0.0 if pen else rng.randf() * 0.6
	var p_on := LiveEngine.duel_p(ae, 10.0, (0.76 + Q_SHOT_ON_ADJ - dist / 55.0 - prs * 0.1) if not pen else 0.86, 0.03)
	s_s[sh] += 1
	t_sh[sd] += 1
	if rng.randf() >= p_on:
		if not pen and rng.randf() < 0.35:
			return _corner()
		_tick(10.0)
		return R_GK
	t_sot[sd] += 1
	var k := gk_i[o]
	var de := (comp[so + C_AIRA] if kind == 1 else comp[so + C_KFIN]) + ls
	var sv := LiveEngine.duel_p(comp[k * NC + C_GK], de, clampf(0.43 + Q_SAVE_ADJ + dist / 90.0, 0.38, 0.9) if not pen else 0.2, 0.025)
	if rng.randf() < sv:
		s_sv[k] += 1
		if rng.randf() < 0.35 + comp[k * NC + C_HND] * 0.025:
			_tick(6.0)
			return R_GK
		if rng.randf() < 0.55:
			return _corner()
		_tick(4.0)
		return R_KEEP if rng.randf() < 0.4 else R_OPP
	# gol
	score[sd] += 1
	_ls_update()
	s_g[sh] += 1
	var a_id := ""
	if a_i >= 0 and a_i != sh and side_of[a_i] == sd:
		s_as[a_i] += 1
		a_id = ids[a_i]
	ev.append({"t": "g", "pid": ids[sh], "as": a_id, "side": "h" if sd == 0 else "a", "min": mini(90, int(clock / 60.0) + 1)})
	_tick(10.0)
	return R_GOAL

func _corner() -> int:
	t_co[sd] += 1
	_tick(13.0)
	if _depth >= 3:
		return R_OPP
	_depth += 1
	var r := _cross(_best(sd, C_CRS), true)
	_depth -= 1
	return r

func _cross(cr: int, set_piece: bool) -> int:
	## canlı: _do_cross + _aerial
	var o := 1 - sd
	var ls := ls_c[sd]
	var pc := LiveEngine.duel_p(comp[cr * NC + C_CRS] + ls, 10.0, 0.42, 0.03)
	if not set_piece:
		s_p[cr] += 1
		t_p[sd] += 1
	if rng.randf() >= pc:
		_tick(6.0)
		if rng.randf() < 0.25:
			return _corner()
		return R_OPP
	if not set_piece:
		s_po[cr] += 1
		t_po[sd] += 1
	var att := _pick(sd, 3, cr)
	var dfd := _pick_def(o, 3)
	if att < 0:
		return R_OPP
	_tick(3.0)
	if dfd >= 0:
		var hd := LiveEngine.duel_p(comp[att * NC + C_AIRA] + ls, comp[dfd * NC + C_AIRD], 0.45, 0.035)
		s_air[att] += 1
		s_air[dfd] += 1
		if rng.randf() >= hd:
			s_airok[dfd] += 1
			if rng.randf() < 0.22:
				return _corner()
			return R_OPP if rng.randf() < 0.7 else R_KEEP
		s_airok[att] += 1
	return _shot(att, 9.0, 1, cr)

func _foul(df: int) -> int:
	## canlı: _foul. Dönüş: 0 hakem devam dedi, 1 penaltı, 2 serbest vuruş
	var in_box := z == 3
	if in_box and rng.randf() < 0.45:
		return 0
	var dsd := 1 - sd
	t_fl[dsd] += 1
	var pc := 0.14 + (0.12 if z >= 2 else 0.0) + (0.1 if in_box else 0.0) - comp[df * NC + C_CMP] * 0.004
	var pr := RED_P + (0.03 if in_box and role[df] == "CB" and rng.randf() < 0.3 else 0.0)
	if df != gk_i[dsd] and rng.randf() < pr:
		_send_off(df)
	elif rng.randf() < pc * LiveEngine.CARD_K * (LiveEngine.YC2_K if s_yc[df] > 0 else 1.0):
		s_yc[df] += 1
		if s_yc[df] >= 2 and df != gk_i[dsd]:
			_send_off(df)
	return 1 if in_box else 2

func _send_off(i: int) -> void:
	on[i] = 0
	s_rc[i] = 1
	men[side_of[i]] -= 1
	_ls_update()
	_rebuild_tables()
	if c == i:
		c = -1

# ================================================================ sonuç

func _result() -> Dictionary:
	var cards := {}
	var rt := {}
	var gd: int = score[0] - score[1]
	var ov_avg := PackedFloat32Array([0.0, 0.0])
	var ov_n := PackedFloat32Array([0.0, 0.0])
	for i in n:
		ov_avg[side_of[i]] += ovr_v[i]
		ov_n[side_of[i]] += 1.0
	for si in 2:
		ov_avg[si] /= maxf(1.0, ov_n[si])
	var tot := [{"kp": 0, "d": 0, "do": 0, "t": 0, "err": 0, "air": 0, "air_ok": 0, "sv": 0},
		{"kp": 0, "d": 0, "do": 0, "t": 0, "err": 0, "air": 0, "air_ok": 0, "sv": 0}]
	for i in n:
		var st := {"p": s_p[i], "po": s_po[i], "kp": s_kp[i], "d": s_d[i], "do": s_do[i], "t": s_t[i], "s": s_s[i],
			"so": 0, "g": s_g[i], "as": s_as[i], "sv": s_sv[i], "err": s_err[i], "air": s_air[i], "air_ok": s_airok[i]}
		if s_yc[i] > 0 or s_rc[i] > 0:
			st["yc"] = s_yc[i]
			if s_rc[i] > 0:
				st["rc"] = 1
			cards[ids[i]] = {"yc": s_yc[i], "rc": s_rc[i]}
		var si := side_of[i]
		var r := LiveEngine.rating_base(st, gd if si == 0 else -gd, role[i] == "GK", score[1 - si], ovr_v[i] - ov_avg[si])
		rt[ids[i]] = snappedf(clampf(r + rng.randfn(0.0, 0.2), 3.5, 9.8), 0.1)
		var tt: Dictionary = tot[si]
		for k in tt:
			tt[k] += st[k]
	ev.sort_custom(func(x, y): return x["min"] < y["min"])
	var tp := maxf(1.0, poss_t[0] + poss_t[1])
	var team := {}
	for si in 2:
		var d := {"sh": t_sh[si], "sot": t_sot[si], "fouls": t_fl[si], "corners": t_co[si],
			"poss": snappedf(100.0 * poss_t[si] / tp, 0.1), "p": t_p[si], "po": t_po[si]}
		d.merge(tot[si])
		team["h" if si == 0 else "a"] = d
	return {"gh": score[0], "ga": score[1], "ev": ev, "rt": rt, "cards": cards, "team": team}
