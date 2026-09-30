# rdf_fdw logo

The rdf_fdw mark is an elephant drawn as an RDF graph, inside a ring.
Colors: navy `#1F3A5F`, orange `#E07B39`, light `#E8EEF5`, ivory `#F7F5F0`, dark `#0F1B2A`.
The wordmark is set in JetBrains Mono SemiBold (SIL Open Font License) and converted to outlines, so no font needs to be installed.

## Files

| Folder | What | Use it for |
|---|---|---|
| `svg/rdf_fdw-mark-*` | Full mark (`on-light`, `on-dark`) | Anywhere at 48 px and larger |
| `svg/rdf_fdw-mark-small-*` | Simplified mark | 16–48 px: favicons, badges, tiny avatars |
| `svg/*-mono-*` | One-color versions (navy, black, white) | Print, stickers, backgrounds you don't control |
| `svg/rdf_fdw-lockup-horizontal-*` | Mark + name, side by side | README header, website nav, slide footers |
| `svg/rdf_fdw-lockup-stacked-*` | Mark above name | Square spaces, stickers, docs landing page |
| `svg/rdf_fdw-wordmark-*` | Name only | When the mark is already visible nearby |
| `svg/`, `png/rdf_fdw-banner-*` | 1280×320 wide banner with tagline (plus a `-2x` PNG) | README top banner, website hero, blog headers |
| `png/rdf_fdw-social-preview-*` | 1280×640 card (GitHub requires 2:1) | GitHub → Settings → Social preview only |
| `png/rdf_fdw-avatar-*` | Square with background | GitHub org, Mastodon, Discord avatars |
| `favicon/` | `favicon.ico`, `favicon.svg`, app icons | Website `<head>` |

`on-light` means "for light backgrounds"; `on-dark` means "for dark backgrounds".
The SVGs are the masters; PNGs are exports.

## README header (switches with GitHub's light/dark theme)

Compact logo:

```html
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="logo/svg/rdf_fdw-lockup-horizontal-on-dark.svg">
    <img alt="rdf_fdw" src="logo/svg/rdf_fdw-lockup-horizontal-on-light.svg" width="420">
  </picture>
</p>
```

Or the full-width banner:

```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="logo/svg/rdf_fdw-banner-dark.svg">
  <img alt="rdf_fdw — Query RDF triplestores from PostgreSQL" src="logo/svg/rdf_fdw-banner-light.svg" width="100%">
</picture>
```

## Website `<head>`

```html
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
```

`favicon.svg` switches to a light version automatically in dark browser themes.

## Usage rules

- **Clear space:** keep at least one node's width of empty space around the ring.
- **Minimum size:** below 48 px, use the `mark-small` files.
- **Don't:** recolor the orange graph edges individually, stretch the mark, or remove the ring.

## License

The logo is licensed under [CHOOSE A LICENSE, e.g. CC BY 4.0], separately from the rdf_fdw source code.
