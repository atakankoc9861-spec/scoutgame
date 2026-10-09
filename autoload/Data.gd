extends Node
## Statik oyun verisi: kulüpler, isim havuzları, pozisyonlar, özellikler.
## Tüm kulüp ve oyuncu isimleri kurgusaldır.

const ATTRS := [
	"pace", "stamina", "strength", "agility",
	"passing", "dribbling", "finishing", "first_touch", "crossing", "tackling", "heading",
	"positioning", "vision", "decisions", "composure", "work_rate",
	"reflexes", "handling",
]
const ATTR_GROUP := {
	"pace": "phy", "stamina": "phy", "strength": "phy", "agility": "phy",
	"passing": "tec", "dribbling": "tec", "finishing": "tec", "first_touch": "tec",
	"crossing": "tec", "tackling": "tec", "heading": "tec",
	"positioning": "men", "vision": "men", "decisions": "men", "composure": "men", "work_rate": "men",
	"reflexes": "gk", "handling": "gk",
}
const HIDDEN := ["professionalism", "injury_prone", "big_match", "consistency", "adaptability"]

const POSITIONS := ["GK", "CB", "LB", "RB", "DM", "CM", "AM", "LW", "RW", "ST"]
const POS_GROUP := {
	"GK": "GK", "CB": "DEF", "LB": "DEF", "RB": "DEF",
	"DM": "MID", "CM": "MID", "AM": "MID", "LW": "ATT", "RW": "ATT", "ST": "ATT",
}

## Pozisyona göre özellik ağırlıkları (OVR hesabı) ve üretimde profil kayması.
const POS_WEIGHTS := {
	"GK": {"reflexes": 5, "handling": 4, "positioning": 3, "composure": 2, "decisions": 2, "agility": 2, "first_touch": 1, "passing": 1},
	"CB": {"tackling": 5, "heading": 4, "positioning": 4, "strength": 3, "decisions": 2, "pace": 2, "composure": 2, "passing": 1},
	"LB": {"pace": 4, "tackling": 4, "crossing": 3, "stamina": 3, "positioning": 3, "work_rate": 2, "dribbling": 1, "passing": 1},
	"RB": {"pace": 4, "tackling": 4, "crossing": 3, "stamina": 3, "positioning": 3, "work_rate": 2, "dribbling": 1, "passing": 1},
	"DM": {"tackling": 4, "positioning": 4, "passing": 3, "work_rate": 3, "stamina": 3, "decisions": 3, "strength": 2, "composure": 1},
	"CM": {"passing": 5, "vision": 3, "decisions": 3, "stamina": 3, "first_touch": 3, "work_rate": 2, "tackling": 2, "composure": 2},
	"AM": {"vision": 5, "passing": 4, "dribbling": 4, "first_touch": 3, "composure": 3, "decisions": 2, "finishing": 2, "agility": 2},
	"LW": {"pace": 5, "dribbling": 5, "crossing": 3, "agility": 3, "first_touch": 2, "finishing": 2, "vision": 1, "work_rate": 1},
	"RW": {"pace": 5, "dribbling": 5, "crossing": 3, "agility": 3, "first_touch": 2, "finishing": 2, "vision": 1, "work_rate": 1},
	"ST": {"finishing": 6, "composure": 3, "first_touch": 3, "heading": 3, "pace": 3, "strength": 2, "positioning": 2, "dribbling": 1},
}

## [isim, kısa ad, şehir, prestij(1-100), ana renk, ikinci renk]
const SUPER_LIG := [
	["Kadıköy SK", "KDK", "İstanbul", 92, "#d4a017", "#14213d"],
	["Karaköy SK", "KRK", "İstanbul", 90, "#b5121b", "#f2c230"],
	["Ortaköy JK", "ORT", "İstanbul", 87, "#111111", "#f5f5f5"],
	["Trabzon FK", "TRB", "Trabzon", 80, "#7a1f3d", "#5fa8d3"],
	["İkitelli SK", "IKT", "İstanbul", 68, "#f26b1d", "#1d3557"],
	["Konya Ovası SK", "KNY", "Konya", 60, "#2a9d4b", "#ffffff"],
	["İzmir Körfez SK", "IZM", "İzmir", 64, "#e9c46a", "#c1121f"],
	["Antalya Sahil FK", "ANT", "Antalya", 58, "#e63946", "#ffffff"],
	["Kayseri Erciyes SK", "KAY", "Kayseri", 55, "#ffd60a", "#c1121f"],
	["Sivas Kızılırmak SK", "SIV", "Sivas", 56, "#c1121f", "#ffffff"],
	["Gaziantep Kale FK", "GZT", "Gaziantep", 54, "#9d0208", "#111111"],
	["Adana Seyhan SK", "ADN", "Adana", 57, "#1d4ed8", "#ffffff"],
	["Samsun Karadeniz SK", "SAM", "Samsun", 59, "#d00000", "#ffffff"],
	["Rize Çay SK", "RIZ", "Rize", 52, "#2b9348", "#1d3557"],
	["Kocaeli Tersane SK", "KOC", "Kocaeli", 53, "#2d6a4f", "#111111"],
	["Kartal Sahil SK", "KRT", "İstanbul", 51, "#0077b6", "#ffffff"],
	["Hatay Defne SK", "HTY", "Hatay", 50, "#6a040f", "#ffffff"],
	["Bodrum Yalı SK", "BDR", "Muğla", 48, "#48cae4", "#023e8a"],
]
const BIRINCI_LIG := [
	["Ankara Başkent SK", "ANK", "Ankara", 46, "#ffbe0b", "#3a0ca3"],
	["Bursa Uludağ SK", "BRS", "Bursa", 47, "#2b9348", "#ffffff"],
	["Eskişehir Porsuk SK", "ESK", "Eskişehir", 42, "#e63946", "#111111"],
	["Malatya Kayısı SK", "MLT", "Malatya", 40, "#ffd60a", "#111111"],
	["Erzurum Palandöken SK", "ERZ", "Erzurum", 41, "#1d4ed8", "#ffffff"],
	["Manisa Spil SK", "MNS", "Manisa", 39, "#111111", "#ffffff"],
	["Sakarya Sapanca SK", "SKR", "Sakarya", 43, "#2b9348", "#111111"],
	["Denizli Pamukkale SK", "DNZ", "Denizli", 41, "#000000", "#ffffff"],
	["Çorum Hitit FK", "COR", "Çorum", 38, "#c1121f", "#111111"],
	["Bandırma Liman SK", "BND", "Balıkesir", 37, "#c1121f", "#ffffff"],
	["Diyarbakır Sur SK", "DYB", "Diyarbakır", 40, "#2b9348", "#c1121f"],
	["Mersin Akdeniz SK", "MRS", "Mersin", 38, "#1d4ed8", "#ffbe0b"],
	["Iğdır Ağrıdağ FK", "IGD", "Iğdır", 33, "#ffbe0b", "#2b9348"],
	["Van Gölü SK", "VAN", "Van", 32, "#48cae4", "#ffffff"],
	["Şanlıurfa Göbekli SK", "SUR", "Şanlıurfa", 34, "#ffbe0b", "#2b9348"],
	["Bolu Abant SK", "BOL", "Bolu", 35, "#c1121f", "#ffffff"],
	["Ümraniye Çamlıca SK", "UMR", "İstanbul", 36, "#c1121f", "#1d4ed8"],
	["Ankara Kızılay FK", "AKZ", "Ankara", 37, "#e63946", "#ffffff"],
]

