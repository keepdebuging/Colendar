@CustomDialog
export struct ImportPackageDialog {
  controller: CustomDialogController = new CustomDialogController({
    builder: this.placeholderBuilder,
    autoCancel: true
  });

  @State importText: string = '';
  onImport?: (text: string) => void;
  onClose?: () => void;

  @Builder
  placeholderBuilder() {
  }

  build() {
    Column() {
      Text('导入任务包')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .padding({ bottom: 8 })

      Text('粘贴由 Colendar 导出的任务包文本。导入的关联动作默认关闭，本地文件动作不会导入。')
        .fontSize(13)
        .fontColor('#666666')
        .width('100%')
        .padding({ bottom: 12 })

      TextArea({ placeholder: '在此粘贴任务包 JSON', text: this.importText })
        .height(180)
        .width('100%')
        .fontSize(14)
        .backgroundColor('#F5F5F5')
        .borderRadius(10)
        .onChange((value: string) => {
          this.importText = value;
        })

      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontColor('#666666')
          .backgroundColor('#F2F2F2')
          .onClick(() => {
            if (this.onClose) {
              this.onClose();
            }
          })

        Button('导入')
          .layoutWeight(1)
          .height(42)
          .backgroundColor('#007AFF')
          .onClick(() => {
            if (this.onImport) {
              this.onImport(this.importText);
            }
          })
      }
      .width('100%')
      .padding({ top: 16 })
    }
    .width('88%')
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
  }
}
