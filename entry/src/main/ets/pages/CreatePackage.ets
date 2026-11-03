/**
 * CreatePackage.ets —— 任务包创建 / 编辑页面
 *
 * 双模式设计：
 * - 创建模式（默认）：无路由参数，空白表单，保存时新增到全局仓库
 * - 编辑模式：路由参数带有 packageId，预填充表单，保存时更新全局仓库
 *
 * 路由参数（编辑模式）：
 *   router.pushUrl({ url: 'pages/CreatePackage', params: { packageId: 'xxx' } })
 *
 * 功能：
 * 1. 输入任务包名称
 * 2. 动态增删步骤（每个步骤包含名称和时长）
 * 3. 创建模式：自动分配主题色，生成新 ID
 * 4. 编辑模式：保留原始 ID 和颜色
 * 5. 保存时校验数据合法性
 * 6. 保存成功后存入全局仓库并返回首页
 */

import { router } from '@kit.ArkUI';
import { TaskStep, TaskPackage, generateId, taskStore, getNextColor } from '../models/TaskPackage';
import { promptAction } from '@kit.ArkUI';
import { TaskAction, TaskActionTrigger, TaskActionType, copyTaskActions } from '../models/TaskAction';

@Entry
@Component
struct CreatePackage {
  // ==================== 模式判断 ====================

  /** 是否为编辑模式（由路由参数 packageId 决定） */
  private isEditMode: boolean = false;

  /** 编辑模式下的任务包 ID，创建模式下为空字符串 */
  private editPackageId: string = '';

  /** 编辑模式下保留原始颜色（用户不可修改颜色） */
  private originalColor: string = '#007AFF';

  // ==================== 表单状态 ====================

  /** 任务包名称 */
  @State packageName: string = '';

  /**
   * 步骤列表。
   * 创建模式：初始包含一个空白步骤（25min 番茄钟）。
   * 编辑模式：由 aboutToAppear() 从全局仓库加载后填充。
   */
  @State steps: TaskStep[] = [
    { name: '', duration: 25 }
  ];
  @State actions: TaskAction[] = [];

  // ==================== 生命周期 ====================

  /**
   * 页面即将出现时：
   * 1. 检查路由参数中是否有 packageId
   * 2. 如果有 → 进入编辑模式，从 taskStore 加载数据预填充
   * 3. 如果没有 → 保持创建模式（默认空白表单）
   */
  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object>;

