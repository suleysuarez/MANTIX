import { AfterViewInit, Directive, ElementRef, OnDestroy, ViewChild } from '@angular/core';

import { ClerkAppearance } from '../../core/clerk.types';

/**
 * Color de error/advertencia de los formularios (ámbar): contrasta sobre el
 * vidrio azul sin chocar con la paleta, a diferencia del rojo por defecto.
 * Se usa en CSS, en `appearance.elements` y en `variables.colorDanger`.
 */
const FORM_ERROR_COLOR = '#f59e0b';

/**
 * Sobre plateado (degradado metálico) para el campo de email. Se define una
 * sola vez y se reutiliza en el CSS global y en `appearance`.
 */
// SVG (sin codificar): sobre 24x24, trazo blanco -> plata claro (#fff -> #eef2f7 -> #cfd7e1).
// Se precodifica a mano porque Angular exige `styles` resolubles en compilación.
const EMAIL_ICON_URL = `url("data:image/svg+xml,%3Csvg%20xmlns%3D'http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg'%20viewBox%3D'0%200%2024%2024'%20fill%3D'none'%3E%3Cdefs%3E%3ClinearGradient%20id%3D'g'%20x1%3D'0'%20y1%3D'0'%20x2%3D'1'%20y2%3D'1'%3E%3Cstop%20offset%3D'0'%20stop-color%3D'%23ffffff'%2F%3E%3Cstop%20offset%3D'.55'%20stop-color%3D'%23eef2f7'%2F%3E%3Cstop%20offset%3D'1'%20stop-color%3D'%23cfd7e1'%2F%3E%3C%2FlinearGradient%3E%3C%2Fdefs%3E%3Crect%20x%3D'2.5'%20y%3D'5'%20width%3D'19'%20height%3D'14'%20rx%3D'2.5'%20stroke%3D'url(%23g)'%20stroke-width%3D'2'%2F%3E%3Cpath%20d%3D'M3.5%207.5l8.5%206%208.5-6'%20stroke%3D'url(%23g)'%20stroke-width%3D'2'%20stroke-linecap%3D'round'%20stroke-linejoin%3D'round'%2F%3E%3C%2Fsvg%3E")`;

/**
 * Fondo/vidrio/humo compartidos entre login y sign-up: mismo `<main>`, mismo
 * `.clerk-host` (Clerk decide qué widget renderiza ahí según qué `mount*` se
 * llame desde la subclase), para que ambas pantallas se vean como una sola
 * pieza visual y no haya que mantener el CSS duplicado en dos archivos.
 */
export const AUTH_SHELL_TEMPLATE = `
  <main class="login-shell">
    <div class="background-image"></div>
    <div class="glass-veil"></div>

    <video
      #smokeVideo
      class="smoke-video"
      autoplay
      muted
      loop
      playsinline
      preload="auto"
      aria-hidden="true">
      <source src="/assets/videos/humo_fondo.webm" type="video/webm" />
      <source src="/assets/videos/humo_fondo.mp4" type="video/mp4" />
    </video>

    <section class="login-area">
      <div class="clerk-shell" #clerkShell>
        <div
          #authHost
          class="clerk-host"
          aria-label="Formulario de autenticación">
        </div>
      </div>
    </section>
  </main>
`;

