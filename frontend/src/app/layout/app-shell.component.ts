import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { NavigationEnd, Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';

import { ClerkService } from '../core/clerk.service';
import { LocalProfileService } from '../core/local-profile.service';
import { NavItem, visibleNavItems } from '../core/nav-items';
import { NotificationsBellComponent } from './notifications-bell.component';

const COLLAPSED_KEY = 'mantix.sidebar.collapsed';

function readCollapsed(): boolean {
  try {
    return localStorage.getItem(COLLAPSED_KEY) === 'true';
  } catch {
    return false;
  }
}

/**
 * Layout de la zona autenticada: marca, navegación según permisos locales,
 * notificaciones y menú de cuenta propio (nombre del perfil local, sesiones
 * activas y cierre de sesión). Solo se activa cuando los guards de las rutas
 * hijas ya dejaron pasar al usuario.
 *
 * Escritorio (lg+): sidebar fijo, contraíble a solo iconos. Tablet/móvil: el
 * sidebar es un drawer que se abre desde el botón de menú del header.
 */
@Component({
  selector: 'app-shell',
  standalone: true,
  imports: [RouterLink, RouterLinkActive, RouterOutlet, NotificationsBellComponent],
  template: `
    <div class="tw-reset min-h-screen bg-[#F7FAFC] font-sans text-[#1E293B] antialiased">
      @if (drawerOpen()) {
        <div class="fixed inset-0 z-40 bg-[#0b1f3a]/50 lg:hidden" (click)="drawerOpen.set(false)" aria-hidden="true"></div>
      }

      <aside
        [class]="(collapsed() ? 'lg:w-20' : 'lg:w-[256px]') + (drawerOpen() ? ' translate-x-0' : ' -translate-x-full lg:translate-x-0')"
        class="fixed inset-y-0 left-0 z-50 flex h-screen w-[256px] flex-col justify-between overflow-hidden rounded-none bg-[linear-gradient(180deg,#0b1f3a_0%,#102b4f_100%)] py-6 transition-all duration-300">
        <div class="flex min-h-0 flex-col gap-6">
          <div class="flex h-10 items-center px-5" [class]="collapsed() ? 'lg:justify-center lg:px-0' : 'justify-between'">
            <a routerLink="/dashboard" aria-label="MANTIX" class="flex min-w-0 items-center">
              <!-- Contraído: solo la "M" del logo (recorte), siempre dentro de la barra -->
              <img src="assets/images/logo/mantix-logo.svg" alt="MANTIX"
                class="h-10 object-contain object-left"
                [class]="collapsed() ? 'w-10 !object-cover lg:block' : 'w-auto max-w-[170px]'" />
            </a>
            @if (!collapsed()) {
              <button type="button" (click)="toggle()" aria-label="Contraer barra lateral"
                class="hidden h-8 w-8 shrink-0 items-center justify-center rounded-full text-white/70 transition-colors hover:bg-white/15 hover:text-white lg:flex">
                <span class="material-symbols-outlined text-[20px]">chevron_left</span>
              </button>
            }
          </div>
          @if (collapsed()) {
            <button type="button" (click)="toggle()" aria-label="Ampliar barra lateral"
              class="mx-auto -mt-3 hidden h-8 w-8 items-center justify-center rounded-full text-white/70 transition-colors hover:bg-white/15 hover:text-white lg:flex">
              <span class="material-symbols-outlined text-[20px]">chevron_right</span>
            </button>
          }

          <nav aria-label="Main navigation" class="flex flex-col gap-1 overflow-y-auto overflow-x-hidden px-3 text-[#CED4DA]">
            @for (item of navItems(); track item.path) {
              <a
                [routerLink]="item.path"
                routerLinkActive="!bg-[#457b9d] !text-white shadow-[0_6px_16px_rgba(69,123,157,0.45)]"
                [title]="item.label"
                [attr.aria-label]="item.label"
                class="flex h-11 items-center gap-3 rounded-xl px-4 text-[14px] font-medium transition-all hover:bg-white/10 hover:text-white"
                [class]="collapsed() ? 'lg:mx-auto lg:w-11 lg:justify-center lg:px-0' : ''">
                <span class="material-symbols-outlined shrink-0 text-[22px]">{{ item.icon }}</span>
                <span class="truncate" [class]="collapsed() ? 'lg:hidden' : ''">{{ item.label }}</span>
              </a>
            }
          </nav>
        </div>

        <div class="flex flex-col gap-2 px-3">
          <span class="px-3 text-[11px] font-bold uppercase tracking-[0.12em] text-white/60" [class]="collapsed() ? 'lg:hidden' : ''">Cuenta</span>
          <a routerLink="/cuenta" [title]="userName()" aria-label="Mi cuenta"
            class="flex items-center gap-3 rounded-xl bg-white/10 px-3 py-2.5 text-white transition-colors hover:bg-white/20" [class]="collapsed() ? 'lg:justify-center lg:px-0' : ''">
            <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[linear-gradient(135deg,#ADD7F6,#A2D2FF)] text-[13px] font-bold text-[#3E5C76]">{{ initials() }}</span>
            <div class="min-w-0 flex-1" [class]="collapsed() ? 'lg:hidden' : ''">
              <p class="truncate text-[13px] font-semibold">{{ userName() }}</p>
              <p class="truncate text-[11px] text-[#CED4DA]">{{ userRole() }}</p>
            </div>
          </a>
        </div>
      </aside>

      <div class="transition-[padding] duration-300" [class]="collapsed() ? 'lg:pl-20' : 'lg:pl-[256px]'">
        <header class="sticky top-0 z-30">
          <div class="flex items-center justify-between gap-3 bg-[#f8f9fa] px-4 py-1 shadow-[0_4px_20px_rgba(62,92,118,0.10)] md:px-8">
          <button type="button" (click)="drawerOpen.set(true)" aria-label="Abrir menú"
            class="flex h-9 w-9 items-center justify-center rounded-full bg-[#ADD7F6]/40 text-[#3E5C76] transition-colors hover:bg-[#ADD7F6]/70 lg:hidden">
            <span class="material-symbols-outlined">menu</span>
          </button>
          <div class="ml-auto flex items-center gap-3 rounded-[14px] border border-[#CED4DA]/70 bg-white px-2 py-1">
            <app-notifications-bell />
            <span class="h-5 w-[2px] rounded-full bg-[#D4A017]" aria-hidden="true"></span>
            <div class="relative">
              <button type="button" (click)="menuOpen.set(!menuOpen())" [attr.aria-expanded]="menuOpen()" aria-haspopup="menu" aria-label="Menú de usuario"
                class="flex items-center gap-2 rounded-xl py-0.5 pl-0.5 pr-2 text-left transition-all duration-[250ms] ease-in-out hover:bg-[#ADD7F6]/20">
                <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[linear-gradient(135deg,#ADD7F6,#A2D2FF)] text-[12px] font-bold text-[#3E5C76]">{{ initials() }}</span>
                <span class="hidden min-w-0 flex-col md:flex">
                  <span class="max-w-[160px] truncate text-[13px] font-bold leading-4 text-[#3E5C76]">{{ userName() }}</span>
                  <span class="max-w-[160px] truncate text-[11px] leading-3 text-[#778DA9]">{{ userRole() }}</span>
                </span>
                <span class="material-symbols-outlined hidden text-[16px] text-[#778DA9] transition-transform duration-[250ms] md:block" [class]="menuOpen() ? 'rotate-180' : ''">expand_more</span>
              </button>
              @if (menuOpen()) {
                <div class="fixed inset-0 z-40" (click)="menuOpen.set(false)" aria-hidden="true"></div>
                <div role="menu" class="absolute right-0 top-full z-50 mt-3 w-64 overflow-hidden rounded-2xl border border-[#3E5C76]/10 bg-white shadow-[0_12px_32px_rgba(62,92,118,0.16)]">
                  <div class="border-b border-[#CED4DA] px-4 py-3">
                    <p class="truncate text-[14px] font-bold text-[#3E5C76]">{{ userName() }}</p>
                    <p class="truncate text-[12px] text-[#778DA9]">{{ userEmail() }}</p>
                    @if (userRole()) {
                      <span class="mt-1.5 inline-block rounded-full bg-[#ADD7F6]/50 px-2 py-0.5 text-[10px] font-bold text-[#3E5C76]">{{ userRole() }}</span>
                    }
                  </div>
                  <a routerLink="/cuenta" role="menuitem" class="flex items-center gap-2 px-4 py-2.5 text-[13px] font-medium !text-[#3E5C76] transition-colors hover:bg-[#ADD7F6]/20">
                    <span class="material-symbols-outlined text-[18px] text-[#778DA9]">devices</span> Mi cuenta y sesiones activas
                  </a>
                  <button type="button" role="menuitem" (click)="signOut()" class="flex w-full items-center gap-2 px-4 py-2.5 text-left text-[13px] font-medium text-[#3E5C76] transition-colors hover:bg-[#ADD7F6]/20">
                    <span class="material-symbols-outlined text-[18px] text-[#D4A017]">logout</span> Cerrar sesión
                  </button>
                </div>
              }
            </div>
          </div>
          </div>
          <div class="h-[2px] w-full bg-[linear-gradient(90deg,transparent,#ADD7F6,#D4A017,#ADD7F6,transparent)]" aria-hidden="true"></div>
        </header>
        <div class="px-4 pb-4 pt-3 md:px-8">
          <router-outlet />
        </div>
      </div>
    </div>
  `,
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class AppShellComponent implements OnInit {
  private readonly clerk = inject(ClerkService);
  private readonly profile = inject(LocalProfileService);
  private readonly router = inject(Router);

  readonly navItems = signal<NavItem[]>([]);
  readonly collapsed = signal(readCollapsed());
  readonly drawerOpen = signal(false);
  readonly menuOpen = signal(false);
  readonly userName = signal('');
  readonly userRole = signal('');
  readonly userEmail = signal('');
  readonly initials = signal('');

  constructor() {
    this.router.events
      .pipe(filter((event) => event instanceof NavigationEnd))
      .subscribe(() => {
        this.drawerOpen.set(false);
        this.menuOpen.set(false);
      });
  }

  async signOut(): Promise<void> {
    this.menuOpen.set(false);
    await this.clerk.signOut();
  }

  toggle(): void {
    this.collapsed.update((value) => !value);
    try {
      localStorage.setItem(COLLAPSED_KEY, String(this.collapsed()));
    } catch {
      /* almacenamiento no disponible: el estado solo dura la sesión */
    }
  }

  async ngOnInit(): Promise<void> {
    const profile = await this.profile.getProfile();
    this.navItems.set(visibleNavItems(profile.permissions.map((permission) => permission.code)));
    this.userName.set(profile.full_name);
    this.userEmail.set(profile.email);
    this.userRole.set(profile.roles[0]?.name ?? '');
    this.initials.set(
      profile.full_name
        .split(' ')
        .filter(Boolean)
        .slice(0, 2)
        .map((part) => part[0].toUpperCase())
        .join(''),
    );
  }
}
