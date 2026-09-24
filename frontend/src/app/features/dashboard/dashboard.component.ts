import {
  AfterViewInit,
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  OnDestroy,
  ViewChild,
  inject,
} from '@angular/core';

import { ClerkService } from '../../core/clerk.service';

@Component({
  standalone: true,
  template: `
    <header class="app-header">
      <div>
        <strong>Technology Equipment Maintenance</strong>
        <span>Maintenance workspace</span>
      </div>
      <div #userButtonHost aria-label="Clerk account menu"></div>
    </header>
    <main>
      <h1>Technology Equipment Maintenance</h1>
      <p>Signed-in application workspace.</p>
    </main>
  `,
  styles: [
    `.app-header { display: flex; justify-content: space-between; align-items: center; padding: 1rem 2rem; background: #0f172a; color: white; }
     .app-header div:first-child { display: grid; gap: .2rem; } .app-header span { color: #cbd5e1; font-size: .85rem; }
     main { max-width: 960px; margin: 4rem auto; padding: 0 1.5rem; }`,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class DashboardComponent implements AfterViewInit, OnDestroy {
  @ViewChild('userButtonHost', { static: true }) private readonly userButtonHost!: ElementRef<HTMLElement>;
  private readonly clerk = inject(ClerkService);

  async ngAfterViewInit(): Promise<void> {
    await this.clerk.mountUserButton(this.userButtonHost.nativeElement);
  }

  async ngOnDestroy(): Promise<void> {
    await this.clerk.unmountUserButton(this.userButtonHost.nativeElement);
  }
}
