import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  OnDestroy,
  OnInit,
  ViewChild,
  inject,
  signal,
} from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

import { ClerkService } from '../core/clerk.service';
import { LocalProfileService } from '../core/local-profile.service';
import { NavItem, visibleNavItems } from '../core/nav-items';
import { NotificationsBellComponent } from './notifications-bell.component';

/**
 * Layout de la zona autenticada: marca, navegación según permisos locales,
 * notificaciones y menú de cuenta de Clerk. Solo se activa cuando los guards de
 * las rutas hijas ya dejaron pasar al usuario.
 */
@Component({
  selector: 'app-shell',
  standalone: true,
  imports: [RouterLink, RouterLinkActive, RouterOutlet, NotificationsBellComponent],
  template: `
    <div class="tw-reset min-h-screen bg-surface-variant p-space-sm font-sans text-on-surface antialiased">
      <aside
        class="fixed bottom-space-sm left-space-sm top-space-sm z-50 flex w-20 flex-col items-center justify-between rounded-[24px] bg-primary py-space-lg shadow-[0_12px_32px_-4px_rgba(43,66,87,0.18)]">
        <a routerLink="/dashboard" class="flex flex-col items-center gap-space-xs" aria-label="MANTIX">
          <span class="flex h-12 w-12 items-center justify-center rounded-xl bg-white/90">
            <img src="assets/images/logo.png" alt="MANTIX" class="h-10 w-10 object-contain" />
          </span>
          <span class="font-label-caps text-label-caps uppercase tracking-wider text-primary-fixed-dim">Mantix</span>
        </a>

        <nav aria-label="Main navigation" class="flex w-full flex-col items-center gap-space-sm px-2">
          @for (item of navItems(); track item.path) {
            <a
              [routerLink]="item.path"
              routerLinkActive="!bg-white !text-primary shadow-[0_4px_16px_rgba(0,0,0,0.12)]"
              [title]="item.label"
              [attr.aria-label]="item.label"
              class="flex h-11 w-11 items-center justify-center rounded-full text-primary-fixed-dim transition-all hover:bg-primary-container hover:text-on-primary-container">
              <span class="material-symbols-outlined text-[22px]">{{ item.icon }}</span>
            </a>
          }
        </nav>

        <div #userButtonHost aria-label="Clerk account menu" class="flex items-center justify-center"></div>
      </aside>

      <div class="min-h-[calc(100vh-1rem)] pl-[88px]">
        <div class="flex min-h-[calc(100vh-1rem)] flex-col overflow-hidden rounded-[32px] bg-surface shadow-[0_4px_24px_-4px_rgba(43,66,87,0.06)]">
          <header class="flex h-16 items-center justify-between px-space-xl">
            <div class="flex flex-col">
              <span class="font-headline-md text-headline-md text-primary">MANTIX</span>
              <span class="font-body-sm text-body-sm text-on-surface-variant">Gestión de mantenimiento tecnológico</span>
            </div>
            <div class="flex items-center gap-space-md text-on-surface">
              <span class="hidden items-center gap-2 rounded-full border border-tertiary-fixed-dim bg-tertiary-fixed/40 px-3 py-1.5 md:flex">
                <span class="h-2 w-2 rounded-full bg-tertiary"></span>
                <span class="font-label-chip text-label-chip text-tertiary">Sistema operativo</span>
              </span>
              <app-notifications-bell />
            </div>
          </header>
          <router-outlet />
        </div>
      </div>
    </div>
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class AppShellComponent implements OnInit, AfterViewInit, OnDestroy {
  @ViewChild('userButtonHost', { static: true }) private readonly userButtonHost!: ElementRef<HTMLElement>;
  private readonly clerk = inject(ClerkService);
  private readonly profile = inject(LocalProfileService);

  readonly navItems = signal<NavItem[]>([]);

  async ngOnInit(): Promise<void> {
    const profile = await this.profile.getProfile();
    this.navItems.set(visibleNavItems(profile.permissions.map((permission) => permission.code)));
  }

  async ngAfterViewInit(): Promise<void> {
    await this.clerk.mountUserButton(this.userButtonHost.nativeElement);
  }

  async ngOnDestroy(): Promise<void> {
    await this.clerk.unmountUserButton(this.userButtonHost.nativeElement);
  }
}
