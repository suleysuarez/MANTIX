import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';

/** Pantalla provisional de módulos aún sin implementar; el título e icono vienen de `route.data`. */
@Component({
  selector: 'app-module-placeholder',
  standalone: true,
  imports: [RouterLink],
  template: `
    <section class="tw-reset flex min-h-[50vh] flex-col items-center justify-center gap-4 rounded-[18px] bg-white p-8 text-center font-sans shadow-[0_8px_25px_rgba(15,23,42,0.05)]">
      <span class="flex h-16 w-16 items-center justify-center rounded-full bg-[#DBEAFE] text-[#2563EB]">
        <span class="material-symbols-outlined text-[32px]">{{ icon }}</span>
      </span>
      <h1 class="text-[22px] font-bold text-[#1E293B]">{{ title }}</h1>
      <p class="max-w-sm text-[14px] text-[#64748B]">{{ description }}</p>
      <span class="rounded-full bg-[#FEF3C7] px-3 py-1 text-[11px] font-bold uppercase tracking-wider text-[#B45309]">Próximamente</span>
      <a routerLink="/dashboard" class="!text-[#2563EB] text-[13px] font-medium hover:underline">Volver al dashboard</a>
    </section>
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ModulePlaceholderComponent {
  private readonly data = inject(ActivatedRoute).snapshot.data;

  readonly title: string = this.data['title'] ?? '';
  readonly icon: string = this.data['icon'] ?? 'construction';
  readonly description: string = this.data['description'] ?? '';
}
