---
name: electric-motorcycle-cover
description: Create or edit electric motorcycle social-media covers and product posters from a user-supplied motorcycle photo. Use for Facebook, TikTok, Video Account/WeChat Channels, Reels, Shorts, 9:16 or 9:12 covers, especially when the user provides motor power, top speed, price, logo, product color, language, or asks to preserve a real factory/showroom background. Do not use for unrelated vehicles, long-form ad copy, product spec sheets, or pure text translation.
---

# Electric Motorcycle Cover Generator

Create a high-fidelity electric motorcycle cover from the user's source photo. Treat the source motorcycle as the primary truth. Prefer a premium social-media cover over a dense advertisement.

## Core behavior

1. Use the user's uploaded motorcycle image as the direct visual source.
2. Preserve the real motorcycle design, product color, proportions, fairings, headlights, wheels, suspension, windshield, seat, mirrors, frame, and key visible hardware unless the user explicitly asks to change them.
3. Preserve the real factory, warehouse, or showroom environment by default. Do not replace the background unless the user explicitly asks.
4. Background motorcycles may remain visible when they strengthen factory scale, inventory, wholesale credibility, or product variety. Keep them visually secondary rather than deleting them automatically.
5. Keep advertising density low by default: one headline plus two or three key specifications is usually enough.
6. Use the user's exact numeric parameters. Never invent power, speed, price, battery, range, or other specs.
7. Choose the visual style dynamically from product color, motorcycle type, environment, and platform. Do not force one fixed red/black racing style onto every product.
8. Generate or edit the image directly when an image generation/editing tool is available.

## Inputs

Required:
- `source_image`

Optional:
- `motor_power` — e.g. `15000W`
- `top_speed` — e.g. `150 KM/H`
- `price` — e.g. `$323`
- `logo` — user-supplied logo asset or instruction
- `product_type` — default `Electric Motorcycle`
- `product_name` — model name if supplied
- `aspect_ratio` — default `9:16`; common alternatives: `9:12`, `1:1`, `4:5`
- `platform` — `Facebook`, `TikTok`, `Video Account`, `General`
- `language` — default `English`
- `product_color` — default `auto`
- `style_mode` — default `auto`
- `style_strength` — default `2` on a 1–4 scale
- `background_mode` — default `preserve`
- `keep_background_motorcycles` — default `true`
- `background_motorcycle_strength` — default `medium`
- `remove_people` — default `true` when people are distracting
- `remove_unrelated_text` — default `true`
- `headline` — default localized equivalent of `ELECTRIC MOTORCYCLE`
- `text_density` — default `low`

If a parameter is not supplied and cannot be safely inferred from the image, omit it rather than inventing it.

## Defaults

Use these defaults unless the user overrides them:

```yaml
aspect_ratio: "9:16"
platform: "General"
language: "English"
product_color: "auto"
style_mode: "auto"
style_strength: 2
background_mode: "preserve"
keep_background_motorcycles: true
background_motorcycle_strength: "medium"
remove_people: true
remove_unrelated_text: true
preserve_vehicle_design: true
preserve_vehicle_color: true
text_density: "low"
headline: "ELECTRIC MOTORCYCLE"
```

## Source-image fidelity

The motorcycle in the source image is the highest-priority visual reference.

Do not redesign or hallucinate a different motorcycle. Preserve:
- silhouette and body proportions
- fairing geometry
- headlight shape
- wheels and tires
- brake discs and calipers when visible
- front and rear suspension when visible
- windshield shape
- mirrors and handlebars
- seat geometry
- body graphics and color blocking
- battery/motor-area structure when visible

Allowed enhancements:
- higher apparent sharpness
- improved exposure and contrast
- cleaner reflections
- more balanced composition
- removal of distracting clutter
- mild background depth separation
- controlled commercial lighting

If the generated result materially changes the motorcycle identity, regenerate.

## Background policy

Default behavior: preserve the original real environment.

Retain useful background motorcycles when possible. They can communicate:
- real factory/showroom context
- inventory depth
- wholesale scale
- product variety

Prefer roughly 2–5 readable background motorcycles when the source image supports it, but do not fabricate a showroom full of inventory when the source does not show one.

Keep background motorcycles secondary through one or more of:
- slightly reduced contrast
- slightly reduced sharpness
- lower saturation
- softer lighting
- partial depth-of-field separation

