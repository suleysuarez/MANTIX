import { ChangeDetectionStrategy, Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';

import { LocalProfile, LocalProfileService } from '../../core/local-profile.service';
import { NavItem, visibleNavItems } from '../../core/nav-items';

@Component({
  standalone: true,
  imports: [RouterLink],
  template: `
    <main>
      @if (profile(); as current) {
        <h1>Welcome, {{ current.full_name }}</h1>
        <p class="roles">
          @for (role of current.roles; track role.code) {
            <span class="role">{{ role.name }}</span>
          }
        </p>
      }
      <section class="shortcuts" aria-label="Shortcuts">
        @for (item of shortcuts(); track item.path) {
          <a [routerLink]="item.path">{{ item.label }}</a>
        }
      </section>
    </main>
  `,
  styles: [
    `main { max-width: 960px; margin: 3rem auto; padding: 0 1.5rem; }
     .roles { display: flex; gap: .5rem; flex-wrap: wrap; }
     .role { background: #e0f2fe; color: #075985; padding: .2rem .6rem; border-radius: 999px; font-size: .85rem; }
     .shortcuts { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem; margin-top: 2rem; }
     .shortcuts a { padding: 1.25rem; background: white; border: 1px solid #e2e8f0; border-radius: 10px; color: #0f172a; text-decoration: none; font-weight: 600; }
     .shortcuts a:hover { border-color: #2563eb; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class DashboardComponent implements OnInit {
  private readonly profileService = inject(LocalProfileService);

  readonly profile = signal<LocalProfile | null>(null);
  readonly shortcuts = signal<NavItem[]>([]);

  async ngOnInit(): Promise<void> {
    const profile = await this.profileService.getProfile();
    this.profile.set(profile);
    this.shortcuts.set(
      visibleNavItems(profile.permissions.map((permission) => permission.code)).filter(
        (item) => item.path !== '/dashboard',
      ),
    );
  }
}
