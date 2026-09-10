"""Report XY drift; no post-hoc application acceptance threshold."""
import argparse,json,math
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('reference');p.add_argument('actual')
a=p.parse_args()
r=json.loads(Path(a.reference).read_text());c=json.loads(Path(a.actual).read_text())
assert r['image_size_wh']==c['image_size_wh'], 'Image dimensions differ'
print('Reference hands:',len(r['hands']),'C++ hands:',len(c['hands']))
assert len(r['hands'])==len(c['hands']), 'Hand count differs'
# Same-image regression only. Anchor ID association is not a general tracker.
ref={h['anchor_index']:h for h in r['hands']}
assert set(ref)=={h['anchor_index'] for h in c['hands']}, 'Selected anchors differ'
for h in c['hands']:
 b=ref[h['anchor_index']]
 assert len(h['landmarks_xy'])==len(b['landmarks_xy'])==21
 distances=[math.dist(x,y) for x,y in zip(h['landmarks_xy'],b['landmarks_xy'])]
 assert all(math.isfinite(x) for x in distances)
 print('Anchor:',h['anchor_index'])
 print('Hand confidence reference / C++:',b['hand_confidence'],h['hand_confidence'])
 print('Handedness raw reference / C++:',b['handedness_raw'],h['handedness_raw'])
 print('Original XY max distance (px):',max(distances))
 print('Original XY mean distance (px):',sum(distances)/21)
 print('Worst landmark:',max(range(21),key=distances.__getitem__))
print('Comparison complete; coordinate drift is reported, not an accuracy PASS.')
