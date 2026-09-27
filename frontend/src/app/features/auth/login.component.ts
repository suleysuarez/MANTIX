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
      <section class="brand-panel" aria-labelledby="brand-title">
        <div class="network-art" aria-hidden="true">
          <svg viewBox="0 0 900 760" preserveAspectRatio="xMidYMid slice">
            <g class="circuit-lines" fill="none" stroke="currentColor" stroke-width="1.5">
              <path d="M20 160h150l68 68h160l80-80h170l95 95h155" />
              <path d="M0 500h115l82-82h130l88 88h160l75-75h250" />
              <path d="M310 0v130l-64 64v132l88 88v156l-76 76v94" />
              <path d="M700 0v114l-96 96v128l72 72v178l-75 75v97" />
            </g>
            <g class="nodes" fill="currentColor">
              <circle cx="170" cy="160" r="5" /><circle cx="238" cy="228" r="5" />
              <circle cx="398" cy="228" r="5" /><circle cx="478" cy="148" r="5" />
              <circle cx="648" cy="148" r="5" /><circle cx="743" cy="243" r="5" />
              <circle cx="115" cy="500" r="5" /><circle cx="197" cy="418" r="5" />
              <circle cx="327" cy="506" r="5" /><circle cx="487" cy="506" r="5" />
              <circle cx="562" cy="431" r="5" /><circle cx="310" cy="130" r="5" />
              <circle cx="334" cy="414" r="5" /><circle cx="700" cy="114" r="5" />
              <circle cx="676" cy="402" r="5" /><circle cx="601" cy="587" r="5" />
            </g>
            <g class="equipment-markers" fill="none" stroke="currentColor" stroke-width="2">
              <rect x="92" y="105" width="54" height="38" rx="5" />
              <path d="M108 154h22M119 143v11" />
              <rect x="720" y="525" width="72" height="46" rx="5" />
              <path d="M733 538h46M733 550h32" />
              <circle cx="522" cy="342" r="31" />
              <path d="M522 324v18l12 11" />
            </g>
          </svg>
        </div>
        <div class="brand-content">
          <img class="brand-logo" src="/assets/images/logo.png" alt="MANTIX" />
          <p class="brand-kicker">Technology equipment maintenance</p>
          <h1 id="brand-title">Mantenimiento inteligente de equipos tecnológicos.</h1>
          <p class="brand-copy">
            Conecta equipos, seguimiento y mantenimiento en un solo espacio de trabajo.
          </p>
          <div class="system-status"><span></span> Plataforma operativa</div>
        </div>
      </section>

      <section class="login-panel" aria-labelledby="login-title">
        <div class="login-card">
          <img class="card-logo" src="/assets/images/logo.png" alt="MANTIX" />
          <div class="card-heading">
            <p class="eyebrow">Acceso a la plataforma</p>
            <h2 id="login-title">Iniciar sesión</h2>
            <p>Accede a tu espacio MANTIX para gestionar tus equipos.</p>
          </div>
          <div #signInHost class="clerk-host" aria-label="Formulario de inicio de sesión"></div>
          <p class="security-note"><span aria-hidden="true">⌁</span> Acceso seguro gestionado por Clerk</p>
        </div>
      </section>
    </main>
  `,
  styles: [
    `
      :host { display: block; min-height: 100vh; }
      .login-shell { min-height: 100vh; display: grid; grid-template-columns: minmax(0, 1.05fr) minmax(420px, .95fr); background: #f8fafc; color: #17324d; }
      .brand-panel { position: relative; display: grid; place-items: center; overflow: hidden; padding: clamp(2rem, 7vw, 6rem); color: #fff; background: #3e5c76; isolation: isolate; }
      .brand-panel::before { content: ''; position: absolute; inset: 0; background: radial-gradient(circle at 18% 18%, #a2d2ff2b, transparent 32%), linear-gradient(145deg, #29475f 0%, #3e5c76 58%, #2f4a62 100%); z-index: -2; }
      .brand-panel::after { content: ''; position: absolute; width: 34rem; height: 34rem; right: -18rem; bottom: -20rem; border: 1px solid #add7f62b; border-radius: 50%; box-shadow: 0 0 0 5rem #add7f612, 0 0 0 10rem #add7f608; z-index: -1; }
      .brand-content { position: relative; width: min(100%, 570px); z-index: 2; }
      .brand-logo { display: block; width: clamp(190px, 32vw, 300px); height: auto; margin-bottom: 2.2rem; filter: drop-shadow(0 12px 20px #0c243833); mix-blend-mode: screen; }
      .brand-kicker, .eyebrow { margin: 0 0 .85rem; color: #a2d2ff; font-size: .76rem; font-weight: 800; letter-spacing: .14em; text-transform: uppercase; }
      .brand-content h1 { max-width: 550px; margin: 0; color: #fff; font-size: clamp(2.2rem, 4vw, 4.25rem); line-height: 1.05; letter-spacing: -.045em; }
      .brand-copy { max-width: 410px; margin: 1.5rem 0 0; color: #ced4da; font-size: 1.05rem; line-height: 1.7; }
      .system-status { display: inline-flex; align-items: center; gap: .55rem; margin-top: 2.5rem; padding: .55rem .8rem; border: 1px solid #add7f62e; border-radius: 99px; color: #add7f6; font-size: .78rem; font-weight: 700; }
      .system-status span { width: .45rem; height: .45rem; border-radius: 50%; background: #a2d2ff; box-shadow: 0 0 0 4px #a2d2ff25; }
      .network-art { position: absolute; inset: 0; color: #add7f62b; z-index: 0; pointer-events: none; }
      .network-art svg { width: 100%; height: 100%; }
      .circuit-lines { stroke-dasharray: 7 12; animation: circuit-flow 26s linear infinite; }
      .nodes { opacity: .8; animation: node-pulse 5s ease-in-out infinite alternate; }
      .equipment-markers { opacity: .5; }
      .login-panel { display: grid; place-items: center; padding: clamp(1.25rem, 5vw, 5rem); background: #f8fafc; }
      .login-card { width: min(100%, 430px); padding: clamp(1.6rem, 4vw, 2.8rem); border: 1px solid #ced4da; border-radius: 22px; background: #fff; box-shadow: 0 24px 70px #17324d14, 0 4px 12px #17324d0d; }
      .card-logo { display: block; width: 112px; height: auto; margin: 0 auto 1.7rem; }
      .card-heading { margin-bottom: 1.45rem; text-align: center; }
      .card-heading h2 { margin: 0; color: #17324d; font-size: clamp(1.8rem, 4vw, 2.35rem); letter-spacing: -.035em; }
      .card-heading p:last-child { margin: .6rem auto 0; max-width: 310px; color: #778da9; line-height: 1.55; }
      .clerk-host { min-height: 245px; }
      .security-note { display: flex; align-items: center; justify-content: center; gap: .45rem; margin: 1.3rem 0 0; color: #778da9; font-size: .72rem; }
      .security-note span { color: #e4b363; font-size: 1rem; }
      @keyframes circuit-flow { to { stroke-dashoffset: -300; } }
      @keyframes node-pulse { from { opacity: .45; } to { opacity: .9; } }
      @media (max-width: 900px) { .login-shell { grid-template-columns: minmax(0, .8fr) minmax(360px, 1.2fr); } .brand-panel { padding: 2.5rem; } .brand-content h1 { font-size: clamp(2rem, 4vw, 3rem); } }
      @media (max-width: 680px) { .login-shell { display: block; } .brand-panel { min-height: 250px; padding: 2rem 1.5rem; place-items: end start; } .brand-logo { width: 170px; margin-bottom: 1rem; } .brand-kicker { margin-bottom: .45rem; } .brand-content h1 { font-size: 1.7rem; } .brand-copy, .system-status { display: none; } .network-art { opacity: .55; } .login-panel { min-height: calc(100vh - 250px); padding: 1.5rem; } .login-card { border-radius: 18px; padding: 1.5rem; } }
      @media (prefers-reduced-motion: reduce) { .circuit-lines, .nodes { animation: none; } }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class LoginComponent implements AfterViewInit, OnDestroy {
  @ViewChild('signInHost', { static: true }) private readonly signInHost!: ElementRef<HTMLElement>;
  private readonly clerk = inject(ClerkService);

  async ngAfterViewInit(): Promise<void> {
    await this.clerk.mountSignIn(this.signInHost.nativeElement);
  }

  async ngOnDestroy(): Promise<void> {
    await this.clerk.unmountSignIn(this.signInHost.nativeElement);
  }
}