## Alt ligler (kurgusal: yer adı + genel ek). [isim, kısa, il, prestij, renk1, renk2]
const IKINCI_LIG := [
	["Menemen Gençlik", "MEN", "İzmir", 35, "#3a0ca3", "#1d4ed8"],
	["Tuzla Yıldız SK", "TUZ", "İstanbul", 33, "#e63946", "#3a0ca3"],
	["Karşıyaka Akıncı SK", "KAR", "İzmir", 36, "#2b9348", "#6a040f"],
	["Bornova Şimşek SK", "BOR", "İzmir", 35, "#264653", "#1d4ed8"],
	["Pendik Anadolu FK", "PEN", "İstanbul", 34, "#3a0ca3", "#111111"],
	["Gebze Gücü", "GEB", "Kocaeli", 33, "#f26b1d", "#7b2cbf"],
	["Alanya Doğan SK", "ALA", "Antalya", 35, "#e63946", "#6a040f"],
	["Etimesgut Kartal FK", "ETI", "Ankara", 31, "#588157", "#264653"],
	["Esenler Ova FK", "ESE", "İstanbul", 31, "#d62828", "#1d4ed8"],
	["Bağcılar Atak SK", "BAG", "İstanbul", 31, "#2a9d8f", "#d62828"],
	["Eyüp Şimşek SK", "EYU", "İstanbul", 33, "#2b9348", "#588157"],
	["Buca Akıncı SK", "BUC", "İzmir", 32, "#1d4ed8", "#3a0ca3"],
	["Giresun Atak SK", "GIR", "Giresun", 31, "#e63946", "#c1121f"],
	["Çorlu Şimşek SK", "CRL", "Tekirdağ", 33, "#e63946", "#111111"],
	["Keçiören Gücü", "KEC", "Ankara", 33, "#ffbe0b", "#1d4ed8"],
	["İnegöl Kale SK", "INE", "Bursa", 31, "#ffbe0b", "#ffd60a"],
	["Zeytinburnu Kale SK", "ZEY", "İstanbul", 32, "#ffd60a", "#3a0ca3"],
	["Sarıyer Kale SK", "SAR", "İstanbul", 30, "#f26b1d", "#023e8a"],
	["Beykoz Atak SK", "BEY", "İstanbul", 30, "#3a0ca3", "#023e8a"],
	["Sincan İdman Yurdu", "SIN", "Ankara", 29, "#023e8a", "#111111"],
	["İskenderun İdman Yurdu", "ISK", "Hatay", 30, "#7b2cbf", "#0077b6"],
	["Düzce Anadolu FK", "DUZ", "Düzce", 31, "#023e8a", "#264653"],
	["Nazilli Ova FK", "NAZ", "Aydın", 27, "#ffbe0b", "#3a0ca3"],
	["Maraş Çelik SK", "MAR", "Kahramanmaraş", 30, "#3a0ca3", "#f26b1d"],
	["Uşak Birlik SK", "USA", "Uşak", 28, "#264653", "#111111"],
	["Edirne İdman Yurdu", "EDI", "Edirne", 30, "#6a040f", "#111111"],
	["Silivri Birlik SK", "SIL", "İstanbul", 28, "#2a9d8f", "#264653"],
	["Afyon Birlik SK", "AFY", "Afyonkarahisar", 27, "#ffd60a", "#264653"],
	["Tekirdağ Akıncı SK", "TEK", "Tekirdağ", 26, "#f26b1d", "#588157"],
	["Mamak İdman Yurdu", "MAM", "Ankara", 28, "#9d0208", "#0077b6"],
	["Akhisar Doğan SK", "AKH", "Manisa", 26, "#6a040f", "#f26b1d"],
	["Osmaniye Atak SK", "OSM", "Osmaniye", 24, "#d62828", "#111111"],
	["Tarsus Yıldız SK", "TAR", "Mersin", 27, "#111111", "#c1121f"],
	["Turgutlu Kale SK", "TUR", "Manisa", 27, "#ffbe0b", "#7b2cbf"],
	["Elazığ Atak SK", "ELA", "Elazığ", 26, "#ffbe0b", "#2a9d8f"],
	["Aksaray Yıldız SK", "AKS", "Aksaray", 23, "#f26b1d", "#588157"],
]
const UCUNCU_LIG := [
	["Ordu Akıncı SK", "ORD", "Ordu", 27, "#111111", "#3a0ca3"],
	["Ereğli Şimşek SK", "ERE", "Konya", 25, "#023e8a", "#ffbe0b"],
	["Gölcük Ova FK", "GOL", "Kocaeli", 24, "#111111", "#d62828"],
	["Aydın Şimşek SK", "AYD", "Aydın", 25, "#f26b1d", "#588157"],
	["Salihli Birlik SK", "SAL", "Manisa", 23, "#7b2cbf", "#9d0208"],
	["Çerkezköy Kale SK", "CER", "Tekirdağ", 23, "#2b9348", "#0077b6"],
	["Zonguldak Atak SK", "ZON", "Zonguldak", 25, "#588157", "#0077b6"],
	["Küçükçekmece Ova FK", "KUC", "İstanbul", 23, "#7b2cbf", "#f26b1d"],
	["Çanakkale Çelik SK", "CAN", "Çanakkale", 23, "#6a040f", "#023e8a"],
	["Bafra Yıldız SK", "BAF", "Samsun", 24, "#023e8a", "#264653"],
	["Batman Akıncı SK", "BAT", "Batman", 26, "#264653", "#588157"],
	["Soma Kale SK", "SOM", "Manisa", 24, "#c1121f", "#6a040f"],
	["Kırşehir İdman Yurdu", "KIR", "Kırşehir", 25, "#1d4ed8", "#9d0208"],
	["Fethiye Akıncı SK", "FET", "Muğla", 23, "#2b9348", "#6a040f"],
	["Nizip Şimşek SK", "NIZ", "Gaziantep", 22, "#1d4ed8", "#588157"],
	["Elbistan Şimşek SK", "ELB", "Kahramanmaraş", 24, "#2b9348", "#3a0ca3"],
	["Akçaabat Ova FK", "AKC", "Trabzon", 22, "#588157", "#6a040f"],
	["Kırıkkale Kartal FK", "KRI", "Kırıkkale", 23, "#2a9d8f", "#111111"],
	["Erzincan Atak SK", "EZI", "Erzincan", 22, "#2b9348", "#d62828"],
	["Isparta Atak SK", "ISP", "Isparta", 22, "#c1121f", "#ffd60a"],
	["Ağrı Kale SK", "AGR", "Ağrı", 21, "#ffbe0b", "#2b9348"],
	["Burdur Anadolu FK", "BUR", "Burdur", 22, "#264653", "#0077b6"],
	["Ayvalık Kartal FK", "AYV", "Balıkesir", 20, "#0077b6", "#111111"],
	["Ünye Çelik SK", "UNY", "Ordu", 20, "#023e8a", "#ffd60a"],
	["Hopa Şimşek SK", "HOP", "Artvin", 19, "#c1121f", "#2a9d8f"],
	["Kütahya Yıldız SK", "KUT", "Kütahya", 20, "#f26b1d", "#9d0208"],
	["Gemlik Kartal FK", "GEM", "Bursa", 20, "#264653", "#2b9348"],
	["Sultanbeyli Gençlik", "SUL", "İstanbul", 22, "#f26b1d", "#111111"],
	["Yalova Gücü", "YAL", "Yalova", 20, "#2a9d8f", "#7b2cbf"],
	["Karabük Şimşek SK", "KRA", "Karabük", 21, "#c1121f", "#d62828"],
	["Mudanya Birlik SK", "MUD", "Bursa", 19, "#ffd60a", "#264653"],
	["Çarşamba Akıncı SK", "CAR", "Samsun", 19, "#ffd60a", "#d62828"],
	["Of Atak SK", "OFF", "Trabzon", 20, "#111111", "#2b9348"],
	["Adıyaman Çelik SK", "ADI", "Adıyaman", 18, "#e63946", "#f26b1d"],
	["Manavgat Kale SK", "MAN", "Antalya", 17, "#588157", "#e63946"],
	["Yıldırım Doğan SK", "YIL", "Bursa", 17, "#111111", "#ffffff"],
	["Marmaris Çelik SK", "MRM", "Muğla", 16, "#0077b6", "#7b2cbf"],
	["Polatlı İdman Yurdu", "POL", "Ankara", 19, "#3a0ca3", "#ffd60a"],
	["Yozgat Gençlik", "YOZ", "Yozgat", 15, "#c1121f", "#ffbe0b"],
	["Lüleburgaz Kartal FK", "LUL", "Kırklareli", 16, "#9d0208", "#f26b1d"],
	["Ödemiş Kale SK", "ODE", "İzmir", 18, "#2a9d8f", "#f26b1d"],
	["Tire Gençlik", "TIR", "İzmir", 18, "#7b2cbf", "#ffffff"],
	["Kastamonu Anadolu FK", "KAS", "Kastamonu", 15, "#9d0208", "#c1121f"],
	["Serik Şimşek SK", "SER", "Antalya", 15, "#0077b6", "#d62828"],
	["Karaman Kale SK", "KAN", "Karaman", 17, "#2b9348", "#023e8a"],
	["Bartın Gücü", "BAR", "Bartın", 17, "#ffbe0b", "#f26b1d"],
	["Kilis Kale SK", "KIL", "Kilis", 15, "#1d4ed8", "#d62828"],
	["Darıca Akıncı SK", "DAR", "Kocaeli", 14, "#ffd60a", "#3a0ca3"],
]
const BAL_LIG := [
	["Körfez Atak SK", "KOR", "Kocaeli", 15, "#264653", "#111111"],
	["Erdemli Kale SK", "ERD", "Mersin", 14, "#023e8a", "#f26b1d"],
	["Karadeniz Ereğli Şimşek SK", "KAI", "Zonguldak", 15, "#e63946", "#0077b6"],
	["Ceyhan Birlik SK", "CEY", "Adana", 15, "#6a040f", "#023e8a"],
	["Amasya Kartal FK", "AMA", "Amasya", 16, "#264653", "#6a040f"],
	["Torbalı Kale SK", "TOR", "İzmir", 13, "#e63946", "#c1121f"],
	["Kuşadası İdman Yurdu", "KUS", "Aydın", 13, "#f26b1d", "#6a040f"],
	["Kozan Şimşek SK", "KOZ", "Adana", 14, "#e63946", "#ffbe0b"],
	["Biga Yıldız SK", "BIG", "Çanakkale", 12, "#023e8a", "#111111"],
	["Niğde Atak SK", "NIG", "Niğde", 11, "#588157", "#3a0ca3"],
	["Patnos Yıldız SK", "PAT", "Ağrı", 14, "#7b2cbf", "#3a0ca3"],
	["Çankırı İdman Yurdu", "CNK", "Çankırı", 11, "#ffbe0b", "#6a040f"],
	["Çatalca Kartal FK", "CAT", "İstanbul", 13, "#3a0ca3", "#e63946"],
	["Bilecik Şimşek SK", "BIL", "Bilecik", 14, "#1d4ed8", "#0077b6"],
	["Siverek Kale SK", "SVE", "Şanlıurfa", 12, "#3a0ca3", "#ffffff"],
	["Fatsa Kale SK", "FAT", "Ordu", 12, "#0077b6", "#ffffff"],
	["Tokat Çelik SK", "TOK", "Tokat", 11, "#2a9d8f", "#588157"],
	["Edremit Atak SK", "EDR", "Balıkesir", 10, "#264653", "#d62828"],
	["Karasu Atak SK", "KAU", "Sakarya", 11, "#e63946", "#2a9d8f"],
	["Nevşehir İdman Yurdu", "NEV", "Nevşehir", 13, "#7b2cbf", "#1d4ed8"],
	["Şırnak Yıldız SK", "SIR", "Şırnak", 9, "#1d4ed8", "#0077b6"],
	["Kırklareli Anadolu FK", "KII", "Kırklareli", 12, "#f26b1d", "#d62828"],
	["Söke Yıldız SK", "SOK", "Aydın", 9, "#c1121f", "#ffffff"],
	["Pazar Atak SK", "PAZ", "Rize", 11, "#588157", "#0077b6"],
	["Mardin Kartal FK", "MRD", "Mardin", 8, "#1d4ed8", "#7b2cbf"],
	["Kars Anadolu FK", "KRS", "Kars", 10, "#1d4ed8", "#3a0ca3"],
	["Akşehir Anadolu FK", "ASE", "Konya", 10, "#0077b6", "#1d4ed8"],
	["Hendek Kartal FK", "HEN", "Sakarya", 8, "#7b2cbf", "#264653"],
	["Milas Atak SK", "MIL", "Muğla", 9, "#588157", "#111111"],
	["Gümüşhane Anadolu FK", "GUM", "Gümüşhane", 7, "#ffd60a", "#ffbe0b"],
	["Siirt Anadolu FK", "SII", "Siirt", 8, "#023e8a", "#1d4ed8"],
	["Artvin Gençlik", "ART", "Artvin", 10, "#e63946", "#7b2cbf"],
	["Bergama Doğan SK", "BER", "İzmir", 7, "#3a0ca3", "#0077b6"],
	["Tunceli Atak SK", "TUN", "Tunceli", 7, "#2a9d8f", "#3a0ca3"],
	["Kızıltepe Yıldız SK", "KIZ", "Mardin", 9, "#2b9348", "#6a040f"],
	["Kemer Şimşek SK", "KEM", "Antalya", 6, "#ffbe0b", "#7b2cbf"],
	["Muş İdman Yurdu", "MUS", "Muş", 6, "#0077b6", "#6a040f"],
	["Keşan Yıldız SK", "KES", "Edirne", 7, "#0077b6", "#111111"],
	["İnegöl Ovası Gücü", "IEG", "Bursa", 7, "#111111", "#f26b1d"],
	["Sinop Doğan SK", "SNO", "Sinop", 6, "#111111", "#6a040f"],
	["Ardahan Doğan SK", "ARD", "Ardahan", 6, "#023e8a", "#6a040f"],
	["Hakkari Kartal FK", "HAK", "Hakkari", 6, "#7b2cbf", "#1d4ed8"],
	["Ergani İdman Yurdu", "ERG", "Diyarbakır", 5, "#111111", "#ffffff"],
	["Bitlis Anadolu FK", "BIT", "Bitlis", 4, "#e63946", "#2b9348"],
	["Bayburt Doğan SK", "BAY", "Bayburt", 4, "#1d4ed8", "#d62828"],
	["Bingöl Şimşek SK", "BIN", "Bingöl", 5, "#6a040f", "#ffd60a"],
	["Kurtalan Gücü", "KUR", "Siirt", 5, "#264653", "#ffd60a"],
	["Muş Ovası Gençlik", "MSO", "Muş", 4, "#023e8a", "#588157"],
]