export const AUTH_SHELL_STYLES = [
  `
    /* ==========================================================================
       1. ESTILOS DEL CONTENEDOR Y MAQUETACIÓN (SHELL & LAYOUT)
       ========================================================================== */
    :host {
      display: block;
      min-height: 100vh;
    }

    .login-shell {
      position: relative;
      min-height: 100vh;
      overflow: hidden;
      isolation: isolate;
    }

    .background-image {
      position: fixed;
      inset: 0;
      background-image: url('/assets/images/background.png');
      background-size: cover;
      background-position: center;
      background-repeat: no-repeat;
      z-index: -3;
    }

    .glass-veil {
      position: fixed;
      inset: 0;
      background: linear-gradient(
        90deg,
        rgba(0, 0, 0, 0.12) 0%,
        rgba(0, 0, 0, 0.08) 40%,
        rgba(0, 0, 0, 0.22) 100%
      );
      z-index: -2;
    }

    /* Franja de humo animado, detrás de la tarjeta y encima del fondo azul.
       Va en un elemento hermano de .login-area (no dentro de la tarjeta) para
       que el backdrop-filter del vidrio de Clerk sí lo capture al difuminarlo. */
    .smoke-video {
      position: fixed;
      left: 0;
      bottom: 0;
      width: 100%;
      /* Alto por defecto antes de que el JS mida el borde inferior real de la
         tarjeta; se sobreescribe en línea para no invadir la zona del vidrio. */
      height: 22vh;
      object-fit: cover;
      object-position: center bottom;
      z-index: -1;
      pointer-events: none;
      mix-blend-mode: screen;
      opacity: 0.95;
      filter: brightness(1.3) contrast(1.2);
      mask-image: linear-gradient(to top, black 50%, transparent 100%);
      -webkit-mask-image: linear-gradient(to top, black 50%, transparent 100%);
    }

    /* Solo ocultamos visualmente con el ajuste de accesibilidad del SO; no
       llamamos a video.pause() por JS, así que esto nunca detiene el clip. */
    @media (prefers-reduced-motion: reduce) {
      .smoke-video {
        display: none;
      }
    }

    .login-area {
      position: relative;
      min-height: 100vh;
      display: flex;
      justify-content: flex-end;
      align-items: center;
      padding-right: 0rem;
      padding-left: 2rem;
      z-index: 1;
    }

    .clerk-shell {
      width: min(420px, 100%);
      background: transparent !important;
      border: none !important;
      box-shadow: none !important;
      padding: 0;
      transform: translateY(-60px);
    }

    .clerk-host {
      min-height: 240px;
    }

    .loading-status {
      margin-top: 1rem;
      text-align: center;
      color: white;
    }

    @media (max-width: 768px) {
      .login-area {
        justify-content: center;
        padding: 1.5rem;
      }

      .clerk-shell {
        width: 100%;
        max-width: 420px;
      }
    }

    /* ==========================================================================
       2. EFECTO GLASSMORPHISM AZUL SOBRE LA TARJETA DE CLERK
       ========================================================================== */

    /* Reset de contenedores: quitamos cualquier fondo/sombra por defecto de Clerk
       para que no quede una capa opaca por debajo del vidrio (rompería el blur). */
    .clerk-host [class*="cl-internal"],
    .clerk-host .cl-rootBox,
    .clerk-host .cl-main,
    .clerk-host .cl-header {
      background: transparent !important;
      background-color: transparent !important;
      box-shadow: none !important;
      border: none !important;
    }

    /* .cl-cardBox es el contenedor visual real: engloba la tarjeta (cl-card) y el
       footer (cl-footer) como una sola pieza. Aplicamos AQUÍ el vidrio -con
       degradado azul y brillo superior izquierdo simulando reflejo- para que
       ambos bloques se vean como un único panel esmerilado. */
    .clerk-host .cl-cardBox {
      /* Dos brillos radiales (nacarado arriba-izq., frío abajo-der.) sobre el
         degradado azul base, para simular un sutil sheen perlado/iridiscente. */
      background:
        radial-gradient(120% 55% at 18% 8%, rgba(255, 255, 255, 0.32) 0%, rgba(255, 255, 255, 0) 52%),
        radial-gradient(80% 50% at 84% 94%, rgba(150, 190, 230, 0.16) 0%, rgba(150, 190, 230, 0) 60%),
        linear-gradient(
          135deg,
          rgba(170, 195, 230, 0.3) 0%,
          rgba(55, 100, 160, 0.44) 40%,
          rgba(10, 30, 65, 0.6) 100%
        ) !important;
      backdrop-filter: blur(18px) saturate(140%) brightness(0.92) !important;
      -webkit-backdrop-filter: blur(18px) saturate(140%) brightness(0.92) !important;
      border: 1px solid rgba(190, 230, 255, 0.85) !important;
      border-radius: 28px !important;
      box-shadow:
        0 0 70px 10px rgba(70, 180, 255, 0.35),
        0 25px 60px -15px rgba(0, 0, 0, 0.55),
        inset 0 1px 0 rgba(255, 255, 255, 0.6),
        inset 0 -1px 0 rgba(255, 255, 255, 0.12),
        inset 0 0 50px rgba(255, 255, 255, 0.08) !important;
      overflow: hidden !important;
    }

    /* Fallback para navegadores sin soporte de backdrop-filter: subimos la
       opacidad del fondo azul para mantener legibilidad sin el desenfoque. */
    @supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
      .clerk-host .cl-cardBox {
        background: rgba(15, 40, 80, 0.88) !important;
      }
    }

    /* La tarjeta (header + formulario) y el footer quedan transparentes para
       heredar el vidrio de cl-cardBox sin pintar una capa sólida encima. */
    .clerk-host .cl-card,
    .clerk-host .cl-footer,
    .clerk-host .cl-footerAction {
      background: transparent !important;
      background-color: transparent !important;
      box-shadow: none !important;
      border: none !important;
      border-radius: 0 !important;
    }

    /* Separador fino translúcido entre el formulario y el footer ("Sign up"/
       "Sign in", "Secured by Clerk", banner de development mode). */
    .clerk-host .cl-footer {
      border-top: 1px solid rgba(255, 255, 255, 0.25) !important;
    }

    /* ==========================================================================
       3. TEXTOS Y CONTRASTE DE INTERFAZ (TEXTS & LABELS)
       ========================================================================== */
    .clerk-host .cl-headerTitle {
      color: #ffffff !important;
      font-weight: 700 !important;
      font-size: 1.6rem !important;
    }

    .clerk-host .cl-formFieldLabel {
      color: #ffffff !important;
      font-weight: 700 !important;
      font-size: 0.95rem !important;
    }

    .clerk-host .cl-headerSubtitle,
    .clerk-host .cl-dividerText,
    .clerk-host .cl-footerActionText,
    .clerk-host .cl-footer,
    .clerk-host .cl-footer p,
    .clerk-host .cl-footer span {
      color: rgba(255, 255, 255, 0.8) !important;
      font-size: 0.95rem !important;
    }

    /* Enlaces del pie de página ("Sign up"/"Sign in" y "Development mode") */
    .clerk-host .cl-footerActionLink,
    .clerk-host .cl-footer a {
      color: #29b6ff !important;
      text-decoration: underline !important;
      font-weight: 600;
      font-size: 0.95rem !important;
    }

    /* Divisor "or" */
    .clerk-host .cl-dividerLine {
      background: rgba(255, 255, 255, 0.25) !important;
    }

    /* ==========================================================================
       4. INPUTS Y BOTONES ESTILO VIDRIO
       ========================================================================== */
    .clerk-host .cl-formFieldInput,
    .clerk-host .cl-socialButtonsBlockButton {
      background-color: rgba(255, 255, 255, 0.08) !important;
      border: 1px solid rgba(170, 220, 255, 0.65) !important;
      border-radius: 14px !important;
      color: #ffffff !important;
      font-weight: 400 !important;
      font-size: 1rem !important;
      /* Bisel metálico: brillo superior + sombra inferior + halo azul. */
      box-shadow:
        inset 0 1px 0 rgba(255, 255, 255, 0.35),
        inset 0 -1px 0 rgba(0, 0, 0, 0.25),
        0 0 18px rgba(41, 182, 255, 0.15) !important;
    }

    .clerk-host .cl-formFieldInput::placeholder {
      color: rgba(255, 255, 255, 0.55) !important;
    }

    .clerk-host .cl-formFieldInput:focus,
    .clerk-host .cl-socialButtonsBlockButton:hover,
    .clerk-host .cl-socialButtonsBlockButton:focus-visible {
      /* background-color (no el shorthand): el shorthand borraría el icono
         de email (background-image) mientras el campo tiene foco/al escribir. */
      background-color: rgba(255, 255, 255, 0.14) !important;
      border-color: #29b6ff !important;
      box-shadow: 0 0 0 3px rgba(41, 182, 255, 0.35) !important;
    }

    /* Icono de sobre en el campo de email (Clerk no soporta iconos nativos).
       El input real usa type="text" con name="identifier"/"emailAddress",
       no type="email". */
    .clerk-host .cl-formFieldInput__identifier,
    .clerk-host .cl-formFieldInput__emailAddress {
      padding-left: 3.1rem !important;
    }

    /* El icono NO es un background-image del input: Chrome aplica
       "background-image: none !important" (hoja UA) a los campos
       autocompletados y ningún CSS de la página puede pisarlo. Tampoco vive
       dentro del DOM de Clerk (que puede recortarlo o re-renderizarlo): es un
       <span> hijo de .clerk-shell (nuestro), que AuthShellBase.syncEmailIcons()
       posiciona encima de cada input de email con getBoundingClientRect. */
    .clerk-shell {
      position: relative;
    }

    .clerk-shell .auth-email-icon {
      position: absolute;
      width: 22px;
      height: 22px;
      transform: translateY(-50%);
      background: ${EMAIL_ICON_URL} no-repeat center / contain;
      pointer-events: none;
      z-index: 5;
      filter: drop-shadow(0 0 2px rgba(255, 255, 255, 0.45));
    }

    /* Clerk reserva un hueco para el CAPTCHA aunque no se muestre. */
    .clerk-host #clerk-captcha:empty {
      display: none !important;
    }

    /* Mensajes de error/advertencia (p. ej. requisitos de contraseña) en
       ámbar, sin altura reservada: el botón queda a la distancia normal. */
    .clerk-host .cl-formFieldErrorText,
    .clerk-host .cl-formFieldWarningText {
      color: ${FORM_ERROR_COLOR} !important;
      font-size: 0.95rem !important;
      font-weight: 500 !important;
      line-height: 1.35 !important;
      margin: 0.3rem 0 0 !important;
      padding: 0 !important;
      min-height: 0 !important;
    }

    .clerk-host .cl-formFieldErrorText svg,
    .clerk-host .cl-formFieldWarningText svg {
      color: ${FORM_ERROR_COLOR} !important;
      fill: currentColor;
    }

    /* Borde del input en estado de error (Clerk marca aria-invalid). Va
       después de :focus para que el aro de foco también sea ámbar. */
    .clerk-host .cl-formFieldInput[aria-invalid='true'],
    .clerk-host .cl-formFieldInput[data-invalid] {
      border-color: ${FORM_ERROR_COLOR} !important;
    }

    .clerk-host .cl-formFieldInput[aria-invalid='true']:focus,
    .clerk-host .cl-formFieldInput[data-invalid]:focus {
      border-color: ${FORM_ERROR_COLOR} !important;
      box-shadow: 0 0 0 3px rgba(245, 158, 11, 0.35) !important;
    }

    /* Ojo de mostrar/ocultar contraseña: más grande y en plata, a juego con
       el sobre. Clerk lo dibuja con currentColor. */
    .clerk-host .cl-formFieldInputShowPasswordButton {
      color: #dfe6ee !important;
      padding-right: 0.9rem !important;
    }

    .clerk-host .cl-formFieldInputShowPasswordIcon {
      width: 1.4rem !important;
      height: 1.4rem !important;
      filter: drop-shadow(0 0 3px rgba(255, 255, 255, 0.35));
    }

    .clerk-host .cl-formFieldInputShowPasswordButton:hover {
      color: #ffffff !important;
    }

    /* Textos de ayuda del formulario (requisitos de contraseña, etc.) */
    .clerk-host .cl-formFieldInfoText,
    .clerk-host .cl-formFieldHintText,
    .clerk-host .cl-formFieldSuccessText {
      color: rgba(255, 255, 255, 0.95) !important;
      font-size: 0.95rem !important;
      font-weight: 500 !important;
      line-height: 1.4 !important;
      text-shadow: 0 1px 2px rgba(0, 0, 0, 0.45);
    }

    /* Botón Continuar: degradado azul marino con flecha */
    .clerk-host .cl-formButtonPrimary {
      margin-top: 0.25rem !important;
      display: flex !important;
      align-items: center;
      justify-content: center;
      gap: 0.5rem;
      background: linear-gradient(135deg, #0b2545, #050f24) !important;
      color: #ffffff !important;
      font-weight: 700 !important;
      font-size: 1.05rem !important;
      border: 1px solid rgba(120, 200, 255, 0.5) !important;
      border-radius: 14px !important;
      box-shadow: 0 0 18px rgba(41, 182, 255, 0.3) !important;
    }

    .clerk-host .cl-formButtonPrimary::after {
      content: '→';
      font-weight: 700;
    }
  `,
];

