import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { pool } from '../src/db/pool.js';
import { closePool, createHarness, type TestHarness } from './helpers.js';

/**
 * What the server is allowed to be able to read.
 *
 * Every free-text column in the schema, each with the reason it is not sealed.
 * The list is the point: adding a column that holds something a person typed is
 * easy, reviewing a migration and noticing is not, and a plaintext column that
 * nobody argued for is how a messenger ends up knowing more than it says. A new
 * one fails this test until it is either sealed or written down here.
 */
const READABLE: Record<string, string> = {
  // Identity, deliberately public: this is how people find each other.
  'accounts.username': 'the handle others look up',
  'accounts.display_name': 'shown to anyone who can look the account up',

  // Credentials. Hashes, not secrets — and the two that are secrets are sealed
  // under a key held outside the database (see "Two-factor secrets").
  'accounts.password_hash': 'Argon2id digest',
  'accounts.totp_secret': 'sealed under TOTP_SECRET_KEY before it gets here',
  'accounts.duress_code_hash': 'Argon2id digest',
  'accounts.privacy': 'the account s own switches, which the server enforces',

  // Capabilities and pointers. None of them says anything about content.
  'backups.storage_key': 'where the sealed blob is, not what is in it',
  'media_objects.storage_key': 'same',
  'media_objects.kind': 'attachment, avatar or channel_avatar, which decides who may download it',
  'channels.invite_code': 'the capability in a link, meant to be shared',
  'groups.invite_code': 'the same',
  'sent_message_keys.idempotency_key': 'opaque to the server; it is compared, never read',
  'schema_migrations.name': 'not user data',
  // A random label a device invents for the key it generated, so members can
  // agree on which key an epoch means. Not derived from the key and says
  // nothing about it; see migration 015.
  'channel_key_epochs.key_id': 'an opaque label for a key the server never sees',

  // Enumerations the server acts on.
  'channels.visibility': 'decides whether it is listed at all',
  'channel_members.role': 'enforced by the server',
  'group_members.role': 'the same',
  'envelopes.envelope_type': 'prekey or ciphertext — which cipher opens it',
  'key_requests.scope': 'group or channel',

  // A public channel is discoverable, and search cannot run over ciphertext.
  // This is the one place content-adjacent text is deliberately readable, and
  // it applies to public channels only: a private one seals its title.
  'channels.handle': 'how a public channel is linked to and found',
  'channels.title': 'public channels are searchable by name',
  'channels.description': 'the same',
  'channels.category': 'the same',
  // A public channel's welcome text, under the same rule as its description:
  // the route refuses to write this column for a private channel at all, whose
  // welcome message goes inside `encrypted_metadata` with its title.
  'channels.welcome_message': 'public channels only; a private one seals it with its title',
  // Token names, not content: one of six accents and one of three backgrounds,
  // held to that by a check constraint. What it says about the channel is what
  // colour it is.
  'channels.accent_name': 'a theme token name, constrained to a fixed list',
  'channels.background_name': 'the same',
  // A random room id on the media server. A livestream is not end-to-end
  // encrypted — no SFU can forward what it cannot read — and this is the name
  // of the room, not of the channel: see docs/channels.md.
  'channels.live_room': 'a random room id on the media server, not derived from the channel',

  // Devices. A push token is an address the server posts to, so it cannot be
  // sealed; the rest is what the connected-devices screen shows.
  'devices.name': 'shown in the device list',
  'devices.platform': 'shown in the device list',
  'devices.push_provider': 'which service to wake',
  'devices.push_token': 'an address this server sends to; sealing it would break it',
  'devices.voip_token': 'the second address iOS needs, for the same reason',
  'sessions.user_agent': 'shown beside the session in the device list',

  // Reactions. The one place in a channel where the server holds something a
  // member chose, and it is held knowingly: a count has to be counted
  // somewhere, and the account id beside it is what stops one person counting
  // ten times and what lets them take it back. Anonymous counters give up
  // both. The emoji is not free text — it has to be one of the channel's own
  // configured set — and nobody is ever served the list of who reacted. See
  // migration 017 and docs/security-model.md.
  'channel_post_reactions.emoji': 'one of the channel s offered emojis, counted by the server',
  'channels.reaction_emojis': 'the menu an admin offers, not anything a member wrote',

  // A report's reason, and the reason it is one of five words rather than a
  // text box. A free field is where somebody pastes the content they are
  // reporting — which would put the very thing the encryption protects into a
  // readable column, written by a person with every reason to. See
  // migration 022.
  'channel_reports.reason': 'one of five fixed words, never free text',

  // The profile status. The one piece of content-bearing text a *person types*
  // that this server can read, and it is here knowingly rather than by
  // oversight. It cannot be sealed the way an avatar is: an avatar is opened
  // with the profile key, which only people who have been written to hold,
  // whereas a status may be addressed to anyone its owner allows — including
  // people who have never exchanged a message and therefore hold no key.
  //
  // So what limits a status is the access rule in `services/status.ts`, not the
  // cryptography, and the sheet where it is typed says so before anybody types
  // anything. Someone who wants a line only one reader can open sends a
  // message. See docs/security-model.md, "The profile status is plaintext on
  // the server, on purpose".
  'accounts.status_text': 'published by its owner to an audience they choose; see docs/security-model.md',
  'accounts.status_emoji': 'the same, held apart from the text so a client can draw it beside the line',

  // Sticker and emoji packs. A pack is *published by link* — the point of the
  // feature is handing somebody a URL and having them see what is in it before
  // they install it — and a recipient of a link holds no key of the author's.
  // Sealing the title would mean either shipping a key inside the link, which
  // is the same as not sealing it, or a preview that cannot say what it is
  // previewing. So the pack's own labels are readable and the *content* is not:
  // the images go through `media_objects` like every other attachment, keyed
  // and fetched with a download token, and this server stores the pack's name,
  // not its pictures. See migration 028.
  'sticker_packs.title': 'shown in a link preview to people who hold no key of the author s',
  'sticker_packs.kind': 'sticker or emoji, which decides where the picker shows it',
  'sticker_packs.share_code': 'the capability in a share link, meant to be handed out, and revocable',
  // The keyboard character a custom item stands in for — `:heart:`, in effect.
  // Not something a person wrote in a conversation: it is the label on a
  // button in a picker, and it travels in the pack, not in a message.
  'sticker_items.emoji': 'the fallback character an item stands for, part of the pack s own description',

  // Bots. Everything below is readable **on purpose and only for bots**, and
  // the reason is one the feature cannot avoid: a bot is a program on somebody
  // else's server reached over HTTP. It holds no Signal keys, so for it to
  // receive a sealed message this server would have to hold its identity key
  // and open the envelope for it — the one capability the whole design exists
  // to deny itself.
  //
  // The choice made instead of weakening that: bot conversations do not join
  // the encrypted path at all. They live here, in their own table, they never
  // touch `envelopes`, a test asserts that they never start to, and the app
  // says so in plain words before the first message to a bot is sent. What is
  // readable is exactly a bot chat and nothing else. See docs/bots.md.
  'bot_messages.body': 'a bot chat is not end-to-end encrypted, knowingly; see docs/bots.md',
  'bot_messages.scope': 'direct, group or channel — which delivery rule applies',
  'bot_messages.author': 'user or bot, which decides whether it is delivered to the operator',
  // The bot's own public description and its command menu, both written by its
  // owner to be shown to everybody who opens the chat.
  'bots.description': 'the bot s public description, shown to anyone who opens it',
  'bots.commands': 'the command menu the owner publishes',
  // Names nobody may register, and why. Not user data: this table is the
  // policy, and it is readable because the server enforces it.
  'reserved_usernames.username': 'the policy the server enforces, not user data',
  'reserved_usernames.reason': 'why the name is held, for whoever reads the table next',
  // How far a conversation with @botcreator has got: `{"at":"awaitingUsername",
  // "name":"..."}`. It holds the half-finished answers to the assistant's own
  // questions — a bot's name — and nothing a person said to another person.
  'botcreator_state.step': 'the assistant s own state machine, not a conversation between people',

  // Which channel carries the verification badge, and who said so.
  //
  // Neither column decides anything — the badge is decided by `channel_id`, a
  // uuid, and these two are the evidence beside it. The handle is what it was
  // at the moment of designation, kept so that a later audit can see whether
  // the channel has since been renamed; `set_by` is an operator's username. A
  // channel's handle is already readable (it is how a public channel is found),
  // and an operator's username is not user data at all.
  'official_channel.designated_handle': 'what the handle was when it was designated, as evidence',
  'official_channel.set_by': 'which operator designated it',

  // Phone numbers, and the shape of what is *not* here.
  //
  // There is no phone-number column in this schema and these three are the
  // reason it is worth saying so: what a phone link holds is a keyed hash
  // (`bytea`, so the digest test covers it) plus the two things below, and
  // neither is a number.
  //
  // The hint is a calling code and the last two digits — "+49 … 87". It exists
  // so the settings screen can say *which* of somebody's numbers is attached,
  // which is a question they cannot answer from a hash. It is shown only to its
  // own owner and never to another account. Two digits and a country identify
  // roughly one person in a million, and the alternative — showing nothing —
  // makes "change my number" a guess.
  'phone_links.hint': 'a calling code and two digits, shown only to its own owner',
  'phone_verifications.hint': 'the same, while a code is outstanding',
  // Argon2id over six digits. Here rather than in the digest test because that
  // test asserts `bytea`, and this one is the encoded-string form Argon2
  // produces — the same shape as `accounts.password_hash`.
  'phone_verifications.code_hash': 'Argon2id digest of the six-digit code',

  // Licensing, which is an order record rather than anything about a person.
  'licenses.source': 'key, apple or google',
  'licenses.status': 'active or revoked',
  'licenses.payment_provider': 'the order this license was issued for',
  'licenses.payment_reference': 'the same',

  // Why a public channel was taken out of discovery. One of the same five words
  // a report uses, and for the same reason: a free field is where somebody
  // pastes what they are moderating. See migration 027.
  'channels.suspended_reason': 'one of five fixed words, never free text',

  // Operators. Staff credentials, not anybody's content — a separate table from
  // `accounts` on purpose, so that a person's own Privio account and their
  // operator login are different credentials with different lifetimes. The two
  // secrets here get the same treatment they get for an account: a digest, and
  // a TOTP secret sealed under a key held outside the database.
  'admin_users.username': 'the operator s login name, shown in the audit log',
  'admin_users.display_name': 'shown in the panel instead of the username',
  'admin_users.password_hash': 'Argon2id digest',
  'admin_users.totp_secret': 'sealed under TOTP_SECRET_KEY before it gets here',
  'admin_users.role': 'owner, admin, support or viewer — enforced by the server',
  'admin_sessions.user_agent': 'shown beside the session, as for an account session',

  // The audit log. Every column is about an operator action and none of it may
  // come from user content — `services/admin_audit.ts` is the single writer and
  // the one place that rule is enforced, which is why it drops anything in
  // `detail` that is not a short scalar rather than stringifying it.
  'admin_audit_log.actor_username': 'who acted, as their name was at the time',
  'admin_audit_log.action': 'a dotted action name from a fixed union',
  'admin_audit_log.target_type': 'account, channel, license, operator or order',
  'admin_audit_log.target_id': 'an id the server already holds',
  'admin_audit_log.detail': 'scalars only: ids, enum values and counts, capped and never nested',
};

