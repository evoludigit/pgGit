# Show HN: pgGit - I implemented Git inside PostgreSQL in 48 hours, and it handles 10TB databases

Hey HN! I'm Lionel, and last weekend I did something that might be either brilliant or insane: I implemented Git's core functionality directly inside PostgreSQL using pure SQL.

**What is pgGit?**

pgGit lets you version control your database schemas and data using Git semantics, but everything runs inside PostgreSQL. No external dependencies, no separate version control system - just SQL.

```sql
-- Create a commit
SELECT pggit.commit('Added user authentication tables');

-- View history  
SELECT * FROM pggit.log();

-- Diff between versions
SELECT * FROM pggit.diff('schema', 'v1.2.0', 'v1.3.0');

-- Three-way merge (yes, really!)
SELECT pggit.merge('feature-branch');
```

**Technical Implementation**

- Implements Git's DAG (Directed Acyclic Graph) in pure SQL
- Real three-way merge algorithm (not just timestamps)
- Built-in diff algorithms for schema and data changes
- Automatic conflict resolution for common cases
- Tiered storage design for handling large databases (10TB+)
- Full test suite (32 tests, all passing)

**Why I Built This**

In 2017, I had a traumatic experience with corrupted PowerBI data that led to catastrophic business decisions. Since then, I've been obsessed with data integrity and version control. I over-engineered everything (my PrintOptim app could handle 1M copiers when we had 10 clients). Everyone thought I was crazy until Claude Code came along and suddenly my over-engineered architecture made sense.

**The Plot Twist**

I built this in 48 hours using Claude Code. But here's the thing - I'm being completely transparent about it because the AI collaboration actually makes the project more interesting, not less. Every line was reviewed, tested, and validated by my most brutal critic: a fictional persona named Viktor "The Terminator" Steinberg who demands perfection.

**Current Status**

- Experimental but functional
- Running in production on my PrintOptim app (400 copiers across French universities)
- Open source (MIT license)
- Comprehensive documentation
- No formal benchmarks yet (bootstrapped project)

**Links**

- GitHub: [github.com/yourusername/pggit]
- Demo: [pggit.demo.com]
- The Viktor Steinberg Saga: [link to marketing repo]

**What I'm Looking For**

- Technical feedback on the approach
- Use cases I haven't considered
- Contributors who want to help make database versioning not suck
- People to try breaking it (Viktor couldn't, but maybe you can)
- Help with benchmarking against existing tools

**P.S.** - I also created an open-source marketing framework where we version control our entire marketing process (including this post). It's either revolutionary or ridiculous, but it got Viktor from 2/10 to 9.3/10, so there's that.