# TensorFlow Lite Face Embedding Model

Place your face embedding model here as `mobile_face_net.tflite`.

Recommended: MobileFaceNet or FaceNet TFLite (128 or 512-dimensional embeddings).

Download from TensorFlow Hub or convert your trained model with:
`tensorflow/lite/python/tflite_convert`

Input: 112x112 RGB, normalized to [-1, 1].
Output: embedding vector for cosine similarity matching.
