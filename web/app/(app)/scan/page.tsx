"use client";

import { useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { CheckCircle2, RotateCcw, UploadCloud } from "lucide-react";
import { apiPost } from "@/lib/api";
import type { Extraction } from "@/lib/types";
import { categoryMeta } from "@/lib/categories";
import { money } from "@/lib/format";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

type Stage =
  | { name: "idle" }
  | { name: "error"; message: string }
  | { name: "reading"; preview: string }
  | { name: "done"; preview: string; result: Extraction };

async function fileToBase64(file: File): Promise<string> {
  const bytes = new Uint8Array(await file.arrayBuffer());
  let binary = "";
  for (let i = 0; i < bytes.length; i += 1) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

export default function ScanPage() {
  const [stage, setStage] = useState<Stage>({ name: "idle" });
  const [dragOver, setDragOver] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const queryClient = useQueryClient();

  async function handleFile(file: File) {
    if (!file.type.startsWith("image/")) {
      setStage({ name: "error", message: "Please choose an image file." });
      return;
    }
    const preview = URL.createObjectURL(file);
    setStage({ name: "reading", preview });
    try {
      const base64 = await fileToBase64(file);
      const result = await apiPost<Extraction>("v1/extract", {
        imageBase64: base64,
        ocrLines: [],
        clientRequestID: crypto.randomUUID(),
      });
      setStage({ name: "done", preview, result });
      void queryClient.invalidateQueries();
    } catch (err) {
      setStage({
        name: "error",
        message: err instanceof Error ? err.message : "Extraction failed.",
      });
    }
  }

  return (
    <div className="mx-auto max-w-xl space-y-xl">
      <h1 className="text-title">Scan a receipt</h1>

      {(stage.name === "idle" || stage.name === "error") && (
        <>
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            onDragOver={(e) => {
              e.preventDefault();
              setDragOver(true);
            }}
            onDragLeave={() => setDragOver(false)}
            onDrop={(e) => {
              e.preventDefault();
              setDragOver(false);
              const file = e.dataTransfer.files?.[0];
              if (file) void handleFile(file);
            }}
            className={cn(
              "flex w-full flex-col items-center gap-md rounded-2xl border-2 border-dashed p-2xl text-center transition-colors",
              dragOver
                ? "border-accent bg-accent-muted"
                : "border-border-strong hover:bg-surface-2",
            )}
          >
            <UploadCloud className="text-accent" size={40} />
            <span className="text-callout">Drop a receipt photo here, or click to choose</span>
            <span className="text-caption text-text-secondary">JPG or PNG</span>
          </button>
          <input
            ref={inputRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={(e) => {
              const file = e.target.files?.[0];
              if (file) void handleFile(file);
            }}
          />
          {stage.name === "error" && (
            <p className="text-caption text-danger">{stage.message}</p>
          )}
        </>
      )}

      {stage.name === "reading" && (
        <Card className="flex flex-col items-center gap-md py-2xl">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={stage.preview}
            alt="Receipt preview"
            className="max-h-56 rounded-md border border-border"
          />
          <p className="text-callout text-text-secondary">Reading receipt…</p>
        </Card>
      )}

      {stage.name === "done" && (
        <Card className="space-y-lg">
          <div className="flex items-center gap-sm text-success">
            <CheckCircle2 size={20} />
            <p className="text-headline text-text">Saved</p>
          </div>

          <dl className="grid grid-cols-2 gap-md text-callout">
            <Field label="Merchant" value={stage.result.merchant || "—"} />
            <Field label="Date" value={stage.result.date ?? "—"} />
            <Field label="Total" value={money(stage.result.total)} mono />
            <Field label="Tax" value={money(stage.result.tax)} mono />
            <Field label="Category" value={categoryMeta(stage.result.category).label} />
            <Field
              label="Confidence"
              value={
                stage.result.confidence != null
                  ? `${Math.round(stage.result.confidence * 100)}%`
                  : "—"
              }
            />
          </dl>

          {stage.result.items.length > 0 && (
            <ul className="divide-y divide-border text-caption">
              {stage.result.items.map((item, i) => (
                <li key={`${item.name}-${i}`} className="flex justify-between py-xs">
                  <span>
                    {item.name}
                    {item.quantity > 1 ? ` ×${item.quantity}` : ""}
                  </span>
                  <span className="tabular text-text-secondary">{money(item.price)}</span>
                </li>
              ))}
            </ul>
          )}

          <Button variant="secondary" onClick={() => setStage({ name: "idle" })}>
            <RotateCcw size={16} />
            Scan another
          </Button>
        </Card>
      )}
    </div>
  );
}

function Field({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div>
      <dt className="text-caption text-text-tertiary">{label}</dt>
      <dd className={mono ? "tabular" : undefined}>{value}</dd>
    </div>
  );
}
