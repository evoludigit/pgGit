# pgGit Governance: Phase 1 Focused Development

## Vision

pgGit is building the standard for PostgreSQL schema version control through disciplined, market-validated phase development. Phase 1 (Feb-July 2026) focuses exclusively on schema VCS: branching, merging, and diffing. All future enhancements are deferred to Phases 2-6 based on real user demand.

---

## Leadership & Roles

### Project Owner (evoludigit)
- **Responsibility**: Strategic vision, community engagement, release coordination
- **Time**: 20-30 hours/week
- **Compensation**: Project equity stake
- **Decisions**: Overall direction, roadmap, phase transitions

### Technical Architect (stephengibson12)
- **Responsibility**: Core implementation, code quality, architecture decisions
- **Time**: 20-30 hours/week (estimated, negotiate as needed)
- **Compensation**: TBD (discuss directly with contributor)
- **Decisions**: Technical approach, code review, performance trade-offs

### Optional Contractor (Phase 3+)
- **Role**: Schema diffing specialist, audit layer implementation
- **Time**: 10-20 hours/week for 6-week engagements
- **Compensation**: $50-100/hour (estimated)
- **Selection**: Hired by project owner based on technical needs

---

## Decision-Making Structure

### Daily Decisions
- **Who**: Technical architect + current developer
- **Process**: Code review, pull request discussion
- **Approval**: At least one approval from technical architect

### Phase-Level Decisions
- **Who**: Project owner + technical architect
- **Process**: Discussion, written rationale in issue/PR
- **Approval**: Both parties agree

### Strategic Decisions
- **Who**: Project owner with technical architect input
- **Process**: Documented decision (in this file or ROADMAP.md)
- **Examples**: Phase transitions, major feature additions, personnel changes

### Community Feedback
- **Who**: All users welcome to comment
- **Process**: GitHub issues, discussions, pull requests
- **Weight**: Considered but not binding (project owner + architect decide)

---

## The Phase 1 Discipline: Absolutely Non-Negotiable

### Core Rule: Is This Schema VCS?

Every pull request must answer: **"Does this contribute to schema version control?"**

**YES** → Merged into Phase 1
**NO** → Deferred to appropriate future phase

### Schema VCS Definition

**Phase 1 IS:**
- Creating/switching/deleting schema branches
- Merging branches with conflict detection
- Diffing schema changes between branches
- Tracking schema history and commit information
- Core infrastructure for future phases

**Phase 1 IS NOT:**
- Data branching (Phase 2+) - requires copy-on-write infrastructure
- Temporal queries (Phase 2) - requires timestamp tracking
- Compliance auditing (Phase 3) - requires immutable audit layer
- Storage optimization (Phase 4) - requires deduplication infrastructure
- Zero-copy branches (Phase 4) - requires filesystem integration
- Time-travel recovery (Phase 2+) - requires temporal layer
- Role-based access control (Phase 2+) - requires permissions layer
- Cloud hosting (Phase 5) - out of scope for Phase 1

### Enforcement Mechanism

1. **PR Template**: Includes "Is this schema VCS?" question
2. **Review Checklist**: Technical architect reviews against this rule
3. **Rejection Policy**: PRs proposing Phase 2+ features are rejected with:
   - Explanation of why deferred
   - Which phase it belongs in
   - Link to ROADMAP.md
   - Invitation to participate in that phase

### Examples

**APPROVED** (Schema VCS):
- `git merge origin/feature/add-merge-detection`
- `git merge origin/feature/improve-diff-algorithm`
- `git merge origin/fix/conflict-resolution-edge-case`

**DEFERRED** (Not Schema VCS):
- ❌ `feat: Add temporal branching` → Phase 2, rejected with explanation
- ❌ `feat: Add compliance auditing` → Phase 3, rejected with explanation
- ❌ `feat: Add copy-on-write storage` → Phase 4, rejected with explanation

---

## PR Approval Process

### 1. Submission
- Create PR with clear description
- Answer: "Is this schema VCS? YES / NO"
- Reference any related issues
- Include tests for new functionality

### 2. Automated Checks
- ✅ Tests pass (make test)
- ✅ Lints clean (no warnings)
- ✅ Builds successfully
- ✅ Documentation updated if needed

### 3. Scope Review
- Is this schema VCS? (see discipline above)
- Does it fit Phase 1 timeline?
- Any blocking issues or dependencies?

### 4. Technical Review
- Code quality and style
- Performance implications
- Edge cases and error handling
- Backward compatibility

### 5. Approval
- **Minimum Required**: 1 approval from technical architect
- **Recommended**: At least 2 approvals if substantial changes
- **Fast Track**: Bug fixes can be merged faster than features

### 6. Merge
- Squash and merge (keep history clean)
- Reference issue number in commit
- Delete feature branch

---

## Contributing Guidelines

### Before You Start

1. **Check ROADMAP.md** - Make sure your idea fits Phase 1
2. **Open an Issue** - Describe what you want to build
3. **Wait for feedback** - Get approval from technical architect first
4. **This prevents wasted effort** - Don't build Phase 2+ features

### Development Process

1. Fork repository
2. Create feature branch: `git checkout -b feature/description`
3. Make changes focused on one feature
4. Run tests: `make test`
5. Commit with clear messages
6. Push and create PR
7. Respond to review feedback

