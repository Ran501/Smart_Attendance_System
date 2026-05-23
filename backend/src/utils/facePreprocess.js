/**
 * Server-side face vector pipeline — must stay aligned with:
 *   lib/core/face/face_preprocess_spec.dart
 *   lib/services/face_preprocess.dart
 *
 * Image resize / landmark alignment runs on-device (TFLite).
 * Server normalizes, averages enrollment templates, and scores cosine similarity.
 */

const FACE_PREPROCESS_SPEC = Object.freeze({
  version: '1.0.0',
  inputSize: 112,
  pixelScale: 127.5,
  normalizeRange: [-1, 1],
  alignment: 'mlkit-eye-landmarks-v1',
  embeddingPostprocess: 'l2-normalize',
  enrollmentStrategy: 'average-5-poses-l2',
  defaultThreshold: 0.70,
});

const MIN_EMBEDDING_DIM = 64;

function l2Normalize(vector) {
  if (!Array.isArray(vector) || !vector.length) return [];
  let norm = 0;
  for (const x of vector) norm += x * x;
  norm = Math.sqrt(norm);
  if (norm === 0) return vector.slice();
  return vector.map((x) => x / norm);
}

function validateEmbedding(embedding) {
  if (!Array.isArray(embedding) || embedding.length < MIN_EMBEDDING_DIM) {
    throw new Error(
      `Invalid embedding: expected at least ${MIN_EMBEDDING_DIM} dimensions`,
    );
  }
  if (!embedding.every((v) => typeof v === 'number' && Number.isFinite(v))) {
    throw new Error('Invalid embedding: non-numeric values');
  }
  return embedding;
}

/** L2-normalize live or stored vectors before similarity (matches client post-process). */
function prepareEmbedding(embedding) {
  return l2Normalize(validateEmbedding(embedding));
}

function averageEmbeddings(embeddings) {
  if (!embeddings?.length) return [];
  const dim = embeddings[0].length;
  const sum = new Array(dim).fill(0);
  for (const emb of embeddings) {
    for (let i = 0; i < dim; i++) sum[i] += emb[i];
  }
  return l2Normalize(sum.map((v) => v / embeddings.length));
}

function buildEnrollmentTemplate(poseEmbeddings) {
  const normalized = poseEmbeddings.map((e) => prepareEmbedding(e));
  return averageEmbeddings(normalized);
}

module.exports = {
  FACE_PREPROCESS_SPEC,
  MIN_EMBEDDING_DIM,
  l2Normalize,
  validateEmbedding,
  prepareEmbedding,
  averageEmbeddings,
  buildEnrollmentTemplate,
};
