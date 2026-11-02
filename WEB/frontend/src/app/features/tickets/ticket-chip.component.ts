import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { priorityMeta, statusMeta } from './ticket-ui';

/** Chip de estado o prioridad de un ticket (presentacional). */
@Component({
  selector: 'app-ticket-chip',
  standalone: true,
  template: `
    <span class="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-1 text-[12px] font-bold" [class]="meta().chip">
      <span class="h-1.5 w-1.5 rounded-full" [class]="meta().dot"></span>{{ meta().label }}
    </span>
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class TicketChipComponent {
  readonly kind = input.required<'status' | 'priority'>();
  readonly value = input.required<string>();

  readonly meta = computed(() =>
    this.kind() === 'status' ? statusMeta(this.value()) : priorityMeta(this.value()),
  );
}
