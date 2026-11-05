import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const templatePath = path.join(root, 'config', 'build-profile.template.json');
const localPath = path.join(root, 'config', 'signing.local.json');
const outputPath = path.join(root, 'build-profile.json5');

const profile = JSON.parse(fs.readFileSync(templatePath, 'utf8'));
profile.app.signingConfigs = [];
for (const product of profile.app.products) {
  delete product.signingConfig;
}

if (fs.existsSync(localPath)) {
  const local = JSON.parse(fs.readFileSync(localPath, 'utf8'));
  const signingConfig = local.signingConfig;
  const material = signingConfig?.material;
  const required = ['certpath', 'keyAlias', 'keyPassword', 'profile', 'signAlg', 'storeFile', 'storePassword'];
  if (!signingConfig?.name || !signingConfig.type || !material ||
    required.some((key) => typeof material[key] !== 'string' || material[key].trim() === '' || material[key].startsWith('REPLACE_'))) {
    throw new Error('config/signing.local.json is incomplete; no signing values were written.');
  }
  profile.app.signingConfigs = [signingConfig];
  const defaultProduct = profile.app.products.find((product) => product.name === 'default');
  if (defaultProduct) {
    defaultProduct.signingConfig = signingConfig.name;
  }
}

fs.writeFileSync(outputPath, JSON.stringify(profile, null, 2) + '\n', { mode: 0o600 });
process.stdout.write('Generated build-profile.json5. Local signing values were not displayed.\n');