### Code Standards

- **Tests Required**: Every feature needs test coverage
- **Documentation**: Update docs for user-facing changes
- **Backward Compatibility**: Don't break existing APIs without major version bump
- **Performance**: Check impact before merging
- **Security**: All user input validated, no SQL injection vectors

### Commit Messages

Use conventional commits:
```
feat(core): add schema diffing
fix(merge): handle circular dependencies
refactor(routing): simplify view creation
docs(architecture): explain phase system
test(merge): add conflict detection tests
```

### PR Description Template

```markdown
## What Does This Do?
[Brief description of the change]

## Schema VCS?
- [x] YES - This is schema version control
- [ ] NO - This is Phase 2+ (explain why deferred)

## Testing
- [ ] Added/updated tests
- [ ] All tests pass locally
- [ ] Tested with PostgreSQL 15, 16, 17

## Documentation
- [ ] Updated API_Reference.md if needed
- [ ] Updated architecture docs if needed
- [ ] Updated CHANGELOG.md for user-facing changes

## Breaking Changes?
- [ ] No breaking changes
- [ ] Breaking change (explain and justify)

## Related Issues
Closes #123
```

---

## Roadmap Authority

### ROADMAP.md is the source of truth for:
- Which features are in which phase
- Timeline for each phase
- Success criteria for phase transitions
- Long-term strategic direction

### Changing the Roadmap
- **Minor updates**: Project owner decides
- **Major changes**: Project owner + technical architect agreement
- **Phase additions/removals**: Requires team discussion and rationale
- **Timeline changes**: Communicated to community with reasoning

---

## Community Engagement

### We Welcome
- Bug reports (with reproduction steps)
- Feature requests (with use cases)
- Pull requests (starting with issue discussion)
- Documentation improvements
- Performance optimizations

### We Don't Accept
- Unsolicited Phase 2+ PRs (discuss in issue first)
- Breaking changes without discussion
- PRs without tests
- PRs without documentation updates

### Communication Channels
- **Issues**: Technical discussions and feature requests
- **Discussions**: General questions and community chat
- **Pull Requests**: Code review and implementation discussion
- **Email**: For sensitive matters or direct communication

---

## Phase Transitions

### Criteria for Proceeding to Next Phase

At the end of each phase, we evaluate:

1. **Technical**:
   - All tests passing
   - No critical bugs outstanding
   - Performance acceptable
   - Code quality high

2. **Community**:
   - User feedback positive
   - Real-world usage proven
   - Active contributor engagement
   - Bug reports declining

3. **Business**:
   - Growth metrics met (stars, users, adoption)
   - Product-market fit validated
   - Team capacity for next phase
   - Strategic alignment clear

### Go/No-Go Decision

**Example: Can We Proceed from Phase 1 to Phase 2?**

Must have ALL of:
- ✅ Phase 1 features working reliably
- ✅ 100+ production users
- ✅ 1500+ GitHub stars
- ✅ Community actively using schema VCS
- ✅ Clear demand for Phase 2 features
- ✅ Team resources allocated

If ANY metric falls short → STAY IN PHASE 1, improve that area

---

## Conflict Resolution

### If We Disagree

1. **Discussion**: All parties present their perspective
2. **Rationale**: Written explanation of position
3. **Compromise**: Look for middle ground
4. **Escalation**: Project owner makes final decision if needed

### Disputes About Scope

If someone disagrees whether a PR is "schema VCS":

1. **Propose in issue first** - Get feedback before coding
2. **Technical architect decides** - Final call on scope
3. **Escalate if needed** - Project owner can override

### Disputes About Timeline

If release is delayed or accelerated:

1. **Communicate to community** - Explain why
2. **Update ROADMAP.md** - Document new timeline
3. **Reset expectations** - Be realistic about capacity

---

## Review of This Document

- **Updated**: When phase policies change
- **Community Input**: We welcome suggestions (open issue)
- **Final Authority**: Project owner approves all changes
- **Transparency**: All governance decisions made public

---

## Appendix: Phase 1 Success Metrics

By end of Phase 1 (July 2026), we need:

### Technical
- ✅ All tests pass (100% pass rate)
- ✅ Works on PG 15-17 reliably
- ✅ Zero critical security issues
- ✅ Documentation complete
- ✅ Installation takes < 5 minutes

### Community
- ✅ 100+ production users
- ✅ 1500+ GitHub stars
- ✅ Active issue discussions
- ✅ stephengibson12 fully engaged

### Business
- ✅ Product-market fit clear (users asking for it, not just building for them)
- ✅ "Git for schemas" resonates with developers
- ✅ Acquisition interest starting (venture firms inquiring)
- ✅ Case studies from real production use

### Strategic
- ✅ Phase 1 focus maintained (zero Phase 2+ features merged)
- ✅ Phases 2-6 understood by community
- ✅ Team culture established
- ✅ Governance working smoothly

If ALL success criteria met → Phase 2 approved
If ANY criteria falling short → STAY IN PHASE 1 and improve

---

*Last Updated: February 2026*
*Governance Lead: evoludigit*
*Technical Lead: stephengibson12*