    if (params && params['packageId']) {
      const pkgId: string = params['packageId'] as string;

      if (pkgId) {
        // ---- 编辑模式 ----
        const pkg: TaskPackage | undefined = taskStore.getPackageById(pkgId);

        if (pkg) {
          this.isEditMode = true;
          this.editPackageId = pkgId;
          this.originalColor = pkg.color;

          // 预填充表单
          this.packageName = pkg.name;

          // 深拷贝步骤数据，避免直接修改仓库中的对象
          if (pkg.steps.length > 0) {
            this.steps = pkg.steps.map((s: TaskStep): TaskStep => ({
              name: s.name,
              duration: s.duration
            }));
          } else {
            // 原任务包没有步骤时，给一个空白步骤
            this.steps = [{ name: '', duration: 25 }];
          }
          this.actions = copyTaskActions(pkg.actions);
        }
        // 如果 pkg 不存在（被并发删除），保持创建模式的默认值
        // 这样用户至少还能操作，不会直接崩溃
      }
    }
    // 如果 params 为空或没有 packageId → 创建模式，使用默认初始值
  }

  // ==================== 辅助方法 ====================

  /** 页面标题（根据模式动态切换） */
  getPageTitle(): string {
    return this.isEditMode ? '编辑任务包' : '创建任务包';
  }

  /** 左上角按钮文字（根据模式动态切换） */
  getBackLabel(): string {
    return this.isEditMode ? '取消' : '← 返回';
  }

  // ==================== 步骤操作 ====================

  /**
   * 在列表末尾添加一个新的空白步骤。
   * 使用不可变更新模式确保 @State 检测到变化。
   */
  addStep(): void {
    this.steps = [...this.steps, { name: '', duration: 25 }];
  }

  /**
   * 删除指定索引的步骤。
   */
  deleteStep(index: number): void {
    const newSteps: TaskStep[] = [...this.steps];
    newSteps.splice(index, 1);
    this.steps = newSteps;
  }

  /**
   * 更新指定索引步骤的名称。
   */
  updateStepName(index: number, value: string): void {
    const newSteps: TaskStep[] = [...this.steps];
    newSteps[index] = { name: value, duration: newSteps[index].duration };
    this.steps = newSteps;
  }

  /**
   * 更新指定索引步骤的时长。
   * @param value 输入框字符串，parseInt 转换，非数字默认为 0
   */
  updateStepDuration(index: number, value: string): void {
    const newSteps: TaskStep[] = [...this.steps];
    const durationNum: number = parseInt(value) || 0;
    newSteps[index] = { name: newSteps[index].name, duration: durationNum };
    this.steps = newSteps;
  }

  private addAction(): void {
    const action: TaskAction = {
      id: generateId(),
      trigger: 'session-start',
      type: 'open-link',
      target: '',
      enabled: false
    };
    this.actions = [...this.actions, action];
  }

  private removeAction(index: number): void {
    const next: TaskAction[] = copyTaskActions(this.actions);
    next.splice(index, 1);
    this.actions = next;
  }

  private updateActionTarget(index: number, target: string): void {
    const next: TaskAction[] = copyTaskActions(this.actions);
    next[index].target = target;
    this.actions = next;
  }

  private toggleActionEnabled(index: number, enabled: boolean): void {
    const next: TaskAction[] = copyTaskActions(this.actions);
    next[index].enabled = enabled;
    this.actions = next;
  }

  private cycleActionType(index: number): void {
    const next: TaskAction[] = copyTaskActions(this.actions);
    const current: TaskActionType = next[index].type;
    next[index].type = current === 'open-link' ? 'open-app' :
      (current === 'open-app' ? 'open-file' : 'open-link');
    this.actions = next;
  }

  private cycleActionTrigger(index: number): void {
    const next: TaskAction[] = copyTaskActions(this.actions);
    const current: TaskActionTrigger = next[index].trigger;
    next[index].trigger = current === 'session-start' ? 'step-start' : 'session-start';
    this.actions = next;
  }

  private actionTypeLabel(type: TaskActionType): string {
    if (type === 'open-app') {
      return '打开应用';
    }
    if (type === 'open-file') {
      return '打开文件';
    }
    return '打开链接';
  }

  // ==================== 保存逻辑 ====================

  /**
   * 保存任务包（创建或更新）。
   *
   * 验证规则（创建和编辑共用）：
   * 1. 任务包名称不能为空
   * 2. 至少有一个有效步骤（名称非空）
   *
   * 分支逻辑：
   * - 创建模式：generateId() + getNextColor() → taskStore.addPackage()
   * - 编辑模式：保留原始 id + color → taskStore.updatePackage()
   */
  savePackage(): void {
    // ===== 验证 1：任务包名称不能为空 =====
    if (this.packageName.trim().length === 0) {
      promptAction.showToast({
        message: '请输入任务包名称',
        duration: 2000
      });
      return;
    }

    // ===== 验证 2：至少需要一个步骤 =====
    if (this.steps.length === 0) {
      promptAction.showToast({
        message: '请至少添加一个步骤',
        duration: 2000
      });
      return;
    }

    // ===== 验证 3：过滤空名称步骤 =====
    const validSteps: TaskStep[] = this.steps.filter(
      (step: TaskStep) => step.name.trim().length > 0
    );
    const validActions: TaskAction[] = copyTaskActions(this.actions).filter(
      (action: TaskAction) => action.target.trim().length > 0
    );

    if (validSteps.length === 0) {
      promptAction.showToast({
        message: '请至少为一个步骤填写名称',
        duration: 2000
      });
      return;
    }

    // ===== 根据模式执行不同操作 =====
    if (this.isEditMode) {
      // ---------- 编辑模式：更新已有任务包 ----------
      const updatedPackage: TaskPackage = {
        id: this.editPackageId,
        name: this.packageName.trim(),
        steps: validSteps,
        color: this.originalColor,
        actions: validActions,
        _version: 0  // 由 updatePackage 内部自增覆盖
      };

      const success: boolean = taskStore.updatePackage(
        this.editPackageId, updatedPackage
      );

      if (success) {
        promptAction.showToast({
          message: '保存成功！',
          duration: 1500
        });
      } else {
        promptAction.showToast({
          message: '保存失败，任务包可能已被删除',
          duration: 2000
        });
      }
    } else {
      // ---------- 创建模式：新增任务包 ----------
      const newPackage: TaskPackage = {
        id: generateId(),
        name: this.packageName.trim(),
        steps: validSteps,
        color: getNextColor(taskStore.packages.length),
        actions: validActions,
        _version: 0
      };

      taskStore.addPackage(newPackage);

      promptAction.showToast({
        message: '创建成功！',
        duration: 1500
      });
    }

    // 返回上一页
    // Index.onPageShow() 会递增 refreshTrigger → Tab 列表自动刷新
    router.back();
  }

  // ==================== UI 构建 ====================

  build() {
    Column() {
      // ==================== 顶部导航栏 ====================
      Row() {
        // 左侧区域（固定宽度，与右侧对称，确保标题居中）
        Row() {
          Button(this.getBackLabel())
            .fontSize(16)
            .backgroundColor('#00000000')
            .fontColor('#007AFF')
            .padding(0)
            .onClick(() => {
              router.back();
            })
        }
        .width(72)

        // 标题（占据剩余空间，文字居中）
        Text(this.getPageTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 右侧对称留白（与左侧等宽）
        Blank()
          .width(72)
      }
      .width('100%')
      .padding(16)
      .backgroundColor('#F5F5F5')

      // ==================== 可滚动的内容区域 ====================
      Scroll() {
        Column() {
          // ---------- 任务包名称输入区 ----------
          Text('任务包名称')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .padding({ left: 20, top: 20, bottom: 8 })

          TextInput({ text: this.packageName, placeholder: '例如：期末复习计划' })
            .onChange((value: string) => {
              this.packageName = value;
            })
            .width('100%')
            .padding(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .margin({ left: 16, right: 16 })

          // ---------- 分割线 ----------
          Divider()
            .margin({ top: 20, left: 16, right: 16 })

          // ---------- 步骤列表标题 ----------
          Row() {
            Text('步骤列表')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)

            Blank()

            Text(`${this.steps.length} 个步骤`)
              .fontSize(14)
              .fontColor('#999999')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 8 })

          // ---------- 动态步骤列表 ----------
          ForEach(this.steps,
            (step: TaskStep, index: number) => {
              Column() {
                Row() {
                  // 步骤序号
                  Text(`${index + 1}`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#007AFF')
                    .width(24)
                    .textAlign(TextAlign.Center)

                  // 步骤名称输入框
                  TextInput({ text: step.name, placeholder: '步骤名称' })
                    .onChange((value: string) => {
                      this.updateStepName(index, value);
                    })
                    .layoutWeight(2)
                    .padding(10)
                    .backgroundColor('#F8F8F8')
                    .borderRadius(6)

                  // 时长输入框（数字键盘）
                  TextInput({
                    text: step.duration > 0 ? step.duration.toString() : '',
                    placeholder: '分钟'
                  })
                    .type(InputType.Number)
                    .onChange((value: string) => {
                      this.updateStepDuration(index, value);
                    })
                    .layoutWeight(1)
                    .padding(10)
                    .backgroundColor('#F8F8F8')
                    .borderRadius(6)
                    .margin({ left: 8, right: 4 })

                  // 删除按钮
                  Button('✕')
                    .fontSize(14)
                    .width(32)
                    .height(32)
                    .borderRadius(16)
                    .backgroundColor('#FFE0E0')
                    .fontColor('#FF4444')
                    .onClick(() => {
                      this.deleteStep(index);
                    })
                }
                .width('100%')
                .padding({ top: 4, bottom: 4 })
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
            },
            (_step: TaskStep, index: number) => {
              // ForEach 键生成器：编辑模式下使用 packageId+index，创建模式下用 index
              return this.isEditMode ?
                `${this.editPackageId}-step-${index}` :
                `create-step-${index}`;
            }
          )

          // ---------- 添加步骤按钮 ----------
          Button('＋ 添加步骤')
            .fontSize(16)
            .fontColor('#007AFF')
            .backgroundColor('#EBF5FF')
            .width('calc(100% - 32px)')
            .padding(12)
            .borderRadius(8)
            .margin({ top: 12, left: 16, right: 16 })
            .onClick(() => {
              this.addStep();
            })

          Divider().margin({ top: 20, left: 16, right: 16 })

          Row() {
            Text('关联动作（可选）')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
            Blank()
            Text('仅在用户开始任务后触发')
              .fontSize(11)
              .fontColor('#888888')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 8 })

          ForEach(this.actions, (action: TaskAction, index: number) => {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Button(this.actionTypeLabel(action.type))
                  .fontSize(12)
                  .onClick(() => { this.cycleActionType(index); })
                Button(action.trigger === 'session-start' ? '任务开始时' : '步骤开始时')
                  .fontSize(12)
                  .onClick(() => { this.cycleActionTrigger(index); })
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: action.enabled })
                  .onChange((isOn: boolean) => { this.toggleActionEnabled(index, isOn); })
                Button('✕')
                  .fontSize(12)
                  .width(32)
                  .height(32)
                  .backgroundColor('#FFE0E0')
                  .fontColor('#FF4444')
                  .onClick(() => { this.removeAction(index); })
              }
              TextInput({
                text: action.target,
                placeholder: action.type === 'open-app' ? '应用 bundleName' :
                  (action.type === 'open-file' ? '已授权文件 URI' : 'https://...')
              })
                .onChange((value: string) => { this.updateActionTarget(index, value); })
                .width('100%')
            }
            .width('calc(100% - 32px)')
            .padding(10)
            .margin({ left: 16, right: 16, bottom: 8 })
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
          }, (action: TaskAction) => action.id)

          Button('＋ 添加关联动作')
            .fontSize(15)
            .fontColor('#007AFF')
            .backgroundColor('#EBF5FF')
            .width('calc(100% - 32px)')
            .padding(10)
            .borderRadius(8)
            .margin({ left: 16, right: 16, top: 4 })
            .onClick(() => { this.addAction(); })

          // 底部留白
          Blank()
            .height(80)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')

      // ==================== 底部保存按钮 ====================
      Button('保 存')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .backgroundColor('#007AFF')
        .width('calc(100% - 32px)')
        .height(48)
        .borderRadius(24)
        .margin(16)
        .onClick(() => {
          this.savePackage();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0F0F0')
  }
}
