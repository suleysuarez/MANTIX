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
    <header class="app-header">
      <a class="brand" routerLink="/dashboard">
        <strong>MANTIX</strong>
        <span>Maintenance workspace</span>
      </a>

      <nav aria-label="Main navigation">
        @for (item of navItems(); track item.path) {
          <a [routerLink]="item.path" routerLinkActive="active">{{ item.label }}</a>
        }
      </nav>

      <div class="actions">
        <app-notifications-bell />
        <div #userButtonHost aria-label="Clerk account menu"></div>
      </div>
    </header>
    <router-outlet />
  `,
  styles: [
    `.app-header { display: flex; align-items: center; gap: 2rem; padding: .75rem 2rem; background: #0f172a; color: white; }
     .brand { display: grid; gap: .1rem; color: inherit; text-decoration: none; }
     .brand span { color: #cbd5e1; font-size: .75rem; }
     nav { display: flex; gap: .25rem; flex: 1; flex-wrap: wrap; }
     nav a { color: #cbd5e1; text-decoration: none; padding: .45rem .8rem; border-radius: 6px; }
     nav a:hover { background: #1e293b; color: white; }
     nav a.active { background: #2563eb; color: white; }
     .actions { display: flex; align-items: center; gap: .75rem; }
     @media (max-width: 720px) { .app-header { flex-wrap: wrap; gap: .75rem; padding: .75rem 1rem; } nav { order: 3; flex-basis: 100%; } }`,
  ],
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
