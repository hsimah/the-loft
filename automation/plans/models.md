# Models and GPU sharing

The apps and all data live on space-needle; helarctos is only the model engine, so reinstalling it never puts an archive at risk. helarctos has 128 GB of unified memory (`GPU_GTT_GIB` in [host.conf](../../hosts/helarctos/host.conf)) but only ~256 GB/s of bandwidth: interactive use needs mixture-of-experts models, while slower models are fine overnight.

## Household roster

Candidates from the second-brain proposal; none are downloaded or measured yet. PaddleOCR-VL-1.6 has community GGUFs only, so the official 1.5 is the one configured.

| Job | Model (open weights) | Approx. memory | Used by |
|---|---|---|---|
| OCR | GLM-OCR (MIT) or PaddleOCR-VL-1.5 (Apache 2.0); both in [llama-swap.yaml](../../services/sputnik/llama-swap.yaml), [fetch commands](../../docs/services/sputnik.md#ocr-models) | ~2 GB each | Vault, wiki attachments, recipe photos |
| Second opinion: disagreements, handwriting | Qwen3.8-27B (vision) | ~20 GB | Vault re-check, overnight only |
| Summaries, tags, links, routing, reports | Qwen3.6-35B-A3B (UD-Q4_K_XL, Apache 2.0), configured for Paperless and on demand; or the Qwen3.8 35B-A3B in [#149](https://github.com/hsimah/the-loft/issues/149) | ~22 GB | All |
| Embeddings | embeddinggemma 300M (Q8_0, Gemma terms), configured and always loaded | < 1 GB | Paperless similar documents, later wiki search |
| Speech to text | whisper large-v3-turbo through whisper.cpp | ~2 GB | Reels, voice notes |
| Coding | Per #149 | 59–86 GiB | [Coding agents](coding-agents.md) |

Avoid models with research-only licences, such as Nanonets-OCR2-3B. Small OCR models (~1B) now top OmniDocBench ([overview](https://blog.roboflow.com/best-open-source-ocr-models/)), cheap enough to re-read the whole archive.

**First OCR test** (one page: a notice about a bill, with a small payment slip; whole page sent straight in, each model's own task prompt; not a benchmark, and unlike a real bill, which is mostly fields and tables): GLM-OCR took 3.0 s and read the body text accurately but omitted two separate regions, the letterhead and the payment slip (reference, biller code, total), without any signal. PaddleOCR-VL took 7.7 s and covered the whole page, but misread words and, in one run, a dollar amount (`$7,300.14` as `97,300.14`); its output varied between runs. Both are designed for layout analysis followed by per-region recognition, which this test skipped. Open: sampling at temperature 0, a larger sample of real documents (full bills, receipts, tables, handwriting, phone photos) scored per field, whether a layout stage is worth adding, and a general vision model as the whole-page reader.

## Serving

- llama-swap stays the single gateway ([llama-swap.yaml](../../services/sputnik/llama-swap.yaml)). Batch jobs never load models themselves.
- The small household set stays resident beside one large model through llama-swap's router groups (`persistent`, `exclusive: false`); the OCR group is configured on the pinned v265 syntax, and the rest of the set joins it.
- Vulkan is in use today. ROCm reportedly does over twice Vulkan's prompt processing on Strix Halo ([discussion](https://github.com/ggml-org/llama.cpp/discussions/27154)), which suits image-heavy OCR. Benchmark both on real documents; the comparison is already open in #149.
- whisper.cpp's server behind llama-swap for `/v1/audio/transcriptions`; verify on the pinned version.

## Sharing the GPU

**Residency (D18).** The household set is ~30 GB without the 27B vision model. gpt-oss-120b (~59 GiB) fits beside it. Qwen3.8-Flash-Next (~86 GiB plus KV cache) does not, so choosing it in #149 means every household request evicts the coder, a 30 s+ swap each way.

**Time.** Coding already claims the night ([overnight pipeline](coding-agents.md)), and the second-brain proposal put household batch work at 1–6 am. Proposed split, settled in D18:

- Household batch (OCR, re-check, linker, wiki agent) gets a fixed early slot, for example 01:00–02:30, then yields to the runner.
- Daytime household requests (a recipe import, a report on demand) run when the runner is idle.
- Before each item, the batch worker checks llama-swap's running requests and waits if an interactive request is in flight: two models generating at once slow each other down.
- Concurrency one, resumable per document, `Nice=19` with low `CPUWeight` and `IOWeight`.
