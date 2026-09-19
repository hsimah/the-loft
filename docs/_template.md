# <host, service or script>

One paragraph: purpose, where it runs, and links to authoritative configuration.

Include only the sections this component needs:

- Required environment and persistent state; link to `.env.example` and Compose instead of copying tag/port inventories.
- Routine operations and their side effects. Link to shared provisioning/upgrade guidance.
- Component-specific constraints and observed incidents: date, evidence, mitigation, verification.
- Unverified live state or proposed work, clearly labeled.

Keep recovery instructions here rather than duplicating them in host pages and DEBUG.md. Link within this repo; do not rely on sibling checkouts or private agent memory. Distinguish a possible cause from a confirmed diagnosis.
