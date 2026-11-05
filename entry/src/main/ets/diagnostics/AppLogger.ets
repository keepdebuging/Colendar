import { hilog } from '@kit.PerformanceAnalysisKit';
import { persistence } from '../models/Persistence';

export interface DiagnosticEntry {
  timestamp: number;
  scope: string;
  code: string;
}

const DOMAIN: number = 0x0000;
const TAG: string = 'Colendar';
const STORAGE_KEY: string = 'diagnostics_recent_v1';
const MAX_ENTRIES: number = 150;

export function reportError(scope: string, code: string): void {
  hilog.error(DOMAIN, TAG, 'scope=%{public}s code=%{public}s', scope, code);
  try {
    const raw: string = persistence.readString(STORAGE_KEY);
    let entries: DiagnosticEntry[] = [];
    if (raw !== '') {
      const parsed: Object = JSON.parse(raw) as Object;
      if (Array.isArray(parsed)) {
        entries = parsed as DiagnosticEntry[];
      }
    }
    entries.push({ timestamp: Date.now(), scope, code });
    if (entries.length > MAX_ENTRIES) {
      entries = entries.slice(entries.length - MAX_ENTRIES);
    }
    persistence.writeString(STORAGE_KEY, JSON.stringify(entries));
  } catch (_error) {
    // The system log remains available if persistent diagnostics cannot be written.
    hilog.warn(DOMAIN, TAG, 'persistent diagnostic write failed');
  }
}

export function getRecentDiagnostics(limit: number = 20): DiagnosticEntry[] {
  try {
    const raw: string = persistence.readString(STORAGE_KEY);
    if (raw === '') {
      return [];
    }
    const parsed: Object = JSON.parse(raw) as Object;
    if (!Array.isArray(parsed)) {
      return [];
    }
    const entries: DiagnosticEntry[] = parsed as DiagnosticEntry[];
    return entries.slice(Math.max(0, entries.length - limit));
  } catch (_error) {
    return [];
  }
}
