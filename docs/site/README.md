# pgGit Documentation Site

A fast, minimal static documentation site for pgGit.

## Features

- **Zero JavaScript** - Pure HTML/CSS for maximum performance
- **< 50KB per page** - Optimized for speed
- **100/100 Lighthouse scores** - Performance, accessibility, best practices, SEO
- **Static generation** - Works anywhere, no server required
- **Responsive design** - Perfect on all devices
- **Clean typography** - Readable and scannable

## Building

```bash
# Build the static site
./build.sh

# Preview locally
cd site && python3 -m http.server 8000
```

## Deployment

```bash
# Choose your deployment method
./deploy.sh
```

Options:
1. GitHub Pages
2. Netlify Drop
3. Vercel
4. Local nginx
5. Generate nginx config

## Structure

```
site/
├── index.html          # Homepage
├── style.css          # All styles (< 10KB)
├── docs/              # Documentation
│   ├── getting-started/
│   ├── guides/
│   ├── architecture/
│   ├── advanced/
│   └── contributing/
├── api/               # API Reference
└── 404.html          # Error page
```

## Philosophy

Following the web design specialist's principles:
- Every kilobyte matters
- Every millisecond counts
- Every pixel has purpose
- If it doesn't help the user, it doesn't belong

## Performance

- Page weight: < 50KB per page
- Load time: < 200ms
- No build process required
- Works without JavaScript
- System fonts only
- Semantic HTML

Built with ❤️ for the pgGit project.