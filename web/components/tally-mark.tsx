/** The Tally mark — a tally-of-five (four strokes + a diagonal). Uses
 *  currentColor so it inherits text color; pair it with the accent square. */
export function TallyMark({ size = 18, className }: { size?: number; className?: string }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 1024 1024"
      fill="none"
      className={className}
      aria-hidden="true"
    >
      <g stroke="currentColor" strokeWidth={96} strokeLinecap="round">
        <line x1="344" y1="300" x2="344" y2="724" />
        <line x1="459" y1="300" x2="459" y2="724" />
        <line x1="574" y1="300" x2="574" y2="724" />
        <line x1="689" y1="300" x2="689" y2="724" />
        <line x1="300" y1="708" x2="733" y2="316" />
      </g>
    </svg>
  );
}
