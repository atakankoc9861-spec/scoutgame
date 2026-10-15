"""T.gd'ye anahtar ekle: addkeys.py keys.json  ({"key": ["tr", "en"]})"""
import json, sys, re, os
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "autoload", "T.gd")
s = open(p, encoding="utf-8").read()
keys = json.load(open(sys.argv[1], encoding="utf-8"))
def lit(v): return json.dumps(v, ensure_ascii=False)
tr_anchor = '"title": "GÖZCÜ", "subtitle": "Scout Kariyeri",'
en_anchor = '"title": "GÖZCÜ", "subtitle": "Scout Career",'
new_keys = {k: v for k, v in keys.items() if ('\t' + lit(k) + ':') not in s}
tr = "".join("\n\t%s: %s," % (lit(k), lit(v[0])) for k, v in new_keys.items())
en = "".join("\n\t%s: %s," % (lit(k), lit(v[1])) for k, v in new_keys.items())
assert tr_anchor in s and en_anchor in s
s = s.replace(tr_anchor, tr_anchor + tr, 1).replace(en_anchor, en_anchor + en, 1)
open(p, "w", encoding="utf-8").write(s)
print("added", len(new_keys), "skipped", len(keys) - len(new_keys))
