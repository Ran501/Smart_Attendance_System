/**
 * Cosine similarity between two embedding vectors.
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
  if (!embeddings.length) return [];
  const dim = embeddings[0].length;
  const sum = new Array(dim).fill(0);
  for (const emb of embeddings) {
    for (let i = 0; i < dim; i++) sum[i] += emb[i];
  }
  return sum.map((v) => v / embeddings.length);
}

/**
 * Strict match: average across all enrolled poses must pass, and the weakest
 * pose must be close to the threshold (stops "one lucky angle" false accepts).
 */
function evaluateFaceMatch(liveEmbedding, storedEmbeddings, threshold) {
  if (!storedEmbeddings?.length) {
    return {
      similarity: 0,
      avgSimilarity: 0,
      minSimilarity: 0,
      maxSimilarity: 0,
      matched: false,
      embeddingId: null,
    };
  }

  const scores = storedEmbeddings.map((stored) => ({
    id: stored.id,
    similarity: cosineSimilarity(liveEmbedding, stored.embedding),
  }));

  const values = scores.map((s) => s.similarity);
  const maxSimilarity = Math.max(...values);
  const minSimilarity = Math.min(...values);
  const avgSimilarity =
    values.reduce((sum, v) => sum + v, 0) / values.length;

  const minRequired = threshold * 0.88;
  const matched =
    avgSimilarity >= threshold &&
    minSimilarity >= minRequired &&
    maxSimilarity >= threshold;

  const best = scores.reduce((a, b) => (b.similarity > a.similarity ? b : a));

  return {
    similarity: avgSimilarity,
    avgSimilarity,
    minSimilarity,
    maxSimilarity,
    matched,
    embeddingId: best.id,
  };
}

/** @deprecated Use evaluateFaceMatch — kept for tests */
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
};
