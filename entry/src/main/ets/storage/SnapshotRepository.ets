import { persistence } from '../models/Persistence';
import { SnapshotEnvelope } from '../types/Models';

/**
 * Preferences-backed repository. Current and previous snapshots share one
 * serialized value so packages, schedules and sessions are committed together.
 */
const SNAPSHOT_KEY: string = 'app_snapshot_v1';

export class SnapshotRepository {
  public readRaw(): string {
    return persistence.readString(SNAPSHOT_KEY);
  }

  public readLegacy(key: string): string {
    return persistence.readString(key);
  }

  public saveRecoveryBackup(raw: string): void {
    persistence.writeString('app_snapshot_v1_recovery_backup', raw);
  }

  public readRecoveryBackup(): string {
    return persistence.readString('app_snapshot_v1_recovery_backup');
  }

  public save(envelope: SnapshotEnvelope): void {
    persistence.writeString(SNAPSHOT_KEY, JSON.stringify(envelope));
  }
}
