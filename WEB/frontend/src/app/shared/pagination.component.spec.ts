import { Component, signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';

import { WCAG_AA, contrastRatio, flatten } from '../features/dashboard/contrast';
import { PaginationComponent } from './pagination.component';

@Component({
  standalone: true,
  imports: [PaginationComponent],
  template: `<div class="tw-reset"><app-pagination noun="tickets" [page]="page()" [pageSize]="10" [total]="total()" [hasNext]="hasNext()" [loading]="loading()" [filtered]="filtered()" (pageChange)="emitted.push($event)" /></div>`,
})
class HostComponent {
  readonly page = signal(1);
  readonly total = signal<number | null>(28);
  readonly hasNext = signal(false);
  readonly loading = signal(false);
  readonly filtered = signal(false);
  readonly emitted: number[] = [];
}

describe('PaginationComponent (shared by every list)', () => {
  let fixture: ComponentFixture<HostComponent>;
  let host: HostComponent;

  const root = () => fixture.nativeElement as HTMLElement;
  const render = () => fixture.detectChanges();
  const buttons = () => Array.from(root().querySelectorAll('button'));
  const named = (label: string) => root().querySelector(`button[aria-label="${label}"]`) as HTMLButtonElement | null;

  beforeEach(() => {
    fixture = TestBed.createComponent(HostComponent);
    host = fixture.componentInstance;
    render();
  });

  describe('with a known total', () => {
    it('hides «Anterior» on the first page and shows «Siguiente»', () => {
      expect(named('Página anterior')).toBeNull();
      expect(named('Página siguiente')).not.toBeNull();
      expect(root().textContent).toContain('Tickets 1–10 de 28');
    });

    it('hides «Siguiente» on the last page and shows «Anterior»', () => {
      host.page.set(3);
      render();
      expect(named('Página siguiente')).toBeNull();
      expect(named('Página anterior')).not.toBeNull();
      expect(root().textContent).toContain('Tickets 21–28 de 28');
    });

    it('shows both in the middle, with numbered pages and the current one marked', () => {
      host.page.set(2);
      render();
      expect(named('Página anterior')).not.toBeNull();
      expect(named('Página siguiente')).not.toBeNull();
      expect(named('Página 2')!.getAttribute('aria-current')).toBe('page');
      expect(named('Página 1')!.getAttribute('aria-current')).toBeNull();
    });

    it('emits the chosen page, previous and next', () => {
      host.page.set(2);
      render();
      named('Página anterior')!.click();
      named('Página siguiente')!.click();
      named('Página 3')!.click();
      expect(host.emitted).toEqual([1, 3, 3]);
    });

    it('does not emit for the current page', () => {
      named('Página 1')!.click();
      expect(host.emitted).toEqual([]);
    });

    it('shows only the summary with a single page, and says so when there are filters', () => {
      host.total.set(7);
      host.filtered.set(true);
      render();
      expect(buttons().length).toBe(0);
      expect(root().textContent).toContain('7 tickets con los filtros aplicados');
    });

    it('shows nothing without records', () => {
      host.total.set(0);
      render();
      expect(root().querySelector('nav')).toBeNull();
    });

    it('collapses long ranges with ellipses', () => {
      host.total.set(500);
      host.page.set(25);
      render();
      expect(root().textContent).toContain('…');
      expect(named('Página 25')!.getAttribute('aria-current')).toBe('page');
      expect(named('Página 50')).not.toBeNull();
    });

    it('disables every control while loading', () => {
      host.page.set(2);
      host.loading.set(true);
      render();
      expect(buttons().every((b) => b.disabled)).toBeTrue();
    });
  });

  describe('without a total (cursor lists)', () => {
    beforeEach(() => host.total.set(null));

    it('shows nothing when everything fits on the first page', () => {
      host.hasNext.set(false);
      render();
      expect(root().querySelector('nav')).toBeNull();
    });

    it('offers only «Siguiente» on page 1 when there is more', () => {
      host.hasNext.set(true);
      render();
      expect(named('Página anterior')).toBeNull();
      expect(named('Página siguiente')).not.toBeNull();
      expect(root().textContent).toContain('Página 1');
    });

    it('offers only «Anterior» on the last page', () => {
      host.page.set(4);
      host.hasNext.set(false);
      render();
      expect(named('Página anterior')).not.toBeNull();
      expect(named('Página siguiente')).toBeNull();
      expect(root().textContent).toContain('Página 4');
    });
  });

  it('keeps the buttons legible inside .tw-reset (AA, 4.5:1)', () => {
    host.page.set(2);
    render();
    for (const el of buttons()) {
      const style = getComputedStyle(el);
      const background = style.backgroundColor === 'rgba(0, 0, 0, 0)' ? '#ffffff' : flatten(style.backgroundColor, '#ffffff');
      expect(contrastRatio(flatten(style.color), background)).withContext(el.getAttribute('aria-label') ?? '').toBeGreaterThanOrEqual(WCAG_AA);
    }
  });
});
