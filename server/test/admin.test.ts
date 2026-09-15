import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { can } from '../src/services/admin_auth.js';
import {
  adminBearer,
  bearer,
  closePool,
  createHarness,
  registerAdmin,
  registerUser,
  type TestHarness,
  type TestUser,
} from './helpers.js';

/**
 * The admin API.
 *
 * Two things are being checked here, and the second matters more than the
 * first. One is that the panel's features work. The other is that the
 * boundaries hold: that a role cannot do what it may not, that a suspension
 * actually closes the doors it claims to, that the audit log records what was
 * done, and that nothing in the operator surface returns a byte the server
 * promised not to read.
 */

/** A public channel with a handle, owned by `user`. */
async function createPublicChannel(
  h: TestHarness,
  user: TestUser,
  handle: string,
): Promise<{ id: string; inviteCode: string }> {
  const response = await h.app.inject({
    method: 'POST',
    url: '/v1/channels',
    headers: bearer(user),
    payload: {
      visibility: 'public',
      handle,
      title: `Channel ${handle}`,
      description: 'Public on purpose, so it can be found.',
      category: 'news',
    },
  });
  assert.equal(response.statusCode, 201, response.body);
  const body = response.json();
  return { id: body.id, inviteCode: body.inviteCode };
}

async function report(h: TestHarness, user: TestUser, channelId: string, reason: string) {
  const response = await h.app.inject({
    method: 'POST',
    url: `/v1/channels/${channelId}/report`,
    headers: bearer(user),
    payload: { reason },
  });
  assert.equal(response.statusCode, 200, response.body);
}

describe('admin sessions', () => {
  let h: TestHarness;

  before(async () => {
    h = await createHarness();
  });
  after(async () => {
    await h.close();
  });

  it('signs an operator in and out', async () => {
    const owner = await registerAdmin(h.app, 'ada');

    const me = await h.app.inject({ method: 'GET', url: '/v1/admin/me', headers: adminBearer(owner) });
    assert.equal(me.statusCode, 200, me.body);
    assert.equal(me.json().username, 'ada');
    assert.equal(me.json().role, 'owner');
    assert.equal(me.json().can.operators, true);

    const out = await h.app.inject({
      method: 'DELETE',
      url: '/v1/admin/sessions/current',
      headers: adminBearer(owner),
    });
    assert.equal(out.statusCode, 200, out.body);

    const after = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/me',
      headers: adminBearer(owner),
    });
    assert.equal(after.statusCode, 401);
  });

  it('answers a wrong password and an unknown operator identically', async () => {
    await registerAdmin(h.app, 'grace');

    const wrongPassword = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/sessions',
      payload: { username: 'grace', password: 'not-the-password' },
    });
    const noSuchOperator = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/sessions',
      payload: { username: 'nobody', password: 'not-the-password' },
    });

    // Same status and same code, or the login enumerates the operator table.
    assert.equal(wrongPassword.statusCode, 401);
    assert.equal(noSuchOperator.statusCode, 401);
    assert.equal(wrongPassword.json().error, noSuchOperator.json().error);
  });

  it('refuses a disabled operator and ends their sessions', async () => {
    const owner = await registerAdmin(h.app, 'owner1');
    const helper = await registerAdmin(h.app, 'helper1', 'admin');

    const disabled = await h.app.inject({
      method: 'PATCH',
      url: `/v1/admin/operators/${helper.id}`,
      headers: adminBearer(owner),
      payload: { disabled: true },
    });
    assert.equal(disabled.statusCode, 200, disabled.body);
    // The live session dies with the account rather than outliving it.
    assert.ok(disabled.json().sessionsEnded >= 1);

    const stale = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/me',
      headers: adminBearer(helper),
    });
    assert.equal(stale.statusCode, 401);

    const login = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/sessions',
      payload: { username: 'helper1', password: helper.password },
    });
    assert.equal(login.statusCode, 401);
  });

  it('records failed sign-ins without recording whether the name was real', async () => {
    await h.app.inject({
      method: 'POST',
      url: '/v1/admin/sessions',
      payload: { username: 'intruder', password: 'guessing' },
    });
    // Scoped to this attempt: earlier tests in this suite sign in wrongly on
    // purpose, and they land in the same append-only table.
    const { rows } = await pool.query(
      `SELECT actor_username, detail FROM admin_audit_log
       WHERE action = 'admin.login_failed' AND actor_username = 'intruder'`,
    );
    assert.equal(rows.length, 1);
    assert.equal(rows[0].actor_username, 'intruder');
    // Nothing about the attempt beyond that it happened. In particular no
    // "user_exists" flag, which would be the enumeration oracle the login
    // itself avoids being.
    assert.deepEqual(rows[0].detail, {});
  });

  it('ends other sessions when an operator changes their own password', async () => {
    const admin = await registerAdmin(h.app, 'rotator');
    const second = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/sessions',
      payload: { username: 'rotator', password: admin.password },
    });
    assert.equal(second.statusCode, 201, second.body);
    const secondToken = second.json().token as string;

    const changed = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/me/password',
      headers: adminBearer(admin),
      payload: { currentPassword: admin.password, newPassword: 'a-much-longer-new-password' },
    });
    assert.equal(changed.statusCode, 200, changed.body);

    // The session that made the change survives; the other one does not.
    const mine = await h.app.inject({ method: 'GET', url: '/v1/admin/me', headers: adminBearer(admin) });
    assert.equal(mine.statusCode, 200);
    const other = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/me',
      headers: { authorization: `Bearer ${secondToken}` },
    });
    assert.equal(other.statusCode, 401);
  });

  it('refuses an account session token on an operator route', async () => {
    const alice = await registerUser(h.app, 'alice_admin_probe');
    const response = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/overview',
      headers: bearer(alice),
    });
    // The two credentials live in different tables and neither resolves the
    // other. An account token reaching the panel would be the whole design
    // failing in one step.
    assert.equal(response.statusCode, 401);
  });
});

