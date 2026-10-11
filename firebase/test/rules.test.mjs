import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, getDocs, collection } from 'firebase/firestore';

let env;
const member = {id: 'mom', name: 'Mom', avatar: 0, archived: false};
const reading = {id: 'uno/1/1', celsius: 36.5, ambient: 25, at: '2026-10-09T12:00:00.000Z', deviceId: 'uno', estimatedTime: false, memberId: 'mom', memberName: 'Mom'};
const path = 'families/family-a';
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-thermocare', firestore: {host: '127.0.0.1', port: 8085, rules: await readFile(new URL('../firestore.rules', import.meta.url), 'utf8')}});
});
beforeEach(async () => { await env.clearFirestore(); });
after(async () => { await env.cleanup(); });
const owner = () => env.authenticatedContext('family-a').firestore();
test('family can create profiles, save readings, list them and delete readings', async () => {
  const db = owner();
  await assertSucceeds(setDoc(doc(db, `${path}/members/mom`), member));
  await assertSucceeds(setDoc(doc(db, `${path}/readings/sample`), reading));
  await assertSucceeds(getDocs(collection(db, `${path}/readings`)));
  await assertSucceeds(setDoc(doc(db, `${path}/readings/sample`), reading));
  await assertSucceeds(deleteDoc(doc(db, `${path}/readings/sample`)));
});
test('another family and anonymous clients cannot access the family', async () => {
  await assertSucceeds(setDoc(doc(owner(), `${path}/members/mom`), member));
  for (const db of [env.authenticatedContext('family-b').firestore(), env.unauthenticatedContext().firestore()]) {
    await assertFails(getDoc(doc(db, `${path}/members/mom`)));
    await assertFails(getDocs(collection(db, `${path}/readings`)));
    await assertFails(setDoc(doc(db, `${path}/members/mom`), member));
    await assertFails(deleteDoc(doc(db, `${path}/members/mom`)));
  }
});
test('profile validation rejects invalid names, avatars, extra fields and IDs', async () => {
  for (const invalid of [{...member, name: ''}, {...member, name: 'x'.repeat(41)}, {...member, avatar: 14}, {...member, avatar: -1}, {...member, avatar: 1.2}, {...member, id: 'dad'}, {...member, admin: true}]) {
    await assertFails(setDoc(doc(owner(), `${path}/members/mom`), invalid));
  }
});
test('all existing symbols and new people avatars can save to a family profile', async () => {
  for (let avatar = 0; avatar <= 13; avatar++) {
    await assertSucceeds(setDoc(doc(owner(), `${path}/members/mom`), {...member, avatar}));
  }
});
test('readings require a real member in the same family and valid measurements', async () => {
  const db = owner();
  await assertFails(setDoc(doc(db, `${path}/readings/sample`), reading));
  await assertSucceeds(setDoc(doc(db, `${path}/members/mom`), member));
  for (const invalid of [{...reading, memberId: null}, {...reading, memberId: 'unknown'}, {...reading, celsius: NaN}, {...reading, celsius: 999}, {...reading, ambient: -99}, {...reading, demo: true}, {...reading, at: 'yesterday'}, {...reading, estimatedTime: 'yes'}]) {
    await assertFails(setDoc(doc(db, `${path}/readings/sample`), invalid));
  }
});
test('a saved sample cannot change person, temperature or time', async () => {
  const db = owner();
  await setDoc(doc(db, `${path}/members/mom`), member);
  await setDoc(doc(db, `${path}/members/dad`), {...member, id: 'dad', name: 'Dad'});
  await setDoc(doc(db, `${path}/readings/sample`), reading);
  for (const invalid of [{...reading, memberId: 'dad', memberName: 'Dad'}, {...reading, celsius: 37}, {...reading, at: '2026-10-10T12:00:00.000Z'}]) {
    await assertFails(setDoc(doc(db, `${path}/readings/sample`), invalid));
  }
  await assertSucceeds(setDoc(doc(db, `${path}/members/mom`), {...member, archived: true}));
  await assertSucceeds(getDoc(doc(db, `${path}/readings/sample`)));
});
test('all other collections are denied', async () => {
  await assertFails(setDoc(doc(owner(), `${path}/settings/admin`), {admin: true}));
  await assertFails(setDoc(doc(owner(), 'users/family-a'), {name: 'Test'}));
});

