#!/usr/bin/env python3
"""Avrupa dünyası üretici -> res://data/world.json
Kulüp adları kurgusaldır: şehir + yerel dilde takma ad."""
import json, random, unicodedata, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from cities import CITIES
from names import P, POOL_OF

# kod: (TR adı, EN adı, dil, üst seviye OVR, en yüksek prestij, [kademe kulüp sayıları ([n] veya [n, grup])], ad stili)
C = {
 "EN": ("İngiltere", "England", "EN", 80, 93, [18, 18, 18], "en"),
 "ES": ("İspanya", "Spain", "ES", 80, 93, [18, 18], "es"),
 "DE": ("Almanya", "Germany", "DE", 79, 92, [18, 18, 18], "de"),
 "IT": ("İtalya", "Italy", "IT", 79, 92, [18, 18], "it"),
 "FR": ("Fransa", "France", "FR", 77, 88, [18, 18], "fr"),
 "PT": ("Portekiz", "Portugal", "PT", 74, 82, [18, 16], "pt"),
 "NL": ("Hollanda", "Netherlands", "NL", 73, 80, [18, 18], "nl"),
 "BE": ("Belçika", "Belgium", "NL", 70, 72, [16, 16], "nl"),
 "SCO": ("İskoçya", "Scotland", "EN", 66, 66, [12, 10], "en"),
 "AT": ("Avusturya", "Austria", "DE", 67, 66, [12, 16], "de"),
 "CH": ("İsviçre", "Switzerland", "DE", 67, 64, [12, 10], "de"),
 "GR": ("Yunanistan", "Greece", "EL", 66, 66, [14, 16], "el"),
 "RU": ("Rusya", "Russia", "RU", 70, 70, [16, 18], "ru"),
 "UA": ("Ukrayna", "Ukraine", "UK", 66, 64, [16, 16], "ua"),
 "CZ": ("Çekya", "Czechia", "CS", 66, 62, [16, 16], "cs"),
 "PL": ("Polonya", "Poland", "PL", 64, 58, [18, 18], "pl"),
 "HR": ("Hırvatistan", "Croatia", "SH", 66, 64, [10, 12], "sh"),
 "RS": ("Sırbistan", "Serbia", "SH", 65, 64, [16, 16], "sh"),
 "DK": ("Danimarka", "Denmark", "DA", 65, 62, [12, 12], "da"),
 "SE": ("İsveç", "Sweden", "SV", 62, 56, [16, 16], "sv"),
 "NO": ("Norveç", "Norway", "NO", 63, 58, [16, 16], "no"),
 "RO": ("Romanya", "Romania", "RO", 62, 56, [16, 18], "ro"),
 "HU": ("Macaristan", "Hungary", "HU", 61, 54, [12, 16], "hu"),
 "BG": ("Bulgaristan", "Bulgaria", "BG", 58, 50, [14], "bg"),
 "SK": ("Slovakya", "Slovakia", "SK", 59, 50, [12], "sk"),
 "SI": ("Slovenya", "Slovenia", "SL", 58, 48, [10], "sl"),
 "IL": ("İsrail", "Israel", "HE", 60, 52, [14], "he"),
 "CY": ("Kıbrıs Rum Kesimi", "Cyprus", "EL", 61, 52, [10], "el"),
 "AZ": ("Azerbaycan", "Azerbaijan", "AZ", 58, 50, [10], "az"),
 "KZ": ("Kazakistan", "Kazakhstan", "RU", 58, 48, [14], "kz"),
 "BY": ("Belarus", "Belarus", "RU", 55, 44, [14], "ru"),
 "MD": ("Moldova", "Moldova", "RO", 50, 40, [8], "ro"),
 "BA": ("Bosna-Hersek", "Bosnia and Herzegovina", "SH", 55, 44, [12], "sh"),
 "ME": ("Karadağ", "Montenegro", "SH", 51, 38, [10], "sh"),
 "MK": ("Kuzey Makedonya", "North Macedonia", "MK", 52, 40, [12], "mk"),
 "AL": ("Arnavutluk", "Albania", "SQ", 53, 42, [10], "sq"),
 "XK": ("Kosova", "Kosovo", "SQ", 52, 40, [10], "sq"),
 "IE": ("İrlanda", "Ireland", "EN", 54, 44, [10, 10], "en"),
 "NIR": ("Kuzey İrlanda", "Northern Ireland", "EN", 49, 36, [12], "en"),
 "WAL": ("Galler", "Wales", "EN", 48, 34, [12], "en"),
 "IS": ("İzlanda", "Iceland", "IS", 51, 38, [12], "is"),
 "FI": ("Finlandiya", "Finland", "FI", 55, 44, [12], "fi"),
 "EE": ("Estonya", "Estonia", "ET", 49, 36, [10], "et"),
 "LV": ("Letonya", "Latvia", "LV", 50, 38, [10], "lv"),
 "LT": ("Litvanya", "Lithuania", "LT", 50, 38, [10], "lt"),
 "GE": ("Gürcistan", "Georgia", "KA", 56, 46, [10], "ka"),
 "AM": ("Ermenistan", "Armenia", "HY", 52, 42, [10], "hy"),
 "LU": ("Lüksemburg", "Luxembourg", "FR", 50, 38, [16], "fr"),
 "MT": ("Malta", "Malta", "EN", 48, 36, [14], "en"),
 "FO": ("Faroe Adaları", "Faroe Islands", "DA", 46, 30, [10], "da"),
 "AD": ("Andorra", "Andorra", "CA", 42, 26, [8], "ca"),
 "SM": ("San Marino", "San Marino", "IT", 38, 22, [14], "it"),
 "GI": ("Cebelitarık", "Gibraltar", "EN", 44, 28, [10], "en"),
 "BR": ("Brezilya", "Brazil", "PT", 72, 86, [18], "pt"),
 "AR": ("Arjantin", "Argentina", "ES", 71, 84, [18, 18], "es"),
 "SA": ("Suudi Arabistan", "Saudi Arabia", "AR", 70, 80, [16], "ar"),
 "EG": ("Mısır", "Egypt", "AR", 60, 60, [8], "ar"),
 "MA": ("Fas", "Morocco", "AR", 60, 58, [8], "ar"),
 "TN": ("Tunus", "Tunisia", "AR", 56, 52, [6], "ar"),
 "DZ": ("Cezayir", "Algeria", "AR", 56, 52, [8], "ar"),
 "QA": ("Katar", "Qatar", "AR", 58, 56, [6], "ar"),
 "AE": ("Birleşik Arap Emirlikleri", "UAE", "AR", 58, 56, [7], "ar"),
 "SN": ("Senegal", "Senegal", "FR", 52, 44, [7], "fr"),
 "NG": ("Nijerya", "Nigeria", "EN", 52, 44, [8], "en"),
 "GH": ("Gana", "Ghana", "EN", 51, 42, [6], "en"),
 "CI": ("Fildişi Sahili", "Ivory Coast", "FR", 52, 44, [6], "fr"),
 "CM": ("Kamerun", "Cameroon", "FR", 50, 40, [6], "fr"),
 "ML": ("Mali", "Mali", "FR", 49, 38, [6], "fr"),
}
import re
_DATA = open(os.path.join(os.path.dirname(__file__), "..", "..", "autoload", "Data.gd"), encoding="utf-8").read()
def _hand(name):
    m = re.search(r"const " + name + r" := \[(.*?)\n\]", _DATA, re.S)
    rows = re.findall(r'\["([^"]+)", "([^"]+)", "([^"]+)", (\d+), "(#[0-9a-fA-F]+)", "(#[0-9a-fA-F]+)"\]', m.group(1))
    return [[a, b, c, int(d), e, f] for (a, b, c, d, e, f) in rows]
