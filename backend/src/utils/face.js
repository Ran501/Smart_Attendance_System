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

function findBestMatch(liveEmbedding, storedEmbeddings, threshold) {
  let best = { similarity: 0, matched: false };
  for (const stored of storedEmbeddings) {
    const sim = cosineSimilarity(liveEmbedding, stored.embedding);
    if (sim > best.similarity) {
      best = { similarity: sim, matched: sim >= threshold, embeddingId: stored.id };
    }
  }
  return best;
}

module.exports = { cosineSimilarity, averageEmbeddings, findBestMatch };
