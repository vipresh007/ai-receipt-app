"use client";

import { useId, useMemo, useRef, useState } from "react";
import { Check, ChevronDown, Plus, X } from "lucide-react";
import type { PersonSummary } from "@/lib/types";
import { cn } from "@/lib/utils";

type Option = { kind: "saved"; person: PersonSummary } | { kind: "new"; name: string };

/** Pick who's on a split from your saved people by typing, or add someone
 * new: scales to any number of people (no wall of chips). */
export function PeoplePicker({
  saved,
  picked,
  names,
  onPick,
  onUnpick,
  onAddName,
  onRemoveName,
}: {
  saved: PersonSummary[];
  picked: { id: string; name: string }[];
  names: string[];
  onPick: (person: PersonSummary) => void;
  onUnpick: (id: string) => void;
  onAddName: (name: string) => void;
  onRemoveName: (index: number) => void;
}) {
  const listId = useId();
  const input = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);

  const options: Option[] = useMemo(() => {
    const taken = new Set(picked.map((p) => p.id));
    const q = query.trim().toLowerCase();
    const available = saved.filter((p) => !taken.has(p.id));
    if (!q) {
      // Nothing typed: the people you've split with most recently.
      return [...available]
        .sort((a, b) => (b.last_shared ?? "").localeCompare(a.last_shared ?? ""))
        .slice(0, 5)
        .map((person) => ({ kind: "saved" as const, person }));
    }
    const matches = available
      .filter((p) => p.name.toLowerCase().includes(q))
      .sort((a, b) => Number(!a.name.toLowerCase().startsWith(q)) - Number(!b.name.toLowerCase().startsWith(q)))
      .slice(0, 6)
      .map((person) => ({ kind: "saved" as const, person }));
    const exact = saved.some((p) => p.name.toLowerCase() === q) || names.some((n) => n.trim().toLowerCase() === q);
    return exact ? matches : [...matches, { kind: "new" as const, name: query.trim() }];
  }, [saved, picked, names, query]);

  function choose(option: Option) {
    if (option.kind === "saved") onPick(option.person);
    else onAddName(option.name);
    setQuery("");
    setActive(0);
    input.current?.focus();
  }

  function onKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setOpen(true);
      setActive((i) => Math.min(i + 1, options.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (options[active]) choose(options[active]);
    } else if (e.key === "Escape") {
      setOpen(false);
    } else if (e.key === "Backspace" && !query) {
      // Backspace in an empty box removes the last person added.
      if (names.length) onRemoveName(names.length - 1);
      else if (picked.length) onUnpick(picked[picked.length - 1].id);
    }
  }

  const chips = [
    ...picked.map((p) => ({ key: `p-${p.id}`, label: p.name, remove: () => onUnpick(p.id) })),
    ...names.map((n, i) => ({ key: `n-${i}`, label: n, isNew: true, remove: () => onRemoveName(i) })),
  ];

  return (
    <div className="space-y-sm">
      {chips.length > 0 && (
        <ul className="flex flex-wrap gap-xs" aria-label="On this split">
          {chips.map((chip) => (
            <li key={chip.key}>
              <span className="inline-flex items-center gap-[2px] rounded-pill bg-accent-muted py-[3px] pl-md pr-[3px] text-caption font-medium text-accent">
                {chip.label}
                {"isNew" in chip && <span className="ml-[2px] text-[10px] opacity-70">new</span>}
                <button
                  type="button"
                  onClick={chip.remove}
                  aria-label={`Remove ${chip.label}`}
                  className="grid h-5 w-5 place-items-center rounded-full hover:bg-accent/20"
                >
                  <X size={12} />
                </button>
              </span>
            </li>
          ))}
        </ul>
      )}
      <div className="relative">
        <input
          ref={input}
          role="combobox"
          aria-expanded={open && options.length > 0}
          aria-controls={listId}
          aria-autocomplete="list"
          aria-activedescendant={open && options[active] ? `${listId}-${active}` : undefined}
          aria-label="Add someone"
          placeholder={chips.length ? "Add someone else" : "Add someone: type a name"}
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setActive(0);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          onBlur={() => setTimeout(() => setOpen(false), 120)}
          onKeyDown={onKeyDown}
          maxLength={120}
          className="h-11 w-full rounded-md border border-border bg-surface px-md text-body text-text placeholder:text-text-tertiary focus-visible:border-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--c-focus-ring)]"
        />
        {open && options.length > 0 && (
          <ul
            id={listId}
            role="listbox"
            className="absolute inset-x-0 top-[calc(100%+4px)] z-20 max-h-72 overflow-y-auto rounded-md bg-surface py-xs shadow-e2 ring-1 ring-border"
          >
            {!query.trim() && (
              <li className="px-md pb-[2px] pt-xs text-[11px] font-medium uppercase tracking-[0.08em] text-text-tertiary">
                Recent
              </li>
            )}
            {options.map((option, i) => (
              <li
                key={option.kind === "saved" ? option.person.id : "new"}
                id={`${listId}-${i}`}
                role="option"
                aria-selected={i === active}
                onMouseDown={(e) => {
                  e.preventDefault();
                  choose(option);
                }}
                onMouseEnter={() => setActive(i)}
                className={cn(
                  "flex cursor-pointer items-center gap-sm px-md py-sm text-callout",
                  i === active && "bg-surface-2",
                )}
              >
                {option.kind === "saved" ? (
                  <>
                    <span className="grid h-6 w-6 place-items-center rounded-full bg-surface-2 text-[11px] font-semibold">
                      {option.person.name.charAt(0).toUpperCase()}
                    </span>
                    {option.person.name}
                  </>
                ) : (
                  <>
                    <Plus size={15} className="text-accent" />
                    Add &ldquo;{option.name}&rdquo; as someone new
                  </>
                )}
              </li>
            ))}
          </ul>
        )}
      </div>
      <p className="text-caption text-text-tertiary">New names are saved to your people. Add their email later to invite them.</p>
    </div>
  );
}

