# DigiLab Web

Marketing website and content hub for [DigiLab](https://app.digilab.cards) — a Digimon TCG tournament tracking platform.

## Features

- **Landing Page** — Introduction to DigiLab and its features
- **Blog** — Announcements, technical deep-dives, meta analysis, community spotlights
- **Roadmap** — Public view of what's coming and what's shipped

## Tech Stack

- [Astro](https://astro.build/) — Static site generator
- [Vercel](https://vercel.com/) — Hosting and deployment
- MDX — Blog posts with embedded components

## Development

```bash
# Install dependencies
npm install

# Start dev server
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

## Project Structure

```
src/
├── pages/          → Route pages (index, blog, roadmap, about)
├── content/        → MDX blog posts
├── components/     → Reusable Astro components
├── layouts/        → Page layouts
└── styles/         → Global styles and design tokens

public/
├── charts/         → Exported highcharter widgets
├── images/         → Static images
└── brand/          → Logo and mascot SVGs
```

## Related

- **Main App**: [digilab-app](https://github.com/lopezmichael/digilab-app) — Shiny tournament tracker
- **Live Site**: [digilab.cards](https://digilab.cards)
- **App**: [app.digilab.cards](https://app.digilab.cards)

## License

MIT
