import { HttpErrorResponse } from '@angular/common/http';
import { Component, signal } from '@angular/core';
import { ComponentFixture, TestBed } from '@angular/core/testing';
import { FormControl, ReactiveFormsModule } from '@angular/forms';
import { Observable, Subject, of, throwError } from 'rxjs';

import { WCAG_AA, contrastRatio, flatten } from '../features/dashboard/contrast';
import { CreatableSelectComponent, SelectOption, sameName } from './creatable-select.component';

@Component({
  standalone: true,
  imports: [CreatableSelectComponent, ReactiveFormsModule],
  template: `<div class="tw-reset">
    <app-creatable-select [formControl]="control" [options]="options()" [canCreate]="canCreate()" [create]="creator" createLabel="Agregar categoría"
      (created)="createdLog.push($event)" (valueChange)="valueLog.push($event)" />
  </div>`,
})
class HostComponent {
  readonly control = new FormControl<string | number | null>(null);
  readonly options = signal<SelectOption[]>([{ value: 'net', label: 'Redes' }, { value: 'hw', label: 'Hardware' }]);
  readonly canCreate = signal(true);
  readonly createdLog: SelectOption[] = [];
  readonly valueLog: (string | number | null)[] = [];
  creator: ((name: string) => Observable<SelectOption>) | null = (name) => of({ value: name.toLowerCase(), label: name });
}

