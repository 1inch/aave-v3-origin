import { GLOSSARY } from '../data/glossary';
import { ERRORS } from '../data/errors';

export type PaletteEntry = {
  kind: 'slide' | 'term' | 'error';
  label: string;
  sub: string;
  targetSlideId: string;
};

export function buildPaletteIndex(
  slides: { id: string; title: string; section: string }[],
): PaletteEntry[] {
  return [
    ...slides.map<PaletteEntry>((s) => ({
      kind: 'slide',
      label: s.title,
      sub: s.section,
      targetSlideId: s.id,
    })),
    ...GLOSSARY.map<PaletteEntry>((g) => ({
      kind: 'term',
      label: g.term,
      sub: g.def.slice(0, 70) + '…',
      targetSlideId: 'glossary',
    })),
    ...ERRORS.map<PaletteEntry>((e) => ({
      kind: 'error',
      label: e.name,
      sub: e.meaning.slice(0, 70),
      targetSlideId: 'errors',
    })),
  ];
}

export function paletteMatches(entry: PaletteEntry, query: string): boolean {
  const q = query.toLowerCase();
  return entry.label.toLowerCase().includes(q) || entry.sub.toLowerCase().includes(q);
}
