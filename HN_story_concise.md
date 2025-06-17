# Show HN: I version-controlled my database AND my marketing

**Title: Show HN: pgGit - Git inside PostgreSQL (and we open-sourced how we market it)**

---

I built Git inside PostgreSQL. Then something weirder happened.

## The Project

**pgGit** - Actual Git operations in your database:
```sql
SELECT * FROM pggit.create_branch('feature/risky-migration');
-- Make schema changes on branch
SELECT * FROM pggit.merge_branches('feature/risky-migration', 'main');
-- Three-way merge with conflict detection!
```

Real specs:
- 61,298 lines of SQL
- Handles 10TB databases
- Built with Claude Code in 48 hours
- Currently experimental (be warned)

## The Weird Part

To explain this, I created "Viktor Steinberg" - a fictional grumpy investor who reviews the code:
- "Git in PostgreSQL? Stupid idea. 2/10"
- *[4 hours of investigation later]*
- "I hate that this actually works. 9.3/10"

Viktor was so effective at finding issues (and driving features), I realized: **marketing is code too**.

## So I Open-Sourced the Marketing

Created [Open Source Marketing Framework](https://github.com/evoludigit/opensource-marketing-framework):
- Git-tracked personas (like Viktor)
- A/B test results in version control
- Community PRs to improve messaging
- Real metrics, including failures

Results:
- 340% better message clarity
- Community created new personas
- Marketing drove actual features
- Documentation became... fun?

## Try It

**pgGit** (if you're brave):
```bash
git clone https://github.com/evoludigit/pgGit
docker run -it pggit/demo
```

**Marketing Framework** (for your project):
```bash
git clone https://github.com/evoludigit/opensource-marketing-framework
# Create personas, track what works
```

## The Ask

1. Try pgGit (and tell Viktor what breaks)
2. Create a persona for your project
3. Submit PRs to improve either project
4. Share what messaging works for you

---

**TL;DR**: I put Git in PostgreSQL, then put marketing in Git. Both work. Both are open source. Viktor approves (grudgingly).

*Built with AI, roasted by fictional investors, improved by community, shipped to HN.*