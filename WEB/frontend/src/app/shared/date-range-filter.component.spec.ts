import { Component, signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';

import { WCAG_AA, contrastRatio, flatten } from '../features/dashboard/contrast';
import { dayString } from './date-range';
import { DateRange, DateRangeFilterComponent } from './date-range-filter.component';

@Component({
  standalone: true,
  imports: [DateRangeFilterComponent],
  template: `<div class="tw-reset"><app-date-range-filter label="Recibidas entre" [from]="from()" [to]="to()" (rangeChange)="onChange($event)" /></div>`,
})
class HostComponent {
  readonly from = signal('');
  readonly to = signal('');
  readonly emitted: DateRange[] = [];
  onChange(range: DateRange): void {
    this.emitted.push(range);
    this.from.set(range.from);
    this.to.set(range.to);
  }
}

describe('DateRangeFilterComponent (shared by every filter by dates)', () => {
  let fixture: ComponentFixture<HostComponent>;
  let host: HostComponent;
  const root = () => fixture.nativeElement as HTMLElement;
  const render = () => fixture.detectChanges();
  const chip = (label: string) => Array.from(root().querySelectorAll('button')).find((b) => b.textContent?.trim() === label) as HTMLButtonElement;
  const input = (side: 'from' | 'to') => root().querySelector(`input[id$="-${side}"]`) as HTMLInputElement;
  const type = (side: 'from' | 'to', value: string) => {
    input(side).value = value;
    input(side).dispatchEvent(new Event('change'));
    render();
  };

  beforeEach(() => {
    fixture = TestBed.createComponent(HostComponent);
    host = fixture.componentInstance;
    render();
  });

  it('shows the label, the six shortcuts and "Todo" selected for an empty range', () => {
    expect(root().querySelector('legend')!.textContent).toContain('Recibidas entre');
    const labels = Array.from(root().querySelectorAll('button')).map((b) => b.textContent!.trim());
    expect(labels).toEqual(['Todo', 'Hoy', '7 días', '30 días', 'Este mes', 'Personalizado']);
    expect(chip('Todo').getAttribute('aria-pressed')).toBe('true');
  });

  it('applies a shortcut and marks it', () => {
    chip('Hoy').click();
    render();
    const today = dayString(new Date());
    expect(host.emitted.at(-1)).toEqual({ from: today, to: today });
    expect(input('from').value).toBe(today);
    expect(chip('Hoy').getAttribute('aria-pressed')).toBe('true');
    chip('Todo').click();
    render();
    expect(input('from').value).toBe('');
  });

  it('marks "Personalizado" when a date is typed, and keeps it while the range is still empty', () => {
    chip('Personalizado').click();
    render();
    expect(chip('Personalizado').getAttribute('aria-pressed')).toBe('true');
    type('from', '2026-01-05');
    expect(host.emitted.at(-1)).toEqual({ from: '2026-01-05', to: '' });
    expect(chip('Personalizado').getAttribute('aria-pressed')).toBe('true');
  });

  it('explains an inverted range under the fields', () => {
    type('from', '2026-09-10');
    type('to', '2026-09-01');
    expect(root().querySelector('[role="alert"]')!.textContent).toContain('La fecha final no puede ser anterior a la inicial.');
    expect(input('from').getAttribute('aria-invalid')).toBe('true');
    type('to', '2026-09-20');
    expect(root().querySelector('[role="alert"]')!.textContent!.trim()).toBe('');
  });

  it('explains a start in the future and a range over 366 days; the start picker cannot go past today', () => {
    type('from', '2999-01-01');
    expect(root().querySelector('[role="alert"]')!.textContent).toContain('no puede ser futura');
    expect(input('from').getAttribute('max')).toBe(dayString(new Date()));
    type('from', '2025-01-01');
    type('to', '2026-06-01');
    expect(root().querySelector('[role="alert"]')!.textContent).toContain('366 días');
  });

  it('has unique ids when there are several on one screen', () => {
    const other = TestBed.createComponent(HostComponent);
    other.detectChanges();
    expect(other.nativeElement.querySelector('input').id).not.toBe(input('from').id);
  });

  it('keeps the shortcuts legible inside .tw-reset (AA, 4.5:1)', () => {
    chip('7 días').click();
    render();
    for (const el of Array.from(root().querySelectorAll('button'))) {
      const style = getComputedStyle(el);
      const background = style.backgroundColor === 'rgba(0, 0, 0, 0)' ? '#ffffff' : flatten(style.backgroundColor, '#ffffff');
      expect(contrastRatio(flatten(style.color), background)).withContext(el.textContent ?? '').toBeGreaterThanOrEqual(WCAG_AA);
    }
  });
});
