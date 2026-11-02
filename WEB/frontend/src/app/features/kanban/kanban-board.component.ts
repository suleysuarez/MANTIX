import { NgTemplateOutlet } from '@angular/common';
import {
  ChangeDetectionStrategy, Component, ContentChild, Directive, TemplateRef, computed, effect, inject, input, output, signal,
} from '@angular/core';
import { Observable } from 'rxjs';

import { ToastService } from '../../core/toast.service';

export interface KanbanColumn<T> {
  id: string;
  title: string;
  hint?: string;
  /** Registros de la columna. */
  items: T[];
  /** Total real si la columna está paginada; por defecto, los que se ven. */
  total?: number;
  /** Punto de color de la cabecera (clase de Tailwind). */
  dot?: string;
  /** Se está pidiendo la siguiente página de esta columna. */
  loading?: boolean;
  /** Texto que sustituye al de «columna vacía» (cargando, error, columna oculta por un filtro…). */
  notice?: string;
}

export interface KanbanMove<T> {
  item: T;
  from: string;
  to: string;
}

/** Lo que responde quien ejecuta el movimiento: hecho, cancelado por la persona (diálogo) o rechazado. */
export type KanbanOutcome = { ok: true } | { ok: false; cancelled?: boolean; message?: string };

/** Plantilla de la tarjeta: `<ng-template appKanbanCard let-item let-column="column">…</ng-template>`. */
@Directive({ selector: 'ng-template[appKanbanCard]', standalone: true })
export class KanbanCardDirective<T = unknown> {
  readonly template = inject<TemplateRef<{ $implicit: T; column: string }>>(TemplateRef);
}

const FOCUS = 'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-accentDeep';

/**
 * Tablero Kanban compartido (Tickets y Solicitudes pendientes): una columna por estado, tarjetas
 * arrastrables, columnas destino válidas resaltadas y las demás atenuadas, movimiento optimista que
 * se revierte si el servidor lo rechaza, y un menú «Mover a…» como alternativa con teclado.
 * Qué pasos son válidos lo decide el padre (`validTargets`, que sale del State Pattern del servidor).
 */
@Component({
  selector: 'app-kanban-board',
  standalone: true,
  imports: [NgTemplateOutlet],
  changeDetection: ChangeDetectionStrategy.OnPush,
  host: { class: 'block' },
  template: `
    <div class="grid items-start gap-3" [style.grid-template-columns]="'repeat(auto-fit, minmax(' + minColumnWidth() + 'px, 1fr))'"
      role="group" [attr.aria-label]="ariaLabel()">
      @for (column of view(); track column.id) {
        <section [attr.aria-label]="column.title" [attr.data-column]="column.id" tabindex="-1"
          (dragover)="onDragOver($event, column.id)" (dragleave)="hover.set(null)" (drop)="onDrop($event, column.id)"
          [class]="'flex min-h-[18rem] min-w-0 flex-col rounded-2xl border bg-surface-container-low p-2.5 transition-all motion-reduce:transition-none ' + columnClass(column.id)">
          <header class="flex items-center justify-between gap-2 border-b border-brand-grey/60 pb-2">
            <span class="flex min-w-0 items-center gap-2 text-[13px] font-bold text-on-surface">
              @if (column.dot) { <span [class]="'h-2.5 w-2.5 shrink-0 rounded-full ' + column.dot" aria-hidden="true"></span> }
              <span class="truncate" [attr.title]="column.hint ?? null">{{ column.title }}</span>
            </span>
            <span class="rounded-full bg-surface-container-lowest px-2 py-0.5 text-[12px] font-bold text-on-surface" [attr.aria-label]="(column.total ?? column.items.length) + ' en ' + column.title">{{ column.total ?? column.items.length }}</span>
          </header>
          <div class="flex-1 space-y-2 pt-2">
            @for (item of column.items; track key()(item)) {
              <div [class]="'group relative rounded-xl ' + (isMoving(item) ? 'opacity-60' : '')" [attr.draggable]="canDrag(item, column.id)" tabindex="-1"
                (dragstart)="onDragStart($event, item, column.id)" (dragend)="onDragEnd()">
                <ng-container [ngTemplateOutlet]="card?.template ?? null" [ngTemplateOutletContext]="{ $implicit: item, column: column.id }" />
                @if (targetsOf(item, column.id).length > 0 && !disabled()) {
                  <div class="absolute right-1.5 top-1.5">
                    <button type="button" (click)="toggleMenu(item, $event)" [attr.aria-expanded]="menuFor() === key()(item)" aria-haspopup="menu"
                      [attr.aria-label]="'Mover a… (' + label()(item) + ')'" [disabled]="isMoving(item)"
                      [class]="focus + ' flex h-7 w-7 items-center justify-center rounded-lg bg-surface-container-lowest/90 !text-brand-accentDeep opacity-0 shadow-sm hover:bg-surface-container-high focus-visible:opacity-100 group-hover:opacity-100'"
                      [style.opacity]="menuFor() === key()(item) ? 1 : null">
                      <span class="material-symbols-outlined text-[18px]" aria-hidden="true">drive_file_move</span>
                    </button>
                    @if (menuFor() === key()(item)) {
                      <ul role="menu" tabindex="-1" aria-label="Mover a…" class="absolute right-0 z-20 mt-1 min-w-[10rem] rounded-xl border border-brand-grey bg-surface-container-lowest p-1 shadow-lg" (keydown.escape)="menuFor.set(null)">
                        @for (target of targetsOf(item, column.id); track target) {
                          <li role="none">
                            <button type="button" role="menuitem" (click)="chooseFromMenu(item, column.id, target)"
                              [class]="focus + ' block w-full rounded-lg bg-transparent px-3 py-1.5 text-left text-[12px] font-semibold !text-on-surface hover:bg-surface-container-high'">{{ titleOf(target) }}</button>
                          </li>
                        }
                      </ul>
                    }
                  </div>
                }
              </div>
            } @empty {
              <div class="flex flex-col items-center gap-1 py-8 text-center">
                @if (emptyImage() && !column.notice) {
                  <img [src]="emptyImage()" alt="" width="160" height="88" class="h-auto w-28 mix-blend-multiply" />
                }
                <p class="text-[12px] italic text-on-surface-variant">{{ column.notice ?? emptyText() }}</p>
              </div>
            }
            @if (column.total !== undefined && column.total > column.items.length) {
              <button type="button" (click)="loadMore.emit(column.id)" [disabled]="column.loading"
                [class]="focus + ' w-full rounded-lg border border-brand-accentDeep bg-transparent px-3 py-2 text-[12px] font-semibold !text-brand-accentDeep hover:bg-surface-container disabled:opacity-50'">
                {{ column.loading ? 'Cargando…' : 'Cargar más (' + (column.total - column.items.length) + ' restantes)' }}
              </button>
            }
          </div>
        </section>
      }
    </div>
    <p class="sr-only" role="status" aria-live="polite">{{ announcement() }}</p>
  `,
})
export class KanbanBoardComponent<T> {
  private readonly toasts = inject(ToastService);