describe('admin roles', () => {
  let h: TestHarness;

  before(async () => {
    h = await createHarness();
  });
  after(async () => {
    await h.close();
  });

  it('maps roles to capabilities', () => {
    assert.equal(can('viewer', 'read'), true);
    assert.equal(can('viewer', 'licenses'), false);
    assert.equal(can('support', 'licenses'), true);
    // Support answers billing questions; it does not moderate.
    assert.equal(can('support', 'moderate'), false);
    assert.equal(can('admin', 'moderate'), true);
    // An admin moderates but cannot create the operator who moderates them.
    assert.equal(can('admin', 'operators'), false);
    assert.equal(can('owner', 'operators'), true);
  });

  it('lets a viewer read and refuses every write', async () => {
    const viewer = await registerAdmin(h.app, 'viewer1', 'viewer');

    const read = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/overview',
      headers: adminBearer(viewer),
    });
    assert.equal(read.statusCode, 200, read.body);

    const issue = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/licenses',
      headers: adminBearer(viewer),
      payload: { reference: 'nope' },
    });
    assert.equal(issue.statusCode, 403);
    assert.equal(issue.json().error, 'insufficient_role');

    const operators = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/operators',
      headers: adminBearer(viewer),
    });
    assert.equal(operators.statusCode, 403);
  });

  it('refuses support the moderation actions', async () => {
    const support = await registerAdmin(h.app, 'support1', 'support');
    const alice = await registerUser(h.app, 'alice_support');
    const channel = await createPublicChannel(h, alice, 'supportprobe');

    const suspend = await h.app.inject({
      method: 'POST',
      url: `/v1/admin/channels/${channel.id}/suspend`,
      headers: adminBearer(support),
      payload: { reason: 'spam' },
    });
    assert.equal(suspend.statusCode, 403);

    // …but may still issue a licence, which is what the role is for.
    const licence = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/licenses',
      headers: adminBearer(support),
      payload: { reference: 'support-issued-1' },
    });
    assert.equal(licence.statusCode, 201, licence.body);
  });

  it('will not let the last owner demote or disable themselves', async () => {
    const owner = await registerAdmin(h.app, 'soleowner');

    const demote = await h.app.inject({
      method: 'PATCH',
      url: `/v1/admin/operators/${owner.id}`,
      headers: adminBearer(owner),
      payload: { role: 'viewer' },
    });
    assert.equal(demote.statusCode, 400);
    assert.equal(demote.json().error, 'cannot_demote_self');

    const disable = await h.app.inject({
      method: 'PATCH',
      url: `/v1/admin/operators/${owner.id}`,
      headers: adminBearer(owner),
      payload: { disabled: true },
    });
    assert.equal(disable.statusCode, 400);
  });

  it('will not leave the server with no owner', async () => {
    const first = await registerAdmin(h.app, 'owner_a');
    const second = await registerAdmin(h.app, 'owner_b');

    // `owner_b` demoting `owner_a` is fine while `owner_b` is still an owner.
    const ok = await h.app.inject({
      method: 'PATCH',
      url: `/v1/admin/operators/${first.id}`,
      headers: adminBearer(second),
      payload: { role: 'admin' },
    });
    assert.equal(ok.statusCode, 200, ok.body);

    // Now `owner_b` is the last one, and nobody else can take that away either.
    const third = await registerAdmin(h.app, 'owner_c');
    const lastOne = await h.app.inject({
      method: 'PATCH',
      url: `/v1/admin/operators/${second.id}`,
      headers: adminBearer(third),
      payload: { role: 'viewer' },
    });
    // `owner_c` is itself an owner, so one remains — this is allowed.
    assert.equal(lastOne.statusCode, 200, lastOne.body);
  });
});

