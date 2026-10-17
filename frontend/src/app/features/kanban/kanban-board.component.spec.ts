import { Component, signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { Subject } from 'rxjs';

import { ToastService } from '../../core/toast.service';
import { KanbanBoardComponent, KanbanCardDirective, KanbanColumn, KanbanMove, KanbanOutcome } from './kanban-board.component';

interface Card {
  id: number;
  name: string;
}

const NEXT: Record<string, string[]> = { a: ['b', 'c'], b: ['c'], c: [] };

@Component({
  standalone: true,
  imports: [KanbanBoardComponent, KanbanCardDirective],
  template: `<div class="tw-reset"><app-kanban-board ariaLabel="Tablero de prueba" [columns]="columns()" [key]="key" [label]="label" [validTargets]="valid"
    [handler]="handler" [disabled]="disabled()" emptyText="Nada aquí">
    <ng-template appKanbanCard let-item><article class="card">{{ item.name }}</article></ng-template>
  </app-kanban-board></div>`,
})
class HostComponent {
  readonly columns = signal<KanbanColumn<Card>[]>([]);
  readonly disabled = signal(false);
  readonly moves: KanbanMove<Card>[] = [];
  pending = new Subject<KanbanOutcome>();
  readonly key = (c: Card) => c.id;
  readonly label = (c: Card) => c.name;
  readonly valid = (_item: Card, from: string) => NEXT[from] ?? [];
  readonly handler = (move: KanbanMove<Card>) => {
    this.moves.push(move);
    return this.pending;
  };
}

function columns(): KanbanColumn<Card>[] {
  return [
    { id: 'a', title: 'Pendiente', items: [{ id: 1, name: 'T-1' }, { id: 2, name: 'T-2' }] },
    { id: 'b', title: 'Clasificada', items: [{ id: 3, name: 'T-3' }], total: 7 },
    { id: 'c', title: 'Asignada', items: [] },
  ];
}

describe('KanbanBoardComponent', () => {
  let fixture: ComponentFixture<HostComponent>;
  let host: HostComponent;
  let toasts: ToastService;

  const root = () => fixture.nativeElement as HTMLElement;
  const render = () => fixture.detectChanges();
  const column = (id: string) => root().querySelector(`section[data-column="${id}"]`) as HTMLElement;
  const cardsOf = (id: string) => Array.from(column(id).querySelectorAll('.card')).map((c) => c.textContent!.trim());
  const wrapper = (name: string) =>
    Array.from(root().querySelectorAll<HTMLElement>('[draggable]')).find((el) => el.textContent?.includes(name))!;
  const drag = (type: string, target: HTMLElement, transfer = new DataTransfer()) => {
    const event = new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: transfer });
    target.dispatchEvent(event);
    render();
    return event;
  };
  const dragAndDrop = (name: string, to: string) => {
    const transfer = new DataTransfer();
    drag('dragstart', wrapper(name), transfer);
    const over = drag('dragover', column(to), transfer);
    drag('drop', column(to), transfer);
    return over;
  };
  const toastMessages = () => toasts.toasts().map((t) => t.message);

  beforeEach(() => {
    fixture = TestBed.createComponent(HostComponent);
    host = fixture.componentInstance;
    toasts = TestBed.inject(ToastService);
    host.columns.set(columns());
    render();
  });

  describe('layout', () => {
    it('draws one column per state with its counter (the real total when paginated)', () => {
      expect(root().querySelectorAll('section[data-column]').length).toBe(3);
      expect(column('a').textContent).toContain('Pendiente');
      expect(column('a').querySelector('header > span:last-child')!.textContent!.trim()).toBe('2');
      expect(column('b').querySelector('header > span:last-child')!.textContent!.trim()).toBe('7');
      expect(cardsOf('a')).toEqual(['T-1', 'T-2']);
    });

    it('says when a column is empty', () => {
      expect(column('c').textContent).toContain('Nada aquí');
    });

    it('fits the columns to the width with a grid that wraps instead of scrolling sideways', () => {
      const grid = root().querySelector('[role="group"]') as HTMLElement;
      expect(grid.style.gridTemplateColumns).toContain('auto-fit');
      expect(grid.className).not.toContain('overflow-x');
    });

    it('only lets a card be dragged if it has somewhere to go', () => {
      expect(wrapper('T-1').getAttribute('draggable')).toBe('true');
      expect(wrapper('T-3').getAttribute('draggable')).toBe('true');
      host.disabled.set(true);
      render();
      expect(wrapper('T-1').getAttribute('draggable')).toBe('false');
    });
  });

  describe('dragging', () => {
    it('highlights valid destinations and dims the others while dragging', () => {
      drag('dragstart', wrapper('T-3'));
      expect(column('c').className).toContain('border-dashed'); // b → c is valid
      expect(column('a').className).toContain('opacity-40'); // b → a is not
      expect(column('b').className).not.toContain('opacity-40'); // its own column
      drag('dragend', wrapper('T-3'));
      expect(column('a').className).not.toContain('opacity-40');
    });

    it('accepts the drop on a valid column and on an invalid one (to explain it)', () => {
      const transfer = new DataTransfer();
      drag('dragstart', wrapper('T-3'), transfer);
      expect(drag('dragover', column('c'), transfer).defaultPrevented).toBeTrue();
      expect(drag('dragover', column('a'), transfer).defaultPrevented).toBeTrue();
      expect(transfer.dropEffect).toBe('none');
    });
  });

  describe('moving to a valid column', () => {
    it('shows the card in its destination at once, before the server answers', () => {
      dragAndDrop('T-1', 'b');
      expect(host.moves.length).toBe(1);
      expect(host.moves[0]).toEqual(jasmine.objectContaining({ from: 'a', to: 'b' }));
      expect(cardsOf('a')).toEqual(['T-2']);
      expect(cardsOf('b')).toEqual(['T-3', 'T-1']);
      expect(column('b').querySelector('header > span:last-child')!.textContent!.trim()).toBe('8'); // 7 + 1
      expect(column('a').querySelector('header > span:last-child')!.textContent!.trim()).toBe('1');
    });

    it('keeps it there when the server accepts, until fresh data arrives', () => {
      dragAndDrop('T-1', 'b');
      host.pending.next({ ok: true });
      host.pending.complete();
      render();
      expect(cardsOf('b')).toContain('T-1');
      host.columns.set([
        { id: 'a', title: 'Pendiente', items: [{ id: 2, name: 'T-2' }] },
        { id: 'b', title: 'Clasificada', items: [{ id: 3, name: 'T-3' }, { id: 1, name: 'T-1' }], total: 8 },
        { id: 'c', title: 'Asignada', items: [] },
      ]);
      render();
      expect(cardsOf('b')).toEqual(['T-3', 'T-1']);
      expect(cardsOf('a')).toEqual(['T-2']);
    });

    it('puts the card back and shows the server message when it rejects the move', () => {
      dragAndDrop('T-1', 'c');
      expect(cardsOf('c')).toEqual(['T-1']);
      host.pending.next({ ok: false, message: 'Ese cambio de estado no está permitido desde el estado actual.' });
      host.pending.complete();
      render();
      expect(cardsOf('a')).toEqual(['T-1', 'T-2']);
      expect(cardsOf('c')).toEqual([]);
      expect(toastMessages()).toContain('Ese cambio de estado no está permitido desde el estado actual.');
    });

    it('puts the card back silently when the person cancels the dialog', () => {
      dragAndDrop('T-1', 'b');
      host.pending.next({ ok: false, cancelled: true });
      host.pending.complete();
      render();
      expect(cardsOf('a')).toEqual(['T-1', 'T-2']);
      expect(toastMessages()).toEqual([]);
    });

    it('puts the card back when the request fails outright', () => {
      dragAndDrop('T-1', 'b');
      host.pending.error(new Error('offline'));
      render();
      expect(cardsOf('a')).toEqual(['T-1', 'T-2']);
      expect(toastMessages().join(' ')).toContain('No se pudo mover la tarjeta');
    });

    it('does not let the same card be moved twice while it is in flight', () => {
      dragAndDrop('T-1', 'b');
      expect(wrapper('T-1').getAttribute('draggable')).toBe('false');
      dragAndDrop('T-1', 'c');
      expect(host.moves.length).toBe(1);
    });

    it('moves the card back to where the server data says if a refresh arrives mid-flight', () => {
      dragAndDrop('T-1', 'b');
      host.columns.set(columns()); // a refresh with the same data
      render();
      expect(cardsOf('a')).toEqual(['T-1', 'T-2']);
    });
  });

  describe('dropping on an invalid column', () => {
    it('leaves the card where it was and explains the rule in Spanish', () => {
      dragAndDrop('T-3', 'a');
      expect(host.moves.length).toBe(0);
      expect(cardsOf('b')).toEqual(['T-3']);
      const [message] = toastMessages();
      expect(message).toContain('No se puede pasar de «Clasificada» a «Pendiente»');
      expect(message).toContain('Desde ahí solo puede ir a «Asignada»');
    });

    it('says a final state is final', () => {
      host.columns.set([
        { id: 'a', title: 'Pendiente', items: [] },
        { id: 'b', title: 'Clasificada', items: [] },
        { id: 'c', title: 'Asignada', items: [{ id: 9, name: 'T-9' }] },
      ]);
      render();
      expect(wrapper('T-9').getAttribute('draggable')).toBe('false'); // no valid target: not even draggable
    });

    it('ignores a drop on its own column', () => {
      dragAndDrop('T-1', 'a');
      expect(host.moves.length).toBe(0);
      expect(toastMessages()).toEqual([]);
    });
  });

  describe('«Mover a…» menu (keyboard alternative)', () => {
    const menuButton = (name: string) => wrapper(name).querySelector('button[aria-haspopup="menu"]') as HTMLButtonElement;

    it('lists only the valid destinations with their titles', () => {
      menuButton('T-1').click();
      render();
      const items = Array.from(root().querySelectorAll('[role="menuitem"]')).map((b) => b.textContent!.trim());
      expect(items).toEqual(['Clasificada', 'Asignada']);
      expect(menuButton('T-1').getAttribute('aria-expanded')).toBe('true');
    });

    it('moves with the same optimistic flow as dragging', () => {
      menuButton('T-1').click();
      render();
      (root().querySelectorAll('[role="menuitem"]')[1] as HTMLElement).click();
      render();
      expect(host.moves[0]).toEqual(jasmine.objectContaining({ from: 'a', to: 'c' }));
      expect(cardsOf('c')).toEqual(['T-1']);
      host.pending.next({ ok: false, cancelled: true });
      render();
      expect(cardsOf('a')).toContain('T-1');
    });

    it('closes with Escape and is announced for screen readers', () => {
      menuButton('T-1').click();
      render();
      root().querySelector('[role="menu"]')!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
      render();
      expect(root().querySelector('[role="menu"]')).toBeNull();
      menuButton('T-1').click();
      render();
      (root().querySelector('[role="menuitem"]') as HTMLElement).click();
      render();
      expect(root().querySelector('[role="status"]')!.textContent).toContain('Moviendo T-1 a Clasificada');
    });

    it('has a labelled button per card', () => {
      expect(menuButton('T-1').getAttribute('aria-label')).toBe('Mover a… (T-1)');
    });
  });
});