## Yabancı ligler (kurgusal, çağrışımlı adlar). [isim, kısa, şehir, prestij, renk1, renk2]
const COUNTRIES := {
	"TR": {"leagues": ["SL", "L1", "L2A", "L2B", "L3A", "L3B", "L3C", "BAL1", "BAL2", "BAL3", "BAL4"], "lang": "TR", "base": 50.0},
	"EN": {"leagues": ["EN1"], "lang": "EN", "base": 52.0},
	"IT": {"leagues": ["IT1"], "lang": "IT", "base": 50.0},
	"BR": {"leagues": ["BR1"], "lang": "PT", "base": 46.0},
}
const EN_LIG := [
	["Manchester Sky FC", "MSK", "Manchester", 93, "#6cabdd", "#1c2c5b"],
	["Liverpool Mersey FC", "LIV", "Liverpool", 92, "#c8102e", "#f6eb61"],
	["Manchester Reds FC", "MRD", "Manchester", 90, "#da291c", "#fbe122"],
	["North London Cannons", "NLC", "London", 90, "#ef0107", "#ffffff"],
	["West London Blues", "WLB", "London", 88, "#034694", "#ffffff"],
	["North London Lilies", "NLL", "London", 84, "#f5f5f5", "#132257"],
	["Tyneside FC", "TYN", "Newcastle", 84, "#241f20", "#ffffff"],
	["Birmingham Villans", "BVL", "Birmingham", 80, "#670e36", "#95bfe5"],
	["East London Irons", "ELI", "London", 76, "#7a263a", "#1bb1e7"],
	["Merseyside Toffees", "MTF", "Liverpool", 74, "#003399", "#ffffff"],
	["Sussex Seagulls", "SUS", "Brighton", 74, "#0057b8", "#ffffff"],
	["Black Country Wolves", "BCW", "Wolverhampton", 72, "#fdb913", "#231f20"],
	["Nottingham Foresters", "NTF", "Nottingham", 72, "#dd0000", "#ffffff"],
	["Thames Palace FC", "TPL", "London", 70, "#1b458f", "#c4122e"],
	["Leeds Yorkshire FC", "LDS", "Leeds", 70, "#ffffff", "#1d428a"],
	["Bournemouth Cherries", "BOU", "Bournemouth", 68, "#da291c", "#000000"],
	["Leicester Foxes", "LEI", "Leicester", 68, "#003090", "#fdbe11"],
	["Brentford Bees", "BRB", "London", 66, "#e30613", "#ffffff"],
]
const IT_LIG := [
	["Milano Biscione", "MBS", "Milano", 90, "#0068a8", "#000000"],
	["Torino Zebre", "TZB", "Torino", 90, "#000000", "#ffffff"],
	["Milano Diavoli", "MDV", "Milano", 88, "#fb090b", "#000000"],
	["Napoli Vesuvio", "NAP", "Napoli", 88, "#12a0d7", "#ffffff"],
	["Roma Lupi", "RML", "Roma", 84, "#8e1f2f", "#f0bc42"],
	["Bergamo Dea", "BGD", "Bergamo", 82, "#1e71b8", "#000000"],
	["Roma Aquile", "RAQ", "Roma", 82, "#87d8f7", "#ffffff"],
	["Firenze Viola", "FIR", "Firenze", 78, "#482e92", "#ffffff"],
	["Bologna Felsina", "BOL", "Bologna", 76, "#1a2f48", "#a21c26"],
	["Torino Granata", "TGR", "Torino", 72, "#8a1e03", "#ffffff"],
	["Como Lago", "COM", "Como", 66, "#004b87", "#ffffff"],
	["Genova Grifone", "GEN", "Genova", 68, "#a3001e", "#001e4d"],
	["Udine Friuli", "UDI", "Udine", 68, "#000000", "#ffffff"],
	["Parma Crociati", "PAR", "Parma", 64, "#ffd200", "#1b4094"],
	["Verona Scaligeri", "VER", "Verona", 64, "#ffe600", "#002f6c"],
	["Cagliari Isola", "CAG", "Cagliari", 64, "#002350", "#ad002a"],
	["Genova Doria", "GSD", "Genova", 66, "#1b5497", "#ffffff"],
	["Lecce Salento", "LEC", "Lecce", 62, "#ffed00", "#d50000"],
]
const BR_LIG := [
	["Rio Rubro-Negro", "RRN", "Rio de Janeiro", 80, "#c3281e", "#000000"],
	["São Paulo Verdão", "SPV", "São Paulo", 80, "#006437", "#ffffff"],
	["São Paulo Timão", "SPT", "São Paulo", 76, "#000000", "#ffffff"],
	["Belo Horizonte Galo", "BHG", "Belo Horizonte", 76, "#000000", "#ffffff"],
	["Rio Tricolor", "RTC", "Rio de Janeiro", 74, "#870a28", "#00613c"],
	["Rio Alvinegro", "RAV", "Rio de Janeiro", 74, "#000000", "#ffffff"],
	["São Paulo Soberano", "SPS", "São Paulo", 74, "#ffffff", "#e30613"],
	["Porto Alegre Imortal", "PAI", "Porto Alegre", 72, "#0d80bf", "#000000"],
	["Porto Alegre Colorado", "PAC", "Porto Alegre", 72, "#e30613", "#ffffff"],
	["Belo Horizonte Raposa", "BHR", "Belo Horizonte", 72, "#2f529e", "#ffffff"],
	["Rio Cruzmaltino", "RCM", "Rio de Janeiro", 70, "#000000", "#ffffff"],
	["Santos Praia FC", "STP", "Santos", 70, "#ffffff", "#000000"],
	["Curitiba Furacão", "CUF", "Curitiba", 68, "#c8102e", "#000000"],
	["Salvador Tricolor de Aço", "SAL", "Salvador", 66, "#0070b8", "#e30613"],
	["Bragança Massa Bruta", "BRG", "Bragança Paulista", 66, "#ffffff", "#e30613"],
	["Fortaleza Leão", "FOR", "Fortaleza", 64, "#0d2c6c", "#e30613"],
	["Recife Leão da Ilha", "REC", "Recife", 60, "#000000", "#e30613"],
	["Goiânia Esmeraldino", "GOI", "Goiânia", 58, "#006a3e", "#ffffff"],
]
## Kulüp uyrukları: ülke -> {uyruk: ağırlık}
const CLUB_NATS := {
	"EN": {"EN": 55, "FR": 7, "PT": 5, "BR": 6, "NL": 5, "NG": 4, "SN": 3, "GH": 3, "AR": 3, "IT": 2, "SE": 3, "PL": 2, "HR": 2},
	"IT": {"IT": 58, "BR": 7, "AR": 7, "FR": 5, "RS": 4, "HR": 4, "NL": 3, "NG": 3, "SN": 3, "PL": 3, "GE": 2, "UY": 3},
	"BR": {"BR": 90, "AR": 5, "UY": 5},
}
## Yabancı şehirler
const CITY_POS_INT := {
	"Manchester": [53.48, -2.24], "Liverpool": [53.41, -2.98], "London": [51.51, -0.13], "Newcastle": [54.97, -1.61],
	"Birmingham": [52.49, -1.89], "Brighton": [50.82, -0.14], "Wolverhampton": [52.59, -2.13], "Nottingham": [52.95, -1.15],
	"Bournemouth": [50.72, -1.88], "Leicester": [52.64, -1.13], "Leeds": [53.80, -1.55],
	"Milano": [45.46, 9.19], "Torino": [45.07, 7.69], "Roma": [41.90, 12.50], "Napoli": [40.85, 14.27], "Bergamo": [45.70, 9.67],
	"Firenze": [43.77, 11.25], "Bologna": [44.49, 11.34], "Genova": [44.41, 8.93], "Udine": [46.06, 13.24], "Verona": [45.44, 10.99],
	"Cagliari": [39.22, 9.12], "Lecce": [40.35, 18.17], "Parma": [44.80, 10.33], "Como": [45.81, 9.09],
	"Rio de Janeiro": [-22.91, -43.17], "São Paulo": [-23.55, -46.63], "Santos": [-23.96, -46.33], "Porto Alegre": [-30.03, -51.23],
	"Belo Horizonte": [-19.92, -43.94], "Salvador": [-12.97, -38.50], "Fortaleza": [-3.73, -38.52], "Curitiba": [-25.43, -49.27],
	"Bragança Paulista": [-22.95, -46.54], "Recife": [-8.05, -34.88], "Goiânia": [-16.68, -49.25],
}

