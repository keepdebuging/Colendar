import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction, router } from '@kit.ArkUI';
import { appStore } from '../state/AppStore';

@Entry
@Component
struct RecoveryPage {
  @State private confirmingReset: boolean = false;
  @State private recoveryReason: string = appStore.recoveryReason;

  private retry(): void {
    try {
      appStore.restore();
      if (appStore.recoveryRequired) {
        this.recoveryReason = appStore.recoveryReason;
        promptAction.showToast({ message: `恢复失败：${this.recoveryReason}` });
        return;
      }
      router.replaceUrl({ url: 'pages/Index' });
    } catch (_error) {
      promptAction.showToast({ message: '重新读取失败，原始数据仍保留' });
    }
  }

  private restorePrevious(): void {
    appStore.restorePrevious().then(() => {
      promptAction.showToast({ message: '已恢复上一份有效快照' });
      router.replaceUrl({ url: 'pages/Index' });
    }).catch((_error: Error) => {
      promptAction.showToast({ message: '没有可用的上一份快照' });
    });
  }

  private copyRawData(): void {
    try {
      const data: string = appStore.exportRawData();
      pasteboard.getSystemPasteboard().setDataSync(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, data)
      );
      promptAction.showToast({ message: '原始数据已复制，可以粘贴到安全位置保存' });
    } catch (_error) {
      promptAction.showToast({ message: '复制失败，请保留此页面并联系支持' });
    }
  }

  private resetData(): void {
    if (!this.confirmingReset) {
      this.confirmingReset = true;
      return;
    }
    appStore.resetAfterConfirmation().then(() => {
      promptAction.showToast({ message: '已创建空数据集' });
      router.replaceUrl({ url: 'pages/Index' });
    }).catch((_error: Error) => {
      promptAction.showToast({ message: '无法创建空数据集，原始数据仍保留' });
    });
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text('数据恢复')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
        Text('应用检测到已有数据无法读取。原始内容已保留；请先复制备份，再尝试恢复。')
          .fontSize(15)
          .fontColor('#555555')
        Text(`错误编号：${this.recoveryReason || 'DATA_RECOVERY_REQUIRED'}`)
          .fontSize(13)
          .fontColor('#9A4B00')
        Button('重新读取')
          .width('100%')
          .onClick(() => this.retry())
        Button('恢复上一份有效快照')
          .width('100%')
          .onClick(() => this.restorePrevious())
        Button('复制原始数据')
          .width('100%')
          .onClick(() => this.copyRawData())
        if (!this.confirmingReset) {
          Button('创建新的空数据集')
            .width('100%')
            .backgroundColor('#FFF0F0')
            .fontColor('#B42318')
            .onClick(() => this.resetData())
        } else {
          Text('这会让应用从空数据开始。原始数据会继续保留在备份键中。')
            .fontSize(13)
            .fontColor('#B42318')
          Row({ space: 10 }) {
            Button('确认创建空数据')
              .layoutWeight(1)
              .onClick(() => this.resetData())
            Button('取消')
              .layoutWeight(1)
              .onClick(() => { this.confirmingReset = false; })
          }
          .width('100%')
        }
      }
      .padding(24)
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7F8FA')
  }
}
