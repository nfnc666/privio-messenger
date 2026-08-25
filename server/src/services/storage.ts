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
}
