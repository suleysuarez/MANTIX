import { AsyncPipe } from '@angular/common';
import { ChangeDetectionStrategy, Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';

import { PendingUsersStore } from '../../core/pending-users.store';
import { ToastHostComponent } from '../../shared/toast-host.component';
import { PendingUserCardComponent } from './pending-user-card.component';

/** Usuarios pendientes: personas que ya iniciaron sesión y esperan que un administrador les dé un rol. */
@Component({
  selector: 'app-pending-users',
  standalone: true,
  imports: [AsyncPipe, RouterLink, PendingUserCardComponent, ToastHostComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (state$ | async; as state) {
      <div class="space-y-4">
        <header class="relative overflow-hidden rounded-2xl bg-gradient-to-r from-brand-sidebar to-primary-container px-6 py-5 md:px-8">
          <div class="flex flex-col gap-2.5 md:flex-row md:items-end md:justify-between">
            <div class="space-y-2">
              <span class="glass inline-flex w-fit items-center gap-2 rounded-full px-3 py-1 text-[11px] font-bold uppercase tracking-[0.08em] text-brand-accentDeep">
                <span class="h-2 w-2 rounded-full bg-brand-mustard"></span> Autorización
              </span>
              <h1 class="text-[24px] font-extrabold uppercase leading-tight tracking-tight text-white">Usuarios <span class="text-brand-accentLight">pendientes</span></h1>
              <p class="max-w-xl text-[13px] leading-snug text-brand-grey">Estas personas ya iniciaron sesión, pero no pueden usar Mantix hasta que les asignes un rol.</p>
            </div>
            <div class="flex items-center gap-3">
              <div class="glass rounded-xl px-4 py-2 text-center" role="status" aria-live="polite">
                <p class="text-[24px] font-extrabold leading-none text-brand-accentDeep">{{ state.loading ? '–' : state.users.length }}</p>
                <p class="text-[11px] font-bold uppercase tracking-wider text-on-surface-variant">en espera</p>
              </div>
              <a routerLink="/usuarios" class="glass flex items-center gap-1.5 rounded-xl bg-transparent px-4 py-2.5 text-[13px] font-bold !text-brand-accentDeep focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white">
                <span class="material-symbols-outlined text-[18px]" aria-hidden="true">manage_accounts</span> Todos los usuarios
              </a>
            </div>
          </div>
        </header>

        @if (state.error) {
          <p role="alert" class="flex flex-wrap items-center gap-3 rounded-lg bg-error-container px-4 py-3 text-[13px] text-on-error-container">
            {{ state.error }}
            <button type="button" (click)="reload()" class="rounded-lg bg-transparent px-2 py-1 text-[13px] font-bold underline">Reintentar</button>
          </p>
        }

        @if (state.loading) {
          <div class="grid grid-cols-1 gap-3 lg:grid-cols-2" role="status" aria-label="Cargando usuarios pendientes">
            @for (n of skeleton; track n) { <div class="h-44 animate-pulse rounded-2xl bg-surface-container motion-reduce:animate-none"></div> }
          </div>
        } @else if (state.users.length === 0 && !state.error) {
          <section class="glass flex flex-col items-center gap-2 rounded-2xl px-6 py-14 text-center">
            <span class="material-symbols-outlined text-[44px] text-brand-accentDeep" aria-hidden="true">how_to_reg</span>
            <h2 class="text-[16px] font-bold text-on-surface">No hay nadie esperando autorización</h2>
            <p class="max-w-sm text-[13px] text-on-surface-variant">Cuando alguien nuevo inicie sesión sin un rol asignado, aparecerá aquí.</p>
          </section>
        } @else {
          <section class="grid grid-cols-1 gap-3 lg:grid-cols-2" aria-label="Personas pendientes de autorización">
            @for (user of state.users; track user.id) {
              <app-pending-user-card
                [user]="user"
                [roles]="state.roles"
                [saving]="state.savingUserId === user.id"
                (assign)="assignRoles(user.id, $event)"
              />
            }
          </section>
        }
      </div>
      <app-toast-host />
    }
  `,
})
export class PendingUsersComponent implements OnInit {
  private readonly store = inject(PendingUsersStore);

  readonly state$ = this.store.state$;
  readonly skeleton = [1, 2];

  ngOnInit(): void {
    this.store.load();
  }

  reload(): void {
    this.store.load();
  }

  assignRoles(userId: number, roleIds: number[]): void {
    this.store.assignRoles(userId, roleIds);
  }
}
