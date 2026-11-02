import { Injectable, computed, inject, signal } from '@angular/core';

import { ClerkService } from './clerk.service';
import { LocalProfileService } from './local-profile.service';

/** Una sesión que se renueva cada minuto no debe pedir los permisos cada vez: como máximo uno por intervalo. */
const REFRESH_EVERY_MS = 60_000;

/**
 * Único lugar donde el frontend pregunta qué puede hacer la persona. Los permisos efectivos (los
 * propios de sus roles más los heredados) los calcula y entrega el servidor en `/auth/me`; aquí solo se
 * leen. Se vuelven a pedir al cambiar el rol de la persona y al renovarse la sesión. Ocultar o
 * deshabilitar con esto es comodidad: la barrera real es el backend, que vuelve a comprobarlo todo.
 */
@Injectable({ providedIn: 'root' })
export class PermissionsService {
  private readonly profile = inject(LocalProfileService);
  private readonly clerk = inject(ClerkService);
  private lastLoad = 0;
  private watching = false;

  private readonly granted = signal<ReadonlySet<string>>(new Set());
  private readonly roleCodes = signal<readonly string[]>([]);
  /** `true` cuando ya se leyeron (con éxito o no): las plantillas pueden decidir sin parpadeos. */
  readonly loaded = signal(false);
  readonly codes = computed(() => this.granted());
  readonly roles = computed(() => this.roleCodes());

  /** Lee los permisos del servidor (una vez; con `force` otra vez) y empieza a vigilar los cambios. */
  async load(force = false): Promise<void> {
    this.watch();
    if (this.loaded() && !force) {
      return;
    }
    try {
      if (force) {
        this.profile.clearQuietly();
      }
      const profile = await this.profile.getProfile();
      this.granted.set(new Set((profile.permissions ?? []).map((item) => item.code)));
      this.roleCodes.set((profile.roles ?? []).map((role) => role.code));
      this.lastLoad = Date.now();
    } catch {
      // Sin respuesta no se concede nada: lo seguro es ocultar, y el servidor decide igualmente.
      this.granted.set(new Set());
      this.roleCodes.set([]);
    } finally {
      this.loaded.set(true);
    }
  }

  /** Respuesta inmediata con lo ya leído (plantillas, directivas). */
  has(code: string): boolean {
    return this.granted().has(code);
  }

  hasAny(codes: readonly string[]): boolean {
    return codes.some((code) => this.has(code));
  }

  hasAll(codes: readonly string[]): boolean {
    return codes.every((code) => this.has(code));
  }

  /** Versión asíncrona: espera a que se lean los permisos. Es la que usan las pantallas al arrancar. */
  async can(code: string): Promise<boolean> {
    try {
      return await this.profile.can(code);
    } catch {
      return false;
    }
  }

  /** Vuelve a leer los permisos (cambió el rol, se renovó la sesión). */
  refresh(): Promise<void> {
    return this.load(true);
  }

  private watch(): void {
    if (this.watching) {
      return;
    }
    this.watching = true;
    // Cambió el rol de esta persona (la pantalla de usuarios o pendientes descartó la copia).
    this.profile.changes.subscribe(() => void this.load(true));
    // Clerk avisa en cada cambio de sesión o de token; se relee como mucho una vez por minuto.
    this.clerk.state$.subscribe((state) => {
      if (state.isSignedIn && Date.now() - this.lastLoad > REFRESH_EVERY_MS && this.loaded()) {
        void this.load(true);
      }
    });
  }
}
