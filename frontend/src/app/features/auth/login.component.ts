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
    <main class="login-shell">
      <div class="network-art" aria-hidden="true">
        <svg viewBox="0 0 1440 900" preserveAspectRatio="xMidYMid slice">
          <g class="circuit-lines" fill="none" stroke="currentColor" stroke-width="1.4">
            <path d="M-20 190h220l74 74h220l94-94h270l106 106h300" />
            <path d="M-20 700h180l112-112h205l106 106h230l108-108h450" />
            <path d="M360 -30v190l-86 86v164l108 108v190l-92 92v150" />
            <path d="M1110 -30v170l-118 118v174l92 92v174l-90 90v150" />
          </g>
          <g class="nodes" fill="currentColor">
            <circle cx="200" cy="190" r="4" /><circle cx="274" cy="264" r="4" />
            <circle cx="494" cy="264" r="4" /><circle cx="588" cy="170" r="4" />
            <circle cx="858" cy="170" r="4" /><circle cx="964" cy="276" r="4" />
            <circle cx="160" cy="700" r="4" /><circle cx="272" cy="588" r="4" />
            <circle cx="477" cy="694" r="4" /><circle cx="707" cy="694" r="4" />
            <circle cx="815" cy="586" r="4" /><circle cx="360" cy="160" r="4" />
            <circle cx="382" cy="518" r="4" /><circle cx="1110" cy="140" r="4" />
            <circle cx="1084" cy="524" r="4" /><circle cx="994" cy="698" r="4" />
          </g>
          <g class="equipment-markers" fill="none" stroke="currentColor" stroke-width="1.8">
            <rect x="105" y="126" width="58" height="40" rx="5" />
            <path d="M122 177h24M134 166v11" />
            <rect x="1210" y="652" width="82" height="50" rx="5" />
            <path d="M1225 667h52M1225 681h36" />
            <circle cx="772" cy="390" r="36" />
            <path d="M772 367v23l15 14" />
          </g>
        </svg>
      </div>

      <div class="ambient-orbit ambient-orbit-one" aria-hidden="true"></div>
      <div class="ambient-orbit ambient-orbit-two" aria-hidden="true"></div>

      <div class="login-layout">
        <section class="brand-content" aria-labelledby="brand-title">
          <div class="logo-plaque">
            <img class="brand-logo" src="/assets/images/logo.png" alt="MANTIX" />
          </div>
          <p class="brand-kicker">Plataforma de mantenimiento tecnológico</p>
          <h1 id="brand-title">Mantenimiento inteligente para tus equipos tecnológicos.</h1>
          <p class="brand-copy">
            Centraliza equipos, mantenimientos y seguimiento operativo en un solo lugar.
          </p>
          <div class="system-status"><span></span> Plataforma operativa</div>
        </section>

        <section class="login-area" aria-labelledby="login-title">
          <div class="login-card">
            <div class="card-heading">
              <p class="eyebrow">Acceso seguro</p>
              <h2 id="login-title">Bienvenido</h2>
              <p>Ingresa para continuar.</p>
            </div>
            <div #signInHost class="clerk-host" aria-label="Formulario de inicio de sesión"></div>
            @if (!signInReady) {
              <p class="loading-status" aria-live="polite">Preparando acceso seguro…</p>
            }
            <p class="security-note"><span aria-hidden="true">⌁</span> Autenticación protegida por Clerk</p>
          </div>
        </section>
      </div>
    </main>
  `,
  styles: [
    `
      :host { display: block; min-height: 100vh; }
      .login-shell { position: relative; min-height: 100vh; overflow: hidden; color: #fff; background: #3e5c76; isolation: isolate; }
      .login-shell::before { content: ''; position: absolute; inset: 0; background: radial-gradient(circle at 12% 18%, #a2d2ff18, transparent 28%), radial-gradient(circle at 88% 82%, #add7f612, transparent 32%), linear-gradient(135deg, #2f4a62 0%, #3e5c76 50%, #365570 100%); z-index: -3; }
      .login-shell::after { content: ''; position: absolute; inset: 0; background: linear-gradient(90deg, #1d38511a, transparent 48%, #1d38511a); pointer-events: none; z-index: -1; }
      .network-art { position: absolute; inset: 0; color: #add7f61c; pointer-events: none; z-index: -2; }
      .network-art svg { width: 100%; height: 100%; }
      .circuit-lines { stroke-dasharray: 7 13; animation: circuit-flow 32s linear infinite; }
      .nodes { opacity: .75; animation: node-pulse 6s ease-in-out infinite alternate; }
      .equipment-markers { opacity: .42; }
      .login-layout { position: relative; z-index: 1; display: grid; grid-template-columns: minmax(0, 1fr) minmax(420px, .82fr); align-items: center; gap: clamp(3rem, 9vw, 9rem); width: min(1180px, calc(100% - 4rem)); min-height: 100vh; margin: 0 auto; padding: 4rem 0; }
      .brand-content { width: min(100%, 560px); }
      .logo-plaque { display: inline-flex; align-items: center; justify-content: center; margin-bottom: 1.7rem; padding: .7rem 1.15rem; border: 1px solid #ced4da99; border-radius: 16px; background: #fff; box-shadow: 0 16px 35px #172f451f; }
      .brand-logo { display: block; width: clamp(160px, 23vw, 230px); height: auto; }
      .brand-kicker, .eyebrow { margin: 0 0 .75rem; color: #a2d2ff; font-size: .73rem; font-weight: 800; letter-spacing: .13em; text-transform: uppercase; }
      .brand-content h1 { max-width: 530px; margin: 0; color: #fff; font-size: clamp(2rem, 4vw, 3.8rem); line-height: 1.06; letter-spacing: -.045em; }
      .brand-copy { max-width: 420px; margin: 1.35rem 0 0; color: #ced4da; font-size: 1rem; line-height: 1.65; }
      .system-status { display: inline-flex; align-items: center; gap: .55rem; margin-top: 2rem; padding: .55rem .8rem; border: 1px solid #add7f62e; border-radius: 99px; color: #add7f6; font-size: .76rem; font-weight: 700; }
      .system-status span { width: .45rem; height: .45rem; border-radius: 50%; background: #a2d2ff; box-shadow: 0 0 0 4px #a2d2ff25; }
      .login-area { display: grid; place-items: center; min-width: 0; }
      .login-card { width: min(100%, 430px); box-sizing: border-box; padding: clamp(1.7rem, 4vw, 2.75rem); border: 1px solid #ced4da; border-radius: 20px; background: #fff; color: #17324d; box-shadow: 0 24px 70px #172f4530, 0 5px 14px #172f4514; }
      .card-heading { margin-bottom: 1.35rem; text-align: center; }
      .card-heading .eyebrow { color: #778da9; }
      .card-heading h2 { margin: 0; color: #17324d; font-size: clamp(1.85rem, 4vw, 2.35rem); letter-spacing: -.04em; }
      .card-heading p:last-child { margin: .55rem 0 0; color: #778da9; line-height: 1.5; }
      .clerk-host { min-height: 245px; }
      .loading-status { margin: -1rem 0 1rem; color: #778da9; font-size: .78rem; text-align: center; }
      .security-note { display: flex; align-items: center; justify-content: center; gap: .45rem; margin: 1.2rem 0 0; color: #778da9; font-size: .72rem; }
      .security-note span { color: #e4b363; font-size: 1rem; }
      .ambient-orbit { position: absolute; border: 1px solid #a2d2ff18; border-radius: 50%; pointer-events: none; z-index: -2; }
      .ambient-orbit-one { width: 40rem; height: 40rem; top: -22rem; right: -15rem; }
      .ambient-orbit-two { width: 28rem; height: 28rem; bottom: -18rem; left: -12rem; border-color: #e4b36318; }
      @keyframes circuit-flow { to { stroke-dashoffset: -420; } }
      @keyframes node-pulse { from { opacity: .35; } to { opacity: .78; } }
      @media (max-width: 900px) { .login-layout { grid-template-columns: minmax(0, .9fr) minmax(360px, 1.1fr); gap: 2.5rem; width: min(100% - 3rem, 800px); } .brand-content h1 { font-size: clamp(1.8rem, 4vw, 2.8rem); } }
      @media (max-width: 680px) { .login-layout { display: flex; flex-direction: column; align-items: stretch; justify-content: center; gap: 2rem; width: min(100% - 2rem, 450px); min-height: 100vh; padding: 2rem 0; } .brand-content { text-align: center; } .logo-plaque { margin-bottom: 1rem; } .brand-logo { width: 155px; } .brand-kicker { margin-bottom: .5rem; } .brand-content h1 { font-size: 1.75rem; } .brand-copy, .system-status { display: none; } .login-card { padding: 1.5rem; } .network-art { opacity: .42; } }
      @media (prefers-reduced-motion: reduce) { .circuit-lines, .nodes { animation: none; } }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class LoginComponent implements AfterViewInit, OnDestroy {
  @ViewChild('signInHost', { static: true }) private readonly signInHost!: ElementRef<HTMLElement>;
  private readonly clerk = inject(ClerkService);
  signInReady = false;

  async ngAfterViewInit(): Promise<void> {
    await this.clerk.mountSignIn(this.signInHost.nativeElement);
    this.signInReady = true;
  }

  async ngOnDestroy(): Promise<void> {
    await this.clerk.unmountSignIn(this.signInHost.nativeElement);
  }
}
