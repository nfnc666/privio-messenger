import { randomBytes } from 'node:crypto';
import { pool, withTransaction } from '../db/pool.js';

/**
 * Sticker and custom-emoji packs.
 *
 * The rule the whole module is built around: **a pack is private until its
 * owner shares it, and sharing is a code they can take back.** Every read below
 * therefore asks one of two questions — "is this yours?" or "did you present
 * the code?" — and there is no third path that returns a pack to somebody who
 * can answer neither.
 */

export type PackKind = 'sticker' | 'emoji';

export interface PackRow {
  id: string;
  owner_account_id: string;
  kind: PackKind;
  title: string;
  share_code: string | null;
  shared_at: Date | null;
  created_at: Date;
  updated_at: Date;
  deleted_at: Date | null;
}

export interface ItemRow {
  id: string;
  pack_id: string;
  media_id: string;
  emoji: string;
  position: number;
}

/** How many items a pack may hold, and how many packs an account may own. */
export const PACK_LIMITS = { itemsPerPack: 120, packsPerAccount: 200 } as const;

/** The public shape of a pack, with its items. */
export function packJson(pack: PackRow, items: ItemRow[], installed = false) {
  return {
    id: pack.id,
    kind: pack.kind,
    title: pack.title,
    // The code itself, not a URL: the client builds the link, the same way it
    // does for a channel invitation. Only ever present for the owner — see
    // `findForViewer`, which strips it for anybody else.
    shareCode: pack.share_code,
    shared: pack.share_code !== null,
    installed,
    updatedAt: pack.updated_at.toISOString(),
    items: items.map((item) => ({
      id: item.id,
      mediaId: item.media_id,
      emoji: item.emoji,
      position: item.position,
    })),
  };
}

export async function itemsOf(packId: string): Promise<ItemRow[]> {
  const { rows } = await pool.query<ItemRow>(
    'SELECT * FROM sticker_items WHERE pack_id = $1 ORDER BY position, created_at',
    [packId],
  );
  return rows;
}

export async function findOwned(packId: string, accountId: string): Promise<PackRow | null> {
  const { rows } = await pool.query<PackRow>(
    `SELECT * FROM sticker_packs
      WHERE id = $1 AND owner_account_id = $2 AND deleted_at IS NULL`,
    [packId, accountId],
  );
  return rows[0] ?? null;
}

/**
 * A pack as a particular viewer may see it.
 *
 * Three outcomes, and the difference between the last two is the whole privacy
 * model: the owner gets everything including the share code; somebody holding a
 * live code gets the pack without the code; everybody else gets nothing, and
 * "nothing" is indistinguishable from "no such pack".
 */
export async function findForViewer(
  packId: string,
  viewerId: string,
  code: string | null,
): Promise<{ pack: PackRow; isOwner: boolean } | null> {
  const { rows } = await pool.query<PackRow>(
    'SELECT * FROM sticker_packs WHERE id = $1 AND deleted_at IS NULL',
    [packId],
  );
  const pack = rows[0];
  if (!pack) return null;
  if (pack.owner_account_id === viewerId) return { pack, isOwner: true };
  // A revoked pack has `share_code` null, so a stale link fails this comparison
  // rather than matching an empty string against an empty string.
  if (pack.share_code !== null && code !== null && pack.share_code === code) {
    return { pack, isOwner: false };
  }
  // Installed already? Then it was shared at the time, and revoking the link
  // stops new people joining rather than confiscating what somebody has.
  const { rowCount } = await pool.query(
    'SELECT 1 FROM sticker_installs WHERE account_id = $1 AND pack_id = $2',
    [viewerId, packId],
  );
  return rowCount === 1 ? { pack, isOwner: false } : null;
}

/** Finds a pack by a share code alone, which is what a link carries. */
export async function findByShareCode(code: string): Promise<PackRow | null> {
  const { rows } = await pool.query<PackRow>(
    'SELECT * FROM sticker_packs WHERE share_code = $1 AND deleted_at IS NULL',
    [code],
  );
  return rows[0] ?? null;
}

export function newShareCode(): string {
  return randomBytes(16).toString('base64url');
}

/**
 * Rewrites a pack's order from a list of item ids.
 *
 * In one transaction and in two passes: everything is first moved to negative
 * positions, then to its final one. Without that, swapping two items collides
 * with the `(pack_id, position)` unique index halfway through — the constraint
 * is deferrable, but relying on deferral for an ordinary reorder would make
 * every future caller depend on a subtlety nobody would look for.
 */
export async function reorder(packId: string, itemIds: string[]): Promise<void> {
  await withTransaction(async (client) => {
    const { rows } = await client.query<{ id: string }>(
      'SELECT id FROM sticker_items WHERE pack_id = $1',
      [packId],
    );
    const known = new Set(rows.map((row) => row.id));
    // Anything the client did not name keeps its relative order at the end,
    // so a reorder computed against a stale list cannot silently drop an item.
    const ordered = [...itemIds.filter((id) => known.has(id))];
    for (const row of rows) if (!ordered.includes(row.id)) ordered.push(row.id);

    for (const [index, id] of ordered.entries()) {
      await client.query('UPDATE sticker_items SET position = $2 WHERE id = $1', [
        id,
        -(index + 1),
      ]);
    }
    for (const [index, id] of ordered.entries()) {
      await client.query('UPDATE sticker_items SET position = $2 WHERE id = $1', [id, index]);
    }
    await client.query('UPDATE sticker_packs SET updated_at = now() WHERE id = $1', [packId]);
  });
}

/**
 * The packs an account has installed, newest install order first.
 *
 * A deleted pack stays installed and simply stops being returned — the owner
 * deleting it must not reach into other people's accounts and delete rows
 * there, and the next read is where it disappears from their picker.
 */
export async function installedFor(accountId: string) {
  const { rows } = await pool.query<PackRow & { position: number }>(
    `SELECT p.*, i.position
       FROM sticker_installs i
       JOIN sticker_packs p ON p.id = i.pack_id
      WHERE i.account_id = $1 AND p.deleted_at IS NULL
      ORDER BY i.position, i.installed_at`,
    [accountId],
  );
  return rows;
}

/** Records that an item was used, which is what the recents list is made of. */
export async function noteUsed(accountId: string, itemIds: string[]): Promise<void> {
  if (itemIds.length === 0) return;
  await pool.query(
    `INSERT INTO sticker_uses (account_id, item_id, used_at)
     SELECT $1, id, now() FROM unnest($2::uuid[]) AS id
     ON CONFLICT (account_id, item_id) DO UPDATE SET used_at = now()`,
    [accountId, itemIds],
  );
}
