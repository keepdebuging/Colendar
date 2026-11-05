import { TaskStep } from '../models/TaskPackage';

export interface PackagePreset {
  key: string;
  name: string;
  color: string;
  steps: TaskStep[];
}

export const DEFAULT_PACKAGES: PackagePreset[] = [
  {
    key: 'study',
    name: '专注学习',
    color: '#007AFF',
    steps: [
      { name: '阅读', duration: 25 },
      { name: '休息', duration: 5 },
      { name: '整理笔记', duration: 10 }
    ]
  },
  {
    key: 'exercise',
    name: '轻量运动',
    color: '#34C759',
    steps: [
      { name: '热身', duration: 5 },
      { name: '运动', duration: 25 },
      { name: '拉伸', duration: 10 }
    ]
  },
  {
    key: 'morning',
    name: '晨间流程',
    color: '#FF9500',
    steps: [
      { name: '整理床铺', duration: 5 },
      { name: '洗漱', duration: 10 },
      { name: '规划今天', duration: 10 }
    ]
  }
];
