import { TaskPackage as TaskPackageModel, TaskStep as TaskStepModel } from '../types/Models';
import { cloneTaskPackage } from '../domain/EventCopies';
import { validatePackage } from '../domain/Validation';
import { appStore } from '../state/AppStore';

export interface TaskStep extends TaskStepModel {}
export interface TaskPackage extends TaskPackageModel {}

export const PACKAGE_COLORS: string[] = [
  '#FF9500', '#007AFF', '#34C759', '#FF3B30',
  '#AF52DE', '#FFCC00', '#5AC8FA', '#FF6482'
];

export function getNextColor(existingCount: number): string {
  return PACKAGE_COLORS[existingCount % PACKAGE_COLORS.length];
}

export function generateId(): string {
  const timePart: string = Date.now().toString(36);
  const randomPart: string = Math.random().toString(36).substring(2, 10);
  return `${timePart}-${randomPart}`;
}

class TaskStore {
  public get packages(): TaskPackage[] {
    return appStore.snapshot.packages as TaskPackage[];
  }

  public restore(): void {
    appStore.restore();
  }

  public async addPackage(pkg: TaskPackage): Promise<void> {
    const copy: TaskPackage = cloneTaskPackage(pkg);
    copy._version = 0;
    const validationError: string = validatePackage(copy);
    if (validationError !== '') {
      throw new Error(validationError);
    }
    await appStore.mutate((draft) => {
      if (draft.packages.some((existing) => existing.id === copy.id)) {
        throw new Error('任务包 ID 重复');
      }
      draft.packages.push(copy);
    });
  }

  public async addPackages(packages: TaskPackage[]): Promise<void> {
    const copies: TaskPackage[] = packages.map((pkg) => {
      const copy: TaskPackage = cloneTaskPackage(pkg);
      copy._version = 0;
      const error: string = validatePackage(copy);
      if (error !== '') {
        throw new Error(error);
      }
      return copy;
    });
    await appStore.mutate((draft) => {
      const ids: Set<string> = new Set<string>(draft.packages.map((pkg) => pkg.id));
      for (const pkg of copies) {
        if (ids.has(pkg.id)) {
          throw new Error('任务包 ID 重复');
        }
        ids.add(pkg.id);
      }
      draft.packages.push(...copies);
    });
  }

  public getPackageById(id: string): TaskPackage | undefined {
    return this.packages.find((pkg: TaskPackage) => pkg.id === id);
  }

  public async updatePackage(id: string, updatedPkg: TaskPackage): Promise<boolean> {
    const index: number = this.packages.findIndex((pkg: TaskPackage) => pkg.id === id);
    if (index < 0) {
      return false;
    }
    const copy: TaskPackage = cloneTaskPackage(updatedPkg);
    copy.id = id;
    copy._version = (this.packages[index]._version || 0) + 1;
    const validationError: string = validatePackage(copy);
    if (validationError !== '') {
      throw new Error(validationError);
    }
    await appStore.mutate((draft) => {
      const targetIndex: number = draft.packages.findIndex((pkg) => pkg.id === id);
      if (targetIndex < 0) {
        throw new Error('任务包不存在');
      }
      draft.packages[targetIndex] = copy;
    });
    return true;
  }

  public async deletePackage(id: string): Promise<boolean> {
    if (!this.packages.some((pkg: TaskPackage) => pkg.id === id)) {
      return false;
    }
    await appStore.mutate((draft) => {
      draft.packages = draft.packages.filter((pkg) => pkg.id !== id);
      draft.events = draft.events.filter((event) => event.packageId !== id);
    });
    return true;
  }
}

export const taskStore: TaskStore = new TaskStore();
