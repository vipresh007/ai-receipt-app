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
  /** Set while the receipt is split: your share, which is what counts as spending. */
  my_share?: string | null;
  split_id?: string | null;
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
  email_notifications: boolean;
  interac: string;
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

// ─────────────────────────── splits & groups (docs/SPLITS.md) ───────────────────────────

export type SplitMode = "even" | "items" | "shares" | "percent" | "custom";
export type Repeat = "" | "weekly" | "monthly";

export interface ParticipantIn {
  is_me?: boolean;
  member_id?: string | null;
  person_id?: string | null;
  name?: string;
  is_payer?: boolean;
  item_indexes?: number[];
  amount?: string | null;
  weight?: string | null;
  /** Several payers: what this person put in. */
  paid?: string | null;
}

export interface SplitIn {
  receipt_id?: string | null;
  group_id?: string | null;
  description?: string;
  total?: string | null;
  currency?: string | null;
  date?: string | null;
  mode: SplitMode;
  items?: ExtractionItem[];
  participants: ParticipantIn[];
  repeat?: Repeat;
}

export interface Participant {
  id: string;
  display_name: string;
  member_id: string | null;
  person_id: string | null;
  is_me: boolean;
  is_payer: boolean;
  item_indexes: number[];
  amount: string | null;
  /** Shares mode: this person's parts; percent mode: their %. */
  weight: string | null;
  /** What they put in (one payer: the whole total). */
  paid: string | null;
  share: string;
  settled: boolean;
  share_url: string;
}

export interface Split {
  id: string;
  receipt_id: string | null;
  group_id: string | null;
  description: string;
  total: string;
  currency: string;
  date: string;
  mode: SplitMode;
  items: ExtractionItem[];
  participants: Participant[];
  my_share: string | null;
  is_owner: boolean;
  /** Anyone on it can change the amounts; only the owner who's on it. */
  can_edit: boolean;
  repeat: Repeat;
  next_at: string | null;
}

/** An expense's history and comments, oldest first. */
export interface TimelineEntry {
  id: string;
  kind: "event" | "comment";
  author_name: string;
  text: string;
  at: string;
  can_delete: boolean;
}

export interface PayDetails {
  interac: string | null;
}

export interface ActivityItem {
  id: string;
  actor_name: string;
  kind: string;
  text: string;
  at: string;
  read: boolean;
  split_id: string | null;
  group_id: string | null;
  person_id: string | null;
}

export interface ActivityFeed {
  unread: number;
  items: ActivityItem[];
}

export interface GroupMember {
  id: string;
  display_name: string;
  is_me: boolean;
  has_account: boolean;
  /** Positive = is owed, negative = owes. */
  balance: string;
  pay_to: PayDetails | null;
}

export interface Payment {
  from_member_id: string;
  to_member_id: string;
  amount: string;
}

export interface Settlement extends Payment {
  id: string;
  note: string;
  date: string;
}

export interface GroupSummary {
  id: string;
  name: string;
  currency: string;
  member_count: number;
  my_balance: string;
  invite_url: string;
  is_owner: boolean;
  /** Settle up with the fewest payments, or who owes whom directly. */
  simplify_debts: boolean;
}

export interface GroupDetail extends GroupSummary {
  members: GroupMember[];
  payments: Payment[];
  splits: Split[];
  settlements: Settlement[];
}

export interface PublicParticipant {
  display_name: string;
  share: string;
  is_you: boolean;
  is_payer: boolean;
  settled: boolean;
  item_indexes: number[];
}

export interface PublicSplit {
  description: string;
  date: string;
  currency: string;
  total: string;
  items: ExtractionItem[];
  participants: PublicParticipant[];
  payer_name: string | null;
  group_name: string | null;
  your_share: string;
  pay_to: PayDetails | null;
  mode: SplitMode;
  tax: string | null;
  owner_name: string;
  invite_url: string | null;
}

export interface PublicGroup {
  name: string;
  members: { id: string; display_name: string; claimed: boolean }[];
}

/** Someone you split with outside groups. Balance: positive = they owe you. */
export interface PersonSummary {
  id: string;
  name: string;
  email: string | null;
  has_account: boolean;
  invite_url: string;
  invited_at: string | null;
  /** Overall: outside groups plus each group you're both in. */
  balance: string;
  outside_groups: string;
  group_balances: { group_id: string; name: string; balance: string }[];
  currency: string;
  can_email: boolean;
  pay_to: PayDetails | null;
}

export interface PersonPayment {
  id: string;
  you_paid: boolean;
  amount: string;
  note: string;
  date: string;
  can_delete: boolean;
}

export interface PersonDetail extends PersonSummary {
  splits: Split[];
  payments: PersonPayment[];
}

/** An invite link, seen by the person invited. Balance from their side. */
export interface PublicPerson {
  from_name: string;
  name: string;
  claimed: boolean;
  balance: string;
  currency: string;
  expense_count: number;
}
