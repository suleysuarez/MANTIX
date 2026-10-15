import { Injectable, inject } from '@angular/core';
import { BehaviorSubject, Observable, of } from 'rxjs';
import { catchError, map, tap } from 'rxjs/operators';

import { apiErrorMessage, apiFieldErrors } from './api-errors';
import { LocalProfileService } from './local-profile.service';
import { ActionResult } from './pending-requests.store';
import { ProfileData, ProfileService, ProfileUpdatePayload } from './profile.service';
import { ToastService } from './toast.service';

export interface ProfileState {
  profile: ProfileData | null;
  /** URL local de la foto (o `null` = iniciales). */
  avatarUrl: string | null;
  loading: boolean;
  error: string;
  busy: boolean;
}

const INITIAL: ProfileState = { profile: null, avatarUrl: null, loading: false, error: '', busy: false };

/**
 * Observer pattern store de mi perfil. Lo comparten el menú lateral (nombre y foto) y la pantalla
 * Perfil, así que un cambio de nombre o de foto se ve en todas partes al instante.
 */
@Injectable({ providedIn: 'root' })
export class ProfileStore {
  private readonly api = inject(ProfileService);
  private readonly toasts = inject(ToastService);
  private readonly local = inject(LocalProfileService);
  private readonly subject = new BehaviorSubject<ProfileState>(INITIAL);

  readonly state$: Observable<ProfileState> = this.subject.asObservable();

  private get value(): ProfileState {
    return this.subject.value;
  }

  private patch(changes: Partial<ProfileState>): void {
    this.subject.next({ ...this.value, ...changes });
  }

  load(): void {
    if (this.value.loading) {
      return;
    }
    this.patch({ loading: true, error: '' });
    this.api.get().subscribe({
      next: (profile) => {
        this.adopt(profile);
        this.patch({ loading: false });
      },
      error: (error) => this.patch({ loading: false, error: apiErrorMessage(error, 'No se pudo cargar tu perfil.') }),
    });
  }

  update(payload: ProfileUpdatePayload): Observable<ActionResult> {
    return this.run(this.api.update(payload), 'Datos actualizados.');
  }

  uploadAvatar(file: File): Observable<ActionResult> {
    return this.run(this.api.uploadAvatar(file), 'Foto actualizada.');
  }

  removeAvatar(): Observable<ActionResult> {
    return this.run(this.api.removeAvatar(), 'Foto eliminada.');
  }

  /** La contraseña viaja al servidor y no se guarda en ningún estado. */
  changePassword(current: string, next: string): Observable<ActionResult> {
    return this.run(this.api.changePassword(current, next), 'Contraseña cambiada.', false);
  }

  private run<T>(call: Observable<T>, success: string, adopt = true): Observable<ActionResult> {
    if (this.value.busy) {
      return of({ ok: false, fieldErrors: {} });
    }
    this.patch({ busy: true });
    return call.pipe(
      tap((result) => {
        if (adopt) {
          this.adopt(result as ProfileData);
        }
        this.toasts.success(success);
      }),
      map(() => {
        this.patch({ busy: false });
        return { ok: true, fieldErrors: {} } as ActionResult;
      }),
      catchError((error) => {
        this.patch({ busy: false });
        this.toasts.error(apiErrorMessage(error, 'No se pudo completar la acción.'));
        return of({ ok: false, fieldErrors: apiFieldErrors(error) });
      }),
    );
  }

  /** Guarda el perfil recibido y trae la foto solo si cambió. */
  private adopt(profile: ProfileData): void {
    const previous = this.value.profile;
    this.patch({ profile });
    // Otras pantallas (p. ej. el saludo del Dashboard) leen esta copia: que no quede con el nombre viejo.
    this.local.setName(profile.full_name);
    if (!profile.has_avatar) {
      this.setAvatarUrl(null);
    } else if (!previous || previous.avatar_version !== profile.avatar_version || !this.value.avatarUrl) {
      this.api.avatar().subscribe({
        next: (blob) => this.setAvatarUrl(URL.createObjectURL(blob)),
        error: () => this.setAvatarUrl(null), // sin foto legible se muestran las iniciales
      });
    }
  }

  private setAvatarUrl(url: string | null): void {
    const old = this.value.avatarUrl;
    if (old && old !== url) {
      URL.revokeObjectURL(old);
    }
    this.patch({ avatarUrl: url });
  }
}
