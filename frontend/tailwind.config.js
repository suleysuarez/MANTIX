/** Design tokens exportados del diseño de Stitch (paleta azul pizarra + mostaza). */
const font = ['"Plus Jakarta Sans"', 'sans-serif'];

/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{html,ts}'],
  // Preflight desactivado: las pantallas existentes y el widget de Clerk traen su propio CSS.
  corePlugins: { preflight: false },
  theme: {
    extend: {
      colors: {
        // Paleta de las pantallas de equipos (referencia de diseño Mantix).
        brand: {
          navy: '#0b172a', sidebar: '#0d1f38', accentLight: '#ADD7F6', accentSky: '#A2D2FF',
          accentDeep: '#3E5C76', slate: '#778DA9', mustard: '#E4B363', mustardHover: '#d4a250',
        },
        'on-tertiary-fixed-variant': '#104a70', 'surface-tint': '#43617c', secondary: '#7d5700',
        'primary-fixed-dim': '#abcae8', 'error-container': '#ffdad6', 'on-error-container': '#93000a',
        primary: '#26445d', 'inverse-surface': '#2b3136', 'secondary-fixed-dim': '#fbbc43',
        'tertiary-fixed': '#cde5ff', background: '#f5faff', 'outline-variant': '#c3c7cd',
        'on-tertiary-fixed': '#001d32', 'tertiary-fixed-dim': '#9bcbf8',
        'on-secondary-fixed-variant': '#5f4100', outline: '#73777d', 'on-surface': '#161c21',
        'surface-container-lowest': '#ffffff', 'on-surface-variant': '#42474d', tertiary: '#05456b',
        'surface-variant': '#dde3e9', 'on-primary': '#ffffff', 'surface-bright': '#f5faff',
        'on-tertiary': '#ffffff', surface: '#f5faff', 'on-secondary-container': '#704e00',
        'secondary-fixed': '#ffdeaa', 'inverse-on-surface': '#ecf1f8', 'inverse-primary': '#abcae8',
        'surface-container-low': '#eef4fa', 'tertiary-container': '#2a5d84',
        'surface-container-highest': '#dde3e9', 'surface-container': '#e9eef5',
        'surface-container-high': '#e3e9ef', 'on-primary-fixed-variant': '#2b4963',
        'primary-fixed': '#cce5ff', 'on-secondary-fixed': '#271900', 'primary-container': '#3e5c76',
        'on-primary-container': '#b5d4f2', 'secondary-container': '#febe46', 'on-error': '#ffffff',
        'on-tertiary-container': '#a9d5ff', error: '#ba1a1a', 'on-secondary': '#ffffff',
        'on-background': '#161c21', 'surface-dim': '#d5dbe1',
      },
      borderRadius: { DEFAULT: '0.25rem', lg: '0.5rem', xl: '0.75rem', full: '9999px' },
      spacing: {
        'space-xs': '0.25rem', 'space-sm': '0.5rem', 'space-md': '1rem', 'space-lg': '1.5rem',
        'space-xl': '2rem',
      },
      fontFamily: {
        sans: font, 'label-chip': font, 'body-lg': font, 'headline-lg': font, 'body-sm': font,
        'headline-sm': font, 'kpi-number': font, 'headline-md': font, 'display-hero': font,
        'label-caps': font, 'body-md': font,
      },
      fontSize: {
        'label-chip': ['12px', { lineHeight: '16px', letterSpacing: '0.01em', fontWeight: '600' }],
        'body-lg': ['16px', { lineHeight: '24px', letterSpacing: '0em', fontWeight: '400' }],
        'headline-lg': ['24px', { lineHeight: '32px', letterSpacing: '0.02em', fontWeight: '700' }],
        'body-sm': ['12px', { lineHeight: '16px', letterSpacing: '0.01em', fontWeight: '400' }],
        'headline-sm': ['15px', { lineHeight: '20px', letterSpacing: '0em', fontWeight: '600' }],
        'kpi-number': ['32px', { lineHeight: '38px', letterSpacing: '-0.02em', fontWeight: '700' }],
        'headline-md': ['18px', { lineHeight: '24px', letterSpacing: '0.01em', fontWeight: '700' }],
        'display-hero': ['36px', { lineHeight: '44px', letterSpacing: '0.04em', fontWeight: '800' }],
        'label-caps': ['11px', { lineHeight: '14px', letterSpacing: '0.06em', fontWeight: '700' }],
        'body-md': ['14px', { lineHeight: '20px', letterSpacing: '0em', fontWeight: '400' }],
      },
    },
  },
};
