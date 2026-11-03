import { describe, it, expect } from '@ohos/hypium';
import { TaskPackage } from '../main/ets/models/TaskPackage';
import { exportTaskPackage, importTaskPackage } from '../main/ets/utils/TaskPackageTransfer';

export default function taskPackageTransferTest() {
  describe('taskPackageTransferTest', () => {
    it('round trips a safe template with new ids and disabled actions', 0, () => {
      const source: TaskPackage = {
        id: 'private-id',
        name: '晨间计划',
        color: '#007AFF',
        steps: [{ name: '阅读', duration: 20 }],
        actions: [{
          id: 'private-action-id', trigger: 'session-start', type: 'open-link',
          target: 'https://example.com', enabled: true
        }],
        _version: 3
      };
      const result = importTaskPackage(exportTaskPackage(source), 2);
      expect(result.error).assertEqual('');
      expect(result.package?.name).assertEqual('晨间计划');
      expect(result.package?.id === source.id).assertFalse();
      expect(result.package?.actions?.[0].enabled).assertFalse();
      expect(result.package?.actions?.[0].id === 'private-action-id').assertFalse();
    });

    it('rejects unsupported versions and local file actions', 0, () => {
      const unsupported = importTaskPackage('{"schemaVersion":2,"name":"x","steps":[]}', 0);
      expect(unsupported.error).assertEqual('不支持的模板版本');
      const withFile = importTaskPackage(
        '{"schemaVersion":1,"name":"x","steps":[{"name":"s","duration":1}],"actions":' +
        '[{"id":"a","trigger":"session-start","type":"open-file","target":"file://secret","enabled":true}]}',
        0
      );
      expect(withFile.package?.actions?.length).assertEqual(0);
    });
  });
}