## Şehirlerin kabaca konumu (km cinsinden mesafe hesabı için enlem/boylam).
const CITY_POS := {
	"Adana": [37.00, 35.30],
	"Adıyaman": [37.76, 38.28],
	"Afyonkarahisar": [38.76, 30.54],
	"Ağrı": [39.72, 43.05],
	"Aksaray": [38.37, 34.03],
	"Amasya": [40.65, 35.83],
	"Ankara": [39.90, 32.90],
	"Antalya": [36.90, 30.70],
	"Ardahan": [41.11, 42.70],
	"Artvin": [41.18, 41.82],
	"Aydın": [37.85, 27.85],
	"Balıkesir": [40.30, 27.90],
	"Bartın": [41.63, 32.34],
	"Batman": [37.88, 41.13],
	"Bayburt": [40.26, 40.23],
	"Bilecik": [40.14, 29.98],
	"Bingöl": [38.88, 40.50],
	"Bitlis": [38.40, 42.11],
	"Bolu": [40.70, 31.60],
	"Burdur": [37.72, 30.29],
	"Bursa": [40.20, 29.10],
	"Çanakkale": [40.15, 26.41],
	"Çankırı": [40.60, 33.62],
	"Çorum": [40.50, 34.90],
	"Denizli": [37.80, 29.10],
	"Diyarbakır": [37.90, 40.20],
	"Düzce": [40.84, 31.16],
	"Edirne": [41.68, 26.56],
	"Elazığ": [38.67, 39.22],
	"Erzincan": [39.75, 39.49],
	"Erzurum": [39.90, 41.30],
	"Eskişehir": [39.80, 30.50],
	"Gaziantep": [37.10, 37.40],
	"Giresun": [40.91, 38.39],
	"Gümüşhane": [40.46, 39.48],
	"Hakkari": [37.57, 43.74],
	"Hatay": [36.20, 36.20],
	"Isparta": [37.76, 30.55],
	"Mersin": [36.80, 34.60],
	"İstanbul": [41.00, 29.00],
	"İzmir": [38.40, 27.10],
	"Kars": [40.60, 43.10],
	"Kastamonu": [41.38, 33.78],
	"Kayseri": [38.70, 35.50],
	"Kırklareli": [41.73, 27.22],
	"Kırşehir": [39.15, 34.16],
	"Kocaeli": [40.80, 29.90],
	"Konya": [37.90, 32.50],
	"Kütahya": [39.42, 29.98],
	"Malatya": [38.40, 38.30],
	"Manisa": [38.60, 27.40],
	"Kahramanmaraş": [37.58, 36.93],
	"Mardin": [37.31, 40.74],
	"Muğla": [37.00, 27.40],
	"Muş": [38.74, 41.49],
	"Nevşehir": [38.62, 34.71],
	"Niğde": [37.97, 34.68],
	"Ordu": [40.98, 37.88],
	"Rize": [41.00, 40.50],
	"Sakarya": [40.80, 30.40],
	"Samsun": [41.30, 36.30],
	"Siirt": [37.93, 41.94],
	"Sinop": [42.03, 35.15],
	"Sivas": [39.70, 37.00],
	"Tekirdağ": [40.98, 27.51],
	"Tokat": [40.31, 36.55],
	"Trabzon": [41.00, 39.70],
	"Tunceli": [39.11, 39.55],
	"Şanlıurfa": [37.20, 38.80],
	"Uşak": [38.68, 29.41],
	"Van": [38.50, 43.40],
	"Yozgat": [39.82, 34.81],
	"Zonguldak": [41.45, 31.79],
	"Karaman": [37.18, 33.22],
	"Kırıkkale": [39.85, 33.51],
	"Şırnak": [37.52, 42.46],
	"Iğdır": [39.90, 44.00],
	"Yalova": [40.65, 29.27],
	"Karabük": [41.20, 32.62],
	"Kilis": [36.72, 37.12],
	"Osmaniye": [37.07, 36.25],
}