Remove only distracting elements such as:
- people who pull attention from the product
- random boxes or trash
- unrelated signage or text
- objects blocking the hero motorcycle
- visual clutter that weakens the composition

Never replace the real background by default. Only use a replacement background when explicitly requested.

## Automatic style routing

When `style_mode: auto`, analyze the source image and choose a style based on the dominant motorcycle color, product type, and environment. Use `references/style-matrix.md` for routing.

General rule: derive accent colors from the product instead of forcing a universal palette.

Examples:
- white + red sport motorcycle → racing performance
- black sport motorcycle → premium performance
- blue motorcycle → future technology
- purple motorcycle → cyber premium
- green motorcycle → energy / urban performance
- white minimalist scooter → clean technology

The chosen style must support the actual product, not overpower it.

## Style strength

Interpret `style_strength` as:

- `1` — mostly original-photo enhancement; almost no advertising feel
- `2` — balanced social-media cover; default
- `3` — stronger commercial poster treatment
- `4` — high-impact campaign visual; use only when explicitly requested or clearly appropriate

## Layout rules

For vertical `9:16` covers:
- reserve the top area for a short headline when the image has usable negative space
- place the hero motorcycle in the center or lower-middle region
- place specs at lower-left or lower-right without covering important motorcycle details
- preserve visible wheels, bodywork, and silhouette whenever possible
- avoid placing text on headlights, windshield, wheels, or the most recognizable body panels
- keep mobile readability high

For `9:12`:
- use a tighter crop than 9:16
- reduce headline height and vertical spacing
- keep spec blocks compact

For `4:5` or `1:1`:
- prioritize the motorcycle over decorative typography
- reduce text to essentials

## Text rules

Default English hierarchy:

1. `ELECTRIC MOTORCYCLE`
2. `{motor_power} Motor`
3. `Top Speed {top_speed}`
4. optional: `Factory Price {price}`
5. optional: model name

Use only parameters the user supplied or confirmed.

Text should be:
- short
- bold
- easy to read on a phone
- consistent with the selected style
- free of invented claims

Avoid:
- long promotional paragraphs
- excessive slogans
- too many icons
- too many badges
- fake certifications
- unsupported superlatives

## Platform behavior

Use `references/platform-rules.md`.

General defaults:
- Facebook: clear product + specs, slightly more informative, low ad density
- TikTok: stronger first-glance hierarchy, fewer words, tighter crop
- Video Account/WeChat Channels: clean product-first layout, minimal English tags on-image unless requested
- General: neutral premium layout

## Prompt construction

When a deterministic text prompt is useful, run:

```bash
python scripts/build_prompt.py --power "15000W" --speed "150 KM/H" --color "white_red" --ratio "9:16" --platform "Facebook"
```

The script returns a structured image-edit prompt. It never generates specs that were not supplied.

## Image generation/editing procedure

1. Inspect the source image.
2. Extract only visually reliable characteristics: dominant color, motorcycle type, background type, orientation, available negative space, and visible clutter.
3. Merge user parameters with defaults.
4. Select style using the routing matrix.
5. Preserve the real background unless explicitly overridden.
6. Keep useful background motorcycles when they reinforce factory/showroom context.
7. Build a concise editing prompt.
8. Generate/edit at the requested aspect ratio.
9. Verify against `references/qa-checklist.md`.
10. If any critical numeric text, product color, motorcycle identity, or aspect-ratio intent is wrong, regenerate.

## Non-negotiable QA

Before finishing, verify:
- source motorcycle still looks like the same product
- motor power is exact if shown
- top speed is exact if shown
- price is exact if shown
- language is correct
- requested aspect ratio is respected
- product color is unchanged unless requested
- background policy is respected
- useful background motorcycles are not removed without reason
- main motorcycle remains dominant
- text is legible on mobile
- advertising density remains low unless requested otherwise
- no invented specs, certifications, or performance claims appear

## Approved visual reference

`assets/reference-approved-racing.png` is an approved example of the overall quality bar for a white/red high-performance sport motorcycle: strong headline, clean spec blocks, real showroom/factory feeling, and visible but secondary background motorcycles.

Treat it as a quality/style reference only. Do not copy its red/black palette when the product color suggests another style.
