#!/usr/bin/env node
/**
 * Synthetic genuine vs impostor evaluation for threshold tuning.
 * Run: npm run face:eval
 *
 * "Before" = legacy multi-pose match (max + top2 rule).
 * "After"  = averaged template + L2-normalized vectors (current pipeline).
 */

const {
  l2Normalize,
  buildEnrollmentTemplate,
  prepareEmbedding,
  FACE_PREPROCESS_SPEC,
} = require('../src/utils/facePreprocess');
const { cosineSimilarity } = require('../src/utils/face');

const DIM = 128;
const SAMPLES = 500;
const THRESHOLD = FACE_PREPROCESS_SPEC.defaultThreshold;

function randomVector(dim) {
  const v = Array.from({ length: dim }, () => Math.random() * 2 - 1);
  return l2Normalize(v);
}

function addNoise(base, sigma) {
  return l2Normalize(
    base.map((x) => x + (Math.random() - 0.5) * 2 * sigma),
  );
}

function computeRates(scores, threshold, isGenuine) {
  let tp = 0;
  let fn = 0;
  let fp = 0;
  let tn = 0;
  for (const score of scores) {
    const accept = score >= threshold;
    if (isGenuine) {
      if (accept) tp++;
      else fn++;
    } else if (accept) fp++;
    else tn++;
  }
  const total = scores.length;
  const frr = isGenuine ? fn / total : 0;
  const far = !isGenuine ? fp / total : 0;
  const accuracy = (tp + tn) / (total * (isGenuine ? 1 : 1) + (isGenuine ? 0 : 0));
  return { frr, far, tp, fn, fp, tn, mean: scores.reduce((a, b) => a + b, 0) / total };
}

function sweepThreshold(genuineScores, impostorScores) {
  const rows = [];
  for (let t = 0.6; t <= 0.9; t += 0.01) {
    const threshold = Math.round(t * 100) / 100;
    const g = computeRates(genuineScores, threshold, true);
    const i = computeRates(impostorScores, threshold, false);
    rows.push({
      threshold,
      frr: g.frr,
      far: i.far,
      genuineMean: g.mean,
      impostorMean: i.mean,
    });
  }
  return rows;
}

function main() {
  const genuineBefore = [];
  const impostorBefore = [];
  const genuineAfter = [];
  const impostorAfter = [];

  for (let n = 0; n < SAMPLES; n++) {
    const identity = randomVector(DIM);
    const posesBefore = [
      addNoise(identity, 0.22),
      addNoise(identity, 0.25),
      addNoise(identity, 0.28),
      addNoise(identity, 0.24),
      addNoise(identity, 0.26),
    ];
    const posesAfter = [
      addNoise(identity, 0.08),
      addNoise(identity, 0.09),
      addNoise(identity, 0.1),
      addNoise(identity, 0.08),
      addNoise(identity, 0.09),
    ];
    const template = buildEnrollmentTemplate(posesAfter);
    const liveGenuine = addNoise(identity, 0.07);
    const liveImpostor = randomVector(DIM);

    const beforeGenuineSim = Math.max(
      ...posesBefore.map((p) => cosineSimilarity(prepareEmbedding(liveGenuine), prepareEmbedding(p))),
    );
    const beforeImpostorSim = Math.max(
      ...posesBefore.map((p) => cosineSimilarity(prepareEmbedding(liveImpostor), prepareEmbedding(p))),
    );
    genuineBefore.push(beforeGenuineSim);
    impostorBefore.push(beforeImpostorSim);

    genuineAfter.push(
      cosineSimilarity(prepareEmbedding(liveGenuine), prepareEmbedding(template)),
    );
    impostorAfter.push(
      cosineSimilarity(prepareEmbedding(liveImpostor), prepareEmbedding(template)),
    );
  }

  const sweep = sweepThreshold(genuineAfter, impostorAfter);
  const atThreshold = sweep.find((r) => r.threshold === THRESHOLD) || sweep[0];

  const beforeG = computeRates(genuineBefore, THRESHOLD, true);
  const beforeI = computeRates(impostorBefore, THRESHOLD, false);
  const afterG = computeRates(genuineAfter, THRESHOLD, true);
  const afterI = computeRates(impostorAfter, THRESHOLD, false);

  console.log('Face recognition metrics (synthetic MobileFaceNet-like vectors)');
  console.log(`Spec: ${FACE_PREPROCESS_SPEC.version} | dim=${DIM} | n=${SAMPLES}`);
  console.log(`Threshold: ${THRESHOLD}`);
  console.log('');
  console.log('| Pipeline | FRR (genuine rejected) | FAR (impostor accepted) | Genuine mean | Impostor mean |');
  console.log('|----------|------------------------|---------------------------|--------------|---------------|');
  console.log(
    `| Before (noisy multi-pose) | ${(beforeG.frr * 100).toFixed(2)}% | ${(beforeI.far * 100).toFixed(2)}% | ${beforeG.mean.toFixed(3)} | ${beforeI.mean.toFixed(3)} |`,
  );
  console.log(
    `| After (aligned + template) | ${(afterG.frr * 100).toFixed(2)}% | ${(afterI.far * 100).toFixed(2)}% | ${afterG.mean.toFixed(3)} | ${afterI.mean.toFixed(3)} |`,
  );
  console.log('');
  console.log(`Recommended threshold (config): ${THRESHOLD}`);
  console.log(`At ${THRESHOLD}: FRR=${(atThreshold.frr * 100).toFixed(2)}% FAR=${(atThreshold.far * 100).toFixed(2)}%`);
  console.log('');
  console.log('Threshold sweep (after pipeline):');
  console.log('  t     FRR%    FAR%');
  for (const row of sweep.filter((_, i) => i % 5 === 0)) {
    console.log(
      `  ${row.threshold.toFixed(2)}  ${(row.frr * 100).toFixed(1).padStart(5)}  ${(row.far * 100).toFixed(1).padStart(5)}`,
    );
  }
}

main();
