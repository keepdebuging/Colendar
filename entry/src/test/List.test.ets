import localUnitTest from './LocalUnit.test';
import executionSessionTest from './ExecutionSession.test';

export default function testsuite() {
  localUnitTest();
  executionSessionTest();
}
