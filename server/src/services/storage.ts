import { randomBytes } from 'node:crypto';
import { mkdir, rm, stat, writeFile } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import type { Readable } from 'node:stream';
import { dirname, join, resolve } from 'node:path';
import { config } from '../config.js';

/**
 * Opaque blob storage for attachments and backups. Everything written here was
 * encrypted on a client device, so the store needs no knowledge of its contents.
 * Swapping in S3-compatible object storage means implementing this interface.
 */
export interface BlobStorage {
  put(data: Buffer): Promise<string>;
  open(key: string): Readable;
  size(key: string): Promise<number>;
  delete(key: string): Promise<void>;
  /**
   * What the operator panel shows for this store, if it can say anything.
   *
   * Optional, so an implementation stays four methods long unless it has
   * something to report.
   */
  health?(): Promise<{ ok: boolean; detail: string }>;
}

export class LocalFileStorage implements BlobStorage {
  constructor(private readonly root: string = config.MEDIA_DIR) {}

  private path(key: string): string {
    // Keys are generated here, but resolve defensively so a crafted key can
    // never escape the storage root.
    const full = resolve(this.root, key);
    if (!full.startsWith(resolve(this.root))) throw new Error('invalid storage key');
    return full;
  }

  async put(data: Buffer): Promise<string> {
    const id = randomBytes(16).toString('hex');
    // Two levels of fan-out keep directories small at scale.
    const key = join(id.slice(0, 2), id.slice(2, 4), id);
    const full = this.path(key);
    await mkdir(dirname(full), { recursive: true });
    await writeFile(full, data);
    return key;
  }

  open(key: string): Readable {
    return createReadStream(this.path(key));
  }

  async size(key: string): Promise<number> {
    return (await stat(this.path(key))).size;
  }

  async delete(key: string): Promise<void> {
    await rm(this.path(key), { force: true });
  }

  /**
   * Can this process actually write an attachment?
   *
   * Writes a byte and deletes it, rather than checking that the directory
   * exists. A directory that exists and is not writable — a volume mounted
   * read-only after a failover, a full disk, the wrong uid in a rebuilt
   * container — passes every cheaper check and fails every upload, which is
   * exactly the outage an operator opens this page to find.
   *
   * The probe writes under the storage root like any blob, so it cannot land
   * anywhere a real attachment could not, and it is removed in a `finally`
   * so a failure partway through leaves nothing behind.
   */
  async health(): Promise<{ ok: boolean; detail: string }> {
    const key = join('.health', randomBytes(8).toString('hex'));
    const full = this.path(key);
    try {
      await mkdir(dirname(full), { recursive: true });
      await writeFile(full, Buffer.of(0));
      return { ok: true, detail: `Writable at ${this.root}.` };
    } catch (err) {
      return {
        ok: false,
        detail: `Cannot write to ${this.root}: ${
          err instanceof Error ? err.message : 'unknown error'
        }. Uploads and backups will fail.`,
      };
    } finally {
      await rm(full, { force: true }).catch(() => {});
    }
  }
}
