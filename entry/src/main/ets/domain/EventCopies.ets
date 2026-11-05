import { ScheduledEvent, TaskPackage, TaskStep } from '../types/Models';
import { copyTaskActions } from '../models/TaskAction';

export function copySteps(steps: TaskStep[]): TaskStep[] {
  return steps.map((step: TaskStep): TaskStep => ({ name: step.name, duration: step.duration }));
}

export function cloneScheduledEvent(source: ScheduledEvent): ScheduledEvent {
  return {
    id: source.id,
    date: source.date,
    packageId: source.packageId,
    packageName: source.packageName,
    color: source.color,
    startHour: source.startHour,
    startMinute: source.startMinute,
    endHour: source.endHour,
    endMinute: source.endMinute,
    steps: copySteps(source.steps),
    reminderEnabled: source.reminderEnabled,
    isCustomized: source.isCustomized,
    sourcePackageVersion: source.sourcePackageVersion,
    actions: copyTaskActions(source.actions)
  };
}

export function cloneTaskPackage(source: TaskPackage): TaskPackage {
  return {
    id: source.id,
    name: source.name,
    color: source.color,
    _version: source._version,
    steps: copySteps(source.steps),
    actions: copyTaskActions(source.actions)
  };
}