## Uyruk: [ağırlık süper lig, ağırlık 1. lig, bayrak kısaltması]
const NATIONS := {
	"TR": [60, 85], "BR": [6, 2], "AR": [3, 1], "NG": [4, 2], "SN": [4, 2], "FR": [3, 1],
	"PT": [3, 1], "RS": [3, 1], "BA": [2, 1], "HR": [2, 1], "GH": [3, 2], "CM": [2, 1],
	"MA": [2, 1], "NL": [2, 1], "GE": [2, 1], "PL": [2, 1], "SE": [1, 0], "UY": [2, 1],
}

const FIRST := {
	"TR": ["Emre", "Mert", "Burak", "Kerem", "Yusuf", "Arda", "Can", "Ozan", "Berkay", "Enes", "Furkan", "Halil", "İsmail", "Kaan", "Oğuz", "Serdar", "Taylan", "Umut", "Volkan", "Yiğit", "Barış", "Cengiz", "Doğukan", "Efe", "Görkay", "Hakan", "İrfan", "Koray", "Metehan", "Okan", "Onur", "Sinan", "Tolga", "Uğurcan", "Batuhan", "Eren", "Ferdi", "Gökhan", "Kazım", "Recep", "Salih", "Semih", "Tarık", "Yunus", "Ahmet", "Bora", "Cenk", "Deniz", "Ege", "Alperen", "Bertuğ", "Kenan", "Orkun", "Rıdvan", "Atakan", "Berkan", "Çağan", "Mücahit", "Ensar", "Tayyip"],
	"BR": ["Thiago", "Gabriel", "Matheus", "Lucas", "Rafael", "Vinícius", "Diego", "Rodrigo", "Felipe", "Bruno", "Caio", "Igor", "João", "Leandro", "Marcelo", "Renan", "Wesley", "Everton", "Jádson", "Kaio"],
	"AR": ["Nicolás", "Facundo", "Lautaro", "Tomás", "Agustín", "Franco", "Gonzalo", "Ezequiel", "Matías", "Leandro", "Joaquín", "Santiago", "Cristian", "Federico"],
	"UY": ["Martín", "Diego", "Rodrigo", "Facundo", "Brian", "Maximiliano", "Nahitan", "Agustín", "Mathías", "Ignacio"],
	"NG": ["Chidi", "Emeka", "Obinna", "Tunde", "Kelechi", "Samuel", "Victor", "Ikenna", "Chinedu", "Sunday", "Ademola", "Uche", "Nnamdi", "Femi"],
	"SN": ["Moussa", "Cheikh", "Ibrahima", "Mamadou", "Pape", "Abdou", "Babacar", "Ismaïla", "Lamine", "Ousmane", "Krépin", "Alioune"],
	"GH": ["Kwame", "Kofi", "Yaw", "Kwabena", "Emmanuel", "Daniel", "Joseph", "Mohammed", "Abdul", "Ebenezer", "Kudus", "Osman"],
	"CM": ["Jean", "Vincent", "Clinton", "Karl", "Bryan", "Olivier", "Frank", "Georges", "Nicolas", "Pierre", "Ambroise"],
	"MA": ["Youssef", "Hakim", "Achraf", "Sofiane", "Ayoub", "Ilias", "Nayef", "Amine", "Bilal", "Zakaria", "Anass", "Hamza"],
	"FR": ["Théo", "Lucas", "Hugo", "Maxime", "Antoine", "Kylian", "Yanis", "Bastien", "Clément", "Enzo", "Florian", "Rayan"],
	"PT": ["João", "Rúben", "Diogo", "Tiago", "Gonçalo", "Nuno", "Rafael", "André", "Pedro", "Bernardo", "Vitinha", "Fábio"],
	"RS": ["Nemanja", "Dušan", "Luka", "Stefan", "Aleksandar", "Marko", "Filip", "Uroš", "Nikola", "Strahinja", "Lazar", "Milan"],
	"BA": ["Edin", "Haris", "Amar", "Ermin", "Benjamin", "Anel", "Kenan", "Adnan", "Sead", "Armin", "Elvir"],
	"HR": ["Ivan", "Josip", "Mateo", "Domagoj", "Ante", "Mario", "Luka", "Borna", "Marin", "Lovro", "Petar"],
	"NL": ["Daan", "Sem", "Bram", "Lars", "Jesper", "Thijs", "Ruben", "Stijn", "Wout", "Joey", "Calvin", "Teun"],
	"GE": ["Giorgi", "Levan", "Otar", "Luka", "Saba", "Zuriko", "Budu", "Davit", "Nika", "Lasha"],
	"PL": ["Jakub", "Kacper", "Mateusz", "Piotr", "Bartosz", "Krzysztof", "Szymon", "Kamil", "Przemysław", "Michał"],
	"EN": ["Harry", "Jack", "Oliver", "George", "Charlie", "James", "Jacob", "Thomas", "Mason", "Declan", "Callum", "Reece", "Jordan", "Kyle", "Bukayo", "Jude", "Cole", "Marcus", "Ollie", "Ben", "Aaron", "Conor", "Lewis", "Ryan", "Jarrod", "Tyrone", "Kieran", "Eddie", "Morgan", "Archie"],
	"IT": ["Lorenzo", "Federico", "Alessandro", "Matteo", "Nicolò", "Davide", "Gianluca", "Andrea", "Marco", "Giacomo", "Sandro", "Riccardo", "Francesco", "Leonardo", "Gianluigi", "Domenico", "Mattia", "Simone", "Tommaso", "Pietro", "Manuel", "Raoul", "Samuele", "Edoardo", "Destiny", "Wilfried"],
	"SE": ["Emil", "Viktor", "Oscar", "Jesper", "Linus", "Anton", "Isak", "Hugo", "Albin", "Gustav"],
}
const LAST := {
	"TR": ["Yılmaz", "Kaya", "Demir", "Şahin", "Çelik", "Yıldız", "Aydın", "Öztürk", "Arslan", "Doğan", "Kılıç", "Aslan", "Çetin", "Kara", "Koç", "Kurt", "Özdemir", "Polat", "Erdem", "Güneş", "Bulut", "Tekin", "Acar", "Akın", "Kalkan", "Bozkurt", "Ünal", "Güler", "Tosun", "Duman", "Karaca", "Uysal", "Işık", "Sarı", "Taş", "Altun", "Ekinci", "Bayram", "Coşkun", "Keskin", "Akgül", "Turan", "Yavuz", "Ateş", "Erkan", "Sezer", "Ayhan", "Karadağ", "Okumuş", "Tunç", "Yazıcı", "Gündoğdu", "Özkan", "Kocabaş", "Akbaba", "Dursun", "Ercan", "Bilgin", "Toprak", "Elmas"],
	"BR": ["Silva", "Santos", "Oliveira", "Souza", "Pereira", "Costa", "Rodrigues", "Almeida", "Nascimento", "Lima", "Araújo", "Fernandes", "Carvalho", "Gomes", "Ribeiro", "Barbosa", "Rocha", "Moura", "Teixeira", "Cardoso"],
	"AR": ["González", "Rodríguez", "Fernández", "López", "Martínez", "Sosa", "Romero", "Álvarez", "Benítez", "Acosta", "Medina", "Herrera", "Castro", "Ledesma"],
	"UY": ["Suárez", "Pereira", "Cáceres", "Olivera", "De León", "Viera", "Rodríguez", "Núñez", "Torreira", "Bentancor"],
	"NG": ["Okafor", "Adeyemi", "Nwosu", "Eze", "Okonkwo", "Balogun", "Ogunleye", "Uzoho", "Iwobi", "Ndidi", "Onyeka", "Akpom", "Babatunde", "Chukwueze"],
	"SN": ["Diallo", "Ndiaye", "Sarr", "Diop", "Gueye", "Sow", "Fall", "Cissé", "Mbaye", "Faye", "Seck", "Diouf"],
	"GH": ["Mensah", "Owusu", "Boateng", "Asante", "Addo", "Ofori", "Appiah", "Amartey", "Agyemang", "Darko", "Quaye", "Tetteh"],
	"CM": ["Mbarga", "Ngadeu", "Tchami", "Etoundi", "Nkoulou", "Onana", "Kunde", "Mbeumo", "Ebosse", "Fai", "Toko"],
	"MA": ["El Amrani", "Benali", "Haddadi", "Ziani", "Bouzid", "Chakir", "El Idrissi", "Amrabet", "Tahiri", "Saïss", "Ounahi", "Bennani"],
	"FR": ["Martin", "Bernard", "Dubois", "Moreau", "Laurent", "Girard", "Roux", "Fontaine", "Chevalier", "Mercier", "Lefèvre", "Blanchard"],
	"PT": ["Ferreira", "Gonçalves", "Marques", "Pinto", "Sousa", "Mendes", "Correia", "Lopes", "Moreira", "Neves", "Vieira", "Tavares"],
	"RS": ["Jovanović", "Petrović", "Nikolić", "Marković", "Đorđević", "Stojanović", "Ilić", "Pavlović", "Milošević", "Lukić", "Babić", "Kostić"],
	"BA": ["Hodžić", "Begić", "Mehmedović", "Kovačević", "Hadžić", "Delić", "Salihović", "Muratović", "Husić", "Omerović", "Zukić"],
	"HR": ["Horvat", "Kovač", "Babić", "Marić", "Jurić", "Novak", "Knežević", "Vuković", "Perić", "Pavić", "Matić"],
	"NL": ["de Jong", "Jansen", "de Vries", "van den Berg", "Bakker", "Visser", "Smit", "Meijer", "Mulder", "de Boer", "Bos", "Vos"],
	"GE": ["Beridze", "Kapanadze", "Gelashvili", "Lomidze", "Tsiklauri", "Mamardashvili", "Kvaratashvili", "Chakvetadze", "Lochoshvili", "Mikautadze"],
	"PL": ["Nowak", "Kowalski", "Wiśniewski", "Wójcik", "Kamiński", "Lewandowski", "Zieliński", "Szymański", "Woźniak", "Dąbrowski"],
	"EN": ["Smith", "Jones", "Taylor", "Brown", "Williams", "Wilson", "Johnson", "Davies", "Robinson", "Wright", "Thompson", "Evans", "Walker", "White", "Roberts", "Green", "Hall", "Wood", "Jackson", "Clarke", "Hughes", "Turner", "Harrison", "Cooper", "Ward", "Morris", "Bennett", "Fletcher", "Holloway", "Ashworth"],
	"IT": ["Rossi", "Russo", "Ferrari", "Esposito", "Bianchi", "Romano", "Colombo", "Ricci", "Marino", "Greco", "Bruno", "Gallo", "Conti", "De Luca", "Mancini", "Costa", "Giordano", "Rizzo", "Lombardi", "Moretti", "Fontana", "Caruso", "Ferri", "Galli", "Marchetti", "Villa", "Serra", "Pellegrini", "Testa", "Sartori"],
	"SE": ["Andersson", "Johansson", "Karlsson", "Nilsson", "Eriksson", "Larsson", "Olsson", "Persson", "Svensson", "Gustafsson"],
}

