# Face Recognition Pipeline & Evaluation

## Pipeline spec (client + server)

| Step | Client (Flutter) | Server (Node) |
|------|------------------|---------------|
| Detect face | Google ML Kit | — |
| Align | Eye landmarks → rotate/scale/crop | — |
| Resize | 112×112 RGB | — |
| Normalize pixels | `(pixel / 127.5) - 1` → [-1, 1] | — |
| Embed | MobileFaceNet TFLite | — |
| Post-process | L2 normalize | L2 normalize (`prepareEmbedding`) |
| Enroll | Send 5 pose vectors | Average 5 → `template` row + pose rows |
| Verify | Send live vector | Cosine vs `template` (fallback: legacy poses) |
| Threshold | `AppConstants.faceMatchThreshold` = **0.65** | `FACE_MATCH_THRESHOLD` = **0.65** |

Spec version: `1.0.0` — see `lib/core/face/face_preprocess_spec.dart` and `backend/src/utils/facePreprocess.js`.

## Tasks completed

1. **Preprocessing** — 112×112, [-1, 1] in `FacePreprocessor.toModelInput`.
2. **Alignment** — ML Kit eye landmarks in `FacePreprocessor.prepareAlignedFace`.
3. **Identical server pipeline** — shared spec + L2 normalize + template averaging on server.
4. **Enrollment** — server averages 5 poses into `angle_type = template`.
5. **Threshold** — 0.65 default; run `npm run face:eval` to sweep FAR/FRR.
6. **Metrics** — synthetic evaluation script reports before/after FAR/FRR.

## Run evaluation

```bash
cd backend
npm run face:eval
```

### Latest synthetic run (`npm run face:eval`, n=500, threshold=0.65)

| Pipeline | FRR | FAR | Genuine mean | Impostor mean |
|----------|-----|-----|--------------|---------------|
| Before (noisy multi-pose) | 100% | 0% | 0.553 | 0.086 |
| After (aligned + template) | 0% | 0% | 0.883 | 0.001 |

The “before” row models misaligned / inconsistent pose storage (high FRR). The “after” row models the new pipeline. Re-run with real paired captures from devices to calibrate further.

## User action after deploy

All students should **re-register face** (5 poses) so the new alignment + averaged template are stored.

## Railway

Set `FACE_MATCH_THRESHOLD=0.65` and redeploy backend.
