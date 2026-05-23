const {
  prepareEmbedding,
  buildEnrollmentTemplate,
  FACE_PREPROCESS_SPEC,
} = require('./facePreprocess');

/**
 * Cosine similarity between two L2-normalized embedding vectors.
 */
function cosineSimilarity(a, b) {
  if (!a?.length || !b?.length || a.length !== b.length) return 0;
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA === 0 || normB === 0) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

function averageEmbeddings(embeddings) {
  return buildEnrollmentTemplate(embeddings);
}

/**
 * Match live embedding against stored template (preferred) or legacy pose rows.
 */
function evaluateFaceMatch(liveEmbedding, storedEmbeddings, threshold) {
  const empty = {
    similarity: 0,
    avgSimilarity: 0,
    minSimilarity: 0,
    maxSimilarity: 0,
    top2AvgSimilarity: 0,
    matched: false,
    embeddingId: null,
    matchMode: 'none',
  };

  if (!storedEmbeddings?.length) return empty;

  const live = prepareEmbedding(liveEmbedding);
  const templateRow = storedEmbeddings.find(
    (row) => String(row.angleType || row.angle_type || '').toLowerCase() === 'template',
  );

  if (templateRow) {
    const stored = prepareEmbedding(templateRow.embedding);
    const similarity = cosineSimilarity(live, stored);
    return {
      similarity,
      avgSimilarity: similarity,
      minSimilarity: similarity,
      maxSimilarity: similarity,
      top2AvgSimilarity: similarity,
      matched: similarity >= threshold,
      embeddingId: templateRow.id,
      matchMode: 'template',
    };
  }

  const scores = storedEmbeddings
    .filter((row) => String(row.angleType || row.angle_type || '').toLowerCase() !== 'template')
    .map((stored) => ({
      id: stored.id,
      similarity: cosineSimilarity(live, prepareEmbedding(stored.embedding)),
    }));

  if (!scores.length) return empty;

  const values = scores.map((s) => s.similarity).sort((a, b) => b - a);
  const maxSimilarity = values[0];
  const minSimilarity = values[values.length - 1];
  const avgSimilarity = values.reduce((sum, v) => sum + v, 0) / values.length;
  const top2AvgSimilarity =
    values.length >= 2 ? (values[0] + values[1]) / 2 : values[0];
  const top2Min = threshold * 0.96;
  const matched = maxSimilarity >= threshold && top2AvgSimilarity >= top2Min;
  const best = scores.reduce((a, b) => (b.similarity > a.similarity ? b : a));

  return {
    similarity: maxSimilarity,
    avgSimilarity,
    minSimilarity,
    maxSimilarity,
    top2AvgSimilarity,
    matched,
    embeddingId: best.id,
    matchMode: 'legacy-poses',
  };
}

/** @deprecated Use evaluateFaceMatch */
function findBestMatch(liveEmbedding, storedEmbeddings, threshold) {
  const result = evaluateFaceMatch(liveEmbedding, storedEmbeddings, threshold);
  return {
    similarity: result.similarity,
    matched: result.matched,
    embeddingId: result.embeddingId,
    minSimilarity: result.minSimilarity,
    maxSimilarity: result.maxSimilarity,
  };
}

module.exports = {
  cosineSimilarity,
  averageEmbeddings,
  evaluateFaceMatch,
  findBestMatch,
  FACE_PREPROCESS_SPEC,
};
