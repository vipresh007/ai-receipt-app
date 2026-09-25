"""Compose the App Store screenshots from raw simulator captures in raw/: a mono eyebrow and a display headline over the capture in a
phone frame, on the ledger ink (dark) or paper (light) ground.

Raw captures: iPhone 17 Pro Max simulator, status bar overridden to 9:41,
app launched with -seedSampleReceipts (see ios/AIReceiptApp/App/SampleData.swift).

    python3 brand/app-store/build.py   # needs Google Chrome; writes out/<size>/

Two sizes, because App Store Connect's iPhone slots each take exact pixels:
6.9" (1320x2868) and 6.5" (1284x2778). Either set satisfies the required
iPhone screenshots. The layout is designed at 1320 wide and zoomed to fit.
"""

import pathlib
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# (output name, raw capture, theme, eyebrow, headline) — in App Store order.
SLIDES = [
    ("01-scan", "scan.png", "dark", "Scan", "Snap a receipt.<br>It reads itself."),
    ("02-dashboard", "dashboard.png", "dark", "This month", "Know where your<br>month stands."),
    ("03-insights", "insights.png", "dark", "Insights", "See where it went<br>and what changed."),
    ("04-receipts", "receipts.png", "light", "Receipts", "Every receipt,<br>one search away."),
    ("05-history", "history.png", "light", "History", "Month over month,<br>at a glance."),
]

# App Store Connect slot → (width, height) in pixels.
SIZES = {"6.9": (1320, 2868), "6.5": (1284, 2778)}
DESIGN_WIDTH = 1320

THEMES = {
    "dark": dict(
        bg="#0C1412", glow="rgba(217,174,92,.22)", ink="#F1ECE1", accent="#D9AE5C",
        bezel="#26332F", shadow="0 60px 120px rgba(0,0,0,.55)",
    ),
    "light": dict(
        bg="#F3EEE3", glow="rgba(138,94,15,.10)", ink="#1E2321", accent="#8A5E0F",
        bezel="#1E2321", shadow="0 50px 110px rgba(48,38,18,.28)",
    ),
}

PAGE = """<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,800&family=IBM+Plex+Mono:wght@500&display=block" rel="stylesheet">
<style>
html{{margin:0;overflow:hidden}}
body{{margin:0;width:1320px;height:{design_height}px;overflow:hidden;zoom:{zoom}}}
body{{background:radial-gradient(1100px 800px at 95% -5%,{glow},transparent 60%),{bg};
  font-family:'Bricolage Grotesque',sans-serif;position:relative}}
.cap{{position:absolute;left:110px;right:110px;top:180px}}
.eb{{font-family:'IBM Plex Mono',monospace;font-weight:500;font-size:34px;letter-spacing:.2em;
  text-transform:uppercase;color:{accent};display:flex;align-items:center;gap:22px}}
.eb:before{{content:"";width:56px;height:3px;background:{accent};border-radius:2px}}
h1{{margin:34px 0 0;font-weight:800;font-size:112px;line-height:1.02;letter-spacing:-.022em;color:{ink}}}
.phone{{position:absolute;left:50%;top:640px;transform:translateX(-50%);width:940px;
  border-radius:108px;padding:16px;background:{bezel};box-shadow:{shadow}}}
.phone img{{display:block;width:100%;border-radius:94px}}
</style></head><body>
<div class="cap"><div class="eb">{eyebrow}</div><h1>{headline}</h1></div>
<div class="phone"><img src="{img}"></div>
</body></html>"""


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        for size, (width, height) in SIZES.items():
            out = HERE / "out" / size
            out.mkdir(parents=True, exist_ok=True)
            zoom = width / DESIGN_WIDTH
            for name, raw, theme, eyebrow, headline in SLIDES:
                page = pathlib.Path(tmp) / f"{size}-{name}.html"
                img = (HERE / "raw" / raw).as_uri()
                page.write_text(
                    PAGE.format(
                        eyebrow=eyebrow, headline=headline, img=img, zoom=zoom,
                        design_height=round(height / zoom), **THEMES[theme],
                    )
                )
                subprocess.run(
                    [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                     "--allow-file-access-from-files", "--force-device-scale-factor=1",
                     f"--window-size={width},{height}", "--virtual-time-budget=4000",
                     f"--screenshot={out / (name + '.png')}", page.as_uri()],
                    check=True, capture_output=True,
                )
                print(out / f"{name}.png")


if __name__ == "__main__":
    main()
