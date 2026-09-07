export type CategorySlug =
  | "groceries"
  | "restaurants"
  | "transport"
  | "shopping"
  | "entertainment"
  | "health"
  | "utilities"
  | "travel"
  | "other";

export interface ExtractionItem {
  name: string;
  price: string;
  quantity: number;
}

export interface Extraction {
  merchant: string;
  date: string | null;
  total: string;
  tax: string;
  category: string;
  items: ExtractionItem[];
  confidence: number | null;
}

export interface ReceiptOut {
  id: string;
  merchant: string;
  purchased_at: string | null;
  total: string;
  tax: string;
  currency: string;
  category_slug: string;
  image_blob_url: string | null;
  extraction_confidence: number | null;
  line_items: ExtractionItem[];
}

export interface CategoryTotal {
  category_slug: string;
  amount: string;
}

export interface SpendingSummary {
  month: string;
  total: string;
  by_category: CategoryTotal[];
  previous_month_total: string;
}

export type InsightKind = "up" | "down" | "neutral" | "streak" | "summary";

export interface Insight {
  id: string;
  kind: InsightKind;
  message: string;
  period_start: string;
  period_end: string;
  generated_by: string;
}

export interface TokenOut {
  access_token: string;
  token_type: string;
  expires_in: number;
}
