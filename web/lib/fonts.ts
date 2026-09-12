import { Fraunces } from "next/font/google";

/** Editorial display serif for headlines — Inter stays the body/UI face.
 * Self-hosted by Next at build time; exposes `--font-serif` everywhere the
 * `variable` className is applied (see app/layout.tsx). */
export const fraunces = Fraunces({
  subsets: ["latin"],
  weight: ["400", "500"],
  style: ["normal", "italic"],
  variable: "--font-serif",
  display: "swap",
});
