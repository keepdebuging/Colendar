import { appStore } from '../state/AppStore';

export class BootstrapService {
  public restore(): void {
    appStore.restore();
  }
}