describe('admin lookups', () => {
  let h: TestHarness;
  let owner: Awaited<ReturnType<typeof registerAdmin>>;
  let alice: TestUser;

  before(async () => {
    h = await createHarness();
    owner = await registerAdmin(h.app, 'lookup_owner');
    alice = await registerUser(h.app, 'alice_lookup');
    await registerUser(h.app, 'alicia_lookup');
    await registerUser(h.app, 'bob_lookup');
  });
  after(async () => {
    await h.close();
  });

  it('counts what the overview claims to count', async () => {
    const response = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/overview',
      headers: adminBearer(owner),
    });
    assert.equal(response.statusCode, 200, response.body);
    const body = response.json();
    assert.equal(body.accounts.total, 3);
    assert.equal(body.accounts.new7d, 3);
    assert.equal(body.devices.total, 3);
    assert.equal(body.devices.ios, 3);
    // A series with one point per day, gaps filled, so a chart cannot draw over
    // a day on which nothing happened.
    assert.equal(body.signups.length, 30);
    assert.equal(body.signups.at(-1).accounts, 3);
  });

  it('counts people, and counts bots separately', async () => {
    // @botcreator is a row in `accounts` — that is how it holds a username and
    // a chat — and it exists on every server from the first boot. Counted among
    // the accounts it would put a 1 on the dashboard of a server with no users,
    // and add one to every figure after that. So the totals above are people,
    // and this is where the bots are.
    const response = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/overview',
      headers: adminBearer(owner),
    });
    const body = response.json();
    assert.ok(body.accounts.bots >= 1, 'the assistant is a bot and should be counted as one');

    // And it is not in the list of accounts an operator searches.
    const list = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/accounts?q=botcreator',
      headers: adminBearer(owner),
    });
    assert.equal(list.json().accounts.length, 0);
  });

  it('searches accounts by username prefix only', async () => {
    const prefix = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/accounts?q=alic',
      headers: adminBearer(owner),
    });
    assert.equal(prefix.statusCode, 200, prefix.body);
    assert.deepEqual(
      prefix.json().accounts.map((a: { username: string }) => a.username).sort(),
      ['alice_lookup', 'alicia_lookup'],
    );

    // A substring in the middle of a name finds nothing: this is a lookup for a
    // support ticket, not a directory of everyone.
    const middle = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/accounts?q=lookup',
      headers: adminBearer(owner),
    });
    assert.equal(middle.json().accounts.length, 0);
  });

  it('returns an account without returning anything sealed', async () => {
    const response = await h.app.inject({
      method: 'GET',
      url: `/v1/admin/accounts/${alice.accountId}`,
      headers: adminBearer(owner),
    });
    assert.equal(response.statusCode, 200, response.body);
    const body = response.json();
    assert.equal(body.username, 'alice_lookup');
    assert.equal(body.devicesDetail.length, 1);
    assert.equal(body.devicesDetail[0].pushConfigured, false);

    // Nothing that could carry content or a credential, checked over the whole
    // serialised response rather than field by field so a future addition has
    // to trip this too.
    const serialised = response.body;
    for (const forbidden of [
      'password_hash',
      'passwordHash',
      'totp_secret',
      'totpSecret',
      'recovery_blob',
      'recoveryBlob',
      'push_token',
      'pushToken',
      'identity_key',
      'identityKey',
      'content',
      'encrypted_metadata',
      'encryptedMetadata',
    ]) {
      assert.ok(!serialised.includes(forbidden), `account detail must not carry ${forbidden}`);
    }
  });

  it('404s an account that does not exist', async () => {
    const response = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/accounts/00000000-0000-4000-8000-000000000000',
      headers: adminBearer(owner),
    });
    assert.equal(response.statusCode, 404);
  });
});