/**
 * Aplicado vía la API `appearance` de Clerk (en vez de depender solo de CSS
 * global): Clerk inyecta sus estilos como CSS-in-JS con clases que pueden
 * cambiar de forma, así que el override más confiable es pasarlo aquí,
 * directo al motor de estilos del propio componente. Se comparte entre
 * SignIn y SignUp porque usan exactamente los mismos nombres de elementos.
 */
const HELP_TEXT_STYLE = {
  color: 'rgba(255,255,255,0.95)',
  fontSize: '0.95rem',
  fontWeight: 500,
  lineHeight: 1.4,
  textShadow: '0 1px 2px rgba(0,0,0,0.45)',
};

const ERROR_TEXT_STYLE = {
  color: FORM_ERROR_COLOR,
  fontSize: '0.95rem',
  fontWeight: 500,
  lineHeight: 1.35,
  margin: '0.3rem 0 0',
  padding: 0,
  minHeight: 0,
};

export const CLERK_APPEARANCE: ClerkAppearance = {
  variables: {
    colorDanger: FORM_ERROR_COLOR,
    colorWarning: FORM_ERROR_COLOR,
  },
  elements: {
    rootBox: {
      background: 'transparent',
      boxShadow: 'none',
    },
    cardBox: {
      background:
        'radial-gradient(120% 55% at 18% 8%, rgba(255,255,255,0.32) 0%, rgba(255,255,255,0) 52%), radial-gradient(80% 50% at 84% 94%, rgba(150,190,230,0.16) 0%, rgba(150,190,230,0) 60%), linear-gradient(135deg, rgba(170,195,230,0.3) 0%, rgba(55,100,160,0.44) 40%, rgba(10,30,65,0.6) 100%)',
      backdropFilter: 'blur(18px) saturate(140%) brightness(0.92)',
      WebkitBackdropFilter: 'blur(18px) saturate(140%) brightness(0.92)',
      border: '1px solid rgba(150,210,255,0.75)',
      borderRadius: '28px',
      boxShadow:
        '0 0 70px 10px rgba(70,180,255,0.35), 0 25px 60px -15px rgba(0,0,0,0.55), inset 0 1px 0 rgba(255,255,255,0.45), inset 0 0 50px rgba(255,255,255,0.08)',
      overflow: 'hidden',
    },
    card: { background: 'transparent', boxShadow: 'none', border: 'none' },
    main: { background: 'transparent' },
    header: { background: 'transparent' },
    headerTitle: { color: '#ffffff', fontWeight: 700, fontSize: '1.6rem' },
    headerSubtitle: { color: 'rgba(255,255,255,0.8)', fontSize: '0.95rem' },
    footer: {
      background: 'transparent',
      borderTop: '1px solid rgba(255,255,255,0.25)',
    },
    footerAction: { background: 'transparent' },
    footerActionText: { color: 'rgba(255,255,255,0.8)', fontSize: '0.95rem' },
    footerActionLink: {
      color: '#29b6ff',
      textDecoration: 'underline',
      fontWeight: 600,
      fontSize: '0.95rem',
    },
    dividerRow: { background: 'transparent' },
    dividerLine: { background: 'rgba(255,255,255,0.25)' },
    dividerText: { color: 'rgba(255,255,255,0.7)', fontSize: '0.95rem' },
    formFieldLabel: { color: '#ffffff', fontWeight: 700, fontSize: '0.95rem' },
    formFieldInput: {
      backgroundColor: 'rgba(255,255,255,0.08)',
      border: '1px solid rgba(170,220,255,0.65)',
      borderRadius: '14px',
      color: '#ffffff',
      fontSize: '1rem',
      boxShadow:
        'inset 0 1px 0 rgba(255,255,255,0.35), inset 0 -1px 0 rgba(0,0,0,0.25), 0 0 18px rgba(41,182,255,0.15)',
      '&::placeholder': { color: 'rgba(255,255,255,0.55)' },
      // background-color (no el shorthand `background`): el shorthand borra
      // el background-image del icono de email al enfocar/escribir.
      '&:focus': {
        backgroundColor: 'rgba(255,255,255,0.14)',
        borderColor: '#29b6ff',
        boxShadow: '0 0 0 3px rgba(41,182,255,0.35)',
      },
    },
    // El CSS global de más arriba no logra pisar el padding/background por
    // defecto de estos campos específicos (Clerk los protege con reglas
    // propias de mayor prioridad); por eso el icono se define aquí también.
    formFieldInput__identifier: { paddingLeft: '3.1rem' },
    formFieldInput__emailAddress: { paddingLeft: '3.1rem' },
    formFieldInputShowPasswordButton: {
      color: '#dfe6ee',
      paddingRight: '0.9rem',
      '&:hover': { color: '#ffffff' },
    },
    formFieldInputShowPasswordIcon: {
      width: '1.4rem',
      height: '1.4rem',
      filter: 'drop-shadow(0 0 3px rgba(255,255,255,0.35))',
    },
    formFieldErrorText: ERROR_TEXT_STYLE,
    formFieldWarningText: ERROR_TEXT_STYLE,
    formFieldInfoText: HELP_TEXT_STYLE,
    formFieldHintText: HELP_TEXT_STYLE,
    formFieldSuccessText: HELP_TEXT_STYLE,
    socialButtonsBlockButton: {
      backgroundColor: 'rgba(255,255,255,0.08)',
      border: '1px solid rgba(170,220,255,0.65)',
      borderRadius: '14px',
      color: '#ffffff',
      fontSize: '1rem',
      boxShadow:
        'inset 0 1px 0 rgba(255,255,255,0.35), inset 0 -1px 0 rgba(0,0,0,0.25), 0 0 18px rgba(41,182,255,0.15)',
      '&:hover': { backgroundColor: 'rgba(255,255,255,0.14)', borderColor: '#29b6ff' },
    },
    formButtonPrimary: {
      background: 'linear-gradient(135deg, #0b2545, #050f24)',
      color: '#ffffff',
      fontWeight: 700,
      fontSize: '1.05rem',
      border: '1px solid rgba(120,200,255,0.5)',
      borderRadius: '14px',
      boxShadow: '0 0 18px rgba(41,182,255,0.3)',
    },
  },
};

