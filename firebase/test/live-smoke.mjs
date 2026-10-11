// Optional live check. Creates and removes two temporary accounts and their synthetic data.
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
import {initializeApp, deleteApp} from 'firebase/app';
import {getAuth, createUserWithEmailAndPassword, signOut, signInWithEmailAndPassword, deleteUser} from 'firebase/auth';
import {getFirestore, doc, setDoc, updateDoc, getDoc, getDocFromServer, getDocs, collection, deleteDoc, terminate, onSnapshot} from 'firebase/firestore';

const config = JSON.parse(await readFile(new URL('../../firebase-config.json', import.meta.url), 'utf8'));
const android = process.argv.includes('--android');
const options = {apiKey: android ? config.FIREBASE_ANDROID_API_KEY : config.FIREBASE_API_KEY, appId: android ? config.FIREBASE_ANDROID_APP_ID : config.FIREBASE_APP_ID, projectId: config.FIREBASE_PROJECT_ID, authDomain: config.FIREBASE_AUTH_DOMAIN};
console.log(`Checking live Firebase with the ${android ? 'Android' : 'web'} client configuration.`);
const sessions = [];
function waitForRemote(ref, predicate) {
  return new Promise((resolve, reject) => {
    let unsubscribe;
    const timer = setTimeout(() => { unsubscribe?.(); reject(new Error('Remote sync timed out')); }, 12000);
    unsubscribe = onSnapshot(ref, {includeMetadataChanges: true}, snapshot => {
      if (!snapshot.metadata.isFromCache && predicate(snapshot)) {
        clearTimeout(timer); unsubscribe?.(); resolve(snapshot);
      }
    }, error => { clearTimeout(timer); unsubscribe?.(); reject(error); });
  });
}
try {
  for (const name of ['a', 'b']) {
    const app = initializeApp(options, `setup-${name}-${randomUUID()}`);
    const auth = getAuth(app), db = getFirestore(app);
    const email = `thermocare-setup-${randomUUID()}@example.com`, password = randomUUID() + 'aA9!';
    const session = {app, auth, db, email, password, refs: []};
    sessions.push(session);
    await createUserWithEmailAndPassword(auth, email, password);
  }
  const [a, b] = sessions;
  const uid = a.auth.currentUser.uid;
  const member = doc(a.db, `families/${uid}/members/setup-check`);
  const rawId = 'setup-check/1/1';
  const recordId = Buffer.from(rawId).toString('base64url');
  const reading = doc(a.db, `families/${uid}/readings/${recordId}`);
  a.refs.push(reading, member);
  await setDoc(member, {id: 'setup-check', name: 'Setup check (temporary)', avatar: 10, archived: false});
  assert.equal((await getDoc(member)).data().avatar, 10);
  await setDoc(reading, {id: rawId, celsius: 36.5, ambient: 25, at: new Date().toISOString(), deviceId: 'setup-check', estimatedTime: true, memberId: 'setup-check', memberName: 'Setup check (temporary)'});
  assert.equal((await getDoc(reading)).data().memberId, 'setup-check');
  await updateDoc(reading, {note: 'After resting (temporary test)'});
  assert.equal((await getDoc(reading)).data().note, 'After resting (temporary test)');
  await updateDoc(reading, {note: 'Updated note (temporary test)'});
  await assert.rejects(updateDoc(reading, {celsius: 37, note: 'Illegal sample edit'}), error => error.code === 'permission-denied');
  await signOut(a.auth);
  await signInWithEmailAndPassword(a.auth, a.email, a.password);
  assert.equal((await getDocs(collection(a.db, `families/${uid}/readings`))).size, 1);
  assert.equal((await getDoc(reading)).data().note, 'Updated note (temporary test)');
  await assert.rejects(getDoc(doc(b.db, `families/${uid}/members/setup-check`)), error => error.code === 'permission-denied');
  const mirrorApp = initializeApp(options, `mirror-${randomUUID()}`);
  const mirrorAuth = getAuth(mirrorApp), mirrorDb = getFirestore(mirrorApp);
  sessions.push({app: mirrorApp, auth: mirrorAuth, db: mirrorDb, refs: [], skipUserDelete: true});
  await signInWithEmailAndPassword(mirrorAuth, a.email, a.password);
  const reminderPath = `families/${uid}/reminders/setup-reminder`;
  const reminder = doc(a.db, reminderPath), remoteReminder = doc(mirrorDb, reminderPath);
  a.refs.unshift(reminder);
  const remoteCreate = waitForRemote(remoteReminder, snapshot => snapshot.exists() && snapshot.data().hour === 19);
  await setDoc(reminder, {id: 'setup-reminder', memberId: 'setup-check', hour: 19, minute: 15, weekdays: [1, 3, 5], enabled: true});
  await remoteCreate;
  const remoteEdit = waitForRemote(doc(a.db, reminderPath), snapshot => snapshot.exists() && snapshot.data().hour === 20);
  await updateDoc(remoteReminder, {hour: 20, enabled: false});
  await remoteEdit;
  await assert.rejects(getDocFromServer(doc(b.db, reminderPath)), error => error.code === 'permission-denied');
  const preparedReading = doc(a.db, `families/${uid}/readings/setup-prepared`);
  a.refs.unshift(preparedReading);
  const quality = {sampleCount: 3, surfaceRange: .2, ambientRange: .1, windowSeconds: 4, prepared: true, method: 'stable-v1'};
  await setDoc(preparedReading, {...(await getDoc(reading)).data(), id: 'setup-prepared', quality});
  assert.equal((await getDocFromServer(doc(mirrorDb, preparedReading.path))).data().quality.prepared, true);
  await updateDoc(preparedReading, {note: 'Synced trend context'});
  await assert.rejects(updateDoc(preparedReading, {'quality.surfaceRange': .1}), error => error.code === 'permission-denied');
  const remoteDelete = waitForRemote(remoteReminder, snapshot => !snapshot.exists());
  await deleteDoc(reminder);
  await remoteDelete;
  console.log('PASS: live accounts, immutable readings and preparation, notes, two-session reminder create/edit/delete sync, and account isolation.');
} finally {
  for (const session of sessions) {
    for (const ref of session.refs) await deleteDoc(ref);
    if (session.auth.currentUser && !session.skipUserDelete) await deleteUser(session.auth.currentUser);
    await terminate(session.db);
    await deleteApp(session.app);
  }
  console.log('Temporary setup accounts and data removed.');
}
