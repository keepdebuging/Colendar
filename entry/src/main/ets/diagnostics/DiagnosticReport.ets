import { deviceInfo } from '@kit.BasicServicesKit';
import { taskStore } from '../models/TaskPackage';
import { scheduleStore } from '../models/ScheduledEvent';
import { executionStore } from '../models/ExecutionSession';
import { appStore } from '../state/AppStore';
import { getRecentDiagnostics } from './AppLogger';

export function buildDiagnosticReport(page: string, viewMode: string = ''): string {
  const active = executionStore.getActiveSession();
  const recent = getRecentDiagnostics(20).map((entry) => ({
    timestamp: new Date(entry.timestamp).toISOString(),
    scope: entry.scope,
    code: entry.code
  }));
  const report = {
    appVersion: '1.0.0',
    buildVersion: '1',
    systemVersion: deviceInfo.osFullName,
    sdkApiVersion: deviceInfo.sdkApiVersion,
    page,
    viewMode,
    counts: {
      packages: taskStore.packages.length,
      schedules: scheduleStore.events.length,
      executionRecords: executionStore.sessions.length
    },
    hasActiveSession: active !== undefined,
    storageRecoveryRequired: appStore.recoveryRequired,
    recentErrors: recent
  };
  return JSON.stringify(report, null, 2);
}