describe('what the server can read', () => {
  let h: TestHarness;

  before(async () => {
    h = await createHarness();
  });
  after(async () => {
    await h.close();
    await closePool();
  });

  it('has no free-text column that nobody argued for', async () => {
    // Arrays of text as well as text. A `text[]` reports its data_type as
    // 'ARRAY' and slipped straight past this check — which is exactly the way
    // a readable column gets added without anybody arguing for it, and it was
    // found by adding one.
    const { rows } = await pool.query<{ name: string }>(
      `SELECT table_name || '.' || column_name AS name
         FROM information_schema.columns
        WHERE table_schema = 'public'
          AND (data_type IN ('text', 'character varying', 'json', 'jsonb')
               OR udt_name IN ('_text', '_varchar', '_json', '_jsonb'))
        ORDER BY table_name, ordinal_position`,
    );
    const unexplained = rows.map((r) => r.name).filter((name) => !(name in READABLE));
    assert.deepEqual(
      unexplained,
      [],
      'a new readable column: seal it, or add it to READABLE with the reason',
    );
  });

  it('keeps every message-bearing column opaque', async () => {
    // The columns that carry what people actually said. If any of these ever
    // stops being bytea, the central claim has quietly changed.
    const sealed = [
      ['envelopes', 'content'],
      ['channel_posts', 'content'],
      ['groups', 'encrypted_metadata'],
      ['channels', 'encrypted_metadata'],
      ['accounts', 'recovery_blob'],
    ];
    for (const [table, column] of sealed) {
      const { rows } = await pool.query<{ data_type: string }>(
        `SELECT data_type FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2`,
        [table, column],
      );
      assert.equal(rows[0]?.data_type, 'bytea', `${table}.${column} must stay opaque`);
    }
  });

  it('stores no session token or license key, only digests', async () => {
    for (const [table, column] of [
      ['sessions', 'token_hash'],
      ['licenses', 'key_hash'],
      ['media_objects', 'download_token_hash'],
      // A bot API token is a credential like any other, so it is held the same
      // way. Listing it here rather than arguing for it in READABLE is the
      // point: the type is checked, not the note beside it.
      ['bot_tokens', 'token_hash'],
    ]) {
      const { rows } = await pool.query<{ data_type: string }>(
        `SELECT data_type FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2`,
        [table, column],
      );
      assert.equal(rows[0]?.data_type, 'bytea', `${table}.${column} holds a digest`);
    }
  });
});