HAND = {"EN": _hand("EN_LIG"), "IT": _hand("IT_LIG"), "BR": _hand("BR_LIG")}
# Ligi simüle edilmeyen, yalnızca keşif (scout) yapılan ülkeler
SCOUT_ONLY = {"HU", "RO", "BG", "SK", "SI", "IL", "CY", "AZ", "KZ", "BY", "MD", "BA", "ME", "MK", "AL", "XK", "IE", "NIR", "WAL",
              "IS", "FI", "EE", "LV", "LT", "GE", "AM", "LU", "MT", "FO", "AD", "SM", "GI",
              "EG", "MA", "TN", "DZ", "QA", "AE", "SN", "NG", "GH", "CI", "CM", "ML"}
# Ülkeler arası yakınlık (yabancı oyuncu havuzu) – bölgeler
REGION = {
 "west": ["EN", "SCO", "WAL", "NIR", "IE", "FR", "BE", "NL", "LU", "ES", "PT", "AD", "GI"],
 "central": ["DE", "AT", "CH", "CZ", "SK", "PL", "HU", "SI"],
 "nordic": ["DK", "SE", "NO", "FI", "IS", "FO", "EE", "LV", "LT"],
 "balkan": ["HR", "RS", "BA", "ME", "MK", "AL", "XK", "BG", "RO", "MD", "GR", "CY", "SI"],
 "east": ["RU", "UA", "BY", "KZ", "GE", "AM", "AZ", "LV", "LT", "EE", "MD"],
 "south": ["IT", "SM", "MT", "ES", "PT", "GR", "CY", "IL"],
 "mena": ["SA", "EG", "MA", "TN", "DZ", "QA", "AE"],
 "africa": ["SN", "NG", "GH", "CI", "CM", "ML"],
 "sam": ["BR", "AR"],
}
GLOBAL_FOREIGN = {"BR": 6, "AR": 3, "FR": 4, "NG": 3, "SN": 3, "GH": 2, "CM": 2, "MA": 2, "PT": 2, "ES": 2, "NL": 1, "RS": 2, "HR": 2, "UY": 1}