  readonly columns = input.required<KanbanColumn<T>[]>();
  readonly key = input.required<(item: T) => string | number>();
  /** Texto corto del registro, para los lectores de pantalla (p. ej. su número de ticket). */
  readonly label = input<(item: T) => string>((item) => String(item));
  /** Columnas a las que esa tarjeta puede ir desde la suya (State Pattern del servidor). */
  readonly validTargets = input.required<(item: T, from: string) => string[]>();
  /** Ejecuta el movimiento; el tablero ya lo mostró y lo revierte si no sale bien. */
  readonly handler = input.required<(move: KanbanMove<T>) => Observable<KanbanOutcome>>();
  /** Mensaje cuando se suelta en una columna inválida; por defecto, uno genérico con los destinos permitidos. */
  readonly invalidMessage = input<((move: KanbanMove<T>, allowed: string[]) => string) | null>(null);
  readonly emptyText = input('Sin registros');
  /** Ilustración decorativa de las columnas vacías (opcional). */
  readonly emptyImage = input('');
  readonly ariaLabel = input('Tablero');
  readonly minColumnWidth = input(150);
  readonly disabled = input(false);
  /** Pide la siguiente página de una columna paginada (solo se ofrece si `total` supera lo cargado). */
  readonly loadMore = output<string>();

  @ContentChild(KanbanCardDirective) card?: KanbanCardDirective<T>;

  readonly focus = FOCUS;
  readonly menuFor = signal<string | number | null>(null);
  readonly announcement = signal('');
  readonly hover = signal<string | null>(null);
  private readonly dragging = signal<{ item: T; from: string } | null>(null);
  /** Colocación optimista: tarjeta → columna a la que se acaba de llevar, hasta que el servidor responda. */
  private readonly overrides = signal<Map<string | number, string>>(new Map());
  private readonly moving = signal<Set<string | number>>(new Set());

  /** Columnas tal como se ven: con las tarjetas movidas optimistamente ya en su destino. */
  readonly view = computed<KanbanColumn<T>[]>(() => {
    const overrides = this.overrides();
    const key = this.key();
    const columns = this.columns();
    if (overrides.size === 0) {
      return columns;
    }
    const byId = new Map(columns.map((c) => [c.id, [] as T[]]));
    const moved: [T, string][] = [];
    for (const column of columns) {
      for (const item of column.items) {
        const target = overrides.get(key(item));
        if (target && byId.has(target)) {
          moved.push([item, target]);
        } else {
          byId.get(column.id)!.push(item);
        }
      }
    }
    // Las tarjetas recién movidas quedan al final de su nueva columna.
    for (const [item, target] of moved) {
      byId.get(target)!.push(item);
    }
    return columns.map((c) => {
      const items = byId.get(c.id)!;
      return { ...c, items, total: c.total === undefined ? undefined : c.total + (items.length - c.items.length) };
    });
  });

