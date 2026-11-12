import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const dir = path.join(root, 'public');
const modules = ['Malovisky-IT-Tools.ps1','Bloquear_Fabricantes_Firewall_Menu.ps1','Otimizacao_windows.ps1','Malovisky_Autodesk_DeepClean.ps1','Malovisky_Hosts_Manager.ps1'];
const entryFiles = ['entry.txt','menu.ps1'];
for (const name of modules) {
  const file = path.join(dir,'scripts',name);
  if (!fs.existsSync(file)) throw Error('Modulo ausente: ' + name);
  const hash = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').toUpperCase();
  const prefix = "    '" + name + "' = '";
  for (const target of entryFiles) {
    const dest = path.join(dir,target);
    let found = 0;
    const content = fs.readFileSync(dest,'utf8').split(/\r?\n/).map(line => {
      if (!line.startsWith(prefix)) return line;
      found++;
      return prefix + hash + "'";
    }).join('\n');
    if (found !== 1) throw Error('Hash nao encontrado corretamente para ' + name + ' em ' + target);
    fs.writeFileSync(dest,content,'utf8');
  }
  console.log(name + ' SHA256 ' + hash);
}
console.log('Build concluido: public/');
