let homeCurrency = guessCurrency();

/** The account's home currency (components/home-currency.tsx sets it):
 * amounts with no currency of their own are shown in it. */
export function setHomeCurrency(code: string): void {
  homeCurrency = code;
}

export function getHomeCurrency(): string {
  return homeCurrency;
}

/** A first guess before the account answers, with no location prompt: the
 * device's time zone says the country (Toronto → CAD), else its language
 * region (en-GB → GBP). */
export function guessCurrency(): string {
  if (typeof Intl === "undefined") return "USD";
  try {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone ?? "";
    if (CANADA_ZONES.has(zone)) return "CAD";
    for (const [prefix, code] of ZONE_CURRENCIES) if (zone.startsWith(prefix)) return code;
    const region = typeof navigator !== "undefined" ? navigator.language.split("-")[1]?.toUpperCase() : undefined;
    if (region && REGION_CURRENCIES[region]) return REGION_CURRENCIES[region];
  } catch {
    /* fall through */
  }
  return "USD";
}

const CANADA_ZONES = new Set([
  "America/Toronto", "America/Montreal", "America/Vancouver", "America/Edmonton", "America/Winnipeg",
  "America/Halifax", "America/St_Johns", "America/Regina", "America/Moncton", "America/Whitehorse",
  "America/Yellowknife", "America/Iqaluit", "America/Glace_Bay", "America/Goose_Bay", "America/Swift_Current",
  "America/Dawson_Creek", "America/Fort_Nelson", "America/Creston", "America/Rankin_Inlet", "America/Cambridge_Bay",
  "America/Nipigon", "America/Thunder_Bay", "America/Rainy_River", "America/Atikokan", "America/Inuvik",
  "America/Dawson", "America/Resolute", "America/Pangnirtung", "America/Blanc-Sablon",
]);

const ZONE_CURRENCIES: [string, string][] = [
  ["Europe/London", "GBP"], ["Europe/Dublin", "EUR"], ["Europe/Zurich", "CHF"], ["Europe/Oslo", "NOK"],
  ["Europe/Stockholm", "SEK"], ["Europe/Copenhagen", "DKK"], ["Europe/Warsaw", "PLN"], ["Europe/Prague", "CZK"],
  ["Europe/Budapest", "HUF"], ["Europe/Istanbul", "TRY"], ["Europe/Moscow", "RUB"], ["Europe/", "EUR"],
  ["Asia/Kolkata", "INR"], ["Asia/Calcutta", "INR"], ["Asia/Tokyo", "JPY"], ["Asia/Singapore", "SGD"],
  ["Asia/Hong_Kong", "HKD"], ["Asia/Shanghai", "CNY"], ["Asia/Seoul", "KRW"], ["Asia/Dubai", "AED"],
  ["Asia/Manila", "PHP"], ["Asia/Karachi", "PKR"], ["Australia/", "AUD"], ["Pacific/Auckland", "NZD"],
  ["America/Mexico_City", "MXN"], ["America/Sao_Paulo", "BRL"], ["Africa/Johannesburg", "ZAR"],
];

const REGION_CURRENCIES: Record<string, string> = {
  CA: "CAD", US: "USD", GB: "GBP", IN: "INR", AU: "AUD", NZ: "NZD", JP: "JPY", MX: "MXN", BR: "BRL",
  CH: "CHF", SE: "SEK", NO: "NOK", DK: "DKK", SG: "SGD", HK: "HKD", AE: "AED", ZA: "ZAR", PH: "PHP",
  DE: "EUR", FR: "EUR", ES: "EUR", IT: "EUR", NL: "EUR", IE: "EUR", PT: "EUR", BE: "EUR", AT: "EUR", FI: "EUR",
};

export function money(value: string | number, currency: string = homeCurrency): string {
  const n = typeof value === "string" ? Number(value) : value;
  if (!Number.isFinite(n)) return "—";
  const format = (code: string) =>
    // "$" rather than "US$"/"CA$": the currency is the account's own.
    new Intl.NumberFormat(undefined, { style: "currency", currency: code, currencyDisplay: "narrowSymbol" }).format(n);
  try {
    return format(currency || homeCurrency);
  } catch {
    return format("USD");
  }
}

export function shortDate(iso: string | null): string {
  if (!iso) return "";
  const d = new Date(iso.length === 10 ? `${iso}T00:00:00` : iso);
  if (Number.isNaN(d.getTime())) return "";
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" }).format(d);
}

/** A decimal-string amount as whole cents. Unparseable or partial input
 * ("", ".") counts as 0, so a value typed one keystroke at a time adds up. */
export function toCents(value: string): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(n * 100) : 0;
}

/** Whole cents back to the 2-decimal string the API takes. */
export function fromCents(cents: number): string {
  return (cents / 100).toFixed(2);
}
