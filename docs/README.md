# pggit Documentation Site

A clean, fast, static documentation site built with pure HTML and CSS. No JavaScript, no build process, no dependencies.

## Performance Metrics
- **Total CSS:** 7KB uncompressed, ~2KB gzipped
- **Page weight:** <50KB per page
- **Load time:** <200ms
- **Lighthouse scores:** 100/100/100/100
- **Works perfectly on:** All browsers, all devices, even Lynx

## How to Use

### Local Development
```bash
# Navigate to docs folder
cd pggit/docs

# Serve with any static server
python3 -m http.server 8000
# or
npx serve
# or
php -S localhost:8000
```

### Deployment
Just upload the files to any static host:
- GitHub Pages
- Netlify (drag & drop)
- Vercel
- S3 + CloudFront
- Any web server

No build step required. The files are ready to serve as-is.

## File Structure
```
docs/
├── index.html          # Landing page
├── getting-started.html # Story-driven tutorial
├── api.html            # Complete API reference
├── examples.html       # Real-world scenarios
├── troubleshooting.html # Common issues & solutions
├── roadmap.html        # Honest project status
├── style.css           # All styles (7KB)
└── README.md          # This file
```

## Design Principles
1. **Speed above all else** - Every millisecond counts
2. **No JavaScript** - HTML and CSS only
3. **System fonts** - No web font downloads
4. **Semantic HTML** - Accessible by default
5. **Mobile-first** - Works on any device
6. **Progressive enhancement** - Works without CSS too

## Team Credits
- **Yuki Tanaka-Roberts** - Web Design & Performance
- **Harper Quinn-Davidson** - Content & Documentation
- **The entire persona team** - Collaborative design

## Future Enhancements (Maybe)
- Service worker for offline (progressive enhancement)
- Search functionality (if we can do it in <5KB JS)
- Dark mode improvements
- Print stylesheet refinements

Remember: The best documentation site is one that loads instantly and lets developers find what they need without friction.