  constructor() {
    // Cuando llegan datos nuevos del servidor, la verdad es la suya: se descarta la colocación optimista.
    effect(() => {
      this.columns();
      this.overrides.set(new Map());
    });
  }

  titleOf(columnId: string): string {
    return this.columns().find((c) => c.id === columnId)?.title ?? columnId;
  }

  targetsOf(item: T, from: string): string[] {
    const ids = new Set(this.columns().map((c) => c.id));
    return this.validTargets()(item, from).filter((id) => ids.has(id) && id !== from);
  }

  isMoving(item: T): boolean {
    return this.moving().has(this.key()(item));
  }

  canDrag(item: T, from: string): boolean {
    return !this.disabled() && !this.isMoving(item) && this.targetsOf(item, from).length > 0;
  }

  /** Aspecto de la columna según lo que se está arrastrando: destino válido, origen o no permitida. */
  columnClass(columnId: string): string {
    const drag = this.dragging();
    if (!drag) {
      return 'border-brand-grey/70';
    }
    if (columnId === drag.from) {
      return 'border-brand-grey/70';
    }
    if (this.targetsOf(drag.item, drag.from).includes(columnId)) {
      return this.hover() === columnId
        ? 'border-brand-accentDeep bg-brand-accentLight/50 ring-2 ring-brand-accentDeep/40'
        : 'border-brand-accentDeep/60 border-dashed bg-brand-accentLight/20';
    }
    return 'border-brand-grey/40 opacity-40';
  }

  onDragStart(event: DragEvent, item: T, from: string): void {
    if (!this.canDrag(item, from)) {
      event.preventDefault();
      return;
    }
    event.dataTransfer?.setData('text/plain', String(this.key()(item)));
    if (event.dataTransfer) {
      event.dataTransfer.effectAllowed = 'move';
    }
    this.menuFor.set(null);
    this.dragging.set({ item, from });
  }

  onDragEnd(): void {
    this.dragging.set(null);
    this.hover.set(null);
  }

  onDragOver(event: DragEvent, columnId: string): void {
    const drag = this.dragging();
    if (!drag) {
      return;
    }
    // Se acepta el drop en cualquier columna para poder explicar por qué una no sirve.
    event.preventDefault();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = this.targetsOf(drag.item, drag.from).includes(columnId) ? 'move' : 'none';
    }
    this.hover.set(columnId);
  }

  onDrop(event: DragEvent, to: string): void {
    event.preventDefault();
    const drag = this.dragging();
    this.onDragEnd();
    if (!drag || to === drag.from) {
      return;
    }
    const move: KanbanMove<T> = { item: drag.item, from: drag.from, to };
    const allowed = this.targetsOf(drag.item, drag.from);
    if (!allowed.includes(to)) {
      // La tarjeta no se movió: queda en su sitio y se explica por qué.
      this.toasts.error((this.invalidMessage() ?? this.defaultMessage)(move, allowed));
      return;
    }
    this.perform(move);
  }

  toggleMenu(item: T, event: Event): void {
    event.stopPropagation();
    const key = this.key()(item);
    this.menuFor.set(this.menuFor() === key ? null : key);
  }

  chooseFromMenu(item: T, from: string, to: string): void {
    this.menuFor.set(null);
    this.perform({ item, from, to });
  }

  private readonly defaultMessage = (move: KanbanMove<T>, allowed: string[]): string => {
    const list = allowed.map((id) => `«${this.titleOf(id)}»`).join(', ');
    return `No se puede pasar de «${this.titleOf(move.from)}» a «${this.titleOf(move.to)}».${list ? ` Desde ahí solo puede ir a ${list}.` : ' Ese estado es final.'}`;
  };

  private perform(move: KanbanMove<T>): void {
    const key = this.key()(move.item);
    if (this.moving().has(key)) {
      return;
    }
    this.moving.update((set) => new Set(set).add(key));
    this.overrides.update((map) => new Map(map).set(key, move.to));
    this.announcement.set(`Moviendo ${this.label()(move.item)} a ${this.titleOf(move.to)}…`);
    const settle = (): void => {
      this.moving.update((set) => {
        const next = new Set(set);
        next.delete(key);
        return next;
      });
    };
    const revert = (): void => this.overrides.update((map) => {
      const next = new Map(map);
      next.delete(key);
      return next;
    });
    this.handler()(move).subscribe({
      next: (outcome) => {
        settle();
        if (outcome.ok) {
          this.announcement.set(`${this.label()(move.item)} pasó a ${this.titleOf(move.to)}.`);
          return;
        }
        revert();
        this.announcement.set(`${this.label()(move.item)} volvió a ${this.titleOf(move.from)}.`);
        if (!outcome.cancelled) {
          this.toasts.error(outcome.message ?? 'No se pudo mover la tarjeta.');
        }
      },
      error: () => {
        settle();
        revert();
        this.toasts.error('No se pudo mover la tarjeta. Inténtalo de nuevo.');
      },
    });
  }
}
