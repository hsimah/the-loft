---
name: wiki-editing
description: Rewrite, correct, reorganise or remove text on existing wiki pages by proposing a diff the user approves before anything is written.
---

# Editing wiki pages

Use this when the user asks to change, correct, reword, reorganise or remove something already on the wiki, or to split a page. To only add something, use append_to_page or create_page as usual.

1. Call read_conventions and any conventions page it points to for this area. If it fails, do not edit; tell the user.
2. Read the page with read_page. For a split or move, also read the pages beside it so new paths follow their neighbours.
3. Change only what the user asked for. Keep everything else on the page exactly as it is: wording, order, links, blank lines. Do not tidy or reformat other parts.
4. Call propose_page_edit with the page path, the complete new page text and a one-sentence summary. The user sees a diff with Approve and Request changes buttons.
5. Stop. Do not repeat the diff or the page in your reply; say in one line what the proposal changes and wait.
6. If the user asks for changes, make a new proposal; the old one is dropped.
7. Call apply_page_edit only when the user's latest message approves that proposal by its id (the Approve button sends it). Approval of one proposal never covers another.
8. Report the path and what changed. If a tool refuses or says the page changed, pass its message on and start again from step 2; do not work around a refusal.

Splitting a page: propose and apply each new sub-page first, then the shortened parent with links to them, so a stop part-way leaves duplicates, not lost text. One page per proposal. You cannot delete pages or edit pages that contain SilverBullet code; tell the user to do those by hand.
