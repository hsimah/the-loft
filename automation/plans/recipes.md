# Recipes

Emails, photos, links and video reels converted into editable, shareable recipes.

## Stack

| Piece | Proposed | Notes |
|---|---|---|
| App | [Mealie](https://docs.mealie.io) (D15) | Polished web UI, households, share links, URL scraping. Its AI features take any OpenAI-compatible base URL ([AI providers](https://docs.mealie.io/documentation/getting-started/installation/ai-providers/)), so they point at llama-swap. Image import needs a vision model. OIDC available for later SSO |
| Alternative | [Tandoor](https://docs.tandoor.dev) 2.x | Stronger meal planning and shopping; AI import through LiteLLM. Heavier, and local-model setup is less documented |
| Reel worker | Bash scripts on the [media worker](workflows.md#shell-steps) | yt-dlp, ffmpeg, whisper |
| Access | LAN and Tailscale | Public sharing is D22 |

## Inputs

| Input | Path |
|---|---|
| Recipe URL | Mealie's built-in scraper |
| Photo of a card, book page or screenshot | Mealie image import, using the household vision model |
| Email (`+recipe` [intake](intake.md)) | n8n: a URL in the body goes to the scraper; recipe text goes to a model that returns schema.org `Recipe` JSON, posted to Mealie's API; image attachments go to image import |
| Instagram reel, TikTok, YouTube Short | Link by email or share sheet → worker: yt-dlp fetches the video and caption. If the caption lacks the recipe, ffmpeg extracts audio for whisper. Frames supply a hero image. A model turns caption and transcript into `Recipe` JSON for Mealie |

All imports land as drafts to edit. Prior art for the reel pipeline: [SousVid](https://github.com/leshicodes/SousVid) (Python, OpenRouter only, cookies for Instagram) and social-to-mealie. Ours is a few bash scripts per repo rules.

Instagram needs a logged-in session for reels (D16). Options: cookies from a throwaway account, which risks that account being banned; caption-only when anonymous access works; or skip Instagram and rely on the creator's linked blog post.

## Open questions

- D15: Mealie or Tandoor? Recommendation: Mealie.
- D22: do recipes need sharing outside the house? A public share link needs a first-level tunnel name, like [Hubbl](../../docs/services/hubbl.md). Exporting or printing avoids that.
