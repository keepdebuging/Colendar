import executionSessionTest from './ExecutionSession.test';
import scheduleStoreTest from './ScheduleStore.test';
import timelineGeometryTest from './TimelineGeometry.test';
import taskPackageTransferTest from './TaskPackageTransfer.test';
import usageMetricsTest from './UsageMetrics.test';

export default function testsuite() {
  executionSessionTest();
  scheduleStoreTest();
  timelineGeometryTest();
  taskPackageTransferTest();
  usageMetricsTest();
}

