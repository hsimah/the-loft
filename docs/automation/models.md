# Models and GPU sharing

The apps and all data live on space-needle; helarctos is only the model engine, so reinstalling it never puts an archive at risk. helarctos has 128 GB of unified memory (`GPU_GTT_GIB` in [host.conf](../../hosts/helarctos/host.conf)) but only ~256 GB/s of bandwidth: interactive use needs mixture-of-experts models, while slower models are fine overnight.

## Household roster

Candidates from the second-brain proposal. The OCR, embedding and 35B text models are downloaded and configured; none is benchmarked. PaddleOCR-VL-1.6 has community GGUFs only, so the official 1.5 is the one configured.

| Job | Model (open weights) | Approx. memory | Used by |
|---|---|---|---|
| OCR | GLM-OCR (MIT) or PaddleOCR-VL-1.5 (Apache 2.0); both in [llama-swap.yaml](../../services/sputnik/llama-swap.yaml), [fetch commands](../services/sputnik.md#ocr-models) | ~2 GB each | Paperless, recipe photos |
| Second opinion: disagreements, handwriting | Qwen3.8-27B (vision) | ~20 GB | Vault re-check, overnight only |
| Summaries, tags, links, routing, reports, chat tools | Qwen3.6-35B-A3B (UD-Q4_K_XL, Apache 2.0), configured and resident | ~22 GB | All |
| Embeddings | embeddinggemma 300M (Q8_0, Gemma terms), configured and always loaded | < 1 GB | Paperless chat and suggestions, later wiki search |
| Speech to text | whisper large-v3-turbo through whisper.cpp | ~2 GB | Reels, voice notes |
| Heavy questions; coding (deferred) | gpt-oss-120b or Qwen3.5-122B-A10B, on demand | 59–71 GiB | Open WebUI, [coding agents](coding-agents.md) |

Avoid models with research-only licences, such as Nanonets-OCR2-3B. Small OCR models (~1B) now top OmniDocBench ([overview](https://blog.roboflow.com/best-open-source-ocr-models/)), cheap enough to re-read the whole archive.

**First OCR test** (one page: a notice about a bill, with a small payment slip; whole page sent straight in, each model's own task prompt; not a benchmark, and unlike a real bill, which is mostly fields and tables): GLM-OCR took 3.0 s and read the body text accurately but omitted two separate regions, the letterhead and the payment slip (reference, biller code, total), without any signal. PaddleOCR-VL took 7.7 s and covered the whole page, but misread words and, in one run, a dollar amount (`$7,300.14` as `97,300.14`); its output varied between runs. Both are designed for layout analysis followed by per-region recognition, which this test skipped. Open: sampling at temperature 0, a larger sample of real documents (full bills, receipts, tables, handwriting, phone photos) scored per field, whether a layout stage is worth adding, and a general vision model as the whole-page reader.

## Serving

- llama-swap stays the single gateway ([llama-swap.yaml](../../services/sputnik/llama-swap.yaml)). Batch jobs never load models themselves.
- The household set stays resident beside one large model through llama-swap's persistent `household` group (`exclusive: false`). The 35B text, OCR and embedding models are in it; whisper joins it.
- Vulkan is in use today. ROCm reportedly does over twice Vulkan's prompt processing on Strix Halo ([discussion](https://github.com/ggml-org/llama.cpp/discussions/27154)), which suits image-heavy OCR. Benchmark both on real documents; the comparison is already open in #149.
- whisper.cpp's server behind llama-swap for `/v1/audio/transcriptions`; verify on the pinned version.

## Sharing the GPU

Household work has the GPU; local coding is deferred (D18).

- **Residency.** The household set (35B text, OCR, embeddings; ~26 GB plus context) is always loaded. A large model must fit beside it in the 108 GiB GTT. Measured 2026-10-29: the 35B text model plus gpt-oss-120b uses 84 GiB; the whole household set plus Qwen3.5-122B uses 101 GiB. The 27B vision model, when added, goes in the `large` group.
- **Large models** load on demand and evict each other, never the household set.
- **Batch.** Household batch work (OCR, re-check, linker, wiki upkeep) runs overnight, concurrency one, resumable per document, `Nice=19` with low `CPUWeight` and `IOWeight`. Before each item it checks llama-swap's running requests and waits if an interactive request is in flight: the 35B model has one slot.
- **Coding, if it returns,** runs overnight or when llama-swap is idle (`/running`, `/upstream/<model>/slots`), on a model that fits beside the household set. Not designed.
