// Administrative setup only. Reuses `firebase login`; never copies credentials into the app.
const {getGlobalDefaultAccount} = require('firebase-tools/lib/auth');
const {requireAuth} = require('firebase-tools/lib/requireAuth');
const {Client} = require('firebase-tools/lib/apiv2');
const {ensure} = require('firebase-tools/lib/ensureApiEnabled');
const project = 'thermocare-family-f87c1';

async function main() {
  const account = getGlobalDefaultAccount();
  if (!account) throw new Error('Run firebase login first.');
  await requireAuth({project, ...account});
  for (const api of ['firestore.googleapis.com', 'identitytoolkit.googleapis.com']) {
    await ensure(project, api, 'ThermoCare setup');
    console.log(`Enabled ${api}`);
  }
  const auth = new Client({urlPrefix: 'https://identitytoolkit.googleapis.com', apiVersion: 'admin/v2'});
  const result = await auth.patch(`projects/${project}/config`, {signIn: {email: {enabled: true, passwordRequired: true}}}, {
    queryParams: {updateMask: 'signIn.email.enabled,signIn.email.passwordRequired'},
  });
  console.log(JSON.stringify({emailSignIn: result.body.signIn?.email}));
}
main().catch(e => {console.error(e.message); process.exitCode = 1;});