describe('CreatableSelectComponent', () => {
  let fixture: ComponentFixture<HostComponent>;
  let host: HostComponent;

  const root = () => fixture.nativeElement as HTMLElement;
  const render = () => fixture.detectChanges();
  const select = () => root().querySelector('select') as HTMLSelectElement;
  const choose = (value: string) => {
    select().value = value;
    select().dispatchEvent(new Event('change'));
    render();
  };
  const draft = () => root().querySelector('input[type="text"]') as HTMLInputElement;
  const type = (value: string) => {
    draft().value = value;
    draft().dispatchEvent(new Event('input'));
    render();
  };
  const button = (text: string) => Array.from(root().querySelectorAll('button')).find((b) => b.textContent?.trim() === text) as HTMLButtonElement | undefined;
  const alertText = () => root().querySelector('[role="alert"]')!.textContent!.trim();
  const labels = () => Array.from(select().options).map((o) => o.textContent!.trim());

  beforeEach(() => {
    fixture = TestBed.createComponent(HostComponent);
    host = fixture.componentInstance;
    render();
  });

  it('lists the options and ends with «+ Agregar categoría»', () => {
    expect(labels()).toEqual(['Selecciona…', 'Redes', 'Hardware', '+ Agregar categoría']);
  });

  it('hides the add option when the role cannot create', () => {
    host.canCreate.set(false);
    render();
    expect(labels()).toEqual(['Selecciona…', 'Redes', 'Hardware']);
  });

  it('selects a normal option and tells the form', () => {
    choose('hw');
    expect(host.control.value).toBe('hw');
    expect(host.valueLog).toEqual(['hw']);
    choose('');
    expect(host.control.value).toBeNull();
  });

  it('shows the form value that was written from outside', () => {
    host.control.setValue('net');
    render();
    expect(select().value).toBe('net');
  });

  describe('adding a new value', () => {
    beforeEach(() => {
      choose('__new__');
    });

    it('swaps the select for a field with Guardar and Cancelar', () => {
      expect(root().querySelector('select')).toBeNull();
      expect(draft()).not.toBeNull();
      expect(button('Guardar')!.disabled).toBeTrue(); // empty
    });

    it('saves, lists it at once and leaves it selected, without a reload', () => {
      type('  Impresoras  ');
      button('Guardar')!.click();
      render();
      expect(labels()).toContain('Impresoras');
      expect(select().selectedOptions[0].textContent!.trim()).toBe('Impresoras');
      expect(host.control.value).toBe('impresoras');
      expect(host.createdLog).toEqual([{ value: 'impresoras', label: 'Impresoras' }]);
    });

    it('saves with Enter and cancels with Escape', () => {
      type('Cámaras');
      draft().dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
      render();
      expect(labels()).toContain('Cámaras');
      choose('__new__');
      draft().dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
      render();
      expect(root().querySelector('select')).not.toBeNull();
    });

    it('validates the length and says why under the field', () => {
      type('a');
      expect(alertText()).toBe('Debe tener al menos 2 caracteres.');
      expect(button('Guardar')!.disabled).toBeTrue();
      type('x'.repeat(101));
      expect(alertText()).toBe('Debe tener como máximo 100 caracteres.');
      type('   ');
      expect(alertText()).toBe('Escribe el nombre.');
    });

    it('does not duplicate: a name that exists (any case, accents, spaces) selects the existing one', () => {
      let calls = 0;
      host.creator = () => {
        calls++;
        return of({ value: 'x', label: 'x' });
      };
      render();
      type('  REDES ');
      button('Guardar')!.click();
      render();
      expect(calls).toBe(0);
      expect(host.control.value).toBe('net');
      expect(labels().filter((l) => l === 'Redes').length).toBe(1);
    });

    it('also treats a value created a moment ago as existing', () => {
      type('Impresoras');
      button('Guardar')!.click();
      render();
      choose('__new__');
      type('impresoras');
      button('Guardar')!.click();
      render();
      expect(host.createdLog.length).toBe(1);
      expect(labels().filter((l) => l === 'Impresoras').length).toBe(1);
    });

    it('blocks a second click while saving', () => {
      const gate = new Subject<SelectOption>();
      let calls = 0;
      host.creator = () => {
        calls++;
        return gate;
      };
      render();
      type('Impresoras');
      button('Guardar')!.click();
      render();
      expect(button('Guardando…')!.disabled).toBeTrue();
      expect(draft().disabled).toBeTrue();
      button('Guardando…')!.click();
      expect(calls).toBe(1);
      gate.next({ value: 'p', label: 'Impresoras' });
      gate.complete();
      render();
      expect(host.createdLog.length).toBe(1);
    });

    it('keeps the field and explains a server rejection in Spanish', () => {
      host.creator = () => throwError(() => new HttpErrorResponse({ status: 409, error: { code: 'conflict', detail: "category 'x' already exists" } }));
      render();
      type('Impresoras');
      button('Guardar')!.click();
      render();
      expect(alertText()).toBe('Ya existe un registro con ese identificador.');
      expect(draft()).not.toBeNull();
      expect(host.createdLog).toEqual([]);
      expect(button('Guardar')!.disabled).toBeFalse(); // can retry
    });

    it('goes back to the select on Cancelar, keeping what was chosen before', () => {
      button('Cancelar')!.click();
      render();
      expect(root().querySelector('select')).not.toBeNull();
      expect(host.control.value).toBeNull();
    });
  });

  it('does nothing without a creator', () => {
    host.creator = null;
    render();
    choose('__new__');
    type('Impresoras');
    button('Guardar')!.click();
    render();
    expect(host.createdLog).toEqual([]);
  });

  it('can be disabled with the form', () => {
    host.control.disable();
    render();
    expect(select().disabled).toBeTrue();
  });

  it('compares names without case, accents or extra spaces', () => {
    expect(sameName('Cámaras', '  camaras ')).toBeTrue();
    expect(sameName('Redes  y   Comunicación', 'redes y comunicacion')).toBeTrue();
    expect(sameName('Redes', 'Red')).toBeFalse();
  });

  it('keeps the save button legible inside .tw-reset (AA, 4.5:1)', () => {
    choose('__new__');
    type('Impresoras');
    const el = button('Guardar')!;
    const style = getComputedStyle(el);
    const background = style.backgroundColor === 'rgba(0, 0, 0, 0)' ? '#ffffff' : flatten(style.backgroundColor, '#ffffff');
    expect(contrastRatio(flatten(style.color), background)).toBeGreaterThanOrEqual(WCAG_AA);
  });
});