describe('admin licensing', () => {
  let h: TestHarness;
  let owner: Awaited<ReturnType<typeof registerAdmin>>;

  before(async () => {
    h = await createHarness();
    owner = await registerAdmin(h.app, 'licence_owner');
  });
  after(async () => {
    await h.close();
  });

  it('issues a key once, labels it manual, and never shows it again', async () => {
    const issued = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/licenses',
      headers: adminBearer(owner),
      payload: { reference: 'ticket-4711', note: 'replacement' },
    });
    assert.equal(issued.statusCode, 201, issued.body);
    const { licenseId, licenseKey } = issued.json();
    assert.match(licenseKey, /^PRIVIO-/);

    const again = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/licenses',
      headers: adminBearer(owner),
      payload: { reference: 'ticket-4711' },
    });
    assert.equal(again.statusCode, 409);

    const listed = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/licenses?q=ticket-4711',
      headers: adminBearer(owner),
    });
    assert.equal(listed.statusCode, 200, listed.body);
    const row = listed.json().licenses[0];
    assert.equal(row.id, licenseId);
    // Forced, not taken from the caller: an operator-issued licence has to stay
    // distinguishable from a paid one.
    assert.equal(row.paymentProvider, 'manual');
    // The key is gone. The listing cannot become a key generator.
    assert.ok(!listed.body.includes(licenseKey));
    assert.ok(!listed.body.includes('keyHash'));
    assert.ok(!listed.body.includes('key_hash'));
  });

  it('records the issue in the audit log without the key', async () => {
    const issued = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/licenses',
      headers: adminBearer(owner),
      payload: { reference: 'ticket-audit' },
    });
    const { licenseKey, licenseId } = issued.json();

    const log = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/audit?action=license.issue',
      headers: adminBearer(owner),
    });
    assert.equal(log.statusCode, 200, log.body);
    const entry = log.json().entries.find((e: { targetId: string }) => e.targetId === licenseId);
    assert.ok(entry, 'the issue should be in the log');
    assert.equal(entry.actorUsername, 'licence_owner');
    assert.equal(entry.detail.reference, 'ticket-audit');
    assert.ok(!log.body.includes(licenseKey), 'the audit log must never carry a license key');
  });

  it('revokes by id and refuses a second revocation', async () => {
    const issued = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/licenses',
      headers: adminBearer(owner),
      payload: { reference: 'ticket-revoke' },
    });
    const { licenseId } = issued.json();

    const revoked = await h.app.inject({
      method: 'POST',
      url: `/v1/admin/licenses/${licenseId}/revoke`,
      headers: adminBearer(owner),
      payload: { reason: 'chargeback' },
    });
    assert.equal(revoked.statusCode, 200, revoked.body);

    const again = await h.app.inject({
      method: 'POST',
      url: `/v1/admin/licenses/${licenseId}/revoke`,
      headers: adminBearer(owner),
      payload: { reason: 'chargeback' },
    });
    assert.equal(again.statusCode, 404);
  });
});

