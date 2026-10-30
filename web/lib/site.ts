/** Public facts about the site, shared by metadata, robots, the sitemap and
 * the landing page's structured data. */
export const SITE_URL = "https://tally.dataeaver.ca";
export const APP_STORE_ID = "6813650117";
export const APP_STORE_URL = `https://apps.apple.com/app/id${APP_STORE_ID}`;
export const SITE_TITLE = "Tally: Receipt Scanner & Spending Tracker";
export const SITE_DESCRIPTION =
  "Snap a photo of any receipt and Tally reads the store, total, tax and every item, then shows where your money goes each month. Free on iPhone and the web. No bank linking.";

/** Signed-in app routes: kept out of search indexes (they redirect to login). */
export const PRIVATE_PATHS = ["/dashboard", "/receipts", "/scan", "/account", "/expenses", "/budgets", "/months", "/groups", "/people", "/activity", "/s/", "/join/", "/p/"];
