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
      <source src="assets/videos/humo_fondo.mp4" type="video/mp4" />
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

const EMAIL_FIELD_STYLE = {
  paddingLeft: '3.1rem',
  backgroundImage: EMAIL_ICON_URL,
  backgroundRepeat: 'no-repeat',
  backgroundPosition: '0.9rem center',
  backgroundSize: '22px 22px',
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
    formFieldInput__identifier: EMAIL_FIELD_STYLE,
    formFieldInput__emailAddress: EMAIL_FIELD_STYLE,
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
      '&::after': { content: '"→"', marginLeft: '0.5rem' },
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
  private badgeObserver: MutationObserver | null = null;
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

    this.patchSecuredBy();
    await this.mount(this.authHost.nativeElement);
    this.ready = true;
    // El contenido de Clerk (Google, footer, banner de dev) llega async y
    // cambia la altura real de la tarjeta después del mount.
    this.updateSmokeHeight();
  }

  /** "Secured by" lo fija Clerk en gris casi negro; se localiza por texto y se aclara. */
  private patchSecuredBy(): void {
    const root = this.clerkShell?.nativeElement;
    if (!root) {
      return;
    }
    const patch = () => {
      root.querySelectorAll<HTMLElement>('p, span, div, a').forEach((el) => {
        if (el.children.length === 0 && el.textContent?.trim() === 'Secured by') {
          el.style.fontSize = '1rem';
          el.style.fontWeight = '500';
          el.style.color = 'rgba(255, 255, 255, 0.95)';
          el.style.textShadow = '0 1px 2px rgba(0, 0, 0, 0.45)';
        }
      });
    };
    patch();
    this.badgeObserver = new MutationObserver(patch);
    this.badgeObserver.observe(root, { childList: true, subtree: true });
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
  private readonly resumeSmokeVideo = (event?: Event): void => {
    // Al volver con "atrás" desde Google la página sale del bfcache con el
    // decodificador del video congelado: play() no basta, hay que recargar el
    // recurso (load() no recarga la página, solo el <video>).
    if ((event as PageTransitionEvent | undefined)?.persisted) {
      this.smokeVideo?.nativeElement.load();
    }
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
  };

  async ngOnDestroy(): Promise<void> {
    window.removeEventListener('resize', this.updateSmokeHeight);
    document.removeEventListener('visibilitychange', this.resumeSmokeVideo);
    window.removeEventListener('pageshow', this.resumeSmokeVideo);
    this.smokeVideo?.nativeElement.removeEventListener('pause', this.resumeSmokeVideo);
    this.cardResizeObserver?.disconnect();
    this.badgeObserver?.disconnect();
    await this.unmount(this.authHost.nativeElement);
  }
}
