import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit';

export default function abilityTest() {
  describe('ColendarAbilitySmokeTest', () => {
    it('launches app and switches from calendar to package list', 0, async () => {
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: 'com.example.colendar',
        abilityName: 'EntryAbility'
      });
      const driver: Driver = Driver.create();
      const tabs: Component = await driver.waitForComponent(ON.id('main-tabs'), 5000);
      expect(tabs !== undefined).assertTrue();

      const packageTab: Component = await driver.waitForComponent(ON.id('tab-packages'), 3000);
      expect(packageTab !== undefined).assertTrue();
      await packageTab.click();

      const packageTitle: Component = await driver.waitForComponent(ON.text('我的任务包'), 3000);
      expect(packageTitle !== undefined).assertTrue();
    });
  });
}

