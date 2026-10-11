// Run locally once with Node.js. The private key is never printed.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const directory = path.resolve(__dirname, '../.tools/apple-signing');
const destination = path.join(directory, 'distribution-private-key.pem');
fs.mkdirSync(directory, { recursive: true });
if (fs.existsSync(destination)) {
  console.log('Existing iOS signing key retained. Use the same key for subsequent builds.');
  process.exit(0);
}
const { privateKey } = crypto.generateKeyPairSync('rsa', {
  modulusLength: 4096,
  publicKeyEncoding: { type: 'spki', format: 'pem' },
  privateKeyEncoding: { type: 'pkcs1', format: 'pem' },
});
fs.writeFileSync(destination, privateKey, { flag: 'wx', mode: 0o600 });
console.log('Created .tools/apple-signing/distribution-private-key.pem.');
console.log('Back it up securely and copy its contents into the IOS_CERTIFICATE_PRIVATE_KEY GitHub secret. Never commit or send the key in chat.');