const MANAGER_STYLES := ["attack", "defend", "press", "possession", "counter"]
## Teknik direktör stillerinin önem verdiği özellikler.
const STYLE_ATTRS := {
	"attack": ["finishing", "dribbling", "vision"],
	"defend": ["tackling", "positioning", "strength"],
	"press": ["work_rate", "stamina", "pace"],
	"possession": ["passing", "first_touch", "composure"],
	"counter": ["pace", "decisions", "finishing"],
}

func city_pos(c: String) -> Array:
	if CITY_POS.has(c):
		return CITY_POS[c]
	return CITY_POS_INT.get(c, [39.0, 35.0])

func city_distance(a: String, b: String) -> float:
	## Büyük daire mesafesi (km)
	if a == b:
		return 0.0
	var pa := city_pos(a)
	var pb := city_pos(b)
	var la1 := deg_to_rad(float(pa[0]))
	var la2 := deg_to_rad(float(pb[0]))
	var dla := la2 - la1
	var dlo := deg_to_rad(float(pb[1]) - float(pa[1]))
	var h := sin(dla / 2.0) * sin(dla / 2.0) + cos(la1) * cos(la2) * sin(dlo / 2.0) * sin(dlo / 2.0)
	return 6371.0 * 2.0 * atan2(sqrt(h), sqrt(1.0 - h))

func city_country(c: String) -> String:
	if CITY_POS.has(c):
		return "TR"
	if CITY_POS_INT.has(c):
		var p: Array = CITY_POS_INT[c]
		if float(p[0]) < 0.0:
			return "BR"
		if float(p[1]) < 2.0:
			return "EN"
		return "IT"
	return "TR"
