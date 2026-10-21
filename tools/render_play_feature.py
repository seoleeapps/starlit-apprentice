#!/usr/bin/env python3
"""Render the Play feature graphic from existing game art and an actual capture."""
from pathlib import Path
import argparse
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'play-store/assets/source/feature-graphic.html'
OUTPUT = ROOT / 'play-store/assets/feature-graphic-1024x500.png'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--browser-channel', default=None)
args = parser.parse_args()

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(headless=True, channel=args.browser_channel)
    page = browser.new_page(viewport={'width': 1024, 'height': 500}, device_scale_factor=1)
    page.goto(SOURCE.as_uri(), wait_until='load')
    page.evaluate('document.fonts.ready')
    assert page.locator('img').evaluate_all('(images) => images.every(i => i.complete && i.naturalWidth > 0)')
    page.screenshot(path=str(OUTPUT), type='png', omit_background=False)
    browser.close()
print(f'Wrote {OUTPUT.relative_to(ROOT)} (1024x500)')
