import { Location } from '@angular/common';
import { TestBed } from '@angular/core/testing';
import { ActivatedRoute, Router, convertToParamMap, provideRouter } from '@angular/router';
import { of } from 'rxjs';

import { ForbiddenComponent } from './forbidden.component';

describe('ForbiddenComponent', () => {
  function render(params: Record<string, string> = {}) {
    TestBed.configureTestingModule({
      providers: [
        provideRouter([]),
        { provide: ActivatedRoute, useValue: { queryParamMap: of(convertToParamMap(params)) } },
      ],
    });
    const fixture = TestBed.createComponent(ForbiddenComponent);
    fixture.detectChanges();
    return fixture;
  }

  it('is a friendly screen with an illustration, not a blank page', () => {
    const root = render().nativeElement as HTMLElement;
    expect(root.querySelector('svg[role="img"]')).not.toBeNull();
    expect(root.querySelector('[role="alert"]')).not.toBeNull();
    expect(root.textContent).toContain('No tienes permiso para ver esta pantalla');
    expect(root.textContent).toContain('Error 403');
    const buttons = Array.from(root.querySelectorAll('button, a')).map((el) => el.textContent!.trim());
    expect(buttons).toEqual(['Volver', 'Ir al dashboard']);
    expect(root.querySelector('a')!.getAttribute('href')).toBe('/dashboard');
  });

  it('says which permission was missing when the guard sends it', () => {
    const root = render({ requiere: 'usuarios:ver' }).nativeElement as HTMLElement;
    expect(root.textContent).toContain('Hace falta el permiso: Usuarios · ver');
  });

  it('does not invent a permission when none is given', () => {
    const root = render().nativeElement as HTMLElement;
    expect(root.textContent).not.toContain('Hace falta el permiso');
  });

  it('goes back to where the person was', () => {
    const fixture = render();
    const location = TestBed.inject(Location);
    spyOn(location, 'back');
    spyOn(fixture.componentInstance, 'canGoBack').and.returnValue(true);

    (fixture.nativeElement.querySelector('button') as HTMLButtonElement).click();

    expect(location.back).toHaveBeenCalled();
  });

  it('without history (a direct link) it goes to the dashboard instead of leaving the app', () => {
    const fixture = render();
    const router = TestBed.inject(Router);
    spyOn(router, 'navigateByUrl').and.resolveTo(true);
    spyOn(fixture.componentInstance, 'canGoBack').and.returnValue(false);

    (fixture.nativeElement.querySelector('button') as HTMLButtonElement).click();

    expect(router.navigateByUrl).toHaveBeenCalledWith('/dashboard');
  });
});