/**
 * Lógica compartida (video de humo, medición dinámica de altura, ocultar el
 * badge de "Development mode") entre las pantallas de SignIn y SignUp. Las
 * subclases solo implementan `mount`/`unmount` contra el widget de Clerk que
 * corresponda.
 */
@Directive()
export abstract class AuthShellBase implements AfterViewInit, OnDestroy {
  @ViewChild('authHost', { static: true }) protected readonly authHost!: ElementRef<HTMLElement>;
  @ViewChild('smokeVideo', { static: true }) private readonly smokeVideo!: ElementRef<HTMLVideoElement>;
  @ViewChild('clerkShell', { static: true }) private readonly clerkShell!: ElementRef<HTMLElement>;

  private cardResizeObserver: ResizeObserver | null = null;
  private readonly emailIcons = new Map<HTMLInputElement, HTMLElement>();
  private iconSettleTimer: ReturnType<typeof setTimeout> | null = null;
  private devBadgeObserver: MutationObserver | null = null;
  ready = false;

  protected abstract mount(host: HTMLElement): Promise<void>;
  protected abstract unmount(host: HTMLElement): Promise<void>;

  async ngAfterViewInit(): Promise<void> {
    this.playSmokeVideo();
    this.updateSmokeHeight();
    window.addEventListener('resize', this.updateSmokeHeight);

    // El navegador pausa el video al minimizar/cambiar de pestaña para
    // ahorrar batería, y al volver (o al restaurarse la página desde el
    // bfcache con el back/forward del navegador) no lo reanuda solo.
    const video = this.smokeVideo?.nativeElement;
    video?.addEventListener('pause', this.resumeSmokeVideo);
    document.addEventListener('visibilitychange', this.resumeSmokeVideo);
    window.addEventListener('pageshow', this.resumeSmokeVideo);

    this.cardResizeObserver = new ResizeObserver(() => this.updateSmokeHeight());
    this.cardResizeObserver.observe(this.clerkShell.nativeElement);

    this.patchClerkBadges();

    await this.mount(this.authHost.nativeElement);
    this.ready = true;
    // El contenido de Clerk (Google, footer, banner de dev) llega async y
    // cambia la altura real de la tarjeta después del mount.
    this.updateSmokeHeight();
  }

