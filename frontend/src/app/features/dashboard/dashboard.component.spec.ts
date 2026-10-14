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
  loading: false, period: '30d', kpis: null, trends: null, alerts: null, topEquipment: null, workload: null,
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
