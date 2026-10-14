import { Injectable, signal } from '@angular/core';

export type ToastKind = 'success' | 'error' | 'info';

export interface Toast {
  id: number;
  kind: ToastKind;
  message: string;
}

const LIFETIME_MS: Record<ToastKind, number> = { success: 4000, info: 4000, error: 7000 };

/** Avisos efímeros consistentes para éxito y error; los pinta `<app-toast-host>`. */
@Injectable({ providedIn: 'root' })
export class ToastService {
  private nextId = 1;
  private readonly timers = new Map<number, ReturnType<typeof setTimeout>>();
  readonly toasts = signal<Toast[]>([]);

  success(message: string): void {
    this.push('success', message);
  }

  error(message: string): void {
    this.push('error', message);
  }

  info(message: string): void {
    this.push('info', message);
  }

  dismiss(id: number): void {
    clearTimeout(this.timers.get(id));
    this.timers.delete(id);
    this.toasts.update((list) => list.filter((toast) => toast.id !== id));
  }

  private push(kind: ToastKind, message: string): void {
    const id = this.nextId++;
    // Un mensaje igual ya visible no se duplica: se reemplaza para reiniciar su temporizador.
    const duplicate = this.toasts().find((toast) => toast.kind === kind && toast.message === message);
    if (duplicate) {
      this.dismiss(duplicate.id);
    }
    this.toasts.update((list) => [...list.slice(-3), { id, kind, message }]);
    this.timers.set(id, setTimeout(() => this.dismiss(id), LIFETIME_MS[kind]));
  }
}