NICK = {
 "en": "Mariners Falcons Ironside Harbour Kestrels Lions Steelmen Oaks Pilgrims Ravens Stags Herons Granite Comets Phoenix Badgers Sky Archers Beacons Foxhall Larks Wolves Thistle Mercury Clarets Valiant Navigators Lancers".split(),
 "es": "Leones Halcones Marineros Toros Lobos Celestes Granates Olivares Tritones Águilas Corsarios Gaviotas Linces Pumas Vientos Faros Centauros Cóndores Delfines Galeones".split(),
 "pt": "Gaviões Falcões Marinheiros Tubarões Lobos Navegadores Corsários Pumas Pinheiros Grifos Andorinhas Faróis Cometas Linces Ventos Golfinhos".split(),
 "fr": "Faucons Lions Corsaires Aigles Dauphins Loups Mouettes Hermines Chênes Comètes Phénix Griffons Étoiles Mistral Lynx Hérons".split(),
 "de": "Adler Falken Löwen Wölfe Greifen Füchse Bären Sterne Stahl Eichen Kometen Raben Luchse Möwen Hirsche Blitz".split(),
 "it": "Leoni Falchi Lupi Aquile Grifoni Delfini Corsari Galli Stelle Querce Fenici Gabbiani Comete Lanceri Vele Linci".split(),
 "nl": "Leeuwen Valken Adelaars Wolven Meeuwen Zwaluwen Sterren Eiken Kometen Vikingen Reigers Haviken Lynxen Golven".split(),
 "da": "Ørne Falke Ulve Bjørne Måger Stjerner Løver Ravne Lynet Bølgen".split(),
 "sv": "Örnar Falkar Vargar Björnar Måsar Stjärnor Lodjur Korpar Blixten Vågen".split(),
 "no": "Ørner Falker Ulver Bjørner Måker Stjerner Ravner Lynet Bølgen Gauper".split(),
 "fi": "Kotkat Haukat Sudet Karhut Lokit Tähdet Korpit Salama Aalto Kometat".split(),
 "is": "Ernir Fálkar Úlfar Birnir Mávar Hrafnar Eldur Bylgja".split(),
 "ru": "Sokol Berkut Yastreb Volna Iskra Kometa Rassvet Grifon Burevestnik Severyanin Meteor Molniya".split(),
 "ua": "Sokil Berkut Yastrub Khvylia Iskra Kometa Svitanok Hryfon Bureviy Meteor Blyskavka".split(),
 "kz": "Burkit Sunkar Kaskyr Tolkyn Zhuldyz Arlan Kyran Barys".split(),
 "pl": "Sokół Orzeł Jastrząb Fala Iskra Kometa Wilki Grom Błyskawica Sowa Żurawie".split(),
 "cs": "Sokol Orel Jestřáb Vlna Jiskra Kometa Vlci Blesk Sova Jeřáb".split(),
 "sk": "Sokol Orol Jastrab Vlna Iskra Kométa Vlci Blesk Sova".split(),
 "sh": "Sokol Orao Jastreb Val Iskra Kometa Vukovi Munja Sova Ždral".split(),
 "sl": "Sokol Orel Jastreb Val Iskra Komet Volkovi Strela".split(),
 "mk": "Sokol Orel Jastreb Bran Iskra Kometa Volci Molnja".split(),
 "bg": "Sokol Orel Yastreb Vulna Iskra Kometa Vultsi Mulniya".split(),
 "ro": "Șoimii Vulturii Lupii Valul Scânteia Cometa Stejarii Grifonii Fulgerul".split(),
 "hu": "Sólymok Sasok Farkasok Hullám Szikra Üstökös Bölények Villám".split(),
 "el": "Aetoi Gerakia Lykoi Kyma Foinikes Delfinia Tritones Keravnos Gryps".split(),
 "sq": "Shqiponjat Skifterat Ujqërit Vala Ylli Kometa Rrufeja Petriti".split(),
 "az": "Qartal Şahin Qurd Dalğa Ulduz Şimşək Pələng".split(),
 "ka": "Artsivi Shevardeni Mgeli Talgha Varskvlavi Elva".split(),
 "hy": "Artsiv Bazeh Gayl Alik Astgh Kaytsak".split(),
 "he": "Nesher Barak Ariot Kochav Gal Zeev".split(),
 "et": "Kotkad Kullid Hundid Laine Täht Välk".split(),
 "lv": "Ērgļi Vanagi Vilki Vilnis Zvaigzne Zibens".split(),
 "lt": "Ereliai Sakalai Vilkai Bangos Žvaigždė Žaibas".split(),
 "ca": "Àligues Falcons Llops Onada Estels Llamps".split(),
 "ar": "Al-Nusur Al-Suqur Al-Fursan Al-Najm Al-Asad Al-Barq Al-Mawj Al-Nakheel Al-Shuhub Al-Sahm Al-Qamar Al-Dhiab".split(),
}
SUFFIX = {"en": ["FC", "", "", "AFC"], "de": ["", "", "SC"], "nl": ["", "", "FC"], "da": ["", "BK", "IF"], "sv": ["", "IF", "FF"],
          "no": ["", "FK", "IL"], "fi": ["", "", "FC"], "is": ["", ""], "fr": ["", "", "FC"], "it": ["", "", "Calcio"]}
