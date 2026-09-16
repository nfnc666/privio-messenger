import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

describe('contacts and privacy', () => {
  let h: TestHarness;
  let alice: TestUser;
  let bob: TestUser;

  before(async () => {
    h = await createHarness();
    alice = await registerUser(h.app, 'alice');
    bob = await registerUser(h.app, 'bob');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  it('finds a user by exact username only', async () => {
    const exact = await h.app.inject({ method: 'GET', url: '/v1/users/bob', headers: bearer(alice) });
    assert.equal(exact.statusCode, 200);
    assert.equal(exact.json().username, 'bob');

    // There is deliberately no prefix search: it would be a user-enumeration tool.
    const prefix = await h.app.inject({ method: 'GET', url: '/v1/users/bo', headers: bearer(alice) });
    assert.equal(prefix.statusCode, 400);
  });

  it('adds, lists and removes a contact', async () => {
    const added = await h.app.inject({
      method: 'POST',
      url: '/v1/contacts',
      headers: bearer(alice),
      payload: { username: 'bob' },
    });
    assert.equal(added.statusCode, 201);

    const listed = await h.app.inject({ method: 'GET', url: '/v1/contacts', headers: bearer(alice) });
    assert.equal(listed.json().contacts[0].username, 'bob');
    // A nickname is not part of what the server holds. It used to accept one,
    // store it in the clear, and hand it back — for a field no screen ever
    // offered. See migration 013.
    assert.equal('alias' in listed.json().contacts[0], false);

    const removed = await h.app.inject({
      method: 'DELETE',
      url: `/v1/contacts/${bob.accountId}`,
      headers: bearer(alice),
    });
    assert.equal(removed.statusCode, 200);
    const empty = await h.app.inject({ method: 'GET', url: '/v1/contacts', headers: bearer(alice) });
    assert.equal(empty.json().contacts.length, 0);
  });

  it('applies the last-seen privacy setting', async () => {
    const visible = await h.app.inject({ method: 'GET', url: '/v1/users/bob', headers: bearer(alice) });
    assert.equal(visible.json().lastSeenAt, null, 'the default is contacts-only, and they are not contacts');

    await h.app.inject({
      method: 'POST',
      url: '/v1/contacts',
      headers: bearer(bob),
      payload: { username: 'alice' },
    });
    const asContact = await h.app.inject({ method: 'GET', url: '/v1/users/bob', headers: bearer(alice) });
    assert.ok(asContact.json().lastSeenAt, 'a contact of Bob sees his last-seen');

    await h.app.inject({
      method: 'PATCH',
      url: '/v1/accounts/me',
      headers: bearer(bob),
      payload: { privacy: { lastSeen: 'nobody' } },
    });
    const hidden = await h.app.inject({ method: 'GET', url: '/v1/users/bob', headers: bearer(alice) });
    assert.equal(hidden.json().lastSeenAt, null);
  });

  it('applies the same last-seen rule to the contacts list', async () => {
    // Its own pair: the tests above leave Bob's setting and Alice's address
    // book in a state this one would otherwise be reading by accident.
    const carol = await registerUser(h.app, 'carol');
    const dave = await registerUser(h.app, 'dave');

    // Carol adds Dave. One direction: Dave has not added Carol, and the
    // default setting tells only the people Dave added himself.
    await h.app.inject({
      method: 'POST',
      url: '/v1/contacts',
      headers: bearer(carol),
      payload: { username: 'dave' },
    });
    const oneWay = await h.app.inject({
      method: 'GET',
      url: '/v1/contacts',
      headers: bearer(carol),
    });
    assert.equal(
      oneWay.json().contacts[0].lastSeenAt,
      null,
      'being in somebody\'s address book must not entitle you to watch them',
    );

    await h.app.inject({
      method: 'POST',
      url: '/v1/contacts',
      headers: bearer(dave),
      payload: { username: 'carol' },
    });
    const mutual = await h.app.inject({
      method: 'GET',
      url: '/v1/contacts',
      headers: bearer(carol),
    });
    assert.ok(mutual.json().contacts[0].lastSeenAt, 'a contact of Dave sees his last-seen');

    await h.app.inject({
      method: 'PATCH',
      url: '/v1/accounts/me',
      headers: bearer(dave),
      payload: { privacy: { lastSeen: 'nobody' } },
    });
    const hidden = await h.app.inject({
      method: 'GET',
      url: '/v1/contacts',
      headers: bearer(carol),
    });
    assert.equal(hidden.json().contacts[0].lastSeenAt, null);

    await h.app.inject({
      method: 'PATCH',
      url: '/v1/accounts/me',
      headers: bearer(dave),
      payload: { privacy: { lastSeen: 'everyone' } },
    });
    const open = await h.app.inject({
      method: 'GET',
      url: '/v1/contacts',
      headers: bearer(carol),
    });
    assert.ok(open.json().contacts[0].lastSeenAt, 'everyone means everyone');
  });

  it('issues an invite link and QR payload for the account', async () => {
    const invite = await h.app.inject({ method: 'GET', url: '/v1/contacts/invite', headers: bearer(alice) });
    assert.equal(invite.statusCode, 200);
    assert.equal(invite.json().deepLink, 'privio://u/alice');
  });

  it('lists and lifts blocks', async () => {
    await h.app.inject({
      method: 'POST',
      url: '/v1/blocks',
      headers: bearer(alice),
      payload: { accountId: bob.accountId },
    });
    const blocked = await h.app.inject({ method: 'GET', url: '/v1/blocks', headers: bearer(alice) });
    assert.equal(blocked.json().blocked[0].username, 'bob');

    await h.app.inject({ method: 'DELETE', url: `/v1/blocks/${bob.accountId}`, headers: bearer(alice) });
    const cleared = await h.app.inject({ method: 'GET', url: '/v1/blocks', headers: bearer(alice) });
    assert.equal(cleared.json().blocked.length, 0);
  });

  it('tells the viewer their own relationship to the account, and nothing more', async () => {
    // Its own pair, like the test above: the ones before it leave Alice's
    // address book and Bob's settings in a state this would read by accident.
    const viewer = await registerUser(h.app, 'profileviewer');
    const target = await registerUser(h.app, 'profiletarget');

    const stranger = await h.app.inject({
      method: 'GET',
      url: `/v1/users/id/${target.accountId}`,
      headers: bearer(viewer),
    });
    assert.equal(stranger.json().isContact, false);
    assert.equal(stranger.json().isBlocked, false);
    assert.equal(stranger.json().isSelf, false);

    await h.app.inject({
      method: 'POST',
      url: '/v1/contacts',
      headers: bearer(viewer),
      payload: { username: 'profiletarget' },
    });
    await h.app.inject({
      method: 'POST',
      url: '/v1/blocks',
      headers: bearer(viewer),
      payload: { accountId: target.accountId },
    });

    const known = await h.app.inject({
      method: 'GET',
      url: `/v1/users/id/${target.accountId}`,
      headers: bearer(viewer),
    });
    assert.equal(known.json().isContact, true);
    assert.equal(known.json().isBlocked, true);

    // The other direction stays silent. The target has neither added nor
    // blocked anybody, and — the part that matters — being blocked is never
    // disclosed to the blocked.
    const back = await h.app.inject({
      method: 'GET',
      url: `/v1/users/id/${viewer.accountId}`,
      headers: bearer(target),
    });
    assert.equal(back.json().isContact, false);
    assert.equal(back.json().isBlocked, false);

    const mine = await h.app.inject({
      method: 'GET',
      url: `/v1/users/id/${viewer.accountId}`,
      headers: bearer(viewer),
    });
    assert.equal(mine.json().isSelf, true);
  });

  it('never puts a phone number in a profile', async () => {
    // The number exists for contact discovery and is not a thing a profile
    // shows. Asserted on the payload rather than trusted to `publicProfile`
    // staying as it is: this is the shape a profile screen renders.
    const profile = await h.app.inject({
      method: 'GET',
      url: `/v1/users/id/${bob.accountId}`,
      headers: bearer(alice),
    });
    const keys = Object.keys(profile.json());
    assert.ok(!keys.some((key) => /phone/i.test(key)), `phone leaked into ${keys.join(', ')}`);
  });

  it('files one standing report per person and says when there already was one', async () => {
    const reporter = await registerUser(h.app, 'profilereporter');
    const reported = await registerUser(h.app, 'profilereported');

    const filed = await h.app.inject({
      method: 'POST',
      url: `/v1/users/${reported.accountId}/report`,
      headers: bearer(reporter),
      payload: { reason: 'spam' },
    });
    assert.equal(filed.statusCode, 201);
    assert.equal(filed.json().alreadyReported, false);

    // Again: not an error, and not a second report either.
    const again = await h.app.inject({
      method: 'POST',
      url: `/v1/users/${reported.accountId}/report`,
      headers: bearer(reporter),
      payload: { reason: 'abuse' },
    });
    assert.equal(again.statusCode, 200);
    assert.equal(again.json().alreadyReported, true);

    // Reporting does not block: the two are offered side by side on the
    // profile screen and neither may quietly do the other.
    const blocks = await h.app.inject({
      method: 'GET',
      url: '/v1/blocks',
      headers: bearer(reporter),
    });
    assert.equal(blocks.json().blocked.length, 0);
  });

  it('refuses a report of yourself, of nobody, and with a reason it does not know', async () => {
    const lone = await registerUser(h.app, 'profilelone');

    const self = await h.app.inject({
      method: 'POST',
      url: `/v1/users/${lone.accountId}/report`,
      headers: bearer(lone),
      payload: { reason: 'spam' },
    });
    assert.equal(self.statusCode, 400);

    const nobody = await h.app.inject({
      method: 'POST',
      url: '/v1/users/00000000-0000-4000-8000-000000000000/report',
      headers: bearer(lone),
      payload: { reason: 'spam' },
    });
    assert.equal(nobody.statusCode, 404);

    // Free text is exactly what must not reach that column: it is where
    // somebody pastes the message they are reporting.
    const freeText = await h.app.inject({
      method: 'POST',
      url: `/v1/users/${alice.accountId}/report`,
      headers: bearer(lone),
      payload: { reason: 'they said something about my sister' },
    });
    assert.equal(freeText.statusCode, 400);
  });

  it('resolves an account id to a profile, so an incoming message has a name', async () => {
    const byId = await h.app.inject({
      method: 'GET',
      url: `/v1/users/id/${bob.accountId}`,
      headers: bearer(alice),
    });
    assert.equal(byId.statusCode, 200);
    assert.equal(byId.json().username, 'bob');

    const unknown = await h.app.inject({
      method: 'GET',
      url: '/v1/users/id/00000000-0000-4000-8000-000000000000',
      headers: bearer(alice),
    });
    assert.equal(unknown.statusCode, 404);
  });
});
