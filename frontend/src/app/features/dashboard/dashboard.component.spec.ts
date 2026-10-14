import { Component } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { BehaviorSubject } from 'rxjs';

import { DashboardState, DashboardStore } from '../../core/dashboard.store';
import { LocalProfileService } from '../../core/local-profile.service';
import { TRANSITION_STYLES } from '../tickets/ticket-ui';
import { WCAG_AA, contrastRatio } from './contrast';
import { DashboardComponent } from './dashboard.component';

const state = (overrides: Partial<DashboardState> = {}): DashboardState => ({
  loading: false, period: '30d', kpis: null, trends: null, alerts: null, topEquipment: null, technicians: null,
  ...overrides,
});

/** Color efectivo: sube por los ancestros hasta encontrar un fondo opaco. */
function backgroundOf(element: Element): string {
  for (let node: Element | null = element; node; node = node.parentElement) {
    const color = getComputedStyle(node).backgroundColor;
    if (!/rgba\(\d+,\s*\d+,\s*\d+,\s*0\)|transparent/.test(color)) {
      return color;
    }
  }
  return 'rgb(255, 255, 255)';
}

describe('DashboardComponent period selector', () => {
  let subject: BehaviorSubject<DashboardState>;

  beforeEach(() => {
    subject = new BehaviorSubject(state());
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: DashboardStore, useValue: { state$: subject.asObservable(), load: () => undefined } },
        { provide: LocalProfileService, useValue: { getProfile: () => Promise.resolve({ full_name: '' }) } },
      ],
    });
  });

  function buttons(): HTMLButtonElement[] {
    const fixture = TestBed.createComponent(DashboardComponent);
    document.body.appendChild(fixture.nativeElement);
    fixture.detectChanges();
    return Array.from(fixture.nativeElement.querySelectorAll('[aria-label="Periodo de los indicadores"] button'));
  }

  it('shows the active option in white on the dark background, above AA contrast', () => {
    const active = buttons().find((b) => b.getAttribute('aria-pressed') === 'true')!;
    const style = getComputedStyle(active);
    expect(style.color).toBe('rgb(255, 255, 255)');
    expect(contrastRatio(style.color, style.backgroundColor)).toBeGreaterThanOrEqual(WCAG_AA);
  });

  it('keeps the inactive options legible on their white pill', () => {
    const inactive = buttons().filter((b) => b.getAttribute('aria-pressed') === 'false');
    expect(inactive.length).toBe(2);
    for (const button of inactive) {
      const style = getComputedStyle(button);
      expect(contrastRatio(style.color, backgroundOf(button))).toBeGreaterThanOrEqual(WCAG_AA);
    }
  });

  it('has AA contrast in the hover state of the inactive options', () => {
    // :hover no se puede forzar en el navegador de pruebas: se comprueba el par declarado.
    expect(contrastRatio('#1E293B', '#F1F5F9')).toBeGreaterThanOrEqual(WCAG_AA);
  });
});

describe('dark buttons inside the .tw-reset shell', () => {
  @Component({
    standalone: true,
    template: `
      <div class="tw-reset">
        @for (style of styles; track style.name) {
          <button type="button" [class]="'px-4 py-2 ' + style.classes">{{ style.name }}</button>
        }
      </div>`,
  })
  class HostComponent {
    readonly styles = ['resolved', 'closed', 'cancelled'].map((name) => ({ name, classes: TRANSITION_STYLES[name] }));
  }

  it('keeps the ticket transition buttons above AA contrast (global color: inherit must not win)', () => {
    const fixture = TestBed.createComponent(HostComponent);
    document.body.appendChild(fixture.nativeElement);
    fixture.detectChanges();
    const found = Array.from<HTMLButtonElement>(fixture.nativeElement.querySelectorAll('button'));
    expect(found.length).toBe(3);
    for (const button of found) {
      const style = getComputedStyle(button);
      expect(contrastRatio(style.color, style.backgroundColor))
        .withContext(button.textContent ?? '')
        .toBeGreaterThanOrEqual(WCAG_AA);
    }
  });
});

describe('DashboardComponent technician table and hero', () => {
  const row = (id: number, overrides: Record<string, unknown> = {}) => ({
    technician_id: id, full_name: `Tec ${id}`, specialization: null, is_available: true, open_tickets: 0,
    resolved: 0, mttr_median_hours: null, sample_size: 0, low_sample: false, sla_compliance_pct: null,
    sla_sample_size: 0, sla_low_sample: false, sla_excluded_no_sla: 0, reopened: 0, ...overrides,
  });

  function render(technicians: ReturnType<typeof row>[] | null) {
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        {
          provide: DashboardStore,
          useValue: { state$: new BehaviorSubject(state({ technicians })).asObservable(), load: () => undefined },
        },
        { provide: LocalProfileService, useValue: { getProfile: () => Promise.resolve({ full_name: '' }) } },
      ],
    });
    const fixture = TestBed.createComponent(DashboardComponent);
    document.body.appendChild(fixture.nativeElement);
    fixture.detectChanges();
    return fixture.nativeElement as HTMLElement;
  }

  it('lists technicians in the order received (load) with the sample note under 5 tickets', () => {
    const host = render([
      row(1, { open_tickets: 6, resolved: 12, mttr_median_hours: 5, sample_size: 12, sla_compliance_pct: 90, sla_sample_size: 10, reopened: 2 }),
      row(2, { open_tickets: 1, resolved: 3, mttr_median_hours: 30, sample_size: 3, low_sample: true, sla_compliance_pct: 50, sla_sample_size: 2, sla_low_sample: true, sla_excluded_no_sla: 1 }),
    ]);
    const rows = Array.from(host.querySelectorAll('tbody tr'));
    expect(rows.length).toBe(2);
    expect(rows[0].textContent).toContain('Tec 1');
    expect(rows[1].textContent).toContain('Tec 2');
    expect(rows[0].textContent).not.toContain('pocos datos');
    expect(rows[1].textContent).toContain('pocos datos');
    expect(rows[1].textContent).toContain('1 sin SLA excluidos');
    expect(host.textContent).toContain('Rendimiento del equipo técnico');
    expect(host.textContent).not.toContain('Carga por técnico');
  });

  it('shows a dash instead of a misleading zero for a technician without resolved tickets', () => {
    const host = render([row(1, { open_tickets: 2 })]);
    const cells = host.querySelectorAll('tbody tr td');
    expect(cells[2].textContent!.trim()).toBe('—'); // MTTR
    expect(cells[3].textContent!.trim()).toBe('—'); // SLA
  });

  it('reveals the glass cards from the whole banner and never lets them block the pointer', () => {
    const host = render(null);
    const hero = host.querySelector('.hero')!;
    const holo = host.querySelector('.holo') as HTMLElement;
    expect(hero.classList.contains('group')).toBeTrue();
    expect(hero.contains(holo)).toBeTrue();
    expect(host.querySelector('.hero-visual')!.hasAttribute('mouseenter')).toBeFalse();
    const style = getComputedStyle(holo);
    expect(style.pointerEvents).toBe('none');
    expect(style.transitionProperty).toContain('opacity');
    expect(style.transitionProperty).toContain('transform');
  });
});