/** "Who had it" for one item when there are many people: one compact
 * dropdown of checkboxes instead of a chip per person. */
export function WhoHadIt({
  people,
  chosen,
  onToggle,
}: {
  people: { key: string; label: string }[];
  chosen: string[];
  onToggle: (key: string) => void;
}) {
  const names = people.filter((p) => chosen.includes(p.key)).map((p) => p.label);
  const summary = names.length === 0 ? "Everyone (nobody picked)" : names.length <= 2 ? names.join(", ") : `${names.slice(0, 2).join(", ")} +${names.length - 2}`;
  return (
    <details className="group relative">
      <summary className="flex cursor-pointer list-none items-center gap-xs rounded-pill px-sm py-[2px] text-[12px] text-text-secondary ring-1 ring-border hover:text-text [&::-webkit-details-marker]:hidden">
        Who had it: <span className="font-medium text-text">{summary}</span>
        <ChevronDown size={12} className="transition-transform group-open:rotate-180" />
      </summary>
      <ul className="absolute left-0 top-[calc(100%+4px)] z-20 max-h-64 w-56 overflow-y-auto rounded-md bg-surface py-xs shadow-e2 ring-1 ring-border">
        {people.map((p) => {
          const on = chosen.includes(p.key);
          return (
            <li key={p.key}>
              <button
                type="button"
                onClick={() => onToggle(p.key)}
                aria-pressed={on}
                className="flex w-full items-center gap-sm px-md py-[6px] text-left text-callout hover:bg-surface-2"
              >
                <span
                  className={cn(
                    "grid h-4 w-4 place-items-center rounded-[4px] ring-1",
                    on ? "bg-accent text-accent-fg ring-accent" : "ring-border",
                  )}
                >
                  {on && <Check size={11} strokeWidth={3} />}
                </span>
                {p.label}
              </button>
            </li>
          );
        })}
      </ul>
    </details>
  );
}