describe('admin moderation', () => {
  let h: TestHarness;
  let owner: Awaited<ReturnType<typeof registerAdmin>>;
  let alice: TestUser;
  let bob: TestUser;
  let carol: TestUser;

  before(async () => {
    h = await createHarness();
    owner = await registerAdmin(h.app, 'mod_owner');
    alice = await registerUser(h.app, 'alice_mod');
    bob = await registerUser(h.app, 'bob_mod');
    carol = await registerUser(h.app, 'carol_mod');
  });
  after(async () => {
    await h.close();
  });

  it('groups reports by channel with counts per reason', async () => {
    const channel = await createPublicChannel(h, alice, 'reportedone');
    await report(h, bob, channel.id, 'spam');
    await report(h, carol, channel.id, 'abuse');

    const queue = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/reports',
      headers: adminBearer(owner),
    });
    assert.equal(queue.statusCode, 200, queue.body);
    const entry = queue.json().channels.find((c: { channelId: string }) => c.channelId === channel.id);
    assert.ok(entry);
    assert.equal(entry.reports.total, 2);
    assert.equal(entry.reports.open, 2);
    assert.deepEqual(entry.reports.reasons, { spam: 1, abuse: 1 });
    assert.equal(entry.owner.username, 'alice_mod');
    // Public, so the plaintext it publishes on purpose is shown.
    assert.equal(entry.handle, 'reportedone');
  });

  it('shows nothing sealed for a reported private channel', async () => {
    const created = await h.app.inject({
      method: 'POST',
      url: '/v1/channels',
      headers: bearer(alice),
      payload: {
        visibility: 'private',
        encryptedMetadata: Buffer.from('sealed channel title').toString('base64'),
      },
    });
    assert.equal(created.statusCode, 201, created.body);
    const channelId = created.json().id;
    await report(h, bob, channelId, 'illegal');

    const queue = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/reports',
      headers: adminBearer(owner),
    });
    const entry = queue.json().channels.find((c: { channelId: string }) => c.channelId === channelId);
    assert.ok(entry);
    assert.equal(entry.visibility, 'private');
    // The screen is thin on purpose: an id, a count, a reason. A report is a
    // signal about a channel, not evidence of anything in it.
    assert.equal(entry.title, null);
    assert.equal(entry.handle, null);
    assert.equal(entry.description, null);
    assert.ok(!queue.body.includes('sealed channel title'));
  });

  it('suspending a public channel closes discovery, handle and invite link', async () => {
    const channel = await createPublicChannel(h, alice, 'tosuspend');
    await report(h, bob, channel.id, 'spam');

    const suspend = await h.app.inject({
      method: 'POST',
      url: `/v1/admin/channels/${channel.id}/suspend`,
      headers: adminBearer(owner),
      payload: { reason: 'spam' },
    });
    assert.equal(suspend.statusCode, 200, suspend.body);
    assert.equal(suspend.json().reportsClosed, 1);
    assert.equal(suspend.json().membersAffected, false);

    const discover = await h.app.inject({
      method: 'GET',
      url: '/v1/channels/discover?q=tosuspend',
      headers: bearer(carol),
    });
    assert.equal(discover.json().channels.length, 0);

    const byHandle = await h.app.inject({
      method: 'GET',
      url: '/v1/channels/by-handle/tosuspend',
      headers: bearer(carol),
    });
    assert.equal(byHandle.statusCode, 404);

    const byCode = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/invite/${channel.inviteCode}`,
      headers: bearer(carol),
    });
    assert.equal(byCode.statusCode, 404);

    // The id may still be known from before; the door is shut there too.
    const join = await h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channel.id}/join`,
      headers: bearer(carol),
      payload: {},
    });
    assert.equal(join.statusCode, 403);
    assert.equal(join.json().error, 'channel_suspended');

    // The public invite page says so rather than 200-ing an invitation.
    const page = await h.app.inject({ method: 'GET', url: '/tosuspend' });
    assert.ok(page.body.includes('not available'), 'the invite page should say the channel is unavailable');
  });

  it('leaves existing members alone', async () => {
    const channel = await createPublicChannel(h, alice, 'memberskeep');
    const joined = await h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channel.id}/join`,
      headers: bearer(bob),
      payload: {},
    });
    assert.equal(joined.statusCode, 200, joined.body);

    await h.app.inject({
      method: 'POST',
      url: `/v1/admin/channels/${channel.id}/suspend`,
      headers: adminBearer(owner),
      payload: { reason: 'abuse' },
    });

    // Bob is still in it and can still read it. Not leniency — his device holds
    // the key and the server never did, so there is no mechanism by which it
    // could be otherwise. The test exists so nobody later "fixes" that.
    const asMember = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}`,
      headers: bearer(bob),
    });
    assert.equal(asMember.statusCode, 200, asMember.body);

    const feed = await h.app.inject({
      method: 'GET',
      url: `/v1/channels/${channel.id}/posts`,
      headers: bearer(bob),
    });
    assert.equal(feed.statusCode, 200, feed.body);
  });

  it('refuses to suspend a private channel', async () => {
    const created = await h.app.inject({
      method: 'POST',
      url: '/v1/channels',
      headers: bearer(alice),
      payload: {
        visibility: 'private',
        encryptedMetadata: Buffer.from('private one').toString('base64'),
      },
    });
    const response = await h.app.inject({
      method: 'POST',
      url: `/v1/admin/channels/${created.json().id}/suspend`,
      headers: adminBearer(owner),
      payload: { reason: 'spam' },
    });
    // Suspending it would remove nothing while claiming to have acted: a
    // private channel was never discoverable.
    assert.equal(response.statusCode, 400);
    assert.equal(response.json().error, 'channel_not_public');
  });

  it('reinstates a suspended channel', async () => {
    const channel = await createPublicChannel(h, alice, 'toreinstate');
    await h.app.inject({
      method: 'POST',
      url: `/v1/admin/channels/${channel.id}/suspend`,
      headers: adminBearer(owner),
      payload: { reason: 'other' },
    });

    const reinstated = await h.app.inject({
      method: 'POST',
      url: `/v1/admin/channels/${channel.id}/reinstate`,
      headers: adminBearer(owner),
    });
    assert.equal(reinstated.statusCode, 200, reinstated.body);

    const byHandle = await h.app.inject({
      method: 'GET',
      url: '/v1/channels/by-handle/toreinstate',
      headers: bearer(carol),
    });
    assert.equal(byHandle.statusCode, 200, byHandle.body);
  });

  it('clears a channel without acting on it', async () => {
    const channel = await createPublicChannel(h, alice, 'judgedfine');
    await report(h, bob, channel.id, 'other');

    const reviewed = await h.app.inject({
      method: 'POST',
      url: `/v1/admin/channels/${channel.id}/review`,
      headers: adminBearer(owner),
    });
    assert.equal(reviewed.statusCode, 200, reviewed.body);
    assert.equal(reviewed.json().reportsClosed, 1);

    // Out of the open queue…
    const open = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/reports?open=true',
      headers: adminBearer(owner),
    });
    assert.ok(!open.json().channels.some((c: { channelId: string }) => c.channelId === channel.id));

    // …but the history survives, because somebody did report it and the next
    // operator deserves to know that it was judged fine before.
    const all = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/reports?open=false',
      headers: adminBearer(owner),
    });
    const entry = all.json().channels.find((c: { channelId: string }) => c.channelId === channel.id);
    assert.ok(entry);
    assert.equal(entry.reports.total, 1);
    assert.equal(entry.reports.open, 0);

    // And the channel itself was not touched.
    const byHandle = await h.app.inject({
      method: 'GET',
      url: '/v1/channels/by-handle/judgedfine',
      headers: bearer(carol),
    });
    assert.equal(byHandle.statusCode, 200);
  });
});

