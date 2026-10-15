from pathlib import Path
import base64,json
root=Path(__file__).resolve().parents[1]
data=json.loads((root/'ui/ramps.json').read_text())
# Include outside-Beltway endpoints as selectable destinations; their express prices stay unavailable.
for id,label,x,y in [('50','Route 50 · Fairfax',712,311),('monument','Monument Drive',653,328),('stringfellow','Stringfellow Road',608,340),('28','Route 28 · Centreville',510,376),('29g','Route 29 · Gainesville',239,500)]:
 for prefix,kind in [('66w:','express'),('66g:','regular lanes')]:
  if prefix=='66g:' and id in ('monument','stringfellow'):continue
  data.append({'id':prefix+id,'label':label+' ('+kind+')','group':'66w','road':'66','ramp':'exit'})
# Cross-highway IDs refer to the same physical inside-Beltway exit dots.
for point in list(data):
 if point.get('road')=='66' and point.get('ramp')=='exit' and str(point.get('id','')).isdigit() and str(point.get('group',''))=='66e':
  data.append({**point,'id':'66e:'+str(point['id'])})
app=((root/'ui/browser66.js').read_text()+'\n'+(root/'ui/app.js').read_text()).replace('/*DATA*/[]',json.dumps(data)).replace('/*OUTSIDE66*/{}',(root/'ui/outside66.json').read_text())
html=(root/'ui/index.html').read_text().replace('/*APP*/',app)
assets={}
for file,type in [('map.png','image/png'),('body.ttf','font/ttf'),('display.ttf','font/ttf')]:
 assets['/assets/'+file]={'type':type,'data':base64.b64encode((root/'assets'/file).read_bytes()).decode()}
output='const HTML='+json.dumps(html)+';\nconst ASSETS='+json.dumps(assets)+';\n'+(root/'server/pricing.js').read_text()
(root/'worker/index.js').write_text(output)
(root/'.openai/preview.html').write_text(html)
print('Assembled UI, image, fonts and pricing worker')
