const { validationResult } = require('express-validator');

function validate(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    const list = errors.array();
    return res.status(400).json({
      error: list[0]?.msg || 'Validation failed',
      errors: list,
    });
  }
  next();
}

module.exports = validate;