PREFIX_STYLE = {"ar", "ru", "ua", "kz", "pl", "cs", "sk", "sh", "sl", "mk", "bg", "ro", "el", "he", "es", "pt", "ca", "it"}
PALETTE = ["#c8102e", "#034694", "#ffffff", "#000000", "#fbe122", "#00843d", "#6cabdd", "#7a263a", "#f58220", "#5b2c83",
           "#1c2c5b", "#e30613", "#009639", "#003399", "#ffcc00", "#95bfe5", "#8b0000", "#004d98", "#a50044", "#00a0dd",
           "#2e7d32", "#d32f2f", "#1565c0", "#fdd835", "#424242", "#ef6c00", "#00838f", "#6a1b9a", "#c0ca33", "#bdbdbd"]

def fold(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")

def lum(h):
    h = h.lstrip("#"); r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return 0.299 * r + 0.587 * g + 0.114 * b

def main():
    rnd = random.Random(1923)
    out = {"countries": {}, "cities": {}, "names": {}, "pool_of": POOL_OF, "lang_names": {}}
    taken_city = set()
    for cc, rows in CITIES.items():
        for (n, la, lo) in rows:
            assert n not in taken_city, n
            taken_city.add(n)
            out["cities"][n] = [la, lo, cc]
    for k, v in P.items():
        if v:
            out["names"][k] = [v[0].replace("_", " ").split(), [x.replace("_", " ") for x in v[1].split()]]
    for cc, (ntr, nen, lang, top_ovr, ptop, tiers, style) in C.items():
        cities = CITIES[cc]
        if cc in SCOUT_ONLY:
            tiers = [8 if sum(tiers) >= 12 or len(cities) >= 8 else 6]
        total = sum(tiers)
        # şehir başına kulüp ataması: büyük şehirler (listede önde) birden fazla kulüp alabilir
        slots = []
        i = 0
        while len(slots) < total:
            for j, cy in enumerate(cities):
                if len(slots) >= total:
                    break
                # ilk turda tüm şehirler, sonra yalnızca ilk %30'u tekrar
                if i == 0 or j < max(2, int(len(cities) * 0.3)):
                    slots.append(cy[0])
            i += 1
        # ilk kademeye büyük şehirler ağırlıklı
        order = slots[:]
        nicks = NICK[style][:]
        used_names = set()
        used_short = set()
        leagues = []
        clubs = []
        idx = 0
        for t, n in enumerate(tiers, start=1):
            lg = f"{cc}{t}"
            leagues.append({"id": lg, "tier": t, "n": n})
            if t == 1 and cc in HAND:
                for row in HAND[cc][:n]:
                    clubs.append(row + [lg])
                    used_names.add(row[0]); used_short.add(row[1])
                idx += n
                continue
            for k in range(n):
                city = order[idx]; idx += 1
                for _ in range(200):
                    nick = rnd.choice(nicks)
                    if style in PREFIX_STYLE:
                        name = f"{nick} {city}"
                    else:
                        name = f"{city} {nick}"
                    suf = rnd.choice(SUFFIX.get(style, [""]))
                    if suf:
                        name = f"{name} {suf}" if style != "da" or rnd.random() < 0.5 else f"{suf} {name}"
                    if name not in used_names and len(name) <= 28:
                        break
                used_names.add(name)
                base = fold(city).upper().replace(" ", "").replace("-", "").replace(".", "")
                sh = base[:3]
                if sh in used_short:
                    nb = fold(nick).upper()
                    for cand in [base[0] + nb[:2], base[:2] + nb[0], nb[:3], base[0] + base[-2:], base[:1] + nb[1:3]]:
                        if cand not in used_short:
                            sh = cand
                            break
                used_short.add(sh)
                frac = k / max(1, n - 1)
                pr = ptop * (0.62 ** (t - 1)) * (1.0 - 0.42 * frac) + rnd.uniform(-3, 3)
                pr = max(3, int(round(pr)))
                c1 = rnd.choice(PALETTE)
                c2 = rnd.choice([p for p in PALETTE if abs(lum(p) - lum(c1)) > 90])
                clubs.append([name, sh, city, pr, c1, c2, lg])
        # yabancı havuzu
        fw = {cc: 0}
        for r, members in REGION.items():
            if cc in members:
                for m in members:
                    if m != cc:
                        fw[m] = fw.get(m, 0) + 2
        for k, v in GLOBAL_FOREIGN.items():
            if k != cc:
                fw[k] = fw.get(k, 0) + v
        home = {"EN": 0.55, "ES": 0.65, "DE": 0.55, "IT": 0.55, "FR": 0.6, "PT": 0.55, "NL": 0.65, "BE": 0.5}.get(cc, 0.78)
        tot = sum(v for k, v in fw.items() if k != cc)
        fw[cc] = int(round(tot * home / (1 - home)))
        base = round(top_ovr - 0.30 * ptop, 1)
        if cc in SCOUT_ONLY:
            home = 0.9
            tot = sum(v for k, v in fw.items() if k != cc)
            fw[cc] = int(round(tot * home / (1 - home)))
        out["countries"][cc] = {"tr": ntr, "en": nen, "lang": lang, "base": base, "ptop": ptop,
                                "leagues": leagues, "clubs": clubs, "nats": fw, "scout": cc in SCOUT_ONLY}
    out["lang_names"] = {
        "EN": ["İngilizce", "English"], "ES": ["İspanyolca", "Spanish"], "DE": ["Almanca", "German"], "IT": ["İtalyanca", "Italian"],
        "FR": ["Fransızca", "French"], "PT": ["Portekizce", "Portuguese"], "NL": ["Felemenkçe", "Dutch"], "EL": ["Yunanca", "Greek"],
        "RU": ["Rusça", "Russian"], "UK": ["Ukraynaca", "Ukrainian"], "CS": ["Çekçe", "Czech"], "SK": ["Slovakça", "Slovak"],
        "PL": ["Lehçe", "Polish"], "SH": ["Boşnakça/Hırvatça/Sırpça", "Bosnian/Croatian/Serbian"], "DA": ["Danca", "Danish"],
        "SV": ["İsveççe", "Swedish"], "NO": ["Norveççe", "Norwegian"], "RO": ["Rumence", "Romanian"], "HU": ["Macarca", "Hungarian"],
        "BG": ["Bulgarca", "Bulgarian"], "SL": ["Slovence", "Slovene"], "HE": ["İbranice", "Hebrew"], "AZ": ["Azerice", "Azerbaijani"],
        "MK": ["Makedonca", "Macedonian"], "SQ": ["Arnavutça", "Albanian"], "IS": ["İzlandaca", "Icelandic"], "FI": ["Fince", "Finnish"],
        "ET": ["Estonca", "Estonian"], "LV": ["Letonca", "Latvian"], "LT": ["Litvanca", "Lithuanian"], "KA": ["Gürcüce", "Georgian"],
        "HY": ["Ermenice", "Armenian"], "CA": ["Katalanca", "Catalan"], "TR": ["Türkçe", "Turkish"], "AR": ["Arapça", "Arabic"],
    }
    path = os.path.join(os.path.dirname(__file__), "..", "..", "data", "world.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    n = sum(len(c["clubs"]) for c in out["countries"].values())
    print("ülke", len(out["countries"]), "kulüp", n, "şehir", len(out["cities"]), "bayt", os.path.getsize(path))

main()
