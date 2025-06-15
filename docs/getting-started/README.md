# Getting Started with pggit

Welcome to pggit - Git-like version control for PostgreSQL databases! This guide will get you up and running in minutes.

## 📋 Quick Navigation

- **New to pggit?** → Start with [Explained Like You're 5](PgGit_Explained_Like_Im_5.md)
- **Want more details?** → Read [Explained Like You're 10](PgGit_Explained_Like_Im_10.md)
- **Ready to install?** → Follow [Getting Started Guide](Getting_Started.md)
- **Having issues?** → Check [Troubleshooting](Troubleshooting.md)

## 🚀 30-Second Demo

```bash
# Install pggit
git clone https://github.com/evoludigit/pggit.git
cd pggit
make && sudo make install

# Use it
psql -c "CREATE EXTENSION pggit"
psql -c "CREATE TABLE users (id SERIAL PRIMARY KEY, name TEXT)"
psql -c "SELECT * FROM pggit.get_version('users')"  # Version 1.0.0!
```

## 🎯 What You'll Learn

1. **Basics** - How pggit tracks your database changes automatically
2. **Workflows** - Best practices for database migrations
3. **Enterprise** - Advanced features for production environments
4. **AI Features** - Intelligent migration analysis and optimization

## 📖 Learning Path

### Beginners (5 minutes)
→ [Explained Like You're 5](PgGit_Explained_Like_Im_5.md)

### Developers (15 minutes)  
→ [Explained Like You're 10](PgGit_Explained_Like_Im_10.md)
→ [Getting Started Guide](Getting_Started.md)

### Production Users (30 minutes)
→ [Performance Guide](../guides/performance.md)
→ [Security Guide](../guides/security.md)
→ [Operations Guide](../guides/operations.md)

## 🆘 Need Help?

- **Stuck?** → [Troubleshooting](Troubleshooting.md)
- **Want to contribute?** → [Contributing Guide](../contributing/README.md)
- **API Reference?** → [API Documentation](../reference/README.md)

## ⚡ Next Steps

Once you're comfortable with the basics:
1. Explore [Enterprise Features](../guides/enterprise-features.md)
2. Set up [CI/CD Integration](../guides/cicd-integration.md)  
3. Try [AI-Powered Analysis](../guides/ai-features.md)

---

*pggit: Making database migrations as easy as `git commit`*