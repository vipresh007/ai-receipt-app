import {
  Car,
  Clapperboard,
  HeartPulse,
  LayoutGrid,
  type LucideIcon,
  Plane,
  Plug,
  ShoppingBag,
  ShoppingCart,
  UtensilsCrossed,
} from "lucide-react";
import type { CategorySlug } from "./types";

export const CATEGORY_ORDER: CategorySlug[] = [
  "groceries",
  "restaurants",
  "transport",
  "shopping",
  "entertainment",
  "health",
  "utilities",
  "travel",
  "other",
];

interface CategoryMeta {
  label: string;
  icon: LucideIcon;
  cssVar: string;
}

export const CATEGORY: Record<CategorySlug, CategoryMeta> = {
  groceries: { label: "Groceries", icon: ShoppingCart, cssVar: "--cat-groceries" },
  restaurants: { label: "Restaurants", icon: UtensilsCrossed, cssVar: "--cat-restaurants" },
  transport: { label: "Transport", icon: Car, cssVar: "--cat-transport" },
  shopping: { label: "Shopping", icon: ShoppingBag, cssVar: "--cat-shopping" },
  entertainment: { label: "Entertainment", icon: Clapperboard, cssVar: "--cat-entertainment" },
  health: { label: "Health", icon: HeartPulse, cssVar: "--cat-health" },
  utilities: { label: "Utilities", icon: Plug, cssVar: "--cat-utilities" },
  travel: { label: "Travel", icon: Plane, cssVar: "--cat-travel" },
  other: { label: "Other", icon: LayoutGrid, cssVar: "--cat-other" },
};

export function categoryMeta(slug: string): CategoryMeta {
  return CATEGORY[slug as CategorySlug] ?? CATEGORY.other;
}

export function categoryColor(slug: string): string {
  return `var(${categoryMeta(slug).cssVar})`;
}
