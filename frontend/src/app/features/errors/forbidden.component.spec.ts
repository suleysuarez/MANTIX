import { TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';

import { ForbiddenComponent } from './forbidden.component';

describe('ForbiddenComponent', () => {
  it('explains the 403 and offers a way back', () => {
    TestBed.configureTestingModule({ providers: [provideRouter([])] });
    const fixture = TestBed.createComponent(ForbiddenComponent);
    fixture.detectChanges();
    const root = fixture.nativeElement as HTMLElement;
    expect(root.querySelector('[role="alert"]')!.textContent).toContain('No tienes permiso para ver esta pantalla');
    expect(root.textContent).toContain('Error 403');
    expect(root.querySelector('a')!.getAttribute('href')).toBe('/dashboard');
  });
});
