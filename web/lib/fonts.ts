import { Bricolage_Grotesque, IBM_Plex_Mono, Inter } from "next/font/google";

/** Body/UI face. Variable weight — headlines just go bolder. (tokens.css names
 * Inter too, but only this next/font load actually fetches it.) */
export const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});

/** Display face for the "ledger" direction — big headlines and hero figures. */
export const display = Bricolage_Grotesque({
  subsets: ["latin"],
  variable: "--font-display",
  display: "swap",
  axes: ["opsz"],
});

/** Receipt/ledger figures, eyebrow labels, and anything that reads as printed. */
export const mono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["400", "500"],
  variable: "--font-mono",
  display: "swap",
});
