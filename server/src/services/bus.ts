import { EventEmitter } from 'node:events';
import type { Redis } from 'ioredis';
import { config } from '../config.js';

/**
 * What a wake-up is about.
 *
 * `envelopes` is the usual one: something is queued, read it. `key-request`
 * carries nothing to read — it means somebody in a group or channel this
 * device belongs to is waiting for its key, and the device should run the
 * housekeeping it would otherwise have run on its next poll.
 *
 * `revoked` is the opposite of a wake-up: stop. It is published when a session
 * ends — a logout, a device revoked from another phone, a password change, an
 * account deleted — and it exists because a WebSocket used to check its session
 * once, at the moment it was opened, and never again. A signed-out device kept
 * receiving envelopes, and its acknowledgements kept deleting them from the
 * queue, for as long as it stayed connected.
 *
 * It rides the same bus as everything else so that it crosses instances: the
 * socket to close is very often not on the process that handled the logout.
 */
export type WakeKind = 'envelopes' | 'key-request' | 'revoked';

export interface Wake {
  deviceId: string;
  kind: WakeKind;

  /**
   * For `revoked`: which session ended, or undefined for "every session on this
   * device". Naming the session matters for a logout — one phone signing out
   * must not close the sockets of that account's other devices, and a device
   * with two sessions open should lose only the one that ended.
   */
  sessionId?: string;
}

/**
 * Notifies a device's live WebSocket connection that there is something to do.
 * The payload is a device id and a reason — envelope bodies are read from
 * Postgres by the connection that owns the socket, so ciphertext never rides
 * the bus, and neither does a key.
 */
export interface DeliveryBus {
  publish(wake: Wake): Promise<void>;
  subscribe(listener: (wake: Wake) => void): () => void;
  close(): Promise<void>;
}

const CHANNEL = 'privio:wake';

/** Single-node bus. Correct whenever every WebSocket lands on the same process. */
export class InProcessBus implements DeliveryBus {
  private readonly emitter = new EventEmitter().setMaxListeners(0);

  async publish(wake: Wake): Promise<void> {
    this.emitter.emit(CHANNEL, wake);
  }

  subscribe(listener: (wake: Wake) => void): () => void {
    this.emitter.on(CHANNEL, listener);
    return () => this.emitter.off(CHANNEL, listener);
  }

  async close(): Promise<void> {
    this.emitter.removeAllListeners();
  }
}

/** Multi-node bus backed by Redis pub/sub. */
export class RedisBus implements DeliveryBus {
  private readonly local = new InProcessBus();

  constructor(
    private readonly publisher: Redis,
    private readonly subscriber: Redis,
  ) {
    // Redis going away must not take the server with it, and neither of these
    // is decoration. An ioredis client emits `error` on every failed
    // connection attempt; an EventEmitter with no `error` listener rethrows,
    // so an unreachable Redis crashed the process rather than degrading it.
    // The clients reconnect on their own — what is needed here is that
    // nothing dies while they do.
    this.publisher.on('error', () => {});
    this.subscriber.on('error', () => {});

    // And a subscribe that never happened is a node that quietly stops
    // receiving revocations: sockets on it would then only close at their next
    // revalidation, with nothing anywhere saying why. The rejection was
    // discarded before — as an unhandled rejection, which is fatal by default
    // in current Node — and is now reported on the client, where a deployment's
    // own error handling already listens.
    this.subscriber.subscribe(CHANNEL).catch((err: unknown) => {
      this.subscriber.emit('error', err);
    });
    this.subscriber.on('message', (channel: string, message: string) => {
      if (channel !== CHANNEL) return;
      try {
        void this.local.publish(JSON.parse(message) as Wake);
      } catch {
        // A frame this node cannot parse is a frame from a version it does not
        // know. Dropping it loses a wake-up, not a message: the queue is still
        // there for the next poll.
      }
    });
  }

  async publish(wake: Wake): Promise<void> {
    await this.publisher.publish(CHANNEL, JSON.stringify(wake));
  }

  subscribe(listener: (wake: Wake) => void): () => void {
    return this.local.subscribe(listener);
  }

  async close(): Promise<void> {
    await this.local.close();
    this.publisher.disconnect();
    this.subscriber.disconnect();
  }
}

export async function createBus(): Promise<DeliveryBus> {
  if (!config.REDIS_URL) return new InProcessBus();
  const { Redis: IORedis } = await import('ioredis');
  return new RedisBus(new IORedis(config.REDIS_URL), new IORedis(config.REDIS_URL));
}