  /**
   * El texto "Development mode" y "Secured by" del pie de Clerk no tiene una
   * clase pública estable, y el CSS/`appearance` normal no logra pisarlo
   * (Clerk lo protege con reglas propias de más prioridad) — por eso, a
   * diferencia del resto de la tarjeta, aquí lo localizamos por su texto
   * (nunca por la clase hash `cl-internal-*`, que cambia en cada build de
   * Clerk) y lo ajustamos directo por JS: ocultamos "Development mode" (solo
   * desaparece de verdad con claves de producción de Clerk) y agrandamos +
   * aclaramos "Secured by" (Clerk lo fija en un gris casi negro que, sobre
   * el vidrio oscuro de la tarjeta, se pierde contra el patrón punteado de
   * su propio overlay de "dev mode"). El MutationObserver cubre el caso de
   * que Clerk los inserte después del mount inicial.
   */
  private patchClerkBadges(): void {
    const root = this.clerkShell?.nativeElement;
    if (!root) {
      return;
    }
    const patch = () => {
      this.syncEmailIcons();
      // Clerk anima la entrada del formulario: reposicionar cuando asiente.
      if (this.iconSettleTimer) {
        clearTimeout(this.iconSettleTimer);
      }
      this.iconSettleTimer = setTimeout(() => this.syncEmailIcons(), 350);
      root.querySelectorAll<HTMLElement>('p, span, div, a').forEach((el) => {
        if (el.children.length !== 0) {
          return;
        }
        const text = el.textContent?.trim();
        if (text === 'Development mode') {
          el.style.display = 'none';
        } else if (text === 'Secured by') {
          el.style.fontSize = '1rem';
          el.style.fontWeight = '500';
          el.style.color = 'rgba(255, 255, 255, 0.95)';
          el.style.textShadow = '0 1px 2px rgba(0, 0, 0, 0.45)';
        }
      });
    };
    patch();
    this.devBadgeObserver = new MutationObserver(patch);
    this.devBadgeObserver.observe(root, { childList: true, subtree: true });
  }

