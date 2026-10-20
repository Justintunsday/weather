import os
root = r'C:\weather\repo'
out = []
for rel in ['src/WSOpenMeteoProvider.m','src/WSQWeatherProvider.m','src/WSShared.h','src/WSWeatherResponsePatcher.mm','src/WSSettings.m']:
    p = os.path.join(root, rel)
    txt = open(p,'r',encoding='utf-8',errors='replace').read()
    out.append('==== '+rel)
    for i,line in enumerate(txt.splitlines(),1):
        if any(ord(c)>127 for c in line):
            out.append(f'{i}: {ascii(line)}')
open(r'C:\weather\repo\_nonascii.txt','w',encoding='utf-8').write('\n'.join(out))
print('written')
