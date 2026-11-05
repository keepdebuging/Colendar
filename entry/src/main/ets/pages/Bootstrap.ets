import { router } from '@kit.ArkUI';
import { appStore } from '../state/AppStore';

@Entry
@Component
struct Bootstrap {
  @State private message: string = '正在恢复数据…';
  @State private failed: boolean = false;

  aboutToAppear(): void {
    try {
      appStore.restore();
      if (appStore.recoveryRequired) {
        router.replaceUrl({ url: 'pages/RecoveryPage' });
        return;
      }
      router.replaceUrl({ url: 'pages/Index' });
    } catch (_error) {
      this.failed = true;
      this.message = '数据暂时无法读取，请进入恢复页面';
    }
  }

  build() {
    Column({ space: 16 }) {
      Text(this.message)
        .fontSize(18)
        .fontColor('#333333')
      if (this.failed) {
        Button('打开恢复页面')
          .onClick(() => router.replaceUrl({ url: 'pages/RecoveryPage' }))
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#F7F8FA')
  }
}
