import { Inter } from "next/font/google";

/** The site's one typeface, actually loaded (previously `--font-sans` named
 * Inter in tokens.css but nothing ever fetched it, so every page silently
 * fell back to the OS UI font). Variable weight — headlines just go bolder. */
export const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
});