  /**
   * Dibuja un icono de sobre sobre cada input de email/identifier de Clerk.
   * Los iconos son hijos de `.clerk-shell` (fuera del DOM de Clerk) y se
   * posicionan con las coordenadas reales del input, así que no los afectan ni
   * el autocompletado de Chrome ni los re-renders de Clerk. Es idempotente:
   * se llama en cada mutación, resize y tras el mount.
   */
  private syncEmailIcons(): void {
    const shell = this.clerkShell?.nativeElement;
    if (!shell) {
      return;
    }
    const inputs = Array.from(
      shell.querySelectorAll<HTMLInputElement>(
        'input[name="emailAddress"], input[name="identifier"], input[id^="emailAddress"], input[id^="identifier"]',
      ),
    );
    const shellRect = shell.getBoundingClientRect();

    for (const [input, icon] of this.emailIcons) {
      if (!inputs.includes(input)) {
        icon.remove();
        this.emailIcons.delete(input);
      }
    }
    for (const input of inputs) {
      let icon = this.emailIcons.get(input);
      if (!icon) {
        icon = document.createElement('span');
        icon.className = 'auth-email-icon';
        icon.setAttribute('aria-hidden', 'true');
        shell.appendChild(icon);
        this.emailIcons.set(input, icon);
      }
      const rect = input.getBoundingClientRect();
      const visible = rect.width > 0 && rect.height > 0;
      icon.style.display = visible ? '' : 'none';
      icon.style.left = `${rect.left - shellRect.left + 14}px`;
      icon.style.top = `${rect.top - shellRect.top + rect.height / 2}px`;
    }
  }

