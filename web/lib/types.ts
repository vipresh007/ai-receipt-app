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

export interface TrendPoint {
  month: string; // YYYY-MM
  total: string;
}

export interface SpendingSummary {
  month: string;
  total: string;
  by_category: CategoryTotal[];
  previous_month_total: string;
  earliest_month: string | null;
}

export type InsightKind = "up" | "down" | "neutral" | "streak" | "summary";

export interface Me {
  id: string;
  email: string;
  display_name: string;
  plan: string;
}

export interface Budget {
  category_slug: string;
  monthly_limit: string;
  spent: string;
  remaining: string;
  percent_used: number;
}

export interface RecurringGroup {
  merchant: string;
  category_slug: string;
  average_amount: string;
  occurrences: number;
  last_purchased_at: string;
  receipt_ids: string[];
}
