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
  /**
   * What the operator panel shows for this bus, if it can say anything.
   *
   * Optional, so a stand-in bus in a test stays three methods long. A bus that
   * does not implement it is reported as configured and nothing more, which is
   * honest: the panel would rather say "no health of its own" than infer one.
   */
  health?(): Promise<{ ok: boolean; detail: string }>;
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

  async health(): Promise<{ ok: boolean; detail: string }> {
    // Nothing can be wrong with it, and that is the point: there is no second
    // process for it to be out of step with.
    return { ok: true, detail: 'In-process bus. One node, nothing to reach.' };
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

  /**
   * Both halves, because they fail separately and mean different things.
   *
   * A dead publisher means this node's wake-ups reach nobody else; a dead
   * subscriber means it stops hearing theirs, which is the quieter and worse
   * failure — sockets here would only close at their next revalidation, with
   * nothing saying why. Reporting one number for the pair would hide that.
   *
   * The ping is bounded. An ioredis client that is reconnecting queues
   * commands by default, so an unreachable Redis would otherwise make this
   * check hang for as long as the panel was willing to wait.
   */
  async health(): Promise<{ ok: boolean; detail: string }> {
    const probe = async (client: Redis, which: string) => {
      const timeout = new Promise<never>((_resolve, reject) => {
        const timer = setTimeout(() => reject(new Error(`${which} did not answer within 2s`)), 2_000);
        timer.unref();
      });
      await Promise.race([client.ping(), timeout]);
    };

    const results = await Promise.allSettled([
      probe(this.publisher, 'publisher'),
      probe(this.subscriber, 'subscriber'),
    ]);
    const failed = (['publisher', 'subscriber'] as const).filter(
      (_name, i) => results[i]!.status === 'rejected',
    );

    if (failed.length === 0) {
      return { ok: true, detail: 'Publisher and subscriber both answering.' };
    }
    return {
      ok: false,
      detail:
        failed.length === 2
          ? 'Neither the publisher nor the subscriber is answering. Wake-ups are not crossing between nodes; devices fall back to polling.'
          : `The ${failed[0]} is not answering. ${
              failed[0] === 'subscriber'
                ? 'This node is not hearing other nodes, so a session revoked elsewhere stays open here until its next revalidation.'
                : 'This node is not reaching other nodes, so its wake-ups are not delivered.'
            }`,
    };
  }
}

export async function createBus(): Promise<DeliveryBus> {
  if (!config.REDIS_URL) return new InProcessBus();
  const { Redis: IORedis } = await import('ioredis');
  return new RedisBus(new IORedis(config.REDIS_URL), new IORedis(config.REDIS_URL));
}
