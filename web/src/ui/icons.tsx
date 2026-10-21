/**
 * Inline icon set. Twenty paths is cheaper than an icon dependency in a
 * single-file bundle, and it keeps the artefact self-contained.
 */

type IconSpec = { paths: string[]; solid?: boolean }

const ICONS = {
  search: { paths: ["M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16Z", "m21 21-4.35-4.35"] },
  play: { paths: ["M8 5.5v13l11-6.5z"], solid: true },
  pause: { paths: ["M9 5h2v14H9z", "M13 5h2v14h-2z"], solid: true },
  download: { paths: ["M12 3v12", "m7 11 5 5 5-5", "M4 19h16"] },
  check: { paths: ["m4 12.5 5 5L20 6.5"] },
  x: { paths: ["m6 6 12 12", "m18 6-12 12"] },
  plus: { paths: ["M12 5v14", "M5 12h14"] },
  minus: { paths: ["M5 12h14"] },
  "chevron-down": { paths: ["m6 9 6 6 6-6"] },
  "chevron-right": { paths: ["m9 6 6 6-6 6"] },
  "chevron-left": { paths: ["m15 6-6 6 6 6"] },
  "arrow-up": { paths: ["M12 20V5", "m5 12 7-7 7 7"] },
  "arrow-down": { paths: ["M12 4v15", "m19 12-7 7-7-7"] },
  folder: { paths: ["M3 7.5A2 2 0 0 1 5 5.5h3.5l2 2H19a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"] },
  trash: { paths: ["M4 7h16", "M9 7V5h6v2", "M6 7l1 12h10l1-12", "M10 11v5", "M14 11v5"] },
  retry: { paths: ["M20 12a8 8 0 1 1-2.5-5.8", "M20 4v4h-4"] },
  film: { paths: ["M3 5h18v14H3z", "M8 5v14", "M16 5v14", "M3 9h5", "M3 15h5", "M16 9h5", "M16 15h5"] },
  users: { paths: ["M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Z", "M2.5 20a6.5 6.5 0 0 1 13 0", "M16 5.2a3.5 3.5 0 0 1 0 6.6", "M17 13.6a6.5 6.5 0 0 1 4.5 6.4"] },
  book: { paths: ["M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5z", "M4 5.5v15"] },
  clock: { paths: ["M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18Z", "M12 7.5V12l3 2"] },
  alert: { paths: ["M12 4 2.5 20h19z", "M12 10v4.5", "M12 17.4v.2"] },
  filter: { paths: ["M3 5h18l-7 8v6l-4-2v-4z"] },
  layers: { paths: ["m12 3 9 5-9 5-9-5z", "m3 13 9 5 9-5"] },
  grid: { paths: ["M4 4h7v7H4z", "M13 4h7v7h-7z", "M4 13h7v7H4z", "M13 13h7v7h-7z"] },
  list: { paths: ["M8 6h13", "M8 12h13", "M8 18h13", "M3.5 6h.01", "M3.5 12h.01", "M3.5 18h.01"] },
  dot: { paths: ["M12 12m-3 0a3 3 0 1 0 6 0 3 3 0 1 0-6 0"], solid: true },
  speed: { paths: ["M12 20a8 8 0 1 1 8-8", "M12 12l5-3"] },
  logo: { paths: ["M5 4h9a6 6 0 0 1 0 12H5z", "M5 12h6", "M5 4v16"] },
} satisfies Record<string, IconSpec>

export type IconName = keyof typeof ICONS

export function Icon({
  name,
  size = 16,
  className,
  strokeWidth = 1.7,
}: {
  name: IconName
  size?: number
  className?: string
  strokeWidth?: number
}) {
  const spec: IconSpec = ICONS[name]
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      className={className}
      aria-hidden="true"
      focusable="false"
      fill={spec.solid ? "currentColor" : "none"}
      stroke={spec.solid ? "none" : "currentColor"}
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {spec.paths.map((path, index) => (
        <path key={index} d={path} />
      ))}
    </svg>
  )
}
