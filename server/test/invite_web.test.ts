import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { escapeHtml } from '../src/web/invite_page.js';
import { bearer, closePool, createHarness, registerUser, type TestHarness, type TestUser } from './helpers.js';

/**
 * The page somebody lands on when they tap a channel link outside Privio.
 *
 * The things worth pinning down here are not the markup. They are: that a
 * private invite discloses nothing, that a page view never spends an
 * invitation, and that every way a link can fail says which way it was.
 */
describe('the invite web page', () => {
  let h: TestHarness;
  let owner: TestUser;

  before(async () => {
    h = await createHarness();
    owner = await registerUser(h.app, 'webowner');
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  const createChannel = (payload: Record<string, unknown>) =>
    h.app.inject({ method: 'POST', url: '/v1/channels', headers: bearer(owner), payload });

  /** The page, fetched the way a stranger fetches it: with no credentials. */
  const open = (path: string) => h.app.inject({ method: 'GET', url: path });

  it('a public channel is shown by its handle, with no invite code in the link', async () => {
    const channel = (await createChannel({
      visibility: 'public',
      handle: 'houseoftrading',
      title: 'House of Trading',
      description: 'Charts every morning',
    })).json();

    const page = await open('/houseoftrading');
    assert.equal(page.statusCode, 200, 'no sign-in: a stranger tapped a link');
    assert.match(page.headers['content-type'] as string, /text\/html/);

    assert.ok(page.body.includes('House of Trading'), 'the real title');
    assert.ok(page.body.includes('Charts every morning'), 'the real description');
    assert.ok(page.body.includes('1 subscriber'), 'the real count');
    assert.ok(page.body.includes('Open in Privio'));

    // A public link is the channel's name. The invite code is a capability and
    // has no business being in a link that gets posted on a website.
    assert.ok(
      !page.body.includes(channel.inviteCode),
      'a public page must not carry the invite code',
    );
  });

  it('and carries a link preview a messenger can use', async () => {
    await createChannel({
      visibility: 'public',
      handle: 'vorschau',
      title: 'Vorschau',
      description: 'Worum es geht',
    });

    const page = await open('/vorschau');
    assert.ok(page.body.includes('<meta property="og:title" content="Vorschau">'));
    assert.ok(page.body.includes('og:description" content="Worum es geht"'));
    assert.ok(page.body.includes('og:image'));
    assert.ok(!page.body.includes('noindex'), 'a public channel is meant to be found');
  });

  it('a private invitation says nothing about the channel', async () => {
    const channel = (await createChannel({
      visibility: 'private',
      encryptedMetadata: Buffer.from('Nur fuer uns').toString('base64'),
    })).json();

    const page = await open(`/+${channel.inviteCode}`);
    assert.equal(page.statusCode, 200);

    // Not its name, not its size, not a word of it. The server does not have
    // the name — it is sealed — and the page must not invent a stand-in that
    // looks like one.
    assert.ok(page.body.includes('A private channel'));
    assert.ok(!page.body.includes('Nur fuer uns'));
    assert.ok(!/\d+ subscribers?/.test(page.body), 'not even how many are in it');

    // And the preview a messenger fetches is neutral: it is fetched by
    // WhatsApp, not by the person who was invited.
    assert.ok(page.body.includes('<meta property="og:title" content="Privio">'));
    assert.ok(page.body.includes('noindex'), 'a token must not reach a search index');
    assert.equal(page.headers['x-robots-tag'], 'noindex, nofollow');
  });

  it('and no request it causes can carry the token anywhere', async () => {
    const channel = (await createChannel({
      visibility: 'private',
      encryptedMetadata: Buffer.from('x').toString('base64'),
    })).json();

    const page = await open(`/+${channel.inviteCode}`);

    // The token is in the URL. A Referer header on any request the page makes
    // would hand that URL to somebody else's server.
    assert.equal(page.headers['referrer-policy'], 'no-referrer');
    assert.match(page.headers['content-security-policy'] as string, /default-src 'none'/);
    assert.equal(page.headers['cache-control'], 'private, no-store');

    // And nothing external to fetch in the first place, which is the part the
    // headers only promise. Every src and href is relative or points back at
    // this same server; a font, an icon or a beacon from anywhere else would
    // be a request carrying this URL off the device.
    const targets = [...page.body.matchAll(/(?:src|href)="([^"]+)"/g)].map((m) => m[1]!);
    assert.ok(targets.length > 0, 'there are some to check');
    for (const target of targets) {
      const external = /^[a-z][a-z0-9+.-]*:/i.test(target) || target.startsWith('//');
      assert.ok(
        !external || target.startsWith('http://localhost'),
        `${target} points off this server`,
      );
    }
    assert.ok(!/<script/i.test(page.body), 'no script at all');
  });

  it('opening the page never spends an invitation', async () => {
    const channel = (await createChannel({
      visibility: 'private',
      encryptedMetadata: Buffer.from('x').toString('base64'),
    })).json();
    await h.app.inject({
      method: 'PUT',
      url: `/v1/channels/${channel.id}/invite`,
      headers: bearer(owner),
      payload: { maxUses: 1 },
    });

    // A preview bot fetches it, and so does everybody the link was forwarded
    // to. Either would burn a one-use invitation before its person arrived.
    for (let i = 0; i < 5; i++) {
      assert.equal((await open(`/+${channel.inviteCode}`)).statusCode, 200);
    }

    const { rows } = await pool.query('SELECT invite_uses FROM channels WHERE id = $1', [
      channel.id,
    ]);
    assert.equal(rows[0].invite_uses, 0, 'the counter moves when somebody joins, not before');
  });

  it('an expired invitation says so, and a used-up one says something else', async () => {
    const expiring = (await createChannel({
      visibility: 'private',
      encryptedMetadata: Buffer.from('x').toString('base64'),
    })).json();
    await pool.query(
      "UPDATE channels SET invite_expires_at = now() - interval '1 minute' WHERE id = $1",
      [expiring.id],
    );

    const expired = await open(`/+${expiring.inviteCode}`);
    assert.equal(expired.statusCode, 410);
    assert.ok(expired.body.includes('expired'));

    const spent = (await createChannel({
      visibility: 'private',
      encryptedMetadata: Buffer.from('x').toString('base64'),
    })).json();
    await pool.query(
      'UPDATE channels SET invite_max_uses = 1, invite_uses = 1 WHERE id = $1',
      [spent.id],
    );

    const usedUp = await open(`/+${spent.inviteCode}`);
    assert.equal(usedUp.statusCode, 410);
    assert.ok(usedUp.body.includes('used up'));
  });

  it('a replaced code and a code that never existed are the same answer', async () => {
    const channel = (await createChannel({
      visibility: 'private',
      encryptedMetadata: Buffer.from('x').toString('base64'),
    })).json();
    const before = await open(`/+${channel.inviteCode}`);
    assert.equal(before.statusCode, 200);

    await h.app.inject({
      method: 'POST',
      url: `/v1/channels/${channel.id}/invite/rotate`,
      headers: bearer(owner),
    });

    const after = await open(`/+${channel.inviteCode}`);
    const nonsense = await open('/+ThisWasNeverACode');
    assert.equal(after.statusCode, 404);
    assert.equal(nonsense.statusCode, 404);
    // For a private channel the existence is the secret, so the two cannot be
    // told apart.
    assert.equal(after.body, nonsense.body);
  });

  it('a deleted channel says it is gone rather than that the link is wrong', async () => {
    const channel = (await createChannel({
      visibility: 'public',
      handle: 'verschwunden',
      title: 'Verschwunden',
    })).json();
    await h.app.inject({
      method: 'DELETE',
      url: `/v1/channels/${channel.id}`,
      headers: bearer(owner),
    });

    const page = await open('/verschwunden');
    assert.equal(page.statusCode, 404);
    assert.ok(page.body.includes('gone'), 'so nobody waits for a link that will never work');
  });

  it('the link shown to the world and the link the app claims are different paths', async () => {
    await createChannel({
      visibility: 'public',
      handle: 'zweiwege',
      title: 'Zwei Wege',
    });

    const page = await open('/zweiwege');
    // The shared link shows this page; only /open/... is claimed by the app,
    // which is what makes the page appear at all rather than being swallowed.
    assert.ok(page.body.includes('/open/zweiwege'), 'the button hands the link to the app');

    const fallback = await open('/open/zweiwege');
    assert.equal(fallback.statusCode, 200);
    assert.ok(fallback.body.includes('Privio did not open'));
    assert.ok(
      fallback.body.includes('in-app browsers') || fallback.body.includes('WhatsApp'),
      'the case people actually hit',
    );
  });

  it('the old link shape still works', async () => {
    const channel = (await createChannel({
      visibility: 'private',
      encryptedMetadata: Buffer.from('x').toString('base64'),
    })).json();

    // Every shipped build generates /c/<code>. A link already pasted somewhere
    // cannot be rewritten.
    const page = await open(`/c/${channel.inviteCode}`);
    assert.equal(page.statusCode, 200);
    assert.ok(page.body.includes('A private channel'));
  });

  it('the API is not shadowed by a handle-shaped path', async () => {
    // `/:handle` is one segment and would swallow anything registered after
    // it. Fastify prefers a static route, and this is the test that says so.
    const health = await open('/health');
    assert.notEqual(health.statusCode, 404);
    assert.ok(!health.body.includes('<!doctype html>'));
  });

  it('shows only download links that exist', async () => {
    await createChannel({
      visibility: 'public',
      handle: 'ohnestore',
      title: 'Ohne Store',
    });

    // Nothing is configured in the test environment, which is the same state a
    // deployment is in before it has store listings.
    const page = await open('/ohnestore');
    assert.ok(!page.body.includes('apps.apple.com'));
    assert.ok(!page.body.includes('play.google.com'));
    assert.ok(
      page.body.includes('not in the app stores yet'),
      'says so rather than showing a button that goes nowhere',
    );
  });

  it('escapes what a channel owner typed', () => {
    // A public channel's title and description are whatever its owner wrote,
    // rendered into a page served to strangers.
    assert.equal(
      escapeHtml('<script>alert("x")</script>'),
      '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;',
    );
    assert.equal(escapeHtml("it's & more"), 'it&#39;s &amp; more');
  });

  it('a title with markup in it lands on the page as text', async () => {
    await createChannel({
      visibility: 'public',
      handle: 'boeswillig',
      title: '<img src=x onerror=alert(1)>',
      description: '</title><script>evil()</script>',
    });

    const page = await open('/boeswillig');
    assert.ok(!page.body.includes('<img src=x'), 'not as markup');
    assert.ok(!page.body.includes('<script>evil()'), 'not in the title tag either');
    assert.ok(page.body.includes('&lt;img src=x'), 'as text');
  });

  it('the app-link files are 404 until they are configured, not served empty', async () => {
    // Apple's CDN caches what it gets for days. A placeholder with the wrong
    // team id is a link that opens nothing for a week after the right one is
    // deployed; a 404 is the state both platforms handle correctly.
    const apple = await open('/.well-known/apple-app-site-association');
    assert.equal(apple.statusCode, 404);
    assert.equal(apple.json().error, 'not_configured');

    const android = await open('/.well-known/assetlinks.json');
    assert.equal(android.statusCode, 404);
    assert.equal(android.json().error, 'not_configured');
  });

  it('serves the mark for the page and for link previews', async () => {
    const mark = await open('/assets/privio-mark.png');
    assert.equal(mark.statusCode, 200);
    assert.equal(mark.headers['content-type'], 'image/png');
    assert.ok(mark.rawPayload.length > 1000);
  });
});
