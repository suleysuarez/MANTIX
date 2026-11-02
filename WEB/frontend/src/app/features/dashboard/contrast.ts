/** Contraste WCAG 2.x entre dos colores `rgb()`/`rgba()`/`#rrggbb` (ratio 1 a 21). */

interface Rgba {
  rgb: [number, number, number];
  alpha: number;
}

/** Acepta `#rrggbb`, `rgb()/rgba()` y `color(srgb r g b / a)` (lo que devuelve `color-mix`). */
function parse(color: string): Rgba {
  const hex = /^#([0-9a-f]{6})$/i.exec(color.trim());
  if (hex) {
    const value = parseInt(hex[1], 16);
    return { rgb: [(value >> 16) & 255, (value >> 8) & 255, value & 255], alpha: 1 };
  }
  const srgb = /color\(srgb\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)(?:\s*\/\s*([\d.]+))?\)/.exec(color);
  if (srgb) {
    return {
      rgb: [Number(srgb[1]) * 255, Number(srgb[2]) * 255, Number(srgb[3]) * 255],
      alpha: srgb[4] === undefined ? 1 : Number(srgb[4]),
    };
  }
  const match = /rgba?\(([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\)/.exec(color);
  if (!match) {
    throw new Error(`Color no soportado: ${color}`);
  }
  return {
    rgb: [Number(match[1]), Number(match[2]), Number(match[3])],
    alpha: match[4] === undefined ? 1 : Number(match[4]),
  };
}

/** Color opaco resultante de poner `color` (con su alfa) sobre `backdrop`. */
export function flatten(color: string, backdrop = '#ffffff'): string {
  const top = parse(color);
  const base = parse(backdrop).rgb;
  const mixed = top.rgb.map((value, i) => Math.round(value * top.alpha + base[i] * (1 - top.alpha)));
  return `rgb(${mixed.join(', ')})`;
}

function channels(color: string): [number, number, number] {
  return parse(color).rgb;
}

function luminance(color: string): number {
  const [r, g, b] = channels(color).map((value) => {
    const c = value / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrastRatio(foreground: string, background: string): number {
  const [light, dark] = [luminance(foreground), luminance(background)].sort((a, b) => b - a);
  return (light + 0.05) / (dark + 0.05);
}

/** Mínimo WCAG AA para texto normal. */
export const WCAG_AA = 4.5;