test('notes can be added, edited and removed without changing the sample', async () => {
  const db = owner();
  await setDoc(doc(db, `${path}/members/mom`), member);
  const ref = doc(db, `${path}/readings/sample`);
  await assertSucceeds(setDoc(ref, {...reading, note: 'After resting'}));
  await assertSucceeds(setDoc(ref, {...reading, note: 'Feeling comfortable'}));
  await assertFails(setDoc(ref, {...reading, note: 'x'.repeat(501)}));
  await assertFails(setDoc(ref, {...reading, note: 42}));
  await assertFails(setDoc(ref, {...reading, note: 'Changed', celsius: 37}));
  await assertSucceeds(setDoc(ref, reading));
  await assertFails(setDoc(doc(db, `${path}/readings/bad-note`), {...reading, note: 'x'.repeat(501)}));
});

const quality = {sampleCount: 3, surfaceRange: .2, ambientRange: .4, windowSeconds: 4, prepared: true, method: 'stable-v1'};
const reminder = {id: 'evening', memberId: 'mom', hour: 19, minute: 30, weekdays: [1, 3, 5], enabled: true};
test('capture context is validated and stays immutable while notes can change', async () => {
  const db = owner();
  await setDoc(doc(db, `${path}/members/mom`), member);
  const ref = doc(db, `${path}/readings/prepared`);
  await assertSucceeds(setDoc(ref, {...reading, quality}));
  await assertSucceeds(setDoc(ref, {...reading, quality, note: 'Same site, after rest'}));
  await assertFails(setDoc(ref, {...reading, quality: {...quality, surfaceRange: .1}}));
  await assertFails(setDoc(ref, reading));
  for (const invalid of [{...quality, prepared: false}, {...quality, sampleCount: 1}, {...quality, surfaceRange: .5}, {...quality, ambientRange: 2}, {...quality, windowSeconds: 1}, {...quality, method: 'diagnosis'}, {...quality, extra: true}, {}]) {
    await assertFails(setDoc(doc(db, `${path}/readings/invalid`), {...reading, quality: invalid}));
  }
});
test('family reminders can sync, edit, pause and delete with account isolation', async () => {
  const db = owner();
  await setDoc(doc(db, `${path}/members/mom`), member);
  const ref = doc(db, `${path}/reminders/evening`);
  await assertSucceeds(setDoc(ref, reminder));
  await assertSucceeds(getDocs(collection(db, `${path}/reminders`)));
  await assertSucceeds(setDoc(ref, {...reminder, hour: 20, enabled: false}));
  for (const other of [env.authenticatedContext('family-b').firestore(), env.unauthenticatedContext().firestore()]) {
    await assertFails(getDoc(doc(other, `${path}/reminders/evening`)));
    await assertFails(getDocs(collection(other, `${path}/reminders`)));
    await assertFails(setDoc(doc(other, `${path}/reminders/evening`), reminder));
    await assertFails(deleteDoc(doc(other, `${path}/reminders/evening`)));
  }
  await assertSucceeds(deleteDoc(ref));
});
test('reminders reject invalid times, days, member links and unexpected fields', async () => {
  const db = owner();
  await setDoc(doc(db, `${path}/members/mom`), member);
  for (const invalid of [{...reminder, hour: 24}, {...reminder, minute: -1}, {...reminder, hour: 1.5}, {...reminder, weekdays: []}, {...reminder, weekdays: [0]}, {...reminder, weekdays: [8]}, {...reminder, weekdays: [1, 1]}, {...reminder, weekdays: ['1']}, {...reminder, memberId: 'unknown'}, {...reminder, enabled: 'yes'}, {...reminder, id: 'other'}, {...reminder, admin: true}]) {
    await assertFails(setDoc(doc(db, `${path}/reminders/evening`), invalid));
  }
});