  /**
   * El atributo `muted` en el HTML no siempre se traduce a la propiedad IDL
   * `video.muted` cuando el elemento lo crea un framework (en vez del parser
   * HTML nativo) — en ese caso el navegador ve el video como "con sonido" y
   * bloquea el autoplay silenciosamente (la promesa de `play()` se rechaza).
   * Forzamos la propiedad explícitamente antes de reproducir para evitarlo.
   */
  private playSmokeVideo(): void {
    const video = this.smokeVideo?.nativeElement;
    if (!video) {
      return;
    }
    video.muted = true;
    video.defaultMuted = true;
    video.playbackRate = 1.35;
    video.play()?.catch(() => {
      /* Autoplay bloqueado por el navegador: el fondo se ve igual, sin humo animado. */
    });
  }

  /**
   * Reintenta reproducir cuando el navegador pausó el clip por su cuenta
   * (pestaña oculta, página restaurada desde el bfcache, etc.). Nunca lo
   * pausamos nosotros, así que cualquier pausa detectada aquí es externa.
   */
  private readonly resumeSmokeVideo = (): void => {
    if (document.visibilityState === 'visible') {
      this.playSmokeVideo();
    }
  };

  /**
   * Mide dónde termina realmente la tarjeta y limita la franja de humo a lo
   * que queda por debajo, para que nunca se superponga al vidrio de Clerk.
   */
  private readonly updateSmokeHeight = (): void => {
    const video = this.smokeVideo?.nativeElement;
    const card = this.clerkShell?.nativeElement;
    if (!video || !card) {
      return;
    }
    const gap = 16;
    const cardBottom = card.getBoundingClientRect().bottom;
    const available = Math.max(window.innerHeight - cardBottom - gap, 0);
    video.style.height = `${available}px`;
    this.syncEmailIcons();
  };

  async ngOnDestroy(): Promise<void> {
    window.removeEventListener('resize', this.updateSmokeHeight);
    document.removeEventListener('visibilitychange', this.resumeSmokeVideo);
    window.removeEventListener('pageshow', this.resumeSmokeVideo);
    this.smokeVideo?.nativeElement.removeEventListener('pause', this.resumeSmokeVideo);
    this.cardResizeObserver?.disconnect();
    this.devBadgeObserver?.disconnect();
    if (this.iconSettleTimer) {
      clearTimeout(this.iconSettleTimer);
    }
    this.emailIcons.forEach((icon) => icon.remove());
    this.emailIcons.clear();
    await this.unmount(this.authHost.nativeElement);
  }
}