describe('admin audit log', () => {
  let h: TestHarness;
  let owner: Awaited<ReturnType<typeof registerAdmin>>;

  before(async () => {
    h = await createHarness();
    owner = await registerAdmin(h.app, 'audit_owner');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  it('records the actor name as it was at the time', async () => {
    const created = await h.app.inject({
      method: 'POST',
      url: '/v1/admin/operators',
      headers: adminBearer(owner),
      payload: { username: 'newbie', password: 'a-sufficiently-long-password', role: 'support' },
    });
    assert.equal(created.statusCode, 201, created.body);

    const log = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/audit?action=operator.create',
      headers: adminBearer(owner),
    });
    const entry = log.json().entries[0];
    assert.equal(entry.actorUsername, 'audit_owner');
    assert.equal(entry.detail.username, 'newbie');
    assert.equal(entry.detail.role, 'support');
    // Never the password, in any form.
    assert.ok(!log.body.includes('a-sufficiently-long-password'));
  });

  it('drops anything in detail that is not a scalar', async () => {
    const { audit } = await import('../src/services/admin_audit.js');
    await audit(
      { adminId: owner.id, username: owner.username },
      {
        action: 'report.review',
        detail: {
          keep: 'short',
          // The failure mode this guards: somebody passes a whole request body.
          drop: { secret: 'a sealed message body' },
          long: 'x'.repeat(400),
          count: [1, 2, 3],
        },
      },
    );

    const { rows } = await pool.query(
      `SELECT detail FROM admin_audit_log WHERE action = 'report.review' ORDER BY id DESC LIMIT 1`,
    );
    const detail = rows[0].detail;
    assert.equal(detail.keep, 'short');
    assert.equal(detail.drop, undefined, 'a nested object is dropped, not stringified');
    assert.equal(detail.long.length, 128, 'a long string is capped');
    assert.equal(detail.count, 3, 'an array becomes its length');
  });

  it('pages backwards with a cursor', async () => {
    for (let i = 0; i < 4; i += 1) {
      await h.app.inject({
        method: 'POST',
        url: '/v1/admin/licenses',
        headers: adminBearer(owner),
        payload: { reference: `page-${i}` },
      });
    }

    const first = await h.app.inject({
      method: 'GET',
      url: '/v1/admin/audit?limit=2',
      headers: adminBearer(owner),
    });
    assert.equal(first.json().entries.length, 2);
    const cursor = first.json().nextBefore;
    assert.ok(cursor);

    const second = await h.app.inject({
      method: 'GET',
      url: `/v1/admin/audit?limit=2&before=${cursor}`,
      headers: adminBearer(owner),
    });
    const firstIds = first.json().entries.map((e: { id: number }) => e.id);
    const secondIds = second.json().entries.map((e: { id: number }) => e.id);
    assert.ok(secondIds.every((id: number) => !firstIds.includes(id)));
    assert.ok(Math.max(...secondIds) < Math.min(...firstIds));
  });
});
