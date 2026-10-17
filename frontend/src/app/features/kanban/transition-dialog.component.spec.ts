import { Component, signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';

import { Technician } from '../../core/technicians.service';
import { Requirement, TransitionData } from '../../core/workflow.service';
import { WCAG_AA, contrastRatio, flatten } from '../dashboard/contrast';
import { TransitionDialogComponent } from './transition-dialog.component';

const technicians = [
  { id: 4, full_name: 'Luis Gómez', is_available: true },
  { id: 5, full_name: 'Marta Ruiz', is_available: false },
] as Technician[];

@Component({
  standalone: true,
  imports: [TransitionDialogComponent],
  template: `<div class="tw-reset"><app-transition-dialog title="Asignar técnico" subtitle="T-1 pasará a «Asignada»." confirmLabel="Asignar"
    [requires]="requires()" [categories]="[{ value: 'net', label: 'Redes' }]" [priorities]="[{ value: 'high', label: 'Alta' }]"
    [technicians]="technicians" [initial]="initial()" [busy]="busy()" (confirmed)="confirmed.push($event)" (cancelled)="cancelled = cancelled + 1" /></div>`,
})
class HostComponent {
  readonly requires = signal<Requirement[]>(['technician']);
  readonly initial = signal<TransitionData>({});
  readonly busy = signal(false);
  readonly technicians = technicians;
  readonly confirmed: TransitionData[] = [];
  cancelled = 0;
}

describe('TransitionDialogComponent', () => {
  let fixture: ComponentFixture<HostComponent>;
  let host: HostComponent;
  const root = () => fixture.nativeElement as HTMLElement;
  const render = () => fixture.detectChanges();
  const field = (id: string) => root().querySelector(`#${id}`) as HTMLInputElement;
  const set = (id: string, value: string) => {
    field(id).value = value;
    field(id).dispatchEvent(new Event(field(id).tagName === 'SELECT' ? 'change' : 'input'));
    render();
  };
  const submit = () => root().querySelector('button[type="submit"]') as HTMLButtonElement;

  function create(requires: Requirement[], initial: TransitionData = {}) {
    fixture = TestBed.createComponent(HostComponent);
    host = fixture.componentInstance;
    host.requires.set(requires);
    host.initial.set(initial);
    document.body.appendChild(root());
    render();
  }

  afterEach(() => root().remove());

  it('asks only for what the step needs', () => {
    create(['technician']);
    expect(field('td-technician')).not.toBeNull();
    for (const id of ['td-category', 'td-priority', 'td-summary', 'td-reason']) {
      expect(field(id)).withContext(id).toBeNull();
    }
    expect(root().querySelector('[role="dialog"]')!.getAttribute('aria-modal')).toBe('true');
    expect(root().textContent).toContain('T-1 pasará a «Asignada».');
  });

  it('shows category and priority together for a classification, starting from the ticket\'s own values', () => {
    create(['category', 'priority'], { category: 'net', priority: 'high' });
    expect(field('td-category').value).toBe('net');
    expect(field('td-priority').value).toBe('high');
    expect(submit().disabled).toBeFalse();
    set('td-category', '');
    expect(submit().disabled).toBeTrue();
  });

  describe('technician', () => {
    beforeEach(() => create(['technician']));

    it('is required and blocks the confirm until chosen', () => {
      expect(submit().disabled).toBeTrue();
      submit().click();
      expect(host.confirmed).toEqual([]);
    });

    it('does not offer a technician who is not available', () => {
      const options = Array.from((field('td-technician') as unknown as HTMLSelectElement).options);
      const unavailable = options.find((o) => o.textContent!.includes('Marta Ruiz'))!;
      expect(unavailable.disabled).toBeTrue();
      expect(unavailable.textContent).toContain('(no disponible)');
    });

    it('confirms with the technician id as a number', () => {
      set('td-technician', '4');
      expect(submit().disabled).toBeFalse();
      submit().click();
      expect(host.confirmed).toEqual([{ technicianId: 4 }]);
    });
  });

  describe('free text', () => {
    it('requires a resolution summary of 5 to 1000 characters, trimmed', () => {
      create(['resolution_summary']);
      expect(submit().disabled).toBeTrue();
      set('td-summary', '   abc  ');
      expect(root().textContent).toContain('al menos 5 caracteres');
      expect(submit().disabled).toBeTrue();
      set('td-summary', '  Se reemplazó el SSD y se reinstaló el sistema.  ');
      expect(submit().disabled).toBeFalse();
      submit().click();
      expect(host.confirmed).toEqual([{ resolutionSummary: 'Se reemplazó el SSD y se reinstaló el sistema.' }]);
      set('td-summary', 'x'.repeat(1001));
      expect(submit().disabled).toBeTrue();
    });

    it('requires a reason of 5 to 500 characters for a cancellation', () => {
      create(['reason']);
      set('td-reason', 'no');
      expect(submit().disabled).toBeTrue();
      set('td-reason', 'Duplicado del TCK-1');
      submit().click();
      expect(host.confirmed).toEqual([{ reason: 'Duplicado del TCK-1' }]);
      set('td-reason', 'x'.repeat(501));
      expect(submit().disabled).toBeTrue();
    });
  });

  it('cancels with the button, Escape and a click outside, but not while saving', () => {
    create(['technician']);
    (Array.from(root().querySelectorAll('button')).find((b) => b.textContent?.trim() === 'Cancelar') as HTMLButtonElement).click();
    root().querySelector('app-transition-dialog')!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    (root().querySelector('[aria-hidden="true"]') as HTMLElement).click();
    expect(host.cancelled).toBe(3);
    host.busy.set(true);
    render();
    (root().querySelector('[aria-hidden="true"]') as HTMLElement).click();
    expect(host.cancelled).toBe(3);
    expect(submit().textContent).toContain('Guardando…');
    expect(submit().disabled).toBeTrue();
  });

  it('focuses the first field and stays legible inside .tw-reset (AA, 4.5:1)', async () => {
    create(['technician']);
    await fixture.whenStable();
    expect(document.activeElement).toBe(field('td-technician'));
    set('td-technician', '4');
    const style = getComputedStyle(submit());
    const background = style.backgroundColor === 'rgba(0, 0, 0, 0)' ? '#ffffff' : flatten(style.backgroundColor, '#ffffff');
    expect(contrastRatio(flatten(style.color), background)).toBeGreaterThanOrEqual(WCAG_AA);
  });
});
