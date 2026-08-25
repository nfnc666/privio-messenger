import { EventEmitter } from 'node:events';
import type { Redis } from 'ioredis';
import { config } from '../config.js';

/**
 * Notifies a device's live WebSocket connection that new envelopes are queued.
 * The payload is a device id only — envelope bodies are read from Postgres by
 * the connection that owns the socket, so ciphertext never rides the bus.
 */
export interface DeliveryBus {
  publish(deviceId: string): Promise<void>;
  subscribe(listener: (deviceId: string) => void): () => void;
  close(): Promise<void>;
}

const CHANNEL = 'privio:wake';

/** Single-node bus. Correct whenever every WebSocket lands on the same process. */
export class InProcessBus implements DeliveryBus {
  private readonly emitter = new EventEmitter().setMaxListeners(0);

  async publish(deviceId: string): Promise<void> {
    this.emitter.emit(CHANNEL, deviceId);
  }

  subscribe(listener: (deviceId: string) => void): () => void {
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
    void this.subscriber.subscribe(CHANNEL);
    this.subscriber.on('message', (channel: string, message: string) => {
      if (channel === CHANNEL) void this.local.publish(message);
    });
  }

  async publish(deviceId: string): Promise<void> {
    await this.publisher.publish(CHANNEL, deviceId);
  }

  subscribe(listener: (deviceId: string) => void): () => void {
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
