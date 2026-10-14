import { fakeAsync, tick } from '@angular/core/testing';

import { ToastService } from './toast.service';

describe('ToastService', () => {
  it('shows a toast and removes it after its lifetime', fakeAsync(() => {
    const service = new ToastService();
    service.success('Guardado');
    expect(service.toasts().map((t) => t.message)).toEqual(['Guardado']);
    tick(4001);
    expect(service.toasts()).toEqual([]);
  }));

  it('keeps errors visible longer than successes', fakeAsync(() => {
    const service = new ToastService();
    service.error('Falló');
    tick(5000);
    expect(service.toasts().length).toBe(1);
    tick(2001);
    expect(service.toasts().length).toBe(0);
  }));

  it('does not stack identical messages and caps the stack', fakeAsync(() => {
    const service = new ToastService();
    service.error('Igual');
    service.error('Igual');
    expect(service.toasts().length).toBe(1);
    ['a', 'b', 'c', 'd', 'e'].forEach((m) => service.info(m));
    expect(service.toasts().length).toBeLessThanOrEqual(4);
    tick(8000);
  }));

  it('dismisses on demand', fakeAsync(() => {
    const service = new ToastService();
    service.info('x');
    service.dismiss(service.toasts()[0].id);
    expect(service.toasts()).toEqual([]);
    tick(5000);
  }));
});